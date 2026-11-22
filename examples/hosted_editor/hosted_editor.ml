open! Core
open! Async
open Bonsai_term
open Bonsai.Let_syntax

module Editor = Cobalt_ui.Editor_view
module Location = Cobalt_app.Session.Open_location

type pane =
  | Editor
  | Sibling
  | Hidden
  | Closed

type layout =
  { terminal : Dimensions.t
  ; editor : Dimensions.t
  ; sibling : Dimensions.t
  }

let layout (terminal : Dimensions.t) pane =
  let height = Int.max 0 (terminal.height - 1) in
  let side_width = Int.min 30 (terminal.width / 2) in
  let shown_sibling_width =
    match pane with
    | Hidden | Closed -> terminal.width
    | Editor | Sibling -> side_width
  in
  { terminal
  ; editor = { width = terminal.width - side_width; height }
  ; sibling = { width = shown_sibling_width; height }
  }
;;

let fit (size : Dimensions.t) view =
  if size.width = 0 || size.height = 0
  then View.none
  else (
    let view =
      View.crop view
        ~r:(Int.max 0 (View.width view - size.width))
        ~b:(Int.max 0 (View.height view - size.height))
    in
    View.zcat [ view; View.rectangle ~width:size.width ~height:size.height () ])
;;

let header layout pane =
  let title =
    match pane with
    | Hidden -> "Editor hidden | Sibling focus"
    | Closed -> "Editor closed | Sibling focus"
    | Editor -> "Editor focus"
    | Sibling -> "Sibling focus"
  in
  let { terminal; editor; _ } = layout in
  Printf.sprintf "%s | Terminal: %dx%d | Editor: %dx%d"
    title terminal.width terminal.height editor.width editor.height
  |> View.text
  |> fit { width = terminal.width; height = Int.min 1 terminal.height }
;;

let sibling size count result =
  [ "HOST SIBLING"
  ; Printf.sprintf "Sibling keys: %d" count
  ; ""
  ; "F2  Switch focus"
  ; "F3  Hide/show editor"
  ; "F4  Open first file"
  ; "F5  Open second at line 2"
  ; "F6  Request missing file"
  ; "F10 End demo (discard edits)"
  ; ""
  ; result
  ]
  |> List.map ~f:View.text
  |> View.vcat
  |> fit size
;;

let takeover_terminal () =
  (* The outer app is the only terminal owner. Keep Enter (CR) distinct from
     Ctrl-J (LF), just as in the standalone frontend. *)
  ignore (Cobalt_ui.Terminal_mode.save () : unit -> unit);
  let tty = Core_unix.Terminal_io.tcgetattr Core_unix.stdin in
  Core_unix.Terminal_io.tcsetattr
    { tty with c_icrnl = false; c_inlcr = false; c_igncr = false }
    Core_unix.stdin ~mode:TCSANOW
;;

let app ~configuration ~startup_configuration controller ~first ~second ~missing
    ~exit ~dimensions (local_ graph) =
  let pane, set_pane = Bonsai.state Editor graph in
  let size = let%arr dimensions and pane in layout dimensions pane in
  let editor_size = let%arr size in size.editor in
  let visible = let%arr pane in match pane with Editor | Sibling -> true | Hidden | Closed -> false in
  let focused = let%arr pane in match pane with Editor -> true | _ -> false in
  let hosted = Editor.hosted ~configuration ~startup_configuration controller
      ~dimensions:editor_size ~visible ~focused graph in
  let count, add_key = Bonsai.state_machine ~default_model:0
      ~apply_action:(fun _ count () -> count + 1) graph in
  let result, set_result = Bonsai.state "" graph in
  (* Several terminal events can share a frame. Route against the current owner,
     not the location of focus in the last painted frame. *)
  let live_pane = ref Editor in
  let change_pane =
    let%arr set_pane in
    fun pane ->
      let%bind.Effect () = Effect.of_thunk (fun () -> live_pane := pane) in
      set_pane pane
  in
  let paste_owner = ref None in
  let set_cursor = Effect.set_cursor graph in
  Bonsai.Edge.after_display
    (let%arr hosted and set_cursor in
     let cursor = Option.map hosted.Editor.cursor ~f:(fun cursor ->
       { cursor with position = { cursor.position with y = cursor.position.y + 1 } })
     in
     set_cursor cursor)
    graph;
  let view =
    let%arr hosted and size and pane and count and result in
    let pane, size =
      if hosted.Editor.closed then Closed, layout size.terminal Closed else pane, size
    in
    let sibling = sibling size.sibling count result in
    let body = match pane with
      | Closed | Hidden -> sibling
      | Editor | Sibling -> View.hcat [ hosted.Editor.view; sibling ]
    in
    View.vcat [ header size pane; body ]
  in
  let handler =
    let%arr hosted and add_key and set_result and change_pane in
    let open_file (request : Location.request) =
      let%bind.Effect result = hosted.Editor.open_location request in
      let description =
        match result with
        | Ok _ -> "Opened " ^ request.relative_file
        | Error `Closed -> "Open failed: editor closed"
        | Error (`Open failure) ->
          "Open failed: " ^ Error.to_string_hum (Location.to_error failure)
      in
      set_result description
    in
    let forward pane event =
      match pane, event with
      | Editor, _ -> hosted.Editor.handle_event event
      | _, Event.Key_press _ -> add_key ()
      | _ -> Effect.Ignore
    in
    fun event ->
      let%bind.Effect pane =
        Effect.of_thunk (fun () -> if hosted.Editor.closed then Closed else !live_pane)
      in
      match !paste_owner, event with
      | _, Event.Paste `Start ->
        paste_owner := Some pane;
        forward pane event
      | Some owner, Event.Paste `End ->
        paste_owner := None;
        forward owner event
      | Some owner, event -> forward owner event
      | None, Key_press { key = Function 2; mods = [] } ->
        (match pane with
         | Editor -> change_pane Sibling
         | Sibling -> change_pane Editor
         | Hidden | Closed -> Effect.Ignore)
      | None, Key_press { key = Function 3; mods = [] } ->
        (match pane with
         | Editor | Sibling -> change_pane Hidden
         | Hidden -> change_pane Editor
         | Closed -> Effect.Ignore)
      | None, Key_press { key = Function 4; mods = [] } -> open_file first
      | None, Key_press { key = Function 5; mods = [] } -> open_file second
      | None, Key_press { key = Function 6; mods = [] } -> open_file missing
      | None, Key_press { key = Function 10; mods = [] } ->
        let%bind.Effect () = hosted.Editor.shutdown () in
        exit ()
      | None, event -> forward pane event
  in
  ~view, ~handler
;;

let run root first second =
  if not (Core_unix.isatty Core_unix.stdin)
  then failwith "Standard input must be an interactive terminal";
  let project_root = Filename_unix.realpath root in
  if not (String.equal (Filename.basename first) first)
  then failwith "The first file must be directly under the project root";
  let request ?position relative_file : Location.request =
    { project_root; relative_file; position }
  in
  let controller =
    Cobalt_app.Controller.open_file ~must_exist:true ~cell_width:Cobalt_screen.Cell_map.width
      (Filename.concat project_root first)
    |> Or_error.ok_exn
  in
  let configuration = Cobalt_ui.Configuration_host.create () in
  let%bind.Deferred startup_configuration = Cobalt_ui.Configuration_host.startup configuration in
  takeover_terminal ();
  let%map.Deferred result =
    Bonsai_term.start_with_exit ~dispose:true ~mouse:No_mouse_events ~bpaste:true
      (app ~configuration ~startup_configuration controller
         ~first:(request first)
         ~second:(request ~position:{ line = 2; column = 3 } second)
         ~missing:(request ".hosted-editor-demo-missing.txt"))
  in
  Or_error.ok_exn result
;;

let () =
  Command.async ~summary:"Host Cobalt beside a demo sibling pane"
    (let%map_open.Command root = anon ("PROJECT_ROOT" %: string)
     and first = anon ("FIRST_FILE" %: string)
     and second = anon ("SECOND_FILE" %: string) in
     fun () -> run root first second)
  |> Command_unix.run
;;
