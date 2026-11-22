open! Core
open! Async
open Bonsai_term

module Handle = Bonsai_test.Handle

type action = Open | Shutdown

let dimensions = { Dimensions.width = 120; height = 36 }

let wait_for what predicate =
  let deadline = Time_ns.add (Time_ns.now ()) (Time_ns.Span.of_int_sec 5) in
  let rec loop () =
    if predicate () then return ()
    else if Time_ns.(now () >= deadline) then failwith ("Timed out waiting for " ^ what)
    else (
      let%bind () = Clock_ns.after (Time_ns.Span.of_int_ms 10) in
      loop ())
  in
  loop ()
;;

let mount ?on_toggle_terminal ~focused ~root () =
  let startup = Cobalt_hosted.open_project root |> Or_error.ok_exn in
  let opened = ref false and closed = ref false in
  let handle =
    Bonsai_term_test.create_handle_generic ~initial_dimensions:dimensions
      ~to_view_with_handler:(fun (pane : Cobalt_hosted.t) ->
        ~view:pane.view, ~handler:pane.handle_event)
      ~handle_incoming:(fun pane -> function
        | Open ->
          Effect.map
            (pane.open_location { project_root = root; relative_file = "document.txt"; position = None })
            ~f:(function
              | Ok _ -> opened := true
              | Error failure -> raise (Error.to_exn (Cobalt_hosted.Open_location.to_error failure)))
        | Shutdown -> Effect.map (pane.shutdown ()) ~f:(fun () -> closed := true))
      (fun ~dimensions (local_ graph) ->
        Cobalt_hosted.component ?on_toggle_terminal startup ~dimensions
          ~visible:(Bonsai.return true) ~focused:(Bonsai.Expert.Var.value focused) graph)
  in
  Handle.recompute_view handle;
  Bonsai_term_test.do_actions handle [ Open ];
  let%map () = wait_for "document open" (fun () -> Handle.recompute_view handle; !opened) in
  let shutdown () =
    Bonsai_term_test.do_actions handle [ Shutdown ];
    wait_for "editor shutdown" (fun () ->
      Handle.recompute_view handle;
      !closed && (Bonsai_term_test.last_result handle).closed)
  in
  handle, shutdown
;;

let send handle ?(mods = []) key =
  Bonsai_term_test.send_event handle (Key_press { key; mods })
;;

let type_ handle = String.iter ~f:(fun c -> send handle (ASCII c))

let view_contains handle substring =
  Handle.recompute_view handle;
  let buffer = Buffer.create 256 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (dimensions.width, dimensions.height)
    (View.Private.notty_image (Bonsai_term_test.last_view handle));
  String.is_substring (Buffer.contents buffer) ~substring
;;

let cursor handle =
  Handle.recompute_view handle;
  let pane : Cobalt_hosted.t = Bonsai_term_test.last_result handle in
  pane.cursor
;;

let delegate ~root ~shells () =
  let focused = Bonsai.Expert.Var.create true in
  let toggles = ref [] and selected = ref 1 in
  let on_toggle_terminal =
    Bonsai.return (fun number ->
      Effect.of_thunk (fun () ->
        let id = Option.value number ~default:!selected in
        selected := id;
        toggles := (number, id) :: !toggles;
        Bonsai.Expert.Var.set focused false))
  in
  let%bind handle, shutdown = mount ~on_toggle_terminal ~focused ~root () in
  Monitor.protect ~finally:shutdown (fun () ->
    (* A pending first half of Insert's jk binding cannot span the handoff. *)
    type_ handle "iAj";
    let before = Option.value_exn (cursor handle) in
    assert (Cursor.Kind.equal before.kind Bar);
    type_ handle "2 /";
    assert (Option.is_none (cursor handle));
    assert ([%equal: (int option * int) list] !toggles [ Some 2, 2 ]);
    assert (not (view_contains handle "Tile Term"));
    (* Even accidental events sent to the old pane are ignored while unfocused. *)
    type_ handle "Q2 /";
    assert (Option.is_none (cursor handle));
    assert ([%equal: (int option * int) list] !toggles [ Some 2, 2 ]);
    Bonsai.Expert.Var.set focused true;
    let after = Option.value_exn (cursor handle) in
    assert (Cursor.Kind.equal after.kind Bar);
    assert ([%equal: int * int] (before.position.x, before.position.y)
              (after.position.x, after.position.y));
    assert (view_contains handle "Ajseed");
    type_ handle "kB2";
    Handle.advance_clock_by handle (Time_ns.Span.of_ms 221.);
    for _ = 1 to 3 do Handle.recompute_view handle done;
    type_ handle " ";
    Handle.advance_clock_by handle (Time_ns.Span.of_ms 221.);
    for _ = 1 to 3 do Handle.recompute_view handle done;
    type_ handle "/";
    Bonsai_term_test.send_event handle (Paste `Start);
    type_ handle "2 /";
    Bonsai_term_test.send_event handle (Paste `End);
    assert (view_contains handle "AjkB2 /2 /seed");
    (* An unfinished prefix is not replayed during a focus handoff, nor can
       later input finish it after focus returns. *)
    type_ handle "2 ";
    Bonsai.Expert.Var.set focused false;
    assert (Option.is_none (cursor handle));
    Bonsai.Expert.Var.set focused true;
    ignore (cursor handle : Cursor.t option);
    type_ handle "/";
    assert (view_contains handle "AjkB2 /2 //seed");
    assert ([%equal: (int option * int) list] !toggles [ Some 2, 2 ]);
    (* A selection in the outer host isn't reflected in Cobalt state. Even in
       Normal mode the uncounted action delegates selection to that host. *)
    selected := 7;
    send handle Escape;
    type_ handle " /";
    assert (Option.is_none (cursor handle));
    assert ([%equal: (int option * int) list] !toggles [ None, 7; Some 2, 2 ]);
    return ())
  >>| fun () -> assert (List.is_empty (shells ()))
;;

let local ~root ~shells () =
  let focused = Bonsai.Expert.Var.create true in
  let%bind handle, shutdown = mount ~focused ~root () in
  Monitor.protect ~finally:shutdown (fun () ->
    (* No handler: same numbered terminal behavior as the standalone editor. *)
    type_ handle "2 /";
    assert (view_contains handle "Tile Term 2");
    let%bind () = wait_for "local shell spawn" (fun () -> not (List.is_empty (shells ()))) in
    let pid = List.hd_exn (shells ()) in
    let%bind () = wait_for "terminal 2 output" (fun () ->
      view_contains handle "Tile Term 2" && view_contains handle ("STARTED_" ^ pid)) in
    type_ handle "2 /";
    assert (not (view_contains handle "Tile Term 2"));
    type_ handle "2 /";
    assert (view_contains handle "Tile Term 2");
    type_ handle "still-live";
    send handle ~mods:[ Ctrl ] (ASCII 'm');
    let%map () = wait_for "reopened live terminal" (fun () ->
      view_contains handle ("REPLY_" ^ pid ^ "_still-live")) in
    assert (List.equal String.equal (shells ()) [ pid ]))
;;

let () =
  let root = Sys.getenv_exn "HOSTED_TOGGLE_TEST_ROOT" in
  let shells () = In_channel.read_lines (Filename.concat root "shells.log") in
  Thread_safe.block_on_async_exn (fun () ->
    let%bind () = delegate ~root ~shells () in
    local ~root ~shells ())
;;
