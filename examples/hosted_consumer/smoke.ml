open! Core
open! Async
open Bonsai_term

module Editor = Cobalt_hosted
module Location = Editor.Open_location
module Handle = Bonsai_test.Handle
module Var = Bonsai.Expert.Var

let check condition message = if not condition then failwith message

let main root =
  let startup = Editor.open_project root |> Or_error.ok_exn in
  let layout = Sexp.of_string "((views ((Problems Band))))" |> Editor.Layout.t_of_sexp in
  let dimensions = Var.create { Dimensions.width = 100; height = 24 } in
  let visible = Var.create true in
  let focused = Var.create true in
  let handle =
    Handle.create Bonsai_test.Result_spec.invisible
      (Editor.component ~layout startup
         ~dimensions:(Var.value dimensions)
         ~visible:(Var.value visible)
         ~focused:(Var.value focused))
  in
  let frame () =
    Handle.recompute_view handle;
    Handle.last_result handle
  in
  let run effect =
    let returned = Ivar.create () in
    Effect.Expert.eval effect ~on_exn:raise ~f:(Ivar.fill_exn returned);
    let rec wait attempts =
      match Ivar.peek returned with
      | Some result -> return result
      | None ->
        check (attempts > 0) "hosted effect did not reply";
        ignore (frame () : Editor.t);
        Deferred.bind (Clock_ns.after (Time_ns.Span.of_ms 1.)) ~f:(fun () ->
          wait (attempts - 1))
    in
    wait 2000
  in
  let open_file ?(project_root = root) ?position relative_file =
    run ((frame ()).open_location { project_root; relative_file; position })
  in
  let opened = function
    | Ok id -> id
    | Error failure -> Error.raise (Location.to_error failure)
  in
  let send key =
    run ((frame ()).handle_event (Key_press { key; mods = [] }))
  in
  let rendered () =
    let view = (frame ()).view in
    let buffer = Buffer.create 4096 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0)
      (View.width view, View.height view) (View.Private.notty_image view);
    Buffer.contents buffer
  in
  let ( let* ) deferred f = Deferred.bind deferred ~f in
  let* first = open_file "src/first.txt" in
  let first = opened first in
  check (String.is_substring (rendered ()) ~substring:"Problems (") "missing Problems band";
  check (not (String.is_substring (rendered ()) ~substring:"History:")) "unexpected History tile";
  let* () = send (ASCII 'i') in
  let* () = send (ASCII 'Z') in
  let* () = send Escape in
  check (String.is_substring (rendered ()) ~substring:"Zfirst") "input did not edit";
  let* second = open_file ~position:{ line = 2; column = 4 } "second.txt" in
  check (not (Location.equal_buffer_id first (opened second))) "files share an id";
  let* wrong = open_file ~project_root:(root ^ "-wrong") "second.txt" in
  (match wrong with
   | Error (Location.Wrong_project _) -> ()
   | _ -> failwith "expected Wrong_project");
  let* missing = open_file "missing.txt" in
  (match missing with
   | Error (Location.Target_unavailable _) -> ()
   | _ -> failwith "expected Target_unavailable");
  Var.set focused false;
  check (Option.is_none (frame ()).cursor) "unfocused cursor was exposed";
  Var.set visible false;
  check (View.width (frame ()).view = 0) "hidden editor still has a view";
  let* reopened = open_file "src/first.txt" in
  check (Location.equal_buffer_id first (opened reopened)) "buffer id changed while hidden";
  Var.set dimensions { width = 74; height = 17 };
  Var.set visible true;
  Var.set focused true;
  check (View.width (frame ()).view = 74) "resized allocation did not reach editor";
  check (String.is_substring (rendered ()) ~substring:"Zfirst") "unsaved edit disappeared";
  let* () = run ((frame ()).shutdown ()) in
  check (frame ()).closed "shutdown did not close the editor";
  let* closed = open_file "src/first.txt" in
  (match closed with
   | Error Session_exited -> ()
   | _ -> failwith "closed editor accepted an open");
  print_endline "external C1/C2 smoke passed";
  return ()
;;

let () =
  don't_wait_for
    (Monitor.try_with (fun () ->
       match Stdlib.Sys.argv with
       | [| _; root |] -> main root
       | _ -> failwith "usage: smoke.exe ABSOLUTE_PROJECT_ROOT")
     >>| function
     | Ok () -> Shutdown.shutdown 0
     | Error exn ->
       eprintf "%s\n%!" (Exn.to_string exn);
       Shutdown.shutdown 1);
  never_returns (Scheduler.go ())
;;
