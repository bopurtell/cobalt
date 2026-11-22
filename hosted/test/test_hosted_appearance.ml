open! Core
open! Async
open Bonsai_term

module Theme = Cobalt_hosted.Theme

let dimensions = { Dimensions.width = 132; height = 36 }

let wait_for what predicate =
  let deadline = Time_ns.add (Time_ns.now ()) (Time_ns.Span.of_int_sec 5) in
  let rec loop () =
    if predicate () then return ()
    else if Time_ns.(now () >= deadline) then failwith ("Timed out waiting for " ^ what)
    else
      let%bind () = Clock_ns.after (Time_ns.Span.of_int_ms 10) in
      loop ()
  in
  loop ()
;;

let run ~root =
  let first =
    Theme.with_colors Theme.default
      [ Background, (11, 12, 13)
      ; Current_line, (14, 15, 16)
      ; Backdrop, (17, 18, 19)
      ; Surface, (20, 21, 22)
      ; Syntax_keyword, (23, 24, 25)
      ; Border, (26, 27, 28)
      ; Selection_foreground, (29, 30, 31)
      ; Selection_background, (32, 33, 34)
      ]
  in
  let named = Option.value_exn (Theme.find "silver-frost") in
  let appearance = Bonsai.Expert.Var.create first in
  let visible = Bonsai.Expert.Var.create true in
  let startup = Cobalt_hosted.open_project root |> Or_error.ok_exn in
  let opened = ref false and closed = ref false in
  let handle =
    Bonsai_term_test.create_handle_generic ~initial_dimensions:dimensions
      ~to_view_with_handler:(fun (pane : Cobalt_hosted.t) ->
        ~view:pane.view, ~handler:pane.handle_event)
      ~handle_incoming:(fun pane -> function
        | `Open ->
          Effect.map
            (pane.open_location { project_root = root; relative_file = "document.s"; position = None })
            ~f:(function
              | Ok _ -> opened := true
              | Error failure -> raise (Error.to_exn (Cobalt_hosted.Open_location.to_error failure)))
        | `Shutdown -> Effect.map (pane.shutdown ()) ~f:(fun () -> closed := true))
      (fun ~dimensions (local_ graph) ->
        let visible = Bonsai.Expert.Var.value visible in
        Cobalt_hosted.component startup ~appearance:(Bonsai.Expert.Var.value appearance)
          ~dimensions ~visible ~focused:visible graph)
  in
  let display () = Bonsai_test.Handle.recompute_view handle in
  let render cap =
    display ();
    let buffer = Buffer.create 256 in
    Notty.Render.to_buffer buffer cap (0, 0) (dimensions.width, dimensions.height)
      (View.Private.notty_image (Bonsai_term_test.last_view handle));
    Buffer.contents buffer
  in
  let send key = Bonsai_term_test.send_event handle (Key_press { key; mods = [] }) in
  let type_ = String.iter ~f:(fun c -> send (ASCII c)) in
  let rgb theme role =
    let r, g, b = Theme.color theme role in
    sprintf "%d;%d;%d" r g b
  in
  let check label text substring =
    if not (String.is_substring text ~substring) then
      failwithf "Expected %s (%S) in rendered editor" label substring ()
  in
  let check_colors theme ~selected =
    let ansi = render Notty.Cap.ansi in
    check "document keyword or visual selection" ansi
      (sprintf ";38;2;%s;48;2;%sm%s"
         (rgb theme (if selected then Selection_foreground else Syntax_keyword))
         (rgb theme (if selected then Selection_background else Current_line))
         (if selected then "." else ".text"));
    check "keyword on ordinary document background" ansi
      (sprintf ";38;2;%s;48;2;%smret" (rgb theme Syntax_keyword) (rgb theme Background));
    check "workspace border on backdrop" ansi
      (sprintf ";38;2;%s;48;2;%sm│" (rgb theme Border) (rgb theme Backdrop));
    check "panel or status surface" ansi
      (sprintf ";38;2;%s;48;2;%sm" (rgb theme Foreground) (rgb theme Surface))
  in
  let shutdown () =
    Bonsai_term_test.do_actions handle [ `Shutdown ];
    wait_for "editor shutdown" (fun () ->
      display ();
      !closed && (Bonsai_term_test.last_result handle).closed)
  in
  display ();
  Monitor.protect ~finally:shutdown (fun () ->
    Bonsai_term_test.do_actions handle [ `Open ];
    let%map () = wait_for "document open" (fun () -> display (); !opened) in
    type_ "Go.byte 7";
    send Escape;
    type_ "gg";
    check_colors first ~selected:false;
    type_ "v";
    check_colors first ~selected:true;
    let before = render Notty.Cap.dumb in
    Bonsai.Expert.Var.set appearance named;
    check_colors named ~selected:true;
    assert (String.equal before (render Notty.Cap.dumb));
    Bonsai.Expert.Var.set visible false;
    display ();
    assert (View.width (Bonsai_term_test.last_view handle) = 0);
    Bonsai.Expert.Var.set appearance first;
    display ();
    Bonsai.Expert.Var.set visible true;
    check_colors first ~selected:true;
    send Escape;
    type_ " vT";
    check_colors first ~selected:false;
    let text = render Notty.Cap.dumb in
    assert (not (String.is_substring text ~substring:"Choose theme"));
    check "unsaved buffer contents" text ".byte 7")
;;

let () =
  let root = Filename_unix.temp_dir "cobalt-hosted-appearance" "" in
  let path = Filename.concat root "document.s" in
  Out_channel.write_all path ~data:".text\nret";
  Exn.protect
    ~f:(fun () -> Thread_safe.block_on_async_exn (fun () -> run ~root))
    ~finally:(fun () -> Core_unix.unlink path; Core_unix.rmdir root)
;;
