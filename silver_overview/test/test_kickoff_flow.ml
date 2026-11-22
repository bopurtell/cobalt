open! Core
open Async
module Flow = Silver_flow

let binding project_id : Flow.binding =
  { endpoint = "http://127.0.0.1:7777"
  ; project_root = "/projects/" ^ project_id
  ; instance_id = "fixture"
  ; project_id
  }
;;

let catalog : Flow.catalog =
  { target = Some { chip = "chip"; variant = "std" }
  ; flows =
      [ { id = "named"
        ; label = "Named flow"
        ; profiles = [ "debug"; "release" ]
        ; default_profile = "debug"
        ; stages = []
        ; kickoff =
            Available
              { endpoints = [ "place"; "signoff" ]
              ; default_endpoint = Some "place"
              ; parameters =
                  [ { key = "frequency"; label = "Frequency"; default = Some "100"
                    ; choices = [ "100"; "200" ]
                    }
                  ]
              }
        }
      ]
  ; default_flow = Some ("named", "debug")
  ; stage_launch = Unavailable "No stages"
  }
;;

let service project ~prepare : Flow.service =
  { binding = binding project; catalog = (fun () -> return (Ok catalog)); prepare }
;;

let get = function Ok value -> value | Error reason -> failwith reason
let choose flow = Flow.draft flow (get (Flow.catalog_view flow)) ~flow:"named" |> get
let reviewed flow = match Flow.preparation flow with Ready value -> value | _ -> assert false

let test () =
  let flow = Flow.create () in
  let planning = Ivar.create () in
  let request = Ivar.create () in
  let preparations = ref 0 in
  let submitted = ref [] in
  let prepare inputs =
    incr preparations;
    Ivar.fill_if_empty request inputs;
    Ivar.read planning
  in
  Flow.bind flow (service "first" ~prepare);
  let%bind () = Flow.refresh flow in
  let defaults = choose flow in
  let inputs = Flow.draft_inputs defaults in
  assert (String.equal inputs.profile "debug");
  assert (String.equal inputs.endpoint "place");
  assert ([%equal: (string * string) list] inputs.assignments [ "frequency", "100" ]);
  let invalid_field assignments = Flow.edit defaults { inputs with assignments } in
  List.iter [ [ "frequency", "999" ]; [ "unknown", "100" ] ] ~f:(fun assignments ->
    assert (Result.is_error (Flow.apply flow (invalid_field assignments))));
  assert (Result.is_error (Flow.apply flow (Flow.edit defaults { inputs with endpoint = "unknown" })));
  assert (!preparations = 0 && List.is_empty !submitted);
  let edited = { inputs with profile = "release"; endpoint = "signoff"; assignments = [ "frequency", "200" ] } in
  get (Flow.apply flow (Flow.edit defaults edited));
  assert (!preparations = 0);
  let old_plan = Flow.prepare flow in
  let%bind actual = Ivar.read request in
  (match actual with
   | Kickoff actual ->
     assert (String.equal actual.profile "release");
     assert (String.equal actual.endpoint "signoff");
     assert ([%equal: (string * string) list] actual.assignments edited.assignments)
   | Stage _ -> assert false);
  assert (List.is_empty !submitted);
  let ack = Ivar.create () in
  let prepared id (inputs : Flow.inputs) : Flow.prepared =
    let inputs = { inputs with assignments = inputs.assignments @ [ "corner", "slow" ] } in
    { preview = { identity = id; inputs }
    ; submit = (fun ~still_current ->
        assert (still_current ());
        submitted := (id, inputs) :: !submitted;
        Ivar.read ack)
    }
  in
  let fail_preparation = ref true in
  let prepare_new = function
    | Flow.Kickoff _ when !fail_preparation -> return (Error "Fixture preparation failed")
    | Kickoff inputs -> return (Ok (prepared "new-plan" inputs))
    | Stage _ -> assert false
  in
  Flow.bind flow (service "second" ~prepare:prepare_new);
  let%bind () = Flow.refresh flow in
  assert (Result.is_error (Flow.apply flow defaults));
  Ivar.fill_exn planning (Ok (prepared "obsolete" edited));
  let%bind () = old_plan in
  (match Flow.preparation flow with Not_prepared _ -> () | _ -> assert false);
  get (Flow.apply flow (Flow.edit (choose flow) edited));
  let%bind () = Flow.prepare flow in
  (match Flow.preparation flow with Not_prepared "Fixture preparation failed" -> () | _ -> assert false);
  assert (List.is_empty !submitted);
  fail_preparation := false;
  let%bind () = Flow.prepare flow in
  let preview = reviewed flow in
  assert (String.equal (Flow.preview preview).identity "new-plan");
  assert (List.is_empty !submitted);
  let response = Flow.kickoff flow preview in
  let%bind duplicated = Flow.kickoff flow preview in
  (match duplicated with Stale _ -> () | _ -> assert false);
  Ivar.fill_exn ack (Flow.Unconfirmed "lost reply");
  let%bind outcome = response in
  (match outcome with Unconfirmed "lost reply" -> () | _ -> assert false);
  let%bind after = Flow.kickoff flow preview in
  (match after with Stale _ -> () | _ -> assert false);
  match !submitted with
  | [ "new-plan", captured ] ->
    assert ([%equal: (string * string) list] captured.assignments (Flow.preview preview).inputs.assignments);
    Deferred.unit
  | _ -> assert false
;;

let () =
  don't_wait_for
    (match%map Clock.with_timeout (Time_float.Span.of_sec 5.) (test ()) with
     | `Result () -> Shutdown.shutdown 0
     | `Timeout -> failwith "Kickoff fake service timed out");
  never_returns (Scheduler.go ())
;;
