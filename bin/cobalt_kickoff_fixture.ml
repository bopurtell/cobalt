(* Test-only executable: keep normal explicit project verification and replace
   only the in-process companion launch service. *)
open! Core
open Async
module Flow = Silver_flow
module Testing = Silver_overview.Testing

let fixture project : Flow.service =
  let dir = Sys.getenv_exn "COBALT_KICKOFF_FIXTURE" in
  let binding : Flow.binding =
    { endpoint = Testing.endpoint project
    ; project_root = Testing.project_root project
    ; instance_id = Testing.instance_id project
    ; project_id = Testing.project_id project
    }
  in
  let project = Filename.basename binding.project_root in
  let target : Flow.target = { chip = project ^ "-chip"; variant = "variant-1" } in
  let catalog : Flow.catalog =
    { target = Some target
    ; flows =
        [ { id = "implement"
          ; label = "Implement " ^ project
          ; profiles = [ "debug"; "release" ]
          ; default_profile = "debug"
          ; stages = []
          ; kickoff =
              Available
                { endpoints = [ "place"; "signoff" ]
                ; default_endpoint = Some "place"
                ; parameters =
                    [ { key = "frequency"; label = "Frequency"; default = Some "100"
                      ; choices = [ "100"; "200"; "250" ]
                      }
                    ]
                }
          }
        ]
    ; default_flow = Some ("implement", "debug")
    ; stage_launch = Unavailable "Not supported by the kickoff fixture"
    }
  in
  let save name line =
    Writer.with_file ~append:true (Filename.concat dir name) ~f:(fun writer ->
      Writer.write_line writer line;
      Writer.flushed writer)
  in
  let rec wait_file name remaining =
    if remaining = 0 || Sys_unix.file_exists_exn (Filename.concat dir name)
    then return ()
    else Clock.after (Time_float.Span.of_ms 20.) >>= fun () -> wait_file name (remaining - 1)
  in
  let summary (inputs : Flow.inputs) =
    let target =
      Option.value_map inputs.target ~default:"no-target" ~f:(fun target ->
        target.chip ^ "/" ^ target.variant)
    in
    let parameters = List.map inputs.assignments ~f:(fun (key, value) -> key ^ "=" ^ value) in
    String.concat ~sep:" " ([ target; inputs.flow; inputs.profile; inputs.endpoint ] @ parameters)
  in
  let preparations = ref 0 in
  let submissions = ref 0 in
  let prepare = function
    | Flow.Stage _ -> return (Error "Not supported by the kickoff fixture")
    | Kickoff inputs ->
      incr preparations;
      let identity = sprintf "%s-plan-%d" project !preparations in
      let%bind () = save "prepared" (identity ^ " " ^ summary inputs) in
      let%bind () =
        if String.equal project "first" then wait_file "release-plan" 400 else Deferred.unit
      in
      let assignments =
        if List.Assoc.mem inputs.assignments "frequency" ~equal:String.equal
        then inputs.assignments
        else [ "frequency", "100" ] @ inputs.assignments
      in
      let resolved = { inputs with assignments = assignments @ [ "corner", "slow" ] } in
      let submit ~still_current =
        assert (still_current ());
        incr submissions;
        let%bind () = save "submitted" (identity ^ " " ^ summary resolved) in
        if !submissions = 1
        then (
          let%bind () = wait_file "release-ack" 400 in
          let%map () = save "acknowledged" identity in
          Flow.Accepted (Workflow { workflow_id = "fixture-workflow"; run_id = Some "fixture-run" }))
        else return (Flow.Unconfirmed "fixture acknowledgement lost")
      in
      return (Ok ({ preview = { identity; inputs = resolved }; submit } : Flow.prepared))
  in
  { binding; catalog = (fun () -> return (Ok catalog)); prepare }
;;

let () =
  Cobalt_cli.run
    ~document_decorations:Cobalt_ui.Document_decoration_host.Factory.unavailable
    ~silver_overview:(Cobalt_silver_composition.Silver_adapter.factory_with_flow_service fixture)
