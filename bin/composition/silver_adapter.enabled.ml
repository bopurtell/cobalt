open! Core
open Async
module Host = Cobalt_ui.Silver_overview_host
module Adapter = Silver_overview
module Testing = Adapter.Testing
module Quick = Silver_quick_launch
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
  ; mutable binding : Host.binding option
  ; mutable shown : bool
  ; mutable stopped : bool
  ; mutable connect_request : int
  ; mutable connection_serial : int
  ; mutable view_serial : int
  ; mutable project : Testing.project option
  ; mutable catalog : Testing.catalog option
  ; mutable model : Quick.t
  ; mutable status : string
  ; mutable pending_project : Testing.project option
  ; mutable known_endpoints : string list
  ; mutable offered_endpoints : Connection.candidate list
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
    if not (Option.exists session.pending_project ~f:(phys_equal project)) then
      Testing.close project);
  session.project <- None
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
  Testing.discover project >>| fun result ->
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

let connect session (binding : Host.binding) ~announce =
  session.connect_request <- session.connect_request + 1;
  let request = session.connect_request in
  session.status <- "Connecting to Silver…";
  touch session;
  let candidate =
    match List.find session.offered_endpoints ~f:(fun candidate ->
      String.equal (Connection.endpoint candidate) binding.endpoint) with
    | Some candidate -> Ok candidate
    | None -> Connection.explicit binding.endpoint
  in
  (match candidate with
   | Ok candidate ->
     Connection.connect candidate ~project_root:binding.project_root
     >>| Result.map ~f:(fun project -> project, Connection.endpoint candidate)
   | Error _ as error -> return error)
  >>= fun result ->
  if session.stopped || request <> session.connect_request then (
    Result.iter result ~f:(fun (project, _) -> Testing.close project);
    return (Error "Silver connection superseded"))
  else
    match result with
    | Error reason ->
      session.status <- reason;
      touch session;
      return (Error reason)
    | Ok (project, endpoint) ->
      session.connection_serial <- session.connection_serial + 1;
      let serial = session.connection_serial in
      let binding = { binding with endpoint; project_root = Testing.project_root project } in
      invalidate session "Silver connection changed; reselect a test";
      stop_project session;
      session.binding <- Some binding;
      session.project <- Some project;
      session.known_endpoints <-
        binding.endpoint :: List.filter session.known_endpoints
          ~f:(fun endpoint -> not (String.equal endpoint binding.endpoint));
      if announce then start_observation session;
      don't_wait_for (discover session serial binding project);
      return (Ok ())
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
      if not (Option.exists session.project ~f:(phys_equal project)) then Testing.close project;
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
    session.connection_serial <- session.connection_serial + 1;
    let serial = session.connection_serial in
    don't_wait_for (discover session serial binding project)
  | Some binding, None -> don't_wait_for (connect session binding ~announce:false >>| ignore)
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

let rows session =
  match session.binding with
  | None -> [ session.status ]
  | Some ({ run = Some _; _ } as binding) ->
    observation_rows binding (Adapter.latest session.observation)
  | Some binding ->
    [ session.status; "Project: " ^ binding.project_root; "Endpoint: " ^ binding.endpoint ]
;;

let connections session () =
  Connection.lookup ~known:session.known_endpoints () >>| fun lookup ->
  session.offered_endpoints <- lookup.candidates;
  List.map lookup.candidates ~f:Connection.endpoint
;;

let factory : Host.factory =
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
      ; binding
      ; shown = false
      ; stopped = false
      ; connect_request = 0
      ; connection_serial = 0
      ; view_serial = 0
      ; project = None
      ; catalog = None
      ; model
      ; status = "Connect to a Silver project first"
      ; pending_project = None
      ; known_endpoints = Option.to_list (Option.map binding ~f:(fun binding -> binding.endpoint))
      ; offered_endpoints = []
      ; revision = 0
      ; changed = Ivar.create ()
      }
    in
    watch_observation session;
    Option.iter binding ~f:(fun binding ->
      don't_wait_for (connect session binding ~announce:false >>| ignore));
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
    ; connections = connections session
    ; connect = (fun binding -> connect session binding ~announce:true)
    ; show
    ; hide
    ; refresh = (fun () -> refresh session)
    ; revision = (fun () -> session.revision)
    ; await_change = (fun ~after ->
      if after <> session.revision then Deferred.unit else Ivar.read session.changed)
    ; shutdown
    })
;;
