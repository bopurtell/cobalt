open! Core
open Async
open Silver_flow

let atom s = Sexp.Atom s
let list xs = Sexp.List xs
let record fields = list (List.map fields ~f:(fun (k, v) -> list [ atom k; v ]))
let ok value = list [ atom "Ok"; value ]
let field value name = [%of_sexp: (string * Sexp.t) list] value |> fun fields ->
  List.Assoc.find_exn fields name ~equal:String.equal
;;

let checked = function Ok value -> value | Error reason -> failwith reason

let run path ~kickoff =
  let exchanges =
    Sexp.load_sexp path |> [%of_sexp: (string * Sexp.t * Sexp.t) list] |> Queue.of_list
  in
  let last = ref None in
  let reply sexp =
    Ok ({ status = 200; body = Sexp.to_string_mach sexp } : Silver_overview.response)
  in
  let rec substitute ~from ~to_ = function
    | Sexp.Atom name when String.equal name from -> atom to_
    | Sexp.Atom _ as atom -> atom
    | Sexp.List values -> list (List.map values ~f:(substitute ~from ~to_))
  in
  let peer ~endpoint:_ ~timeout:_ ~stop:_ (request : Silver_overview.request) =
    return
      (match request.path with
       | "/api/hello" ->
         reply (record [ "protocol_versions", list [ atom "1" ]; "instance_id", atom "recorded"
                       ; "capabilities", list [ atom "simulation"; atom "asic"
                                              ; atom "source-bundle-preparation-v1" ] ])
       | "/api/v1/open-project" ->
         reply (ok (record [ "project", record [ "id", atom "project"
                                               ; "root", record [ "path", atom "/fixture" ] ] ]))
       | path ->
         let body = Sexp.of_string request.body in
         assert (Sexp.equal (field body "instance_id") (atom "recorded"));
         assert (Sexp.equal (field body "project") (atom "project"));
         let operation =
           match path, field body "operation" with
           | "/api/v1/preparation", Sexp.Atom "Get" as pair -> snd pair
           | "/api/v1/asic", Sexp.List (Sexp.Atom "In_context" :: fields) ->
             let context = list fields in
             assert (Sexp.equal (field context "context") (atom "cobalt-companion-v1"));
             assert (Sexp.equal (field context "initial_target") (list []));
             field context "operation"
           | _ -> failwith ("Unexpected recorded-flow request: " ^ request.body)
         in
         let operation, bind_submission =
           match operation with
           | Sexp.List (Sexp.Atom ("Launch_fresh" | "Run") :: fields) ->
             let key = [%of_sexp: string] (field (list fields) "key") in
             (substitute ~from:key ~to_:"@submission" operation,
              substitute ~from:"@submission" ~to_:key)
           | _ -> operation, Fn.id
         in
         match Queue.peek exchanges with
         | Some (next_path, next_operation, response)
           when String.equal next_path path && Sexp.equal operation next_operation ->
           ignore (Queue.dequeue_exn exchanges : string * Sexp.t * Sexp.t);
           if String.equal path "/api/v1/asic" then last := Some response;
           reply (bind_submission response)
         | _ when String.equal path "/api/v1/asic" && Sexp.equal operation (atom "Get") ->
           (* The captures omit redundant polling. The last real snapshot
              remains observable until the next recorded transition. *)
           reply (Option.value_exn !last)
         | _ -> failwith ("Unexpected recorded-flow operation: " ^ Sexp.to_string_hum operation))
  in
  let%bind project =
    Silver_overview.Testing.connect ~peer ~endpoint:"http://127.0.0.1:1234"
      ~project_root:"/fixture" ()
  in
  let project = checked project in
  let flow = create () in
  bind flow (production project);
  let%bind () = refresh flow in
  let view = checked (catalog_view flow) in
  let%map result =
    if kickoff then (
      let draft = checked (draft flow view ~flow:"explore") in
      let draft = edit draft
          { (draft_inputs draft) with profile = "review"; endpoint = "routing"
                                   ; assignments = [ "STRATEGY", "delay" ] } in
      checked (apply flow draft);
      let%bind () = prepare flow in
      let ready = match preparation flow with
        | Ready value -> value
        | Not_prepared why -> failwith why
        | Preparing -> failwith "Still planning"
      in
      assert (List.equal [%equal: string * string]
                (preview ready).inputs.assignments [ "STRATEGY", "delay" ]);
      Silver_flow.kickoff flow ready)
    else launch_stage flow (checked (resolve_alias flow view Routing))
  in
  (match result with
   | Accepted (Workflow { workflow_id; run_id = None }) ->
     assert (String.is_prefix workflow_id ~prefix:"workflow-")
   | _ -> failwith "Expected a workflow reservation, not an allocated ASIC run");
  assert (Queue.is_empty exchanges);
  Silver_overview.Testing.close project
;;

let () =
  don't_wait_for
    (let%bind () = run "wb095-c8.sexp" ~kickoff:false in
     let%bind () = run "wb095-c9.sexp" ~kickoff:true in
     Shutdown.exit 0);
  never_returns (Scheduler.go ())
;;
