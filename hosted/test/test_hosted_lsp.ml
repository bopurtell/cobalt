open! Core
open! Async
open Bonsai_term

module Handle = Bonsai_test.Handle

type action = Open of Cobalt_hosted.Open_location.request | Shutdown

let wait_for description predicate =
  let deadline = Time_ns.add (Time_ns.now ()) (Time_ns.Span.of_int_sec 5) in
  let rec loop () =
    if predicate () then return ()
    else if Time_ns.(now () >= deadline)
    then failwith ("Timed out waiting for " ^ description)
    else (
      let%bind () = Clock_ns.after (Time_ns.Span.of_int_ms 10) in
      loop ())
  in
  loop ()
;;

let run ~root =
  let log = Filename.concat root "lsp.log" in
  let methods () =
    if Stdlib.Sys.file_exists log
    then List.filter_map (In_channel.read_lines log) ~f:(fun line ->
      String.lsplit2 line ~on:' ' |> Option.map ~f:snd)
    else []
  in
  let startup = Cobalt_hosted.open_project root |> Or_error.ok_exn in
  let visible = Bonsai.Expert.Var.create true in
  let open_reply = ref None and shutdown_done = ref false in
  let handle =
    Bonsai_term_test.create_handle_generic ~initial_dimensions:{ width = 132; height = 36 }
      ~to_view_with_handler:(fun (pane : Cobalt_hosted.t) ->
        ~view:pane.view, ~handler:pane.handle_event)
      ~handle_incoming:(fun pane -> function
        | Open request ->
          Effect.map (pane.open_location request) ~f:(fun result -> open_reply := Some result)
        | Shutdown -> Effect.map (pane.shutdown ()) ~f:(fun () -> shutdown_done := true))
      (fun ~dimensions (local_ graph) ->
        let visible = Bonsai.Expert.Var.value visible in
        Cobalt_hosted.component startup ~dimensions ~visible ~focused:visible graph)
  in
  let display () = Handle.recompute_view handle in
  let received method_ = List.mem (methods ()) method_ ~equal:String.equal in
  let send char =
    Bonsai_term_test.send_event handle (Key_press { key = ASCII char; mods = [] });
    display ()
  in
  let text () =
    let buffer = Buffer.create 256 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (132, 36)
      (View.Private.notty_image (Bonsai_term_test.last_view handle));
    Buffer.contents buffer
  in
  display ();
  let%bind () = Scheduler.yield () in
  assert (not (received "spawn"));
  Bonsai_term_test.do_actions handle
    [ Open { project_root = root; relative_file = "first.ml"; position = None } ];
  let%bind () = wait_for "C1 open acknowledgement" (fun () ->
    display ();
    Option.is_some !open_reply)
  in
  (match Option.value_exn !open_reply with
   | Ok _ -> ()
   | Error failure -> raise (Error.to_exn (Cobalt_hosted.Open_location.to_error failure)));
  String.iter " li" ~f:send;
  let%bind () = wait_for "LSP didOpen and native running inventory" (fun () ->
    display ();
    let text = text () in
    received "textDocument/didOpen"
    && List.for_all [ "Language servers (live)"; "ocamllsp#1"; "Status: Running" ]
         ~f:(fun substring -> String.is_substring text ~substring))
  in
  assert (received "initialize");
  Bonsai.Expert.Var.set visible false;
  display ();
  assert (not (received "shutdown"));
  Bonsai.Expert.Var.set visible true;
  display ();
  assert (String.is_substring (text ()) ~substring:"Status: Running");
  Bonsai_term_test.do_actions handle [ Shutdown ];
  let%map () = wait_for "pane and language-server shutdown" (fun () ->
    display ();
    !shutdown_done && received "shutdown" && received "exit")
  in
  assert ((Bonsai_term_test.last_result handle).closed);
  assert (List.count (methods ()) ~f:(String.equal "spawn") = 1)
;;

let () =
  let root = Sys.getenv_exn "HOSTED_LSP_TEST_ROOT" in
  Thread_safe.block_on_async_exn (fun () -> run ~root)
;;
