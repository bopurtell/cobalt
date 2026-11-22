open! Core
open Async
module Observation = Silver_stage_observation

type pending =
  { request : Silver_overview.request
  ; response : (Silver_overview.response, string) Result.t Ivar.t
  ; stop : unit Deferred.t
  }

let sexp = Sexp.of_string
let render = Sexp.to_string_mach
let span = Time_ns.Span.of_int_ms
let atom s = Sexp.Atom s
let list xs = Sexp.List xs
let record fields = list (List.map fields ~f:(fun (key, value) -> list [ atom key; value ]))
let opt = function None -> list [] | Some node -> list [ node ]
let at day =
  Time_ns.Alternate_sexp.sexp_of_t (Time_ns.of_string_with_utc_offset
    (sprintf "2026-01-%02dT00:00:00Z" day))
;;

let reference ?(backend = "asic") id =
  record [ "backend", atom backend; "id", atom id; "build", list []; "label", list [] ]
;;

let selection ?(variant = "v1") ?(profile = "balanced") ?(endpoint = "signoff")
    ?(assignments = []) ?(legacy = false) () =
  record
    ([ "flow", atom "standard"; "profile", atom profile; "endpoint", atom endpoint
     ; "assignments", list (List.map assignments ~f:atom)
     ]
     @ if legacy then [] else
         [ "chip_target", opt (Some (record [ "chip", atom "chip"; "variant", atom variant ])) ])
;;

let stage ?timing ?action ?(has_action_field = true) id status =
  record
    ([ "id", atom id; "name", atom (String.capitalize id); "status", sexp status
     ; "requested", atom "true"; "reason", list []; "execution_timing", opt timing
     ]
     @ if has_action_field then [ "action", opt action ] else [])
;;

let timing ?started ?seconds running =
  record [ "started_at", opt started; "measured_seconds", opt (Option.map seconds ~f:Float.sexp_of_t)
         ; "running", Bool.sexp_of_t running ]
;;

let run ?started ?(status = "completed") ?(backend = "asic")
    ?(selected = selection ()) ?(stages = []) id =
  record
    [ "run", reference ~backend id; "selection", opt (Some selected)
    ; "execution_timing", opt (Option.map started ~f:(fun started -> timing ~started false))
    ; "status", atom status; "stages", list stages; "error", list []
    ; "execution_file", opt (Some (atom "/fixture/run"))
    ]
;;

let workflow ?run_id ?started ?finished ?job ?(cancel_requested = false)
    ~phase ~elaboration_status id =
  record
    [ "id", atom id; "phase", atom phase; "created_at", at 5
    ; "cancel_requested", Bool.sexp_of_t cancel_requested
    ; "elaboration_status", atom elaboration_status; "elaboration_started_at", opt started
    ; "elaboration_finished_at", opt finished
    ; "build_job", opt (Option.map job ~f:(fun state -> record [ "state", atom state ]))
    ; "run", opt (Option.map run_id ~f:(reference ?backend:None)); "error", list []
    ; "intent", record [ "elaboration_only", atom "false"; "selection", selection () ]
    ]
;;

let operation ?run_id ~key ~kind state =
  record
    [ "key", atom key; "kind", atom kind; "state", atom state; "error", list []
    ; "run", opt (Option.map run_id ~f:(reference ?backend:None))
    ]
;;

let summary ?timing_status ~freshness id =
  let analysis = Option.map timing_status ~f:(fun status ->
    record
      [ "status", atom status; "reason", list []
      ; "duration", opt (Some (record [ "seconds", atom "0.5" ]))
      ]) in
  record [ "run", reference id; "freshness", sexp freshness; "timing_analysis", opt analysis ]
;;

let snapshot ?(runs = []) ?(workflows = []) ?(summaries = []) ?(operations = []) () =
  list [ atom "Ok"; record
           [ "configured", atom "true"; "runs", list runs; "workflows", list workflows
           ; "summaries", list summaries; "operations", list operations
           ] ]
;;

let respond pending body =
  Ivar.fill_exn pending.response (Ok { Silver_overview.status = 200; body = render body })
;;

let timeout deferred =
  match%map Clock_ns.with_timeout (span 2000) deferred with
  | `Result x -> x
  | `Timeout -> failwith "Expected ASIC observation progress"
;;

let wait observer accept =
  timeout (let rec next () =
    let before = Observation.revision observer in
    match accept (Observation.latest observer) with
    | Some x -> return x
    | None -> Observation.await_change observer ~after:before >>= next
  in
  next ())
;;

let fresh observer f = wait observer (function Observation.Fresh s -> f s | _ -> None)

let fresh_run observer expected =
  fresh observer (fun s ->
    Option.some_if (Option.equal String.equal s.run_id expected) s)
;;

let row (snapshot : Observation.snapshot) id =
  List.find_exn snapshot.stages ~f:(fun s -> String.equal s.id id)
;;

let catalog_scope : Observation.selection =
  { target = Some { chip = "chip"; variant = "v1" }; flow = "standard"; profile = "balanced" }
;;

let test () =
  let requests, writer = Pipe.create () in
  let peer ~endpoint:_ ~timeout:_ ~stop request =
    match request.Silver_overview.path with
    | "/api/hello" ->
      return (Ok { Silver_overview.status = 200
                 ; body = "((instance_id daemon) (protocol_versions (1)) (capabilities (simulation asic)))" })
    | "/api/v1/open-project" ->
      let fields = [%of_sexp: (string * Sexp.t) list] (sexp request.body) in
      let root = List.Assoc.find_exn fields "root" ~equal:String.equal in
      return (Ok { Silver_overview.status = 200
                 ; body = render (list [ atom "Ok"; record
                     [ "project", record [ "id", root; "root", record [ "path", root ] ] ] ]) })
    | "/api/v1/asic" ->
      let response = Ivar.create () in
      Pipe.write_without_pushback writer { request; response; stop };
      Ivar.read response (* Intentionally returns a late response after local stop. *)
    | other -> failwith ("Unexpected request " ^ other)
  in
  let connect project_root =
    match%map Silver_overview.Testing.connect ~peer ~endpoint:"http://127.0.0.1:9123" ~project_root () with
    | Ok project -> project
    | Error reason -> failwith reason
  in
  let next ?(project = "/fixture") expected =
    match%map timeout (Pipe.read requests) with
    | `Eof -> assert false
    | `Ok pending ->
      let fields = [%of_sexp: (string * Sexp.t) list] (sexp pending.request.body) in
      let get key = List.Assoc.find_exn fields key ~equal:String.equal in
      assert (Sexp.equal (get "instance_id") (atom "daemon"));
      assert (Sexp.equal (get "project") (atom project));
      assert (Sexp.equal (get "operation") expected);
      let header key value =
        Option.equal String.equal
          (List.Assoc.find pending.request.headers key ~equal:String.equal) (Some value)
      in
      assert (header "X-Workbench-Execution-Timing" "1");
      assert (header "X-Workbench-Asic-Timing-Analysis" "2");
      pending
  in
  let%bind project = connect "/fixture" in
  let%bind replacement = connect "/replacement" in
  let observer = Observation.create ~poll_interval:(span 35) ~idle_interval:(span 150) () in
  Observation.bind observer project (Latest_matching catalog_scope);
  let%bind () = Clock_ns.after (span 40) in
  assert (Pipe.length requests = 0);
  Observation.set_visible observer true;
  let%bind initial = next (atom "Get") in
  let older = run ~started:(at 1) ~stages:[ stage "routing" "Failed" ] "older" in
  let latest = run ~started:(atom "2026-01-02T00:00:00Z") ~status:"running"
      ~stages:
        [ stage ~timing:(timing ~started:(at 2) true) "routing" "Running"
            ~action:(selection ~endpoint:"route-mapped" ~assignments:[ "HISTORICAL=true" ] ())
        ; stage "synthesis" "Pending"
            ~action:(selection ~variant:"other" ~profile:"other" ~endpoint:"synthesis" ())
        ; stage "floorplan" "Unsupported"
        ; stage "legacy-row" "Pending"
            ~action:(selection ~legacy:true ~endpoint:"legacy-endpoint" ())
        ; stage "cts" "Pending" ~has_action_field:false
        ] "latest" in
  let other_variant = run ~started:(at 3) ~selected:(selection ~variant:"other" ()) "other-variant" in
  let other_profile = run ~started:(at 4) ~selected:(selection ~profile:"other" ()) "other-profile" in
  let simulation = run ~backend:"simulation" ~started:(at 5) "test-attempt" in
  let active = operation ~run_id:"latest" ~key:"run:owned" ~kind:"run" "executing" in
  respond initial (snapshot ~runs:[ older; other_variant; other_profile; simulation; latest ]
                     ~operations:[ active ] ());
  let%bind first = fresh_run observer (Some "latest") in
  assert (List.equal String.equal first.matching_run_ids [ "latest"; "older" ]);
  let routing = row first "routing" in
  assert (Poly.equal routing.status Running);
  assert (match routing.duration with Some (Since _) -> true | _ -> false);
  assert (Poly.equal routing.launch_destination (Some (catalog_scope, "route-mapped")));
  let other_scope : Observation.selection =
    { target = Some { chip = "chip"; variant = "other" }; flow = "standard"; profile = "other" }
  in
  (* A mismatched action must remain explicit so it cannot become a legacy ID match. *)
  assert (Poly.equal (row first "synthesis").launch_destination (Some (other_scope, "synthesis")));
  assert (Option.is_none (row first "floorplan").launch_destination);
  assert (Option.is_none (row first "cts").launch_destination);
  assert (Poly.equal (row first "legacy-row").launch_destination
            (Some ({ catalog_scope with target = None }, "legacy-endpoint")));
  assert (Poly.equal (row first "signoff").status Unconfirmed);
  assert (Poly.equal (row first "analysis:post-pnr-sta").origin Supplementary_timing);
  assert (Poly.equal (row first "preparation:elaboration").status Unavailable);
  List.iter [ "signoff"; "analysis:post-pnr-sta"; "preparation:elaboration" ] ~f:(fun id ->
    assert (Option.is_none (row first id).launch_destination));
  (* A visible running run progresses even with no new input or change notification. *)
  let%bind poll = next (atom "Get") in
  respond poll (snapshot ~runs:[ latest; older ] ());
  let%bind observe = next (list [ atom "Observe"; reference "latest" ]) in
  let finished = run ~started:(at 2)
      ~stages:[ stage ~timing:(timing ~seconds:0. false) "routing" "Completed"
              ; stage "signoff" "Cancelled" ] "latest" in
  respond observe (snapshot ~runs:[ finished ] ());
  let%bind completed = fresh observer (fun s ->
    Option.some_if (Poly.equal (row s "routing").status Completed) s) in
  assert (Poly.equal (row completed "routing").duration (Some (Measured 0.)));
  assert (Poly.equal (row completed "signoff").status Cancelled);
  let%bind poll = next (atom "Get") in
  respond poll (snapshot ~runs:[ finished ] ());
  let%bind summary_read = next (list [ atom "Load_summary"; reference "latest" ]) in
  let wrong_summary = summary ~timing_status:"Completed" ~freshness:"Validated" "older" in
  let saved_summary = summary ~timing_status:"Completed" ~freshness:"Missing_source" "latest" in
  let hot = snapshot ~runs:[ finished ] ~summaries:[ wrong_summary; saved_summary ] () in
  respond summary_read hot;
  let%bind with_summary = fresh observer (fun s ->
    Option.some_if (Poly.equal s.summary_freshness (Some Missing_source)) s) in
  assert (Poly.equal (row with_summary "analysis:post-pnr-sta").duration (Some (Measured 0.5)));
  let%bind failing = next (atom "Get") in
  Ivar.fill_exn failing.response (Error "offline");
  let%bind () = wait observer (function
    | Stale (s, _) when Option.equal String.equal s.run_id (Some "latest") -> Some ()
    | _ -> None) in
  Observation.refresh observer;
  let%bind recovering = next (atom "Get") in
  respond recovering hot;
  let%bind _ = fresh_run observer (Some "latest") in
  Observation.refresh observer;
  let%bind late = next (atom "Get") in
  Observation.bind observer replacement (Exact_run "missing");
  let%bind () = timeout late.stop in
  let%bind new_request = next ~project:"/replacement" (atom "Get") in
  respond late hot;
  respond new_request (snapshot ~runs:[ finished; older ] ());
  let%bind missing = fresh_run observer None in
  assert (List.is_empty missing.stages);
  assert (Option.equal String.equal missing.notice (Some "Selected ASIC run unavailable: missing"));
  Observation.bind observer replacement (Exact_matching_run (catalog_scope, "other-variant"));
  let%bind scoped_request = next ~project:"/replacement" (atom "Get") in
  respond scoped_request (snapshot ~runs:[ other_variant; older; finished ] ());
  let%bind mismatched_pin = fresh_run observer None in
  assert (List.is_empty mismatched_pin.stages);
  assert (List.equal String.equal mismatched_pin.matching_run_ids [ "latest"; "older" ]);
  Observation.bind observer replacement (Exact_matching_run (catalog_scope, "older"));
  let%bind scoped_request = next ~project:"/replacement" (atom "Get") in
  let cached = summary ~freshness:"Validated" "older" in
  respond scoped_request (snapshot ~runs:[ other_variant; older; finished ] ~summaries:[ cached ] ());
  let%bind pinned = fresh_run observer (Some "older") in
  assert (Poly.equal (row pinned "routing").status Failed);
  Observation.bind observer replacement (Exact_workflow "workflow");
  let%bind request = next ~project:"/replacement" (atom "Get") in
  let building ?job ?(cancel_requested = false) () =
    workflow ?job ~cancel_requested ~started:(at 5) ~phase:"Building" ~elaboration_status:"building" "workflow"
  in
  respond request (snapshot ~runs:[ finished ] ~workflows:[ building () ] ());
  let%bind queued = fresh_run observer None in
  assert (Poly.equal (row queued "preparation:elaboration").status Pending);
  assert (Poly.equal (row queued "signoff").status Unconfirmed);
  let%bind request = next ~project:"/replacement" (atom "Get") in
  respond request (snapshot ~workflows:[ building ~job:"Running" () ] ());
  let%bind running = fresh observer (fun s ->
    Option.some_if (Poly.equal (row s "preparation:elaboration").status Running) s) in
  assert (match (row running "preparation:elaboration").duration with Some (Since _) -> true | _ -> false);
  let%bind request = next ~project:"/replacement" (atom "Get") in
  respond request (snapshot ~workflows:[ building ~job:"Running" ~cancel_requested:true () ] ());
  let%bind _ = fresh observer (fun s ->
    Option.some_if (Poly.equal (row s "preparation:elaboration").status Cancelling) s) in
  let%bind request = next ~project:"/replacement" (atom "Get") in
  let linked = workflow ~run_id:"new" ~started:(at 4) ~finished:(at 5)
      ~phase:"Physical" ~elaboration_status:"completed" "workflow" in
  let new_run = run ~started:(at 5) ~status:"running"
      ~stages:[ stage "timing" "Interrupted" ] "new" in
  let owned = operation ~run_id:"new" ~key:"run:new" ~kind:"run" "executing" in
  respond request (snapshot ~runs:[ finished; new_run ] ~workflows:[ linked ] ~operations:[ owned ] ());
  let%bind physical = fresh_run observer (Some "new") in
  assert (Poly.equal (row physical "preparation:elaboration").status Completed);
  assert (Poly.equal (row physical "timing").status Interrupted);
  assert (not (List.exists physical.stages ~f:(fun s -> Poly.equal s.origin Supplementary_timing)));
  let%bind hidden = next ~project:"/replacement" (atom "Get") in
  Observation.set_visible observer false;
  let%bind () = timeout hidden.stop in
  let before = Observation.revision observer in
  respond hidden hot;
  let%bind () = Clock_ns.after (span 80) in
  assert (Pipe.length requests = 0);
  assert (Observation.revision observer = before);
  Observation.set_visible observer true;
  let%bind restart = next ~project:"/replacement" (atom "Get") in
  respond restart (sexp "(Error ((kind Instance_changed) (message replaced)))");
  let%bind () = wait observer (function Not_available _ -> Some () | _ -> None) in
  Observation.bind observer project No_selection;
  let%bind unselected = fresh_run observer None in
  assert (List.is_empty unselected.stages);
  assert (Option.equal String.equal unselected.notice (Some "No ASIC run selected"));
  let%bind () = Clock_ns.after (span 60) in
  assert (Pipe.length requests = 0);
  Observation.shutdown observer;
  Silver_overview.Testing.close project;
  Silver_overview.Testing.close replacement;
  return ()
;;

let () =
  don't_wait_for (let%map () = test () in Shutdown.shutdown 0);
  never_returns (Scheduler.go ())
;;
