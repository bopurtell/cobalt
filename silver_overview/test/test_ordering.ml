open! Core
open Async

module Overview = Silver_overview

type pending =
  { request : Overview.request
  ; response : (Overview.response, string) Result.t Ivar.t
  ; stop : unit Deferred.t
  }

let span = Time_ns.Span.of_int_ms

let deadline message deferred =
  match%map Clock_ns.with_timeout (span 2000) deferred with
  | `Result result -> result
  | `Timeout -> failwith message
;;

let reply pending body = Ivar.fill_exn pending.response (Ok { status = 200; body })

let bind t project_root run =
  Overview.rebind t { endpoint = "http://127.0.0.1:12811"; project_root; run }
;;

let expect_unavailable t =
  match Overview.latest t with
  | Unavailable _ -> ()
  | _ -> failwith "changing or closing a scope must immediately drop old data"
;;

let expect_fresh t ~root ~run ~id =
  match Overview.latest t with
  | Fresh { binding = { project_root; run = actual_run; _ }; attempts = [ attempt ]; _ }
    when String.equal project_root root
         && Option.equal String.equal run actual_run
         && String.equal attempt.id id -> ()
  | _ -> failwithf "expected fresh snapshot %s for %s" id root ()
;;

let next reader path =
  match%map deadline ("no request to " ^ path) (Pipe.read reader) with
  | `Ok pending ->
    assert (String.equal pending.request.path path);
    pending
  | `Eof -> assert false
;;

let hello =
  "((application_version test)(protocol_versions (1))(instance_id daemon)(capabilities \
   (simulation)))"
;;

let open_project ~root ~project =
  sprintf "(Ok ((project ((id %s)(root ((path %s)))))))" project root
;;

let status ?detail ~id () =
  let detail =
    match detail with
    | None -> ""
    | Some root ->
      sprintf
        "((id %s)(project_root %s)(job 1)(captured ((selection ((suite \
         suite)(seed 42)))))(lifecycle Running)(outcome Unknown)(cases ())(artifacts \
         ())(progress ()))"
        id
        root
  in
  sprintf
    "(Ok ((attempts (((id %s)(suite suite)(job 1)(seed 42)(created_at \
     2026-01-01T00:00:00Z)(lifecycle Running)(outcome Unknown))))(detail (%s))))"
    id
    detail
;;

let test () =
  let reader, writer = Pipe.create () in
  let peer ~endpoint:_ ~timeout:_ ~stop request =
    let response = Ivar.create () in
    Pipe.write_without_pushback writer { request; response; stop };
    (* Deliberately ignore [stop] and allow out-of-order completion. *)
    Ivar.read response
  in
  let t = Overview.create ~peer ~poll_interval:(span 500) () in
  let handshake ~root ~project =
    let%bind hello_request = next reader "/api/hello" in
    reply hello_request hello;
    let%bind open_request = next reader "/api/v1/open-project" in
    reply open_request (open_project ~root ~project);
    next reader "/api/v1/simulation"
  in
  expect_unavailable t;
  bind t "/one" None;
  let%bind old_project = handshake ~root:"/one" ~project:"old" in
  expect_unavailable t;
  bind t "/two" (Some "old-run");
  let%bind old_attempt = handshake ~root:"/two" ~project:"new" in
  bind t "/two" (Some "new-run");
  let%bind new_attempt = handshake ~root:"/two" ~project:"new" in
  let after = Overview.revision t in
  let changed = Overview.await_change t ~after in
  assert (not (Deferred.is_determined changed));
  reply new_attempt (status ~detail:"/two" ~id:"new-run" ());
  let%bind () = deadline "fresh snapshot did not notify" changed in
  expect_fresh t ~root:"/two" ~run:(Some "new-run") ~id:"new-run";
  assert (Deferred.is_determined (Overview.await_change t ~after));
  assert (Deferred.is_determined old_project.stop);
  assert (Deferred.is_determined old_attempt.stop);
  let current = Overview.revision t in
  reply old_project (status ~id:"old-project" ());
  Ivar.fill_exn old_attempt.response (Error "late failure of superseded attempt");
  let%bind () = Clock_ns.after (span 20) in
  expect_fresh t ~root:"/two" ~run:(Some "new-run") ~id:"new-run";
  assert (Overview.revision t = current);
  (* Rebinding identical arguments still invalidates work and drops the cache. *)
  bind t "/two" (Some "new-run");
  expect_unavailable t;
  let%bind on_close = handshake ~root:"/two" ~project:"new" in
  Overview.unbind t;
  expect_unavailable t;
  let%bind () = deadline "close did not abandon request" on_close.stop in
  reply on_close (status ~detail:"/two" ~id:"new-run" ());
  bind t "/two" (Some "new-run");
  let%bind on_shutdown = handshake ~root:"/two" ~project:"new" in
  Overview.shutdown t;
  Overview.shutdown t;
  expect_unavailable t;
  let%bind () = deadline "shutdown did not abandon request" on_shutdown.stop in
  reply on_shutdown (status ~detail:"/two" ~id:"new-run" ());
  let%map () = Clock_ns.after (span 50) in
  expect_unavailable t;
  assert (Pipe.length reader = 0)
;;

let () =
  don't_wait_for
    (let%map () = test () in
     Shutdown.shutdown 0);
  never_returns (Scheduler.go ())
;;
