open! Core
open Async

type selection =
  { target : Silver_flow.target option
  ; flow : string
  ; profile : string
  }

type subject =
  | No_selection
  | Exact_run of string
  | Exact_matching_run of selection * string
  | Exact_workflow of string
  | Latest_matching of selection

type status =
  | Pending | Running | Cancelling | Completed | Failed | Skipped | Cancelled
  | Interrupted | Not_requested | Unsupported | Unconfirmed | Unavailable
  | Unknown of string

type duration = Measured of float | Since of Time_ns.t
type origin = Physical | Elaboration | Supplementary_timing | Requested_endpoint

type stage =
  { id : string
  ; label : string
  ; origin : origin
  ; status : status
  ; duration : duration option
  ; reason : string option
  ; launch_destination : (selection * string) option
  }

type freshness = Validated | Cached_unverified | Missing_source | Refresh_failed of string

type snapshot =
  { subject : subject
  ; run_id : string option
  ; workflow_id : string option
  ; process_status : string option
  ; stages : stage list
  ; summary_freshness : freshness option
  ; notice : string option
  ; matching_run_ids : string list
  }

type availability = Not_available of string | Fresh of snapshot | Stale of snapshot * string

module Wire = struct
  exception Invalid of string

  let invalid reason = raise (Invalid reason)
  let atom value = Sexp.Atom value
  let list = function Sexp.List xs -> xs | _ -> invalid "Expected Silver ASIC list"
  let text = function Sexp.Atom s -> s | _ -> invalid "Expected Silver ASIC atom"
  let find node key =
    List.fold (list node) ~init:None ~f:(fun found -> function
      | Sexp.List [ Sexp.Atom name; value ] when String.equal name key ->
        if Option.is_some found then invalid ("Duplicate Silver ASIC field: " ^ key);
        Some value
      | _ -> found)
  ;;
  let get node key =
    Option.value_or_thunk (find node key)
      ~default:(fun () -> invalid ("Missing Silver ASIC field: " ^ key))
  ;;
  let opt = function Sexp.List [] -> None | Sexp.List [ x ] -> Some x | _ -> invalid "Invalid Silver ASIC option"
  let optional node key = Option.bind (find node key) ~f:opt
  let rows node key = Option.value_map (find node key) ~default:[] ~f:list
  let safe value =
    let buf = Buffer.create 64 in
    let rec copy i =
      if i < String.length value && i < 4096 then (
        let u = Stdlib.String.get_utf_8_uchar value i in
        let n = Stdlib.Uchar.utf_decode_length u in
        let c = Stdlib.Uchar.(utf_decode_uchar u |> to_int) in
        if i + n <= 4096 then (
          if Stdlib.Uchar.utf_decode_is_valid u && c >= 32 && (c < 127 || c > 159)
             && c <> 0x2028 && c <> 0x2029
          then Buffer.add_substring buf value ~pos:i ~len:n
          else Buffer.add_char buf '?';
          copy (i + n)))
    in
    copy 0;
    Buffer.contents buf
  ;;
  let display value = text value |> safe
  let identity value =
    let s = text value in
    if String.is_empty s || not (String.equal s (safe s)) then invalid "Invalid Silver ASIC identity";
    s
  ;;
  let id node key = get node key |> identity
  let bool node key = get node key |> Bool.t_of_sexp
  let timestamp = function
    | Sexp.Atom value as atom when String.length value <= 128 ->
      (match Option.try_with (fun () -> Time_ns.Alternate_sexp.t_of_sexp atom) with
       | Some _ as at -> at
       | None -> Option.try_with (fun () -> Time_ns.of_string_with_utc_offset value))
    | _ -> None
  ;;
  let seconds value =
    Option.try_with (fun () -> Float.t_of_sexp value)
    |> Option.filter ~f:(fun n -> Float.is_finite n && Float.(n >= 0. && n <= 1e12))
  ;;
  let timed node =
    let started = Option.bind (optional node "started_at") ~f:timestamp in
    let measured = Option.bind (optional node "measured_seconds") ~f:seconds in
    match measured, started with
    | Some n, _ -> Some (Measured n)
    | None, Some at when bool node "running" -> Some (Since at)
    | _ -> None
  ;;
  let duration node = Option.bind (optional node "execution_timing") ~f:timed
  let start node =
    Option.bind (optional node "execution_timing") ~f:(fun timing ->
      Option.bind (optional timing "started_at") ~f:timestamp)
  ;;
  let selection node : selection =
    let target = Option.map (optional node "chip_target") ~f:(fun c : Silver_flow.target ->
      { chip = id c "chip"; variant = id c "variant" }) in
    { target; flow = id node "flow"; profile = id node "profile" }
  ;;
  let stage_status = function
    | Sexp.Atom "Pending" -> Pending
    | Sexp.Atom "Running" -> Running
    | Sexp.Atom "Cancelling" -> Cancelling
    | Sexp.Atom "Completed" -> Completed
    | Sexp.Atom "Failed" -> Failed
    | Sexp.Atom "Skipped" -> Skipped
    | Sexp.Atom "Cancelled" -> Cancelled
    | Sexp.Atom "Interrupted" -> Interrupted
    | Sexp.Atom "Not_requested" -> Not_requested
    | Sexp.Atom "Unsupported" -> Unsupported
    | Sexp.List [ Sexp.Atom "Unknown"; Sexp.Atom ("unconfirmed" | "observation_unavailable") ] ->
      Unconfirmed
    | Sexp.List [ Sexp.Atom "Unknown"; detail ] | (Sexp.Atom _ as detail) ->
      Unknown (display detail)
    | _ -> invalid "Invalid Silver ASIC stage status"
  ;;
  let stage node =
    let status = get node "status" |> stage_status in
    let duration =
      match duration node with
      | Some (Since _) when not (Poly.equal status Running || Poly.equal status Cancelling) -> None
      | other -> other
    in
    let launch_destination =
      Option.map (optional node "action") ~f:(fun action ->
        selection action, id action "endpoint")
    in
    { id = id node "id"; label = get node "name" |> display; origin = Physical
    ; status; duration; reason = Option.map (optional node "reason") ~f:display
    ; launch_destination
    }
  ;;
  let freshness node =
    match get node "freshness" with
    | Sexp.Atom "Validated" -> Validated
    | Sexp.Atom "Cached_unverified" -> Cached_unverified
    | Sexp.Atom "Missing_source" -> Missing_source
    | Sexp.List [ Sexp.Atom "Refresh_failed"; reason ] -> Refresh_failed (display reason)
    | _ -> invalid "Invalid Silver ASIC summary freshness"
  ;;
  let run_ref node =
    if String.equal (id node "backend") "asic" then Some (id node "id") else None
  ;;
  let time_field node key = Option.bind (optional node key) ~f:timestamp
  let error node = Option.map (optional node "error") ~f:display

  type failure = Read_failed of string | Binding_lost of string

  let decode f =
    try Ok (f ()) with
    | Invalid reason -> Error (Read_failed reason)
    | _ -> Error (Read_failed "Malformed Silver ASIC reply")
  ;;

  let request project ~stop operation =
    match%map Silver_overview.Testing.send_bound ~asic_observation_metadata:true ~stop
                project ~path:"/api/v1/asic" operation with
    | Error message -> Error (Read_failed message)
    | Ok (response : Silver_overview.response) ->
      let rpc_error node =
        let kind = id node "kind" in
        let reason = "Silver ASIC " ^ kind ^ ": " ^ display (get node "message") in
        Error (if String.equal kind "Instance_changed" || String.equal kind "Not_found"
               then Binding_lost reason
               else Read_failed reason)
      in
      Result.join (decode (fun () ->
        if String.length response.body > Silver_http.max_body_bytes
        then invalid "Silver ASIC response exceeds the size limit";
        match response.status, Sexp.of_string response.body with
        | 200, Sexp.List [ Sexp.Atom "Ok"; data ] -> Ok data
        | 200, Sexp.List [ Sexp.Atom "Error"; data ]
        | (400 | 404 | 409), data -> rpc_error data
        | status, _ -> Error (Read_failed (sprintf "Silver ASIC HTTP %d" status))))
  ;;
end

type run =
  { run_id : string
  ; reference : Sexp.t
  ; selection : Sexp.t option
  ; started : Time_ns.t option
  ; process : string
  ; file : string option
  ; error : string option
  ; physical : stage list
  }

type workflow =
  { workflow_id : string
  ; run_reference : Sexp.t option
  ; selection : Sexp.t
  ; elaboration_only : bool
  ; created : Time_ns.t option
  ; phase : string
  ; error : string option
  ; elaboration : stage
  }

let find_unique rows ~f =
  match List.filter rows ~f with
  | [] -> None
  | [ x ] -> Some x
  | _ -> Wire.invalid "Conflicting Silver ASIC observation identities"
;;

let parse_run node =
  let open Wire in
  let reference = get node "run" in
  Option.map (run_ref reference) ~f:(fun run_id ->
    let physical = List.map (rows node "stages") ~f:stage in
    if List.contains_dup (List.map physical ~f:(fun s -> s.id)) ~compare:String.compare
    then invalid "Conflicting Silver ASIC stage observations";
    { run_id; reference; physical; selection = optional node "selection"
    ; started = start node; process = id node "status"
    ; file = Option.map (optional node "execution_file") ~f:text; error = error node
    })
;;

let parse_workflow node =
  let open Wire in
  let intent = get node "intent" in
  let phase = id node "phase" in
  let elaboration_status = id node "elaboration_status" in
  let job = optional node (if String.equal phase "Building" then "build_job" else "emission_job") in
  let queued = Option.value_map job ~default:true ~f:(fun job -> String.equal (id job "state") "Queued") in
  let status =
    match elaboration_status, phase with
    | "completed", _ -> Completed
    | ("build_failed" | "emission_failed"), _ | _, "Failed" -> Failed
    | "cancelled", _ | _, "Cancelled" -> Cancelled
    | "interrupted", _ | _, "Interrupted" -> Interrupted
    | _, "Completed" -> Completed
    | ("building" | "emitting"), _ when bool node "cancel_requested" -> Cancelling
    | ("building" | "emitting"), _ -> if queued then Pending else Running
    | _ -> Pending
  in
  let duration =
    Option.bind (time_field node "elaboration_started_at") ~f:(fun start ->
      match time_field node "elaboration_finished_at" with
      | Some finish when Time_ns.(finish >= start) ->
        Some (Measured (Time_ns.diff finish start |> Time_ns.Span.to_sec))
      | None when Poly.equal status Running || Poly.equal status Cancelling -> Some (Since start)
      | _ -> None)
  in
  let error = error node in
  { workflow_id = id node "id"; run_reference = optional node "run"
  ; selection = get intent "selection"; elaboration_only = bool intent "elaboration_only"
  ; created = timestamp (get node "created_at"); phase; error
  ; elaboration = { id = "preparation:elaboration"; label = "Elaboration"; origin = Elaboration
                  ; status; duration; reason = error; launch_destination = None }
  }
;;

let run_live (run : run) =
  List.mem [ "allocated"; "observing"; "running"; "starting"; "queued"; "cancelling" ]
    run.process ~equal:String.equal
;;

let run_terminal (run : run) =
  not (run_live run)
  && (Option.is_some run.file
      || List.mem [ "completed"; "complete"; "succeeded"; "success"; "failed"; "cancelled"
                  ; "canceled"; "interrupted"; "terminated" ] run.process ~equal:String.equal)
;;

let workflow_live workflow =
  List.mem [ "Reserved"; "Building"; "Emitting"; "Prepared"; "Physical" ]
    workflow.phase ~equal:String.equal
;;

let linked (run : run) workflow =
  Option.exists workflow.run_reference ~f:(Sexp.equal run.reference)
;;

let linked_workflow workflows run = find_unique workflows ~f:(linked run)

let matching_runs selected runs workflows =
  List.filter_map runs ~f:(fun run ->
    let workflow = linked_workflow workflows run in
    let selection = Option.first_some run.selection (Option.map workflow ~f:(fun w -> w.selection)) in
    if Option.exists selection ~f:(fun node -> Poly.equal selected (Wire.selection node))
    then Some (Option.first_some run.started (Option.bind workflow ~f:(fun w -> w.created)), run, workflow)
    else None)
;;

let scoped_run_ids matching =
  match matching with
  | [ _, run, _ ] -> [ run.run_id ]
  | _ ->
    List.filter_map matching ~f:(fun (at, run, _) -> Option.map at ~f:(fun at -> at, run.run_id))
    |> List.sort ~compare:(fun (a, aid) (b, bid) ->
      match Time_ns.compare b a with 0 -> String.compare aid bid | result -> result)
    |> List.map ~f:snd
;;

let resolve subject runs workflows matching =
  let run_for workflow =
    find_unique runs ~f:(fun run -> linked run workflow)
  in
  let workflow_for = linked_workflow workflows in
  let pin run = Some run, workflow_for run in
  let unresolved message = None, None, Some message in
  let found (run, workflow) = run, workflow, None in
  match subject with
  | No_selection -> unresolved "No ASIC run selected"
  | Exact_run id ->
    (match find_unique runs ~f:(fun run -> String.equal run.run_id id) with
     | Some run -> found (pin run)
     | None -> unresolved ("Selected ASIC run unavailable: " ^ Wire.safe id))
  | Exact_matching_run (_, id) ->
    (match find_unique matching ~f:(fun (_, run, _) ->
       String.equal run.run_id id) with
     | Some (_, run, workflow) -> found (Some run, workflow)
     | None -> unresolved ("Selected ASIC run unavailable in this scope: " ^ Wire.safe id))
  | Exact_workflow id ->
    (match find_unique workflows ~f:(fun workflow -> String.equal workflow.workflow_id id) with
     | Some workflow -> found (run_for workflow, Some workflow)
     | None -> unresolved ("Selected ASIC workflow unavailable: " ^ Wire.safe id))
  | Latest_matching selected ->
    let matches node = Poly.equal selected (Wire.selection node) in
    let run_candidates = List.map matching
        ~f:(fun (at, run, workflow) -> at, (Some run, workflow)) in
    let workflow_candidates =
      List.filter_map workflows ~f:(fun w ->
        if not w.elaboration_only && Option.is_none (run_for w) && matches w.selection
        then Some (w.created, (None, Some w))
        else None)
    in
    let candidates = run_candidates @ workflow_candidates in
    (* Silver's run registry is ordered by last update, not start time. Keep
       reservation time for pre-allocation workflows and do not break ties by
       registry order. A sole legacy match needs no inferred ordering. *)
    (match candidates with
     | [] -> unresolved "No ASIC run matches the active flow/profile"
     | [ _, chosen ] -> found chosen
     | _ ->
       let dated =
         List.filter_map candidates ~f:(fun (at, value) -> Option.map at ~f:(fun at -> at, value))
         |> List.sort ~compare:(fun (a, _) (b, _) -> Time_ns.compare b a)
       in
       (match dated with
        | (at, _) :: (next, _) :: _ when Time_ns.equal at next ->
          unresolved "Latest matching ASIC run is ambiguous"
        | (_, chosen) :: _ -> found chosen
        | [] -> unresolved "Latest matching ASIC run is unavailable (start times not reported)"))
;;

let missing_elaboration =
  { id = "preparation:elaboration"; label = "Elaboration"; origin = Elaboration
  ; status = Unavailable; duration = None
  ; reason = Some "No elaboration workflow is linked to this ASIC run"
  ; launch_destination = None
  }
;;

let requested_endpoint selection =
  let id = Wire.id selection "endpoint" in
  { id; label = String.capitalize id; origin = Requested_endpoint
  ; status = Unconfirmed; duration = None
  ; reason = Some "Captured requested endpoint only; physical stage evidence unavailable"
  ; launch_destination = None
  }
;;

let timing summary =
  let open Wire in
  let status, duration, reason =
    match Option.bind summary ~f:(fun s -> optional s "timing_analysis") with
    | None -> Unknown "not reported", None, Some "No authoritative STA observation"
    | Some analysis ->
      let status =
        match id analysis "status" with
        | "Completed" -> Completed
        | "Unavailable" -> Unavailable
        | status -> Unknown status
      in
      let duration = Option.bind (optional analysis "duration") ~f:(fun d ->
        Option.map (seconds (get d "seconds")) ~f:(fun n -> Measured n)) in
      status, duration, Option.map (optional analysis "reason") ~f:display
  in
  { id = "analysis:post-pnr-sta"; label = "Timing"; origin = Supplementary_timing
  ; status; duration; reason; launch_destination = None }
;;

let checklist run workflow summary =
  let stages = Option.value_map run ~default:[] ~f:(fun r -> r.physical) in
  let selection =
    Option.first_some (Option.bind run ~f:(fun r -> r.selection))
      (Option.bind workflow ~f:(fun w -> Option.some_if (not w.elaboration_only) w.selection))
  in
  let endpoint_only = List.is_empty stages && Option.is_some selection in
  let stages =
    match Option.map selection ~f:requested_endpoint with
    | Some endpoint when not (List.exists stages ~f:(fun s -> String.equal s.id endpoint.id)) ->
      stages @ [ endpoint ]
    | _ -> stages
  in
  let rec add_timing = function
    | [] -> [ timing summary ]
    | s :: rest when String.equal s.id "routing" -> s :: timing summary :: rest
    | s :: _ as stages when String.equal s.id "signoff" -> timing summary :: stages
    | s :: rest -> s :: add_timing rest
  in
  if Option.is_none run && Option.is_none workflow then []
  else
    Option.value_map workflow ~default:missing_elaboration ~f:(fun w -> w.elaboration)
    :: (if Option.is_none run || endpoint_only
           || List.exists stages ~f:(fun s -> String.equal s.id "timing")
        then stages
        else add_timing stages)
;;

type query =
  { snapshot : snapshot
  ; run : run option
  ; live : bool
  ; summary_missing : bool
  ; operations : Sexp.t list
  ; reader_error : string option
  }

let op_active op =
  List.mem [ "reserving"; "pending"; "executing" ] (Wire.id op "state") ~equal:String.equal
;;

let keyed operations key =
  find_unique operations ~f:(fun op -> String.equal (Wire.id op "key") key)
;;

let reader_failed op =
  Option.first_some (Wire.error op)
    (Option.some_if
       (List.mem [ "failed"; "detached" ] (Wire.id op "state") ~equal:String.equal)
       ("Silver ASIC " ^ Wire.id op "kind" ^ " failed"))
;;

let parse subject node =
  let open Wire in
  if not (bool node "configured") then
    { snapshot = { subject; run_id = None; workflow_id = None; process_status = None
                 ; stages = []; summary_freshness = None; notice = Some "Silver ASIC is not configured"
                 ; matching_run_ids = [] }
    ; run = None; live = false; summary_missing = false; operations = []; reader_error = None }
  else (
    let runs = List.filter_map (rows node "runs") ~f:parse_run in
    let workflows = List.map (rows node "workflows") ~f:parse_workflow in
    if List.contains_dup (List.map runs ~f:(fun run -> run.run_id)) ~compare:String.compare
    then invalid "Conflicting Silver ASIC run IDs";
    let matching =
      match subject with
      | Exact_matching_run (scope, _) | Latest_matching scope ->
        matching_runs scope runs workflows
      | No_selection | Exact_run _ | Exact_workflow _ -> []
    in
    let run, workflow, notice = resolve subject runs workflows matching in
    let matching_run_ids = scoped_run_ids matching in
    let summary =
      Option.bind run ~f:(fun run ->
        find_unique (rows node "summaries") ~f:(fun s -> Sexp.equal run.reference (get s "run")))
    in
    let operations = rows node "operations" in
    let reader_error =
      Option.bind run ~f:(fun r ->
        List.find_map [ "observe:"; "refresh:"; "summary:" ] ~f:(fun prefix ->
          Option.bind (keyed operations (prefix ^ r.run_id)) ~f:(fun op ->
            if op_active op then None else reader_failed op)))
    in
    let stages = checklist run workflow summary in
    let notice =
      List.find_map
        [ notice; Option.bind run ~f:(fun r -> r.error); Option.bind workflow ~f:(fun w -> w.error)
        ; reader_error; Option.map (optional node "cache_error") ~f:display
        ; Option.some_if (Option.exists run ~f:(fun r -> List.is_empty r.physical))
            "No physical stage evidence reported for this run"
        ] ~f:Fn.id
    in
    { snapshot =
        { subject; run_id = Option.map run ~f:(fun r -> r.run_id)
        ; workflow_id = Option.map workflow ~f:(fun w -> w.workflow_id)
        ; process_status = Option.first_some (Option.map run ~f:(fun r -> r.process))
                             (Option.map workflow ~f:(fun w -> w.phase))
        ; stages; summary_freshness = Option.map summary ~f:freshness; notice; matching_run_ids
        }
    ; run
    ; live = Option.exists run ~f:run_live || Option.exists workflow ~f:workflow_live
    ; summary_missing = Option.is_none summary
    ; operations; reader_error
    })
;;

type session =
  { project : Silver_overview.Testing.project
  ; subject : subject
  ; stop : unit Ivar.t
  ; mutable wake : unit Ivar.t
  ; mutable probe : Sexp.t option
  ; mutable summary : Sexp.t option
  ; mutable last_run : Sexp.t option
  ; mutable last_observe : Time_ns.t option
  }

type t =
  { poll_interval : Time_ns.Span.t
  ; idle_interval : Time_ns.Span.t
  ; mutable binding : (Silver_overview.Testing.project * subject) option
  ; mutable session : session option
  ; mutable visible : bool
  ; mutable disposed : bool
  ; mutable latest : availability
  ; mutable revision : int
  ; mutable changed : unit Ivar.t
  }

let unbound = Not_available "Connect to a Silver project first"

let create ?(poll_interval = Time_ns.Span.of_sec 1.) ?(idle_interval = Time_ns.Span.of_sec 5.) () =
  if List.exists [ poll_interval; idle_interval ] ~f:(fun span -> Time_ns.Span.(span <= zero))
  then invalid_arg "Silver ASIC observation intervals must be positive";
  { poll_interval; idle_interval; binding = None; session = None; visible = false
  ; disposed = false; latest = unbound; revision = 0; changed = Ivar.create () }
;;

let latest t = t.latest
let revision t = t.revision
let await_change t ~after = if t.revision <> after then Deferred.unit else Ivar.read t.changed

let publish t value =
  if not (Poly.equal t.latest value) then (
    t.latest <- value;
    t.revision <- t.revision + 1;
    Ivar.fill_if_empty t.changed ();
    t.changed <- Ivar.create ())
;;

let schedule_reads session query =
  let open Wire in
  match query.run with
  | None -> None, false
  | Some run ->
    let keys prefixes = List.filter_map prefixes ~f:(fun prefix -> keyed query.operations (prefix ^ run.run_id)) in
    let observe_tasks = keys [ "observe:"; "refresh:" ] in
    let summary_tasks = keys [ "summary:"; "validate-summary:" ] in
    let observe_active = List.exists observe_tasks ~f:op_active in
    let summary_active = List.exists summary_tasks ~f:op_active in
    let owned =
      List.exists query.operations ~f:(fun op ->
        op_active op && String.equal (id op "kind") "run"
        && Option.exists (optional op "run") ~f:(Sexp.equal run.reference))
    in
    let read_allowed = Option.is_none run.error && Option.is_none query.reader_error in
    let timing_ready =
      Option.is_some run.file
      && List.exists run.physical ~f:(fun s ->
        List.mem [ "timing"; "signoff" ] s.id ~equal:String.equal && Poly.equal s.status Completed)
    in
    let same slot = Option.exists slot ~f:(Sexp.equal run.reference) in
    let now = Time_ns.now () in
    let observe_due = Option.value_map session.last_observe ~default:true ~f:(fun last ->
      Time_ns.Span.(Time_ns.diff now last >= of_sec 2.)) in
    let operation =
      if read_allowed && query.summary_missing && not summary_active && not (same session.summary)
         && ((run_terminal run && not owned && not observe_active) || timing_ready)
      then (
        session.summary <- Some run.reference;
        Some (Sexp.List [ atom "Load_summary"; run.reference ]))
      else if read_allowed && not (run_terminal run) && not owned && not observe_active
              && (if run_live run then observe_due
                  else query.summary_missing && not (same session.probe))
      then (
        session.probe <- Some run.reference;
        session.last_observe <- Some now;
        Some (Sexp.List [ atom "Observe"; run.reference ]))
      else None
    in
    operation, (observe_active || summary_active)
;;

let failed t = function
  | Wire.Binding_lost reason -> publish t (Not_available reason)
  | Wire.Read_failed reason ->
    publish t (match t.latest with Fresh s | Stale (s, _) -> Stale (s, reason)
                                  | Not_available _ -> Not_available reason)
;;

let rec loop t session operation =
  let stop = Ivar.read session.stop in
  let active () = not (Deferred.is_determined stop) in
  if not (active ()) then Deferred.unit
  else (
    let%bind result = Wire.request session.project ~stop operation in
    if not (active ()) then Deferred.unit
    else (
      let result = Result.bind result ~f:(fun node -> Wire.decode (fun () -> parse session.subject node)) in
      let next, delay, continue =
        match result with
        | Error reason ->
          failed t reason;
          None, t.idle_interval, (match reason with Wire.Binding_lost _ -> false | _ -> true)
        | Ok query ->
          let run = Option.map query.run ~f:(fun r -> r.reference) in
          if not (Option.equal Sexp.equal session.last_run run) then (
            session.last_run <- run;
            session.probe <- None;
            session.summary <- None;
            session.last_observe <- None);
          (match Wire.decode (fun () ->
            (* Read responses already reflect the queued reader. Give it time to
               settle and do not issue another read on the same response. *)
            match operation with
            | Sexp.Atom "Get" -> schedule_reads session query
            | _ -> None, true) with
           | Error reason ->
             failed t reason;
             None, t.idle_interval, true
           | Ok (next, reader_active) ->
             publish t (Fresh query.snapshot);
             next, (if reader_active || query.live then t.poll_interval else t.idle_interval), true)
      in
      if not continue then Deferred.unit
      else
        match next with
        | Some operation -> loop t session operation
        | None ->
          let%bind () = Deferred.any_unit [ stop; Ivar.read session.wake; Clock_ns.after delay ] in
          session.wake <- Ivar.create ();
          loop t session (Wire.atom "Get")))
;;

let stop t =
  Option.iter t.session ~f:(fun s -> Ivar.fill_if_empty s.stop ());
  t.session <- None
;;

let start t =
  if t.visible then
    Option.iter t.binding ~f:(fun (project, subject) ->
      match subject with
      | No_selection ->
        publish t (Fresh { subject; run_id = None; workflow_id = None; process_status = None
                         ; stages = []; summary_freshness = None; notice = Some "No ASIC run selected"
                         ; matching_run_ids = [] })
      | _ when not (Silver_overview.Testing.supports project "asic") ->
        publish t (Not_available "Silver daemon does not advertise ASIC observation")
      | _ ->
        let session =
          { project; subject; stop = Ivar.create (); wake = Ivar.create (); probe = None
          ; summary = None; last_run = None; last_observe = None }
        in
        t.session <- Some session;
        (* Do not start transport synchronously at binding/visibility boundaries. *)
        upon Deferred.unit (fun () -> don't_wait_for (loop t session (Wire.atom "Get"))))
;;

let bind t project subject =
  if not t.disposed
     && not (Option.exists t.binding ~f:(fun (previous, selected) ->
       phys_equal previous project && Poly.equal selected subject))
  then (
    stop t;
    t.binding <- Some (project, subject);
    publish t (Not_available "Awaiting Silver ASIC observation");
    start t)
;;

let unbind t =
  if not t.disposed then (
    stop t;
    t.binding <- None;
    publish t unbound)
;;

let set_visible t visible =
  if not t.disposed && not (Bool.equal visible t.visible) then (
    t.visible <- visible;
    if visible then (
      (match t.latest with
       | Fresh ({ subject = (Exact_run _ | Exact_matching_run _ | Exact_workflow _ | Latest_matching _); _ } as snapshot) ->
         publish t (Stale (snapshot, "Rechecking Silver ASIC evidence"))
       | _ -> ());
      start t)
    else stop t)
;;

let refresh t =
  Option.iter t.session ~f:(fun session ->
    (* Wake a sleeping reader or request one extra cycle after the pending read. *)
    Ivar.fill_if_empty session.wake ())
;;

let shutdown t =
  if not t.disposed then (
    unbind t;
    t.disposed <- true;
    publish t (Not_available "Silver ASIC observation stopped"))
;;
