open! Core
open! Async

module Main_location = Cobalt_main_editor.Open_location
module Session_location = Cobalt_app.Session.Open_location

let to_session_request ({ project_root; relative_file; position } : Main_location.request)
  : Session_location.request
  =
  let position = Option.map position ~f:(fun ({ line; column } : Main_location.position) ->
    ({ line; column } : Session_location.position))
  in
  { project_root; relative_file; position }
;;

let to_transport_failure : Session_location.failure -> Main_location.failure = function
  | Session_exited -> Session_exited
  | Wrong_project { expected; requested } -> Wrong_project { expected; requested }
  | Invalid_relative_file file -> Invalid_relative_file file
  | Target_unavailable error -> Target_unavailable error
  | Invalid_position error -> Invalid_position error
;;

let command ~document_decorations ~silver_overview =
  Command.async
    ~summary:"Edit UTF-8, LF files and directory workspaces"
    ~readme:(fun () ->
       "Directory PATH opens an editable directory buffer (including cobalt .): Enter opens, \
         - goes to the parent, Space o toggles file/directory, Space r refreshes.\n\
         Files stay open in tabs: Space b n/p switches, b c closes, b C discards.\n\
         Space b t/s shows buffers in the top strip/status rows (also --buffers top/status).\n\
         Visual Enter opens selected files; Space m m/s/u/c/o toggles/marks/unmarks/clears/opens marks.\n\
         Space d m/s/h/f selects major/side/hide/focus; d +/- sizes the side browser.\n\
         Edit only names after @cobalt[ID] and its TAB. Bare rows create files; final / creates directories.\n\
         Explicit @copy[ID]<TAB>destination copies disk contents; duplicate @cobalt IDs are invalid.\n\
         Existing/copy rows accept relative or absolute destinations with existing parents.\n\
         Space w applies directory edits directly: omitted rows PERMANENTLY DELETE files/links\n\
         or EMPTY directories. No trash, recursive delete, filesystem undo, or confirmation dialog.\n\
         Directory save may partially succeed: actual paths and remaining intent are retained; save retries.\n\
         Linux no-overwrite renames are required; cross-device moves are refused (copies may cross devices).\n\
         Deleted open files retain text; routine save refuses. Space b r recreates a missing path exclusively.\n\
         Quit checks hidden dirty directories and missing files too; Space Q discards only memory intent.\n\
         See docs/editor_reference.md for byte escapes, identity, copy metadata, and race limits.\n\
        File PATH opens, or starts an empty document if nothing exists there; saving \
       creates it.\n\
       Normal mode: h/j/k/l move, w/b/e and W/B/E move by words, 0/^/$ to the\n\
       line start/first non-blank/end, _/g_ to the first/last non-blank,\n\
       gg/G to the first/last line, % to the matching (), [] or {}; a count\n\
       first (20j, 3w, 20G) repeats or picks the line. i/a insert before/after\n\
       the cursor, I/A at the line's first non-blank/end, o/O open a line\n\
       below/above; x deletes, u undoes, Ctrl-r redoes, Space w saves, Space q\n\
       quits, Space Q quits discarding changes. Ctrl-e/Ctrl-y scroll the view a\n\
       line, Ctrl-d/Ctrl-u half a screen with the cursor, zz/zt/zb put the cursor\n\
       line at the middle/top/bottom.\n\
       Space v c/h/l/H/L/-/+/r: toggle centering, move, resize, reset the layout;\n\
         Space v n/N toggle absolute/relative line numbers; Space v s toggles the smear cursor (off by default; --smear opts in);\n\
          Space v T chooses a theme with live preview (Enter accepts; Escape restores).\n\
        Space v t toggles status; Space v p h/l/k/j places it, p -/+ sizes it;\n\
         Zen is the startup default; Space v z toggles workspace (--workspace starts there).\n\
         Space v e cycles retained problems; idle Escape acknowledges.\n\
         Space v b toggles the problems preview; Space v f filters workspace/current document;\n\
         Space v o focuses problems: j/k, gg/G, Ctrl-d/u navigate, e inspects, a acknowledges,\n\
         Enter jumps to a supported current-file location; Escape cancels/back/returns.\n\
         Space v m toggles notification history; Space v M focuses it (X clears history).\n\
         --demo-problems seeds eight labelled, jumpable synthetic problems without editing PATH.\n\
         --demo-report installs a static report: Space v d shows it, Space v D focuses it.\n\
         --demo-diagnostics seeds static synthetic checker findings (two sources, another\n\
         file, one stopped source) to review the problems view; edits leave them dimmed.\n\
          --synthetic-checker runs a per-file synthetic checker like ocamllsp: about\n\
         0.4s after an edit, lines containing ERROR/TODO are errors/warnings; about 0.8s\n\
         after a save, ERROR lines again plus a finding in another file, merged into the\n\
         same lists. Space v K crashes it; Space v R restarts it. It replaces the LSP.\n\
         For a .ml, .mli, .mll, or .mly PATH, cobalt runs ocamllsp from PATH as Neovim\n\
         does, rooted at the nearest dune-project (else dune-workspace, *.opam, opam,\n\
         esy.json, package.json, .git, else PATH's directory); its diagnostics go to the\n\
         problems view. It never runs dune: errors needing a build need your own\n\
         `dune build --watch`. For .sv, .svh, .v, or .vh, cobalt runs slang-server\n\
          from SLANG_SERVER, PATH, or ~/slang-server/build/bin/slang-server, rooted\n\
          at .slang, then .git, else PATH's directory. Configure it in .slang/server.json.\n\
          Space l i shows attached language servers, commands, roots and status (palette: Language servers).\n\
           Space v R restarts all managed servers; --no-lsp disables them.\n\
           --main-editor makes this session the explicit local destination for cobalt-open.\n\
           Use the absolute startup directory (PATH itself for a directory, its parent for a file)\n\
           with cobalt-open --project ROOT FILE [LINE [COLUMN]]. No other session is tried.\n\
            Supply --silver-endpoint and --silver-project together for a Silver project\n\
            binding (when built with the adapter); --silver-run watches a specific attempt.\n\
            The editor's current buffer does not change the binding. Space v S\n\
           shows/closes it; Space v U focuses it (j/k scroll, r refresh, Escape returns).")
    (let%map_open.Command path = anon (maybe ("PATH" %: Filename_unix.arg_type))
      and list_themes = flag "--list-themes" no_arg
        ~doc:" List theme IDs, titles and dark/light kinds without opening the editor"
       and main_editor = flag "--main-editor" no_arg
         ~doc:" Opt in as the local open-location destination for this startup directory"
       and silver_endpoint = flag "--silver-endpoint" (optional string)
         ~doc:"URL Explicit Silver loopback HTTP endpoint"
       and silver_project = flag "--silver-project" (optional string)
         ~doc:"ROOT Explicit canonical absolute Silver project root"
        and silver_run = flag "--silver-run" (optional string)
          ~doc:"ATTEMPT Optional exact Silver simulation attempt to watch"
        and silver_test_default = flag "--silver-test-default" (optional string)
          ~doc:"SUITE[/VARIANT] Target for exact test, scoped to the explicit Silver project"
      and theme = flag "--theme"
        (optional
           (Command.Arg_type.create (fun name ->
              match Cobalt_theme.Theme.find name with
              | Some theme -> theme
              | None -> failwithf "Unknown theme %S; use --list-themes for available IDs" name ())))
        ~doc:"NAME Override configuration theme (default vim-classic; Space v T chooses at runtime)"
     and demo_problems = flag "--demo-problems" no_arg
       ~doc:" Seed synthetic problems with locations for manual pane/navigation testing"
     and demo_diagnostics = flag "--demo-diagnostics" no_arg
       ~doc:" Seed static synthetic diagnostic findings for manual problems-view review"
     and synthetic_checker = flag "--synthetic-checker" no_arg
       ~doc:" Run a synthetic diagnostic checker (ERROR/TODO lines) for manual review"
     and no_lsp = flag "--no-lsp" no_arg
        ~doc:" Do not run a language server (ocamllsp or slang-server)"
      and smear_enabled = flag "--smear" no_arg
        ~doc:" Enable the animated smear cursor (default off; Space v s toggles)"
      and markdown = flag "--markdown" no_arg
        ~doc:" Opt in to optional document decorations (palette: Toggle document decorations)"
      and workspace = flag "--workspace" no_arg
        ~doc:" Start in workspace instead of the default Zen (Space v z toggles)"
      and mouse = flag "--mouse" no_arg
        ~doc:" Enable editor mouse clicks and wheel scrolling (default: native terminal selection)"
     and bare = flag "--bare" ~aliases:[ "--superzen" ] no_arg
       ~doc:" Start borderless with transient feedback only; overrides --workspace (Space v B returns to workspace)"
     and demo_report = flag "--demo-report" no_arg
       ~doc:" Install a static, error-free report view for manual tile testing"
     and buffer_presentation = flag "--buffers"
       (optional_with_default Cobalt_input.View_command.Buffer_presentation.Top
          (Command.Arg_type.create (function
            | "top" -> Cobalt_input.View_command.Buffer_presentation.Top
            | "status" -> Status_rows
            | _ -> failwith "expected top or status")))
       ~doc:"top|status File buffers in the top strip (default) or status rows" in
      fun () ->
       let fail error =
         eprintf "cobalt: %s\n" (Error.to_string_hum error);
         exit 1
        in
         let%bind silver_binding =
          match silver_endpoint, silver_project, silver_run with
          | None, None, None -> return None
          | Some endpoint, Some project_root, run ->
            if list_themes then
              fail (Error.of_string "Silver overview requires an interactive session, not --list-themes")
            else if String.is_empty (String.strip endpoint) || Filename.is_relative project_root
               || Option.exists run ~f:(fun run -> String.is_empty (String.strip run)) then
              fail (Error.of_string "Silver overview requires an endpoint, an absolute project root and, if supplied, a nonempty run ID")
            else (match silver_overview with
             | Some _ -> return (Some { Cobalt_ui.Silver_overview_host.endpoint; project_root; run })
             | None -> fail (Error.of_string "Silver overview adapter unavailable in this build"))
          | _ ->
            fail (Error.of_string "--silver-endpoint and --silver-project must be supplied together; --silver-run requires both")
        in
        let%bind silver_test_default =
          match silver_test_default, silver_binding with
          | None, _ -> return None
          | Some _, None ->
            fail (Error.of_string "--silver-test-default requires --silver-endpoint and --silver-project")
          | Some raw, Some _ ->
            let nonempty part = not (String.is_empty (String.strip part)) in
            (match String.split raw ~on:'/' with
             | [ suite ] when nonempty suite -> return (Some (suite, None))
             | [ suite; variant ] when nonempty suite && nonempty variant ->
               return (Some (suite, Some variant))
             | _ -> fail (Error.of_string "--silver-test-default expects SUITE or SUITE/VARIANT"))
        in
        (* Bonsai_term reads keys from stdin; without a terminal there it fails with a
          long message meant for its developers. *)
         if list_themes && main_editor then
           fail (Error.of_string "--main-editor requires an interactive session, not --list-themes")
         else if list_themes then (
          List.iter Cobalt_theme.Theme.all ~f:(fun theme ->
            printf "%s\t%s\t%s\n" (Cobalt_theme.Theme.id theme)
              (Cobalt_theme.Theme.title theme)
              (match Cobalt_theme.Theme.kind theme with Dark -> "dark" | Light -> "light"));
          return ())
         else
         let%bind path = match path with
           | Some path -> return path
            | None when Option.is_some silver_binding ->
             fail (Error.of_string "Silver overview requires an editor startup PATH")
           | None when main_editor ->
             fail (Error.of_string "--main-editor requires an editor startup PATH")
           | None -> fail (Error.of_string "PATH is required when editing (use --list-themes to list themes)") in
        if not (Core_unix.isatty Core_unix.stdin)
       then fail (Error.of_string "standard input is not a terminal")
       else (
         match
            Cobalt_app.Startup.open_path ~cell_width:Cobalt_screen.Cell_map.width path
         with
         | Error error -> fail error
          | Ok controller ->
            let controller = if demo_problems
              then Cobalt_app.Demo_problems.install controller else controller in
            let controller = if demo_diagnostics
              then Cobalt_app.Demo_diagnostics.install controller else controller in
           let report =
             Option.some_if demo_report Cobalt_screen.Report_tile.demo in
           (* One source: the synthetic checker, a test flag, replaces the server. *)
            let source =
              if no_lsp && not synthetic_checker
              then None
              else
                 Some (if synthetic_checker then
                   Cobalt_source.Workspace.start ~create:(fun path ->
                     Some (Cobalt_source.Synthetic.start ~root:(Cobalt_source.Workspace_root.find path) ())) ()
                 else Cobalt_source.Lsp_client.start_workspace ~cell_width:Cobalt_screen.Cell_map.width ())
           in
           (* One runner for the VCS view's git commands (Space g g); it inherits this
              process's environment and never prompts on the terminal. *)
             let vcs = Cobalt_ui.Vcs_host.create () in
             let open_location_listener =
               if not main_editor then None
               else Some (fun ~project_root ~on_request ->
                  let forward request =
                    let%map result = on_request (to_session_request request) in
                    Result.map_error result ~f:to_transport_failure
                  in
                  let%map result = Cobalt_main_editor.start ~project_root ~on_request:forward in
                 Result.map result ~f:(fun listener () -> Cobalt_main_editor.stop listener)
                 |> Result.map_error ~f:(fun error ->
                   Error.tag error ~tag:(sprintf "--main-editor for %S" project_root)))
             in
            (* Preserve CR (Enter) versus LF (Ctrl-J) before Notty reads stdin.
               Notty's own terminal setup retains these input flags. Restore the
               original settings after its shutdown handlers have run. *)
             ignore (Cobalt_ui.Terminal_mode.save () : unit -> unit);
             let tty = Core_unix.Terminal_io.tcgetattr Core_unix.stdin in
            Core_unix.Terminal_io.tcsetattr
              { tty with c_icrnl = false; c_inlcr = false; c_igncr = false }
              Core_unix.stdin ~mode:TCSANOW;
                let silver_overview = Option.map silver_overview ~f:(fun factory ->
                  factory ~test_default:silver_test_default silver_binding) in
               (match%bind Cobalt_ui.Editor_view.run ~document_decorations
                   ~document_decorations_enabled:markdown ~smear_enabled ~mouse
                   ~zen:(not workspace && Option.is_none silver_binding)
                  ~bare ?theme ~buffer_presentation ?report ?silver_overview ?source ~vcs ?open_location_listener controller with
            | Ok () -> return ()
            | Error error -> fail error)))
;;

let run ~document_decorations ~silver_overview =
  Command_unix.run (command ~document_decorations ~silver_overview)
;;
