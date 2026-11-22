open! Core
open Async
module Host = Cobalt_ui.Silver_overview_host
module Adapter = Silver_overview
module Testing = Adapter.Testing
module Quick = Silver_quick_launch
module Flow = Silver_flow
module Connection = Silver_connection
module Tile = Cobalt_screen.Silver_overview_tile

let attempt_rows ({ id; suite; lifecycle; outcome } : Adapter.attempt) =
  [ "Lifecycle: " ^ lifecycle
  ; "Outcome: " ^ Option.value outcome ~default:"Unknown"
  ; "Suite: " ^ suite
  ; "Attempt: " ^ id
  ]
;;

let observation_rows (binding : Host.binding) availability =
  let status, snapshot, reason =
    match availability with
    | Adapter.Unavailable reason -> "Unavailable", None, Some reason
    | Fresh snapshot -> "Fresh", Some snapshot, None
    | Stale (snapshot, reason) -> "Stale", Some snapshot, Some reason
  in
  [ "Status: " ^ status; "Project: " ^ binding.project_root ]
  @ Option.value_map binding.run ~default:[] ~f:(fun run -> [ "Run: " ^ run ])
  @ Option.value_map snapshot ~default:[] ~f:(fun snapshot ->
      List.concat_map snapshot.attempts ~f:attempt_rows
      @ (if snapshot.truncated then [ "More attempts omitted" ] else []))
  @ [ "Endpoint: " ^ binding.endpoint ]
  @ Option.value_map reason ~default:[] ~f:(fun reason -> [ reason ])
;;

type session =
  (* Observation is disposable; project/model/acknowledgement are editor-session
     state. Rebinding the observation can never retarget a submitted test. *)
  { observation : Adapter.t
  ; flow : Flow.t
  ; flow_service : Testing.project -> Flow.service
  ; stage_projection : Stage_projection.t
  ; mutable pending_flow_projects : Testing.project list
  ; mutable binding : Host.binding option
  ; mutable shown : bool
  ; mutable stopped : bool
  ; mutable connect_request : int
  ; mutable connecting : bool
  ; mutable shared_project : bool
  ; mutable shared_snapshot : Adapter.snapshot option
  ; mutable connection_serial : int
  ; mutable view_serial : int
  ; mutable project : Testing.project option
  ; mutable catalog : Testing.catalog option
  ; mutable model : Quick.t
  ; mutable status : string
  ; mutable pending_project : Testing.project option
  ; share_fixture : string option
  ; mutable lookup_request : int
  ; mutable candidate_serial : int
  ; mutable offered_shares : (Host.Connection.Id.t * Connection.Share.t) list
  ; mutable revision : int
  ; mutable changed : unit Ivar.t
  }

let touch session =
  session.revision <- session.revision + 1;
  let previous = session.changed in
  session.changed <- Ivar.create ();
  Ivar.fill_exn previous ()
;;

let project_key ({ endpoint; project_root; _ } : Host.binding) : Quick.project =
  { endpoint; project_root }
;;

let model_catalog wire : Quick.catalog =
  let suites = List.map (Testing.suites wire) ~f:(fun (suite : Testing.suite) : Quick.suite ->
    { id = suite.id
    ; label = suite.label
    ; cases = List.map suite.cases ~f:(fun ({ id; label } : Testing.case) : Quick.case ->
        { id; label })
    ; parameters =
        List.map suite.parameters
          ~f:(fun ({ key; label; default; choices } : Testing.parameter) : Quick.parameter ->
            { key; label; default; choices })
    ; default_seed = suite.default_seed
    })
  in
  { discovery_digest = Testing.digest wire; suites }
;;

let current session serial = not session.stopped && session.connection_serial = serial

let invalidate session reason =
  session.catalog <- None;
  session.view_serial <- session.view_serial + 1;
  Option.iter session.binding ~f:(fun binding ->
    session.model <- Quick.invalidate_catalog session.model ~project:(project_key binding) ~reason)
;;

let stop_project session =
  Option.iter session.project ~f:(fun project ->
    if not (Option.exists session.pending_project ~f:(phys_equal project))
       && not (List.mem session.pending_flow_projects project ~equal:phys_equal)
    then
      Testing.close project);
  session.project <- None
;;

let close_retired_project session project =
  if not (Option.exists session.project ~f:(phys_equal project))
     && not (Option.exists session.pending_project ~f:(phys_equal project))
     && not (List.mem session.pending_flow_projects project ~equal:phys_equal)
  then Testing.close project
;;

(* The Flow model owns catalog, settings/drafts, and generation fencing for both
   surfaces. Keep the exact verified project alive only for an already-dispatched
   submission, also when the user switches project while its reply is pending. *)
let bind_flow session project =
  let service = session.flow_service project in
  let prepare request =
    service.prepare request >>| Result.map ~f:(fun (prepared : Flow.prepared) ->
       let submit ~still_current =
        session.pending_flow_projects <- project :: session.pending_flow_projects;
         Monitor.protect (fun () -> prepared.submit ~still_current) ~finally:(fun () ->
          let rec remove_one = function
            | [] -> []
            | head :: rest when phys_equal head project -> rest
            | head :: rest -> head :: remove_one rest
          in
          session.pending_flow_projects <- remove_one session.pending_flow_projects;
          close_retired_project session project;
          return ())
      in
      { prepared with submit })
  in
  Flow.bind session.flow { service with prepare };
  don't_wait_for (Flow.refresh session.flow)
;;

let start_observation session =
  match session.binding with
  | Some { endpoint; project_root; run = Some run } when session.shown ->
    Adapter.rebind session.observation { endpoint; project_root; run = Some run }
  | _ -> Adapter.unbind session.observation
;;

let discover session serial binding project =
  session.status <- "Loading Silver test catalog…";
  touch session;
  let on_snapshot =
    Option.some_if session.shared_project (fun snapshot ->
      if current session serial then session.shared_snapshot <- Some snapshot)
  in
  Testing.discover ~may_start:(not session.shared_project) ?on_snapshot project >>| fun result ->
  if current session serial then (
    (match result with
     | Ok catalog ->
       let project = project_key binding in
       let parsed = model_catalog catalog in
       if Option.is_none session.catalog
          || not (Option.exists (Quick.catalog_view session.model ~project)
                    ~f:(fun previous -> Poly.equal (Quick.catalog_contents previous) parsed))
       then session.view_serial <- session.view_serial + 1;
       session.catalog <- Some catalog;
       session.model <- Quick.set_catalog session.model ~project parsed;
       session.status <- "Silver test catalog ready"
     | Error reason ->
       invalidate session reason;
       session.status <- reason);
    touch session)
;;

let connect session ~announce ~shared verify =
  session.connect_request <- session.connect_request + 1;
  let request = session.connect_request in
  session.connecting <- true;
  touch session;
  verify () >>= fun result ->
  if session.stopped || request <> session.connect_request then (
    Result.iter result ~f:(fun (project, _) -> Testing.close project);
    return None)
  else (
    session.connecting <- false;
    match result with
    | Error reason ->
      if Option.is_none session.project then session.status <- reason;
      touch session;
      return (Some (Error reason))
    | Ok (project, (binding : Host.binding)) ->
      session.connection_serial <- session.connection_serial + 1;
      let serial = session.connection_serial in
      let binding = { binding with project_root = Testing.project_root project } in
       invalidate session "Silver connection changed; reselect a test";
       stop_project session;
       session.binding <- Some binding;
       session.project <- Some project;
        session.shared_project <- shared;
        session.shared_snapshot <- None;
       bind_flow session project;
      if announce then start_observation session;
      don't_wait_for (discover session serial binding project);
      return (Some (Ok ("Connected to Silver · " ^ binding.project_root))))
;;

let connect_explicit session (binding : Host.binding) ~announce =
  connect session ~announce ~shared:false (fun () ->
    match Connection.explicit binding.endpoint with
    | Error reason -> return (Error reason)
    | Ok candidate ->
      let endpoint = Connection.endpoint candidate in
      Connection.connect candidate ~project_root:binding.project_root
      >>| Result.map ~f:(fun project -> project, { binding with endpoint }))
;;

let connect_selected session (selection : Host.Connection.selection) =
  match selection with
  | Manual { endpoint; project_root } ->
    connect_explicit session { endpoint; project_root; run = None } ~announce:true
  | Share id ->
    connect session ~announce:true ~shared:true (fun () ->
      match List.Assoc.find session.offered_shares id ~equal:Host.Connection.Id.equal with
      | None -> return (Error "Silver share choice is stale; rediscover")
      | Some share ->
        let endpoint = Connection.Share.endpoint share in
        let project_root = Connection.Share.project_root share in
        let binding : Host.binding = { endpoint; project_root; run = None } in
        Connection.Share.connect share >>| Result.map ~f:(fun project -> project, binding))
;;

let launch session (launch : Quick.launch) =
  if Option.is_some session.pending_project then
    return (Error "A Silver launch acknowledgement is still pending")
  else
    match session.catalog, session.project with
    | Some catalog, Some project
      when String.equal (Testing.digest catalog) launch.discovery_digest ->
      session.pending_project <- Some project;
      touch session;
      let { Quick.suite; cases; seed; parameters } = launch.selection in
      Testing.launch catalog ~suite ~cases ~seed ~parameters >>| fun result ->
      session.pending_project <- None;
       close_retired_project session project;
      touch session;
      (match result with
       | Accepted { attempt_id; job_id } ->
         if not session.stopped then session.model <- Quick.record_launch session.model launch;
         Ok (sprintf "%s · Accepted · attempt %s · job %s" launch.display attempt_id job_id)
       | Rejected reason -> Error (sprintf "%s · Rejected: %s" launch.display reason)
       | Uncertain reason -> Error (sprintf "%s · Delivery unconfirmed: %s" launch.display reason)
       | Stale_catalog reason ->
         if not session.stopped
            && Option.exists session.project ~f:(phys_equal project)
            && Option.exists session.catalog ~f:(fun current ->
              String.equal (Testing.digest current) launch.discovery_digest)
         then (
           session.connection_serial <- session.connection_serial + 1;
           invalidate session reason;
           Option.iter session.binding ~f:(fun binding ->
             don't_wait_for (discover session session.connection_serial binding project)));
         Error (sprintf "%s · Catalog changed; reselect a test: %s" launch.display reason))
    | _ -> return (Error "Silver test catalog changed; reselect a test")
;;

let with_catalog session ~f ~unavailable =
  match session.binding with
  | None -> unavailable session.status
  | Some binding ->
    let project = project_key binding in
    (match Quick.catalog_view session.model ~project with
     | Some view -> f view
     | None ->
       unavailable (Option.value (Quick.catalog_error session.model ~project)
                      ~default:session.status))
;;

let target_rows view =
  List.concat_map (Quick.catalog_contents view).suites ~f:(fun suite ->
    Option.to_list (Option.some_if (not (List.is_empty suite.cases))
                      (Quick.Suite suite.id, suite.id, None))
    @ List.map suite.cases ~f:(fun case ->
      Quick.Variant { suite_id = suite.id; case_id = case.id }, suite.id, Some case.id))
;;

let field_name = function
  | Quick.Seed -> "Seed"
  | Parameter key when String.equal key "Seed" || String.is_prefix key ~prefix:"Parameter " ->
    "Parameter " ^ key
  | Parameter key -> key
;;

(* A tile target carries the rendered catalog generation, not the wire digest.
   A reconnect fences old targets even if Silver rediscovers identical bytes. *)
let view_token session = Int.to_string session.view_serial

let present_target session view (target, suite, variant) =
  Result.bind (Quick.select session.model view target) ~f:(fun (model, selected) ->
    Quick.begin_edit model selected)
  |> Result.ok
  |> Option.map ~f:(fun edit : Tile.Target.t ->
    { suite
    ; variant
    ; digest = view_token session
    ; fields = List.map (Quick.fields edit) ~f:(fun field : Tile.Field.t ->
        { name = field_name field.id; value = field.value; default = field.default })
    })
;;

let targets session =
  with_catalog session ~unavailable:(fun _ -> []) ~f:(fun view ->
    List.filter_map (target_rows view) ~f:(present_target session view))
;;

let test_action session : Tile.Test_action.t =
  match session.binding with
  | _ when Option.is_some session.pending_project ->
    Unavailable "A Silver launch acknowledgement is pending"
  | None -> Unavailable "Connect to a Silver project first"
  | Some _ when Option.is_none session.project -> Unavailable session.status
  | Some binding ->
    let project = project_key binding in
    match Quick.resolve_alias session.model ~project with
    | Quick.Blocked reason -> Unavailable reason
    | Pick_target -> Pick
    | Ready launch ->
      with_catalog session ~unavailable:(fun reason -> Unavailable reason) ~f:(fun view ->
        match List.find (target_rows view) ~f:(fun (target, _, _) -> Poly.equal target launch.target)
              |> Option.bind ~f:(present_target session view) with
        | Some target -> Tile.Test_action.Run target
        | None -> Tile.Test_action.Unavailable "Silver test catalog changed; reselect a test")
;;

let resolve_row session (row : Tile.Target.t) =
  if not (String.equal row.digest (view_token session)) then
    Error "Silver test catalog changed; reselect a test"
  else
    with_catalog session ~unavailable:(fun reason -> Error reason) ~f:(fun view ->
      let target =
        match row.variant with
        | None -> Quick.Suite row.suite
        | Some case_id -> Quick.Variant { suite_id = row.suite; case_id }
      in
      match present_target session view (target, row.suite, row.variant) with
      | Some live when Tile.Target.equal live row -> Quick.select session.model view target
      | _ -> Error "Silver test settings changed; reselect a test")
;;

let run_row session row =
  let request =
    let open Result.Let_syntax in
    let%bind model, selected = resolve_row session row in
    let%bind request = Quick.resolve model selected in
    let%map () = Quick.check_launch model request in
    model, request
  in
  match request with
  | Error reason -> return (Error reason)
  | Ok (model, request) ->
    session.model <- model;
    launch session request
;;

let apply_settings session row fields =
  Result.bind (resolve_row session row) ~f:(fun (model, selected) ->
    match Quick.begin_edit model selected with
    | Error reason -> Error reason
    | Ok edit ->
      let edit =
        List.fold (Quick.fields edit) ~init:edit ~f:(fun edit field ->
          match List.Assoc.find fields (field_name field.id) ~equal:String.equal with
          | None -> edit
          | Some value -> Quick.set_field edit field.id value)
      in
      match Quick.apply model edit with
      | Error reason -> Error reason
      | Ok model ->
        session.model <- model;
        touch session;
        Ok ())
;;

let refresh session =
  start_observation session;
  match session.binding, session.project with
  | Some binding, Some project ->
    don't_wait_for (Flow.refresh session.flow);
    session.connection_serial <- session.connection_serial + 1;
    let serial = session.connection_serial in
    don't_wait_for (discover session serial binding project)
  | Some binding, None when not session.connecting ->
    don't_wait_for (connect_explicit session binding ~announce:false >>| ignore)
  | _ -> ()
;;

let watch_observation session =
  let rec loop after =
    Adapter.await_change session.observation ~after >>= fun () ->
    if session.stopped then return ()
    else (
      touch session;
      loop (Adapter.revision session.observation))
  in
  don't_wait_for (loop (Adapter.revision session.observation))
;;

let watch_flow session =
  let rec loop after =
    Flow.await_change session.flow ~after >>= fun () ->
    if session.stopped then return ()
    else (
      touch session;
      loop (Flow.revision session.flow))
  in
  don't_wait_for (loop (Flow.revision session.flow))
;;

let rows session =
  (if session.connecting then [ "Connecting to Silver…" ] else []) @
  match session.binding with
  | None -> [ session.status ]
  | Some ({ run = Some _; _ } as binding) ->
    observation_rows binding (Adapter.latest session.observation)
  | Some binding ->
    [ session.status; "Project: " ^ binding.project_root; "Endpoint: " ^ binding.endpoint ]
    @ (match session.shared_project, session.project with
       | true, Some project ->
         [ "Project ID: " ^ Testing.project_id project
         ; "Instance: " ^ Testing.instance_id project
         ]
        | _ -> [])
    @ Option.value_map session.shared_snapshot ~default:[] ~f:(fun snapshot ->
        List.concat_map snapshot.attempts ~f:attempt_rows
        @ (if snapshot.truncated then [ "More attempts omitted" ] else []))
;;

let connections session ~generation =
  let empty : Host.Connection.lookup = { rows = []; error = None } in
  if session.stopped || generation <= session.lookup_request then return empty
  else (
    session.lookup_request <- generation;
    session.offered_shares <- [];
    let%map (lookup : Connection.Share.lookup) =
      match session.share_fixture with
      | None -> Connection.Share.lookup_live ()
      | Some file -> Connection.Share.lookup ~file
    in
    if session.stopped || generation <> session.lookup_request then empty
    else (
      let module Share = Connection.Share in
      let offer_ids = List.map lookup.shares ~f:Share.offer_id in
      let offer_label share =
        let id = Share.offer_id share in
        let rec distinguish length =
          let prefix = String.prefix id length in
          if length >= String.length id
             || not (List.exists offer_ids ~f:(fun other ->
               not (String.equal id other) && String.is_prefix other ~prefix))
          then prefix
          else distinguish (length + 1)
        in
        distinguish 12
      in
      let rows =
        List.map lookup.shares ~f:(fun share ->
          session.candidate_serial <- session.candidate_serial + 1;
          let id = Host.Connection.Id.of_int session.candidate_serial in
          session.offered_shares <- (id, share) :: session.offered_shares;
          let title =
            match Share.mode share with
            | None ->
              sprintf "Offered · %s/%s · %s · %s @ %s"
                (Share.offer_id share) (Share.project_id share) (Share.project_root share)
                (Share.instance_id share) (Share.endpoint share)
            | Some mode ->
              let label = match mode with Share.Embedded -> "embedded" | Attached -> "attached" in
              sprintf "%s [%s · %s] · %s @ %s"
                (Filename.basename (Share.project_root share)) label
                (offer_label share)
                (Share.project_root share) (Share.endpoint share)
          in
          { Host.Connection.id; title })
      in
      { Host.Connection.rows; error = lookup.error }))
;;

let factory_with_flow_service flow_service : Host.factory =
  Some (fun ~test_default binding ->
    let binding = Option.map binding ~f:(fun (binding : Host.binding) ->
      match Connection.explicit binding.endpoint with
      | Error _ -> binding
      | Ok candidate -> { binding with endpoint = Connection.endpoint candidate })
    in
    let model =
      Option.value_map (Option.both binding test_default) ~default:Quick.empty
        ~f:(fun (binding, (suite_id, variant)) ->
          let target =
            match variant with
            | None -> Quick.Suite suite_id
            | Some case_id -> Quick.Variant { suite_id; case_id }
          in
          Quick.set_configured_default Quick.empty ~project:(project_key binding) (Some target))
    in
    let session =
      { observation = Adapter.create ()
      ; flow = Flow.create ()
      ; flow_service
      ; stage_projection = Stage_projection.create ()
      ; pending_flow_projects = []
      ; binding
      ; shown = false
      ; stopped = false
      ; connect_request = 0
      ; connecting = false
       ; shared_project = false
       ; shared_snapshot = None
      ; connection_serial = 0
      ; view_serial = 0
      ; project = None
      ; catalog = None
      ; model
      ; status = "Connect to a Silver project first"
      ; pending_project = None
      ; share_fixture =
          Option.filter (Sys.getenv "COBALT_SILVER_SHARE_FIXTURE") ~f:(Fn.non String.is_empty)
      ; lookup_request = 0
      ; candidate_serial = 0
      ; offered_shares = []
      ; revision = 0
      ; changed = Ivar.create ()
      }
    in
    watch_observation session;
    watch_flow session;
    Option.iter binding ~f:(fun binding ->
      don't_wait_for (connect_explicit session binding ~announce:false >>| ignore));
    let show () =
      session.shown <- true;
      start_observation session
    in
    let hide () =
      session.shown <- false;
      Adapter.unbind session.observation
    in
    let shutdown () =
      if not session.stopped then (
        session.stopped <- true;
        Flow.unbind session.flow;
        List.iter session.pending_flow_projects ~f:Testing.close;
        Option.iter session.pending_project ~f:Testing.close;
        stop_project session;
        Adapter.shutdown session.observation;
        touch session)
    in
    { Host.rows = (fun () -> rows session)
    ; targets = (fun () -> targets session)
    ; status_first = (fun () ->
      Option.exists session.binding ~f:(fun binding -> Option.is_some binding.run))
    ; test_action = (fun () -> test_action session)
    ; apply_settings = apply_settings session
    ; launch = run_row session
    ; stages = (fun () -> Stage_projection.snapshot session.stage_projection session.flow)
    ; launch_stage = Stage_projection.launch session.stage_projection session.flow
    ; connections = connections session
    ; connect = connect_selected session
    ; show
    ; hide
    ; refresh = (fun () -> refresh session)
    ; revision = (fun () -> session.revision)
    ; await_change = (fun ~after ->
      if after <> session.revision then Deferred.unit else Ivar.read session.changed)
     ; shutdown
     ; kickoff =
         Some
           (Silver_kickoff_adapter.create ~flow:session.flow ~changed:(fun () -> touch session)
              ~project_root:(fun () ->
                Option.map session.binding ~f:(fun binding -> binding.project_root)))
    })
;;

let factory = factory_with_flow_service Flow.production
