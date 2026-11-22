(* Test-only executable. Verification still uses the normal explicit Silver
   binding; only the companion launch service is replaced. *)
open! Core
open Async
module Flow = Silver_flow
module Testing = Silver_overview.Testing

let fixture project : Flow.service =
  let journal = Sys.getenv_exn "COBALT_STAGE_FIXTURE_JOURNAL" in
  let release = Sys.getenv_exn "COBALT_STAGE_FIXTURE_RELEASE" in
  let binding : Flow.binding =
    { endpoint = Testing.endpoint project
    ; project_root = Testing.project_root project
    ; instance_id = Testing.instance_id project
    ; project_id = Testing.project_id project
    }
  in
  let target : Flow.target = { chip = "fixture-chip"; variant = "fixture-variant" } in
  let catalog : Flow.catalog =
    { target = Some target
    ; flows =
        [ { id = "fixture-flow"
          ; label = "Fixture flow"
          ; profiles = [ "fixture-profile" ]
          ; default_profile = "fixture-profile"
          ; stages =
              [ { id = "synthesis"; label = "Synthesis"; alias = Some Synth
                ; endpoint = Available "mapped-synthesis" }
              ; { id = "timing-stage"; label = "Timing"; alias = Some Timing
                ; endpoint = Available "mapped-post-cts" }
              ; { id = "routing-stage"; label = "Routing"; alias = Some Routing
                ; endpoint = Unavailable "Routing endpoint not published" }
              ]
          ; kickoff = Unavailable "Kickoff not part of this stage fixture"
          }
        ]
    ; default_flow = Some ("fixture-flow", "fixture-profile")
    ; stage_launch = Available ()
    }
  in
  let count = ref 0 in
  let rec wait_release attempts =
    if attempts = 0 || Sys_unix.file_exists_exn release then return ()
    else Clock.after (Time_float.Span.of_ms 25.) >>= fun () -> wait_release (attempts - 1)
  in
  let prepare = function
    | Flow.Kickoff _ -> return (Error "Kickoff not part of this stage fixture")
    | Flow.Stage inputs ->
      let submit ~still_current =
        assert (still_current ());
        incr count;
        let target =
          Option.value_map inputs.target ~default:"no-target" ~f:(fun target ->
            target.chip ^ "/" ^ target.variant)
        in
        let line =
          String.concat ~sep:" " [ target; inputs.flow; inputs.profile; inputs.endpoint ]
        in
        Writer.with_file ~append:true journal ~f:(fun writer ->
          Writer.write_line writer line;
          Writer.flushed writer)
        >>= fun () ->
        if !count = 1
        then wait_release 320 >>| fun () -> Flow.Accepted (Run "stage-fixture-run")
        else return (Flow.Unconfirmed "fixture acknowledgement lost")
      in
      return (Ok ({ preview = { identity = "fixture-stage"; inputs }; submit } : Flow.prepared))
  in
  { binding; catalog = (fun () -> return (Ok catalog)); prepare }
;;

let () =
  Cobalt_cli.run
    ~document_decorations:Cobalt_ui.Document_decoration_host.Factory.unavailable
    ~silver_overview:
      (Cobalt_silver_composition.Silver_adapter.factory_with_flow_service fixture)
