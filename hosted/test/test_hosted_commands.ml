open! Core
open! Async
open Bonsai_term

let dimensions = { Dimensions.width = 132; height = 36 }

let wait_for what predicate =
  let deadline = Time_ns.add (Time_ns.now ()) (Time_ns.Span.of_int_sec 5) in
  let rec loop () =
    if predicate () then return ()
    else if Time_ns.(now () >= deadline) then failwith ("Timed out waiting for " ^ what)
    else Clock_ns.after (Time_ns.Span.of_int_ms 10) >>= loop
  in
  loop ()
;;

let fixture : Cobalt_hosted.Host_command.t list =
  [ { id = "overview"; title = "Silver: Overview"; aliases = [ "ov" ] }
  ; { id = "workspace.save"; title = "Silver: Save workspace"; aliases = [ "w" ] }
  ]
;;

let run ~root ~enabled =
  let commands = Bonsai.Expert.Var.create fixture in
  let focused = Bonsai.Expert.Var.create true in
  let opened = ref false and closed = ref false and calls = ref [] in
  let host_commands = if enabled then Some (Bonsai.Expert.Var.value commands) else None in
  let on_host_command =
    if not enabled then None
    else Some (Bonsai.return (fun id ->
      Effect.of_thunk (fun () ->
        calls := id :: !calls;
        Bonsai.Expert.Var.set focused false)))
  in
  let startup = Cobalt_hosted.open_project root |> Or_error.ok_exn in
  let path = Filename.concat root "document.txt" in
  let handle =
    Bonsai_term_test.create_handle_generic ~initial_dimensions:dimensions
      ~to_view_with_handler:(fun (pane : Cobalt_hosted.t) ->
        ~view:pane.view, ~handler:pane.handle_event)
      ~handle_incoming:(fun pane -> function
        | `Open ->
          Effect.map
            (pane.open_location { project_root = root; relative_file = "document.txt"; position = None })
            ~f:(function
              | Ok _ -> opened := true
              | Error failure ->
                raise (Error.to_exn (Cobalt_hosted.Open_location.to_error failure)))
        | `Shutdown -> Effect.map (pane.shutdown ()) ~f:(fun () -> closed := true))
      (fun ~dimensions (local_ graph) ->
        Cobalt_hosted.component ?host_commands ?on_host_command startup ~dimensions
          ~visible:(Bonsai.return true) ~focused:(Bonsai.Expert.Var.value focused) graph)
  in
  let display () = Bonsai_test.Handle.recompute_view handle in
  let render () =
    display ();
    let buffer = Buffer.create 256 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (dimensions.width, dimensions.height)
      (View.Private.notty_image (Bonsai_term_test.last_view handle));
    Buffer.contents buffer
  in
  let contains substring = String.is_substring (render ()) ~substring in
  let send_event = Bonsai_term_test.send_event handle in
  let send key = send_event (Key_press { key; mods = [] }) in
  let type_ = String.iter ~f:(fun c -> send (ASCII c)) in
  let open_palette query = type_ " cc"; type_ query in
  let expect_calls ids =
    display ();
    [%test_eq: string list] !calls ids
  in
  let shutdown () =
    Bonsai_term_test.do_actions handle [ `Shutdown ];
    wait_for "editor shutdown" (fun () ->
      display ();
      !closed && (Bonsai_term_test.last_result handle).closed)
  in
  display ();
  Monitor.protect ~finally:shutdown (fun () ->
    if enabled then (
      (* Project-directory startup, before opening a file. *)
      open_palette "ov";
      assert (contains "Silver: Overview");
      send Escape;
      expect_calls []);
    Bonsai_term_test.do_actions handle [ `Open ];
    let%map () = wait_for "document open" (fun () -> display (); !opened) in
    open_palette "ov";
    assert (Bool.equal enabled (contains "Silver: Overview"));
    send Escape;
    if enabled then (
      (* In Insert the leader is literal, in Visual c retains its existing
         edit, and the colon prompt does not execute host aliases. *)
      type_ "i ccTAG";
      send Escape;
      assert (contains " ccTAGseed");
      type_ "v cc";
      send Escape;
      type_ ":ov";
      send Enter;
      send_event (Paste `Start);
      type_ " ccov";
      send_event (Paste `End);
      expect_calls [];
      assert (not (contains "Silver: Overview"));
      type_ "iMARK";
      send Escape;
      open_palette "w";
      assert (contains "Save buffer");
      assert (contains "Silver: Save workspace");
      send Enter;
      expect_calls [];
      assert (String.is_substring (In_channel.read_all path) ~substring:"MARK");
      open_palette "w";
      send Tab;
      send Enter;
      expect_calls [ "workspace.save" ];
      assert (not (contains "Silver: Save workspace"));
      Bonsai.Expert.Var.set focused true;
      display ();
      open_palette "";
      send_event (Paste `Start);
      type_ "OV";
      send_event (Paste `End);
      expect_calls [ "workspace.save" ];
      assert (contains "Silver: Overview");
      send Enter;
      expect_calls [ "overview"; "workspace.save" ];
      send Enter;
      expect_calls [ "overview"; "workspace.save" ];
      Bonsai.Expert.Var.set focused true;
      display ();
      open_palette "overview";
      assert (contains "Silver: Overview");
      Bonsai.Expert.Var.set commands [];
      display ();
      send Enter;
      assert (not (contains "Silver: Overview"));
      expect_calls [ "overview"; "workspace.save" ];
      open_palette "ov";
      assert (not (contains "Silver: Overview"));
      send Escape)
    else expect_calls [])
;;

let () =
  let root = Filename_unix.temp_dir "cobalt-hosted-commands" "" in
  let path = Filename.concat root "document.txt" in
  Out_channel.write_all path ~data:"seed\n";
  Exn.protect
    ~f:(fun () ->
      Thread_safe.block_on_async_exn (fun () ->
        let%bind () = run ~root ~enabled:true in
        run ~root ~enabled:false))
    ~finally:(fun () -> Core_unix.unlink path; Core_unix.rmdir root)
;;
