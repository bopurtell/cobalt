open! Core
open Async
open Silver_flow

let check result = Result.ok_or_failwith result
let binding project_id : binding =
  { endpoint = "http://127.0.0.1:1234"; project_root = "/fixture"; instance_id = "daemon"; project_id }
;;
let target = { chip = "chipA"; variant = "variantB" }
let default = "quick"
let explicit = "balanced"
let flow =
  { id = "main"; label = "Main"; profiles = [ default; explicit ]; default_profile = default
  ; stages =
      [ { id = "synth-row"; label = "Synthesis"; alias = Some Synth; endpoint = Available "compile" }
      ; { id = "timing-row"; label = "Timing"; alias = Some Timing; endpoint = Available "analyze" }
      ; { id = "route-row"; label = "Routing"; alias = Some Routing; endpoint = Unavailable "No routing here" }
      ]
  ; kickoff = Available { endpoints = [ "compile"; "analyze" ]; default_endpoint = Some "compile"
                        ; parameters = [ { key = "area"; label = "Area"; default = Some "low"; choices = [ "low"; "high" ] } ] }
  }
;;
let catalog : catalog = { target = Some target; flows = [ flow ]; default_flow = Some ("main", default); stage_launch = Available () }
let view session = check (catalog_view session)
let draft session = check (draft session (view session) ~flow:"main")
let timings session = check (resolve_alias session (view session) Timing)
let ready session = match preparation session with Ready ready -> ready | _ -> failwith "expected ready preview"
let blocked = function Stale _ | Rejected _ -> true | _ -> false
let string_equal = [%equal: string]

let model () =
  let t = create () in
  let staging = Queue.create () in
  let submissions = Queue.create () in
  let delayed_plan = ref None and delayed_ack = ref None in
  let service project_id =
    { binding = binding project_id
    ; catalog = (fun () -> return (Ok catalog))
    ; prepare = (fun request ->
        Queue.enqueue staging request;
        let inputs = match request with Stage i | Kickoff i -> i in
        let on_submit ~still_current =
          assert (still_current ());
          Queue.enqueue submissions (project_id, inputs);
          match !delayed_ack with
          | None -> return (Unconfirmed "lost")
          | Some ivar -> Ivar.read ivar
        in
        let prepared = { preview = { identity = "reviewed"; inputs }; submit = on_submit } in
        match !delayed_plan with
        | None -> return (Ok prepared)
        | Some ivar -> Ivar.read ivar >>| fun () -> Ok prepared)
    }
  in
  bind t (service "one");
  let%bind () = refresh t in
  let first_view = view t in
  let synthesis = check (resolve_alias t first_view Synth) in
  assert (String.equal (stage_inputs synthesis).endpoint "compile");
  assert (Result.is_error (resolve_alias t first_view Routing));
  let d = draft t in
  assert (List.equal [%equal: string * string] (draft_inputs d).assignments [ "area", "low" ]);
  let invalid = edit d { (draft_inputs d) with assignments = [ "area", "unknown" ] } in
  assert (Result.is_error (apply t invalid));
  let edited = edit d { (draft_inputs d) with profile = explicit; assignments = [ "area", "high" ] } in
  assert (Queue.is_empty staging);
  check (apply t edited);
  let%bind stale = launch_stage t synthesis in
  assert (blocked stale && Queue.is_empty staging);
  let row = check (resolve_stage t first_view ~id:"timing-row") in
  let alias = check (resolve_alias t first_view Timing) in
  assert (equal_stage_intent row alias);
  let inputs = stage_inputs alias in
  assert (String.equal inputs.profile explicit && String.equal inputs.endpoint "analyze");
  assert (List.equal [%equal: string * string] inputs.assignments [ "area", "high" ]);
  let%bind outcome = launch_stage t row in
  assert (match outcome with Unconfirmed _ -> true | _ -> false);
  let%bind replay = launch_stage t alias in
  assert (blocked replay && Queue.length submissions = 1);
  let%bind () = prepare t in
  assert (Queue.length submissions = 1);
  let old_ready = ready t in
  assert (String.equal (preview old_ready).inputs.profile explicit);
  check (apply t edited);
  let%bind stale = kickoff t old_ready in
  assert (blocked stale && Queue.length submissions = 1);
  let planning_gate = Ivar.create () in
  delayed_plan := Some planning_gate;
  let planning = prepare t in
  bind t (service "two");
  let%bind () = refresh t in
  Ivar.fill_exn planning_gate ();
  let%bind () = planning in
  assert (match preparation t with Not_prepared _ -> true | _ -> false);
  delayed_plan := None;
  let ack_gate = Ivar.create () in
  delayed_ack := Some ack_gate;
  let d = draft t in
  check (apply t d);
  let%bind () = prepare t in
  let captured = ready t in
  let kicking = kickoff t captured in
  let%bind duplicate = kickoff t captured in
  assert (blocked duplicate);
  bind t (service "three");
  let%bind () = refresh t in
  let%bind current_result =
    delayed_ack := None;
    launch_stage t (timings t)
  in
  Ivar.fill_exn ack_gate (Accepted (Run "old-run"));
  let%bind old_result = kicking in
  assert (match old_result with Accepted (Run "old-run") -> true | _ -> false);
  assert (match submission t, current_result with Finished (_, Unconfirmed _), Unconfirmed _ -> true | _ -> false);
  assert (Queue.length submissions = 3);
  let%bind () = refresh t in
  let old = timings t in
  let gate = Ivar.create () in
  delayed_plan := Some gate;
  let pending_stage = launch_stage t old in
  let%bind () = refresh t in
  Ivar.fill_exn gate ();
  let%bind outcome = pending_stage in
  assert (blocked outcome && Queue.length submissions = 3);
  assert (Result.is_ok (catalog_view t));
  Deferred.unit
;;

module X = struct
  let a s = Sexp.Atom s
  let l xs = Sexp.List xs
  let r xs = l (List.map xs ~f:(fun (key, value) -> l [ a key; value ]))
  let o = function None -> l [] | Some x -> l [ x ]
  let field x name =
    match x with
    | Sexp.Atom _ -> failwith "expected record"
    | Sexp.List xs ->
      List.find_map_exn xs ~f:(function
        | Sexp.List [ Sexp.Atom key; value ] when String.equal key name -> Some value
        | _ -> None)
  ;;
  let text = function Sexp.Atom text -> text | _ -> failwith "expected atom"
  let reply node : Silver_overview.response = { status = 200; body = Sexp.to_string_mach node }
  let ok node = Ok (reply (l [ a "Ok"; node ]))
end

let wire () =
  let open X in
  let calls = Queue.create () in
  let selection =
    r [ "flow", a "main"; "profile", a "quick"; "endpoint", a "synthesis"
      ; "assignments", l [ a "area=high" ]
      ; "chip_target", o (Some (r [ "chip", a target.chip; "variant", a target.variant ])) ]
  in
  let stage_selection =
    r [ "flow", a "main"; "profile", a "quick"; "endpoint", a "timing"
      ; "assignments", l []
      ; "chip_target", field selection "chip_target" ]
  in
  let identity = String.make 64 '7' in
  let raw_description = {|
      {"contract":"hardcaml-asic.flow-describe","schema_version":1,
       "capabilities":{"stage_selection":"complete-prefix-through-declared-endpoint","arbitrary_overrides":false},
       "entry":{"methodology":{"id":"main","label":"Fixture main","endpoints":["synthesis","timing","routing"],"defaults":[{"key":"area","value":"low"}],"configurable":["area"]},
                "profiles":[{"id":"quick","assignments":[]}],"default_profile":"quick"},
       "parameter_descriptors":[{"key":"area","type":"enum","allowed_values":["low","high"]}]} |}
  in
  let raw_plan =
    sprintf {| {"contract":"hardcaml-asic.methodology-plan","schema_version":1,
      "plan_identity":"%s","methodology":{"snapshot":{"contract":"hardcaml-asic.flow-snapshot","schema_version":1,
      "selected":{"flow":"main","profile":"quick"},"endpoint":"synthesis","request":[{"key":"area","value":"high"}]},
      "effective_parameters":[{"winning":{"assignment":{"key":"area","value":"high"}}},
                              {"winning":{"assignment":{"key":"clock_opt","value":true}}}]}} |} identity
  in
  let exact_preview = r [ "selection", selection; "plan_identity", a identity; "plan_json", a raw_plan ] in
  let intent expected_plan_identity selection =
    r [ "id", a "stage-receipt"; "selection", selection; "elaboration_only", a "false"
      ; "expected_plan_identity", o (Option.map expected_plan_identity ~f:a) ]
  in
  let workflow ~key ~run intent =
    r [ "key", key; "id", a "exact-workflow"; "intent", intent
      ; "run", o (Option.map run ~f:(fun id -> r [ "id", a id; "backend", a "asic" ])) ]
  in
  let task ~key ~kind = r [ "key", a key; "kind", a kind; "state", a "pending" ] in
  let snapshot ?(operations = []) ?description ?preview ?fresh ?(workflows = []) () =
    ok (r [ "configured", a "true"; "chip_target", field selection "chip_target"
          ; "flows", l [ r [ "id", a "main"; "profiles", l [ a "quick" ]; "default_profile", a "quick"
                           ; "fresh_stage_endpoints", l [ a "synthesis"; a "timing" ] ] ]
          ; "catalog_default", o (Some (r [ "flow", a "main"; "profile", a "quick" ]))
          ; "operations", l operations; "description_json", o (Option.map description ~f:a)
          ; "preview", o preview; "fresh_intent", o fresh; "workflows", l workflows ])
  in
  let next_get = ref (snapshot ()) in
  let expected = Queue.of_list
      [ "Get"; "Discover"; "Get"; "Describe"; "Get"
      ; "Get"; "Stage_fresh"; "Get"; "Launch_fresh"
       ; "Get"; "Plan"; "Get"; "Get"; "Run"
      ; "Get"; "Stage_fresh"; "Get"; "Launch_fresh"
      ; "Get"; "Stage_fresh"; "Get"
      ]
  in
  let launches = ref 0 in
  let advertised = ref true in
  let peer ~endpoint:_ ~timeout:_ ~stop:_ (request : Silver_overview.request) =
    Queue.enqueue calls request.path;
    return
      (match request.path with
       | "/api/hello" ->
         let capabilities =
           [ "simulation" ]
           @ (if !advertised then [ "asic"; "source-bundle-preparation-v1" ] else [])
         in
         Ok (reply (r [ "application_version", a "fixture"; "protocol_versions", l [ a "1" ]
                      ; "instance_id", a "daemon"; "capabilities", l (List.map capabilities ~f:a) ]))
       | "/api/v1/open-project" ->
         ok (r [ "project", r [ "id", a "project"; "root", r [ "path", a "/fixture" ] ] ])
       | path ->
         assert (List.mem request.headers ("X-Workbench-Protocol", "1") ~equal:[%equal: string * string]);
         let body = Sexp.of_string request.body in
         assert (Sexp.equal (field body "instance_id") (a "daemon"));
         assert (Sexp.equal (field body "project") (a "project"));
         let op =
           match path, field body "operation" with
           | "/api/v1/preparation", (Sexp.Atom "Get" as op) -> op
            | "/api/v1/asic", Sexp.List (Sexp.Atom "In_context" :: fields) ->
              let context = l fields in
             assert (Sexp.equal (field context "context") (a "cobalt-companion-v1"));
             assert (Sexp.equal (field context "initial_target") (l []));
             field context "operation"
           | _ -> failwith "unexpected Silver request"
         in
         if String.equal path "/api/v1/preparation"
         then ok (r [ "availability", a "Available" ])
         else (
           let tag = match op with Sexp.List (head :: _) -> text head | Sexp.Atom s -> s | _ -> assert false in
           assert (string_equal tag (Queue.dequeue_exn expected));
           match op with
            | Sexp.Atom "Get" ->
              let response = !next_get in
              if not (Option.value_map (Queue.peek expected) ~default:false ~f:(String.equal "Get"))
              then next_get := snapshot ();
              response
           | Sexp.Atom "Discover" ->
             next_get := snapshot ();
             snapshot ~operations:[ task ~key:"discover" ~kind:"discover" ] ()
           | Sexp.List [ Sexp.Atom "Describe"; Sexp.Atom "main" ] ->
             next_get := snapshot ~description:raw_description ();
             let key = "describe-chip:" ^ Sexp.to_string_mach (l [ r [ "chip", a target.chip; "variant", a target.variant ]; a "main" ]) in
             snapshot ~operations:[ task ~key ~kind:"describe" ] ()
            | Sexp.List (Sexp.Atom "Stage_fresh" :: fields) ->
              let record = l fields in
             assert (Sexp.equal (field record "selection") stage_selection);
             assert (Sexp.equal (field record "elaboration_only") (a "false"));
             assert (Sexp.equal (field record "expected_plan_identity") (l []));
             let staged = intent None stage_selection in
             next_get := (if !launches = 2 then snapshot () else snapshot ~fresh:staged ());
             snapshot ~fresh:staged ()
            | Sexp.List (Sexp.Atom "Launch_fresh" :: fields) ->
              let record = l fields in
             assert (Sexp.equal (field record "intent_id") (a "stage-receipt"));
             incr launches;
             if !launches = 2
             then Error "connection lost"
             else snapshot ~workflows:[ workflow ~key:(field record "key") ~run:None (intent None stage_selection) ] ()
           | Sexp.List [ Sexp.Atom "Plan"; submitted ] ->
             assert (Sexp.equal submitted selection);
             next_get := snapshot ~preview:exact_preview ();
             snapshot ~operations:[ task ~key:"plan:fixture" ~kind:"plan" ] ()
            | Sexp.List (Sexp.Atom "Run" :: fields) ->
              let record = l fields in
             assert (Sexp.equal (field record "preview") exact_preview);
             snapshot ~workflows:[ workflow ~key:(field record "key") ~run:(Some "allocated-run") (intent (Some identity) selection) ] ()
           | _ -> failwith "unexpected native operation"))
  in
  let%bind project =
    Silver_overview.Testing.connect ~peer ~endpoint:"http://127.0.0.1:1234" ~project_root:"/fixture" ()
  in
  let project = check project in
  let t = create () in
  bind t (production project);
  let%bind () = refresh t in
  let view = view t in
  assert (Result.is_error (resolve_alias t view Routing)); (* Describe cannot invent a missing executable endpoint. *)
  let%bind accepted = launch_stage t (timings t) in
  assert (match accepted with Accepted (Workflow { workflow_id = "exact-workflow"; run_id = None }) -> true | _ -> false);
  let d = draft t in
  check (apply t (edit d { (draft_inputs d) with assignments = [ "area", "high" ] }));
  let%bind () = prepare t in
  let ready = ready t in
  assert (String.equal (preview ready).identity identity);
  assert (List.equal [%equal: string * string] (preview ready).inputs.assignments [ "area", "high"; "clock_opt", "true" ]);
  let%bind accepted = kickoff t ready in
  assert (match accepted with Accepted (Workflow { run_id = Some "allocated-run"; _ }) -> true | _ -> false);
  (* Clear kickoff settings explicitly to use the declared stage defaults. *)
  check (set_stage_inputs t view None);
  let stage = timings t in
  let%bind uncertain = launch_stage t stage in
  assert (match uncertain with Unconfirmed _ -> true | _ -> false);
  let%bind stale = launch_stage t stage in
  assert (blocked stale && !launches = 2);
  let%bind superseded = launch_stage t (timings t) in
  assert (blocked superseded && !launches = 2 && Queue.is_empty expected);
  assert (not (Queue.exists calls ~f:(String.equal "/api/v1/simulation")));
  Silver_overview.Testing.close project;
  advertised := false;
  let%bind legacy =
    Silver_overview.Testing.connect ~peer ~endpoint:"http://127.0.0.1:1234" ~project_root:"/fixture" ()
  in
  let legacy = check legacy in
  let before = Queue.length calls in
  bind t (production legacy);
  let%map () = refresh t in
  assert (Result.is_error (catalog_view t) && Queue.length calls = before);
  Silver_overview.Testing.close legacy
;;

let () =
  don't_wait_for
    (match%map Clock.with_timeout (Time_float.Span.of_sec 10.) (model () >>= wire) with
     | `Result () -> Shutdown.shutdown 0
     | `Timeout -> failwith "Silver flow fixtures timed out");
  never_returns (Scheduler.go ())
;;
