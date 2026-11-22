open! Core
open Cobalt_input

module Id = struct
  type t = string [@@deriving sexp_of, equal, compare]

  let of_string = Fn.id
  let to_string = Fn.id

  let is_valid t =
    (not (String.is_empty t))
    && String.for_all t ~f:(fun c ->
      Char.is_lowercase c || Char.is_digit c || Char.equal c '.' || Char.equal c '-')
  ;;
end

module Context = struct
  type t = { mode : Cobalt_core.Mode.t } [@@deriving sexp_of]
end

module Host_command = struct
  type t = { id : string; title : string; aliases : string list } [@@deriving sexp_of]
end

module Target = struct
  type t = Native of Keymap.Action.t | Host of string [@@deriving sexp_of]
end

module Entry = struct
  type t =
    { id : Id.t
    ; title : string
    ; description : string option
    ; keywords : string list
    ; available : (Context.t -> bool[@sexp.opaque])
    ; target : Target.t
    ; priority_aliases : string list
    ; locks_priority_aliases : bool
    ; exact_only : bool
    }
  [@@deriving sexp_of, fields ~getters]

  let normal_mode_only (context : Context.t) =
    Cobalt_core.Mode.equal context.mode Normal
  ;;

  let create_target ~id ~title ?description ?(keywords = []) ?(available = normal_mode_only)
      ?(priority_aliases = []) target
    =
    { id = Id.of_string id; title; description; keywords = priority_aliases @ keywords
    ; available; target; priority_aliases
    ; locks_priority_aliases = (match target with Native _ -> true | Host _ -> false)
    ; exact_only = false }
  ;;

  let create ~id ~title ?description ?keywords ?available ?priority_aliases action =
    create_target ~id ~title ?description ?keywords ?available ?priority_aliases (Native action)
  ;;

  let action t =
    match t.target with
    | Native action -> Some action
    | Host _ -> None
  ;;

  let is_available t context = t.available context

  let create_host ~id ~title ?(aliases = []) ?priority_alias ?(exact_only = false) () =
    { (create_target ~id:("host." ^ id) ~title ~keywords:aliases
         ~priority_aliases:(Option.to_list priority_alias) (Host id))
      with exact_only }
  ;;
end

type t = Entry.t list [@@deriving sexp_of]

let create entries =
  let malformed =
    List.filter_map entries ~f:(fun (entry : Entry.t) ->
      if Id.is_valid entry.id
      then None
      else Some (sprintf "Malformed ID: %S" (Id.to_string entry.id)))
  in
  let duplicates =
    List.map entries ~f:Entry.id
    |> List.find_all_dups ~compare:Id.compare
    |> List.map ~f:(fun id -> sprintf "Duplicate ID: %s" (Id.to_string id))
  in
  let untitled =
    List.filter_map entries ~f:(fun (entry : Entry.t) ->
      if String.is_empty (String.strip entry.title)
      then Some (sprintf "Empty title: %s" (Id.to_string entry.id))
      else None)
  in
  match malformed @ duplicates @ untitled with
  | [] -> Ok entries
  | problems ->
    Or_error.error_s [%message "Invalid command catalog" ~_:(problems : string list)]
;;

let default =
  let editor ~id ~title ?keywords (command : Cobalt_core.Command.t) =
    Entry.create ~id ~title ?keywords (Editor command)
  in
  let view ~id ~title ?description ?keywords ?priority_aliases (command : View_command.t) =
    Entry.create ~id ~title ?description ?keywords ?priority_aliases (View command)
  in
  let numbers = [ "gutter"; "numbering"; "line numbers" ] in
  let conflict = [ "merge"; "rebase"; "markers"; "resolve"; "smerge" ] in
  let problems = View_id.of_string "problems"
  and history = View_id.of_string "history"
  and demo_report = View_id.of_string "demo-report"
  and silver_overview = View_id.of_string "silver-overview"
  and vcs = View_id.of_string "vcs" in
  create
     [ editor ~id:"file.save" ~title:"Save buffer" ~keywords:[ "write"; "w"; "file"; "directory"; "apply"; "permanent delete" ] Save
     ; view ~id:"harness.new-sv" ~title:"Quick-Harness: New SV scratch"
         ~keywords:["scratch"; "systemverilog"; "qh"]
         (Request_view { view = View_id.of_string "quick-harness"; request = "new-sv" })
     ; view ~id:"harness.new-hardcaml" ~title:"Quick-Harness: New Hardcaml scratch"
         ~keywords:["scratch"; "ocaml"; "qh"]
         (Request_view { view = View_id.of_string "quick-harness"; request = "new-hardcaml" })
     ; view ~id:"harness.new-ocaml" ~title:"Quick-Harness: New OCaml scratch"
         ~keywords:["scratch"; "qh"]
         (Request_view { view = View_id.of_string "quick-harness"; request = "new-ocaml" })
     ; view ~id:"harness.run" ~title:"Quick-Harness: Run harness"
         ~keywords:["simulate"; "build"; "qh"]
         (Request_view { view = View_id.of_string "quick-harness"; request = "run" })
     ; view ~id:"harness.waveform" ~title:"Quick-Harness: Open latest waveform"
         ~keywords:["waves"; "vcd"; "qh"]
         (Request_view { view = View_id.of_string "quick-harness"; request = "latest" })
     ; view ~id:"harness.log" ~title:"Quick-Harness: Open latest run log"
         ~keywords:["errors"; "qh"]
         (Request_view { view = View_id.of_string "quick-harness"; request = "log" })
     ; view ~id:"language-servers.inspect" ~title:"Language servers"
        ~description:"Live managed servers and attachments for the current file"
        ~keywords:[ "lsp"; "attached"; "clients"; "status"; "server" ] Show_language_servers
    ; Entry.create ~id:"signature.help" ~title:"Signature help"
        ~available:(fun _ -> true) (View Signature_help)
    ; Entry.create ~id:"signature.toggle" ~title:"Toggle automatic signature help"
        ~available:(fun _ -> true) (View Toggle_signature_help)
    ; view ~id:"navigation.companion" ~title:"Switch interface/implementation"
        ~keywords:[ "counterpart"; "ocaml"; "lsp" ] Switch_companion
    ; view ~id:"navigation.hover" ~title:"Hover" ~keywords:[ "symbol"; "documentation"; "lsp" ] Hover
    ; view ~id:"navigation.declaration" ~title:"Go to declaration" Go_to_declaration
    ; view ~id:"navigation.definition" ~title:"Go to definition" Go_to_definition
    ; view ~id:"navigation.references" ~title:"Find references" ~keywords:[ "symbol"; "lsp" ] Find_references
    ; view ~id:"navigation.instance" ~title:"Select active instance" ~keywords:[ "slang"; "hierarchy" ] Select_active_instance
    ; view ~id:"navigation.instantiation" ~title:"Go to instantiation" Go_to_instantiation
    ; view ~id:"navigation.back" ~title:"Jump back" Jump_back
    ; view ~id:"navigation.forward" ~title:"Jump forward" Jump_forward
    ; view ~id:"tabs.next" ~title:"Next file tab" ~keywords:[ "buffer"; "switch" ] Next_tab
    ; view ~id:"tabs.previous" ~title:"Previous file tab" ~keywords:[ "buffer"; "switch" ] Previous_tab
    ; view ~id:"tabs.close" ~title:"Close file tab" ~keywords:[ "buffer" ] Close_tab
    ; view ~id:"tabs.close-discarding-changes" ~title:"Close file tab, discarding unsaved changes" ~keywords:[ "buffer"; "force close" ] Force_close_tab
    ; view ~id:"file.recreate-missing" ~title:"Recreate missing path" ~keywords:[ "deleted"; "recover" ] Recreate_missing_file
    ; editor
        ~id:"app.quit"
        ~title:"Quit"
        ~keywords:[ "exit"; "close"; "q" ]
        Quit
    ; editor
        ~id:"app.quit-discarding-changes"
        ~title:"Quit, discarding unsaved changes"
        ~keywords:[ "force quit"; "exit"; "q!" ]
        Force_quit
    ; editor ~id:"edit.undo" ~title:"Undo" ~keywords:[ "revert" ] Undo
    ; editor ~id:"edit.redo" ~title:"Redo" Redo
    ; view
        ~id:"view.toggle-absolute-numbers"
        ~title:"Toggle absolute line numbers"
        ~keywords:(numbers @ [ "number"; "nu" ])
        Toggle_absolute_numbers
    ; view
        ~id:"view.toggle-relative-numbers"
        ~title:"Toggle relative line numbers"
        ~keywords:(numbers @ [ "relativenumber"; "rnu" ])
        Toggle_relative_numbers
    ; view
        ~id:"view.toggle-centered"
        ~title:"Toggle centered layout"
        ~keywords:[ "center"; "full width"; "layout" ]
        Toggle_centered
    ; view
        ~id:"view.toggle-smear"
        ~title:"Toggle animated smear cursor"
        ~keywords:[ "animation"; "cursor trail" ]
        Toggle_smear
    ; view
        ~id:"view.toggle-document-decorations"
        ~title:"Toggle document decorations"
        ~keywords:[ "presentation"; "source"; "optional" ]
        Toggle_document_decorations
    ; view
        ~id:"view.reset-layout"
        ~title:"Reset layout"
        ~keywords:[ "default"; "restore"; "layout" ]
        Reset
    ; view
        ~id:"view.move-tile-left-2"
        ~title:"Move document tile left by 2 columns"
        ~keywords:[ "shift" ]
        (Shift (-2))
    ; view
        ~id:"view.move-tile-right-2"
        ~title:"Move document tile right by 2 columns"
        ~keywords:[ "shift" ]
        (Shift 2)
    ; view
        ~id:"view.move-tile-left-10"
        ~title:"Move document tile left by 10 columns"
        ~keywords:[ "shift" ]
        (Shift (-10))
    ; view
        ~id:"view.move-tile-right-10"
        ~title:"Move document tile right by 10 columns"
        ~keywords:[ "shift" ]
        (Shift 10)
    ; view
        ~id:"view.narrow-tile-10"
        ~title:"Narrow document tile by 10 columns"
        ~keywords:[ "width"; "shrink" ]
        (Adjust_width (-10))
    ; view
        ~id:"view.widen-tile-10"
        ~title:"Widen document tile by 10 columns"
        ~keywords:[ "width"; "grow" ]
        (Adjust_width 10)
    ; view
        ~id:"workspace.toggle-status"
        ~title:"Toggle status tile"
        ~keywords:[ "statusline"; "info"; "panel" ]
        Toggle_status
    ; view
        ~id:"workspace.toggle-hotkey-hints"
        ~title:"Toggle tile hotkey hints"
        ~keywords:[ "keys"; "controls"; "help"; "show"; "hide" ]
        Toggle_hotkey_hints
    ; view
        ~id:"buffers.top"
        ~title:"Show open buffers in top strip"
        ~keywords:[ "file tabs"; "presentation"; "horizontal" ]
        (Present_buffers Top)
    ; view
        ~id:"buffers.status-rows"
        ~title:"Show open buffers as status rows"
        ~keywords:[ "file tabs"; "presentation"; "vertical" ]
        (Present_buffers Status_rows)
    ; view
        ~id:"workspace.status-left"
        ~title:"Move status tile left"
        ~keywords:[ "position"; "dock" ]
        (Position_status Left)
    ; view
        ~id:"workspace.status-right"
        ~title:"Move status tile right"
        ~keywords:[ "position"; "dock" ]
        (Position_status Right)
    ; view
        ~id:"workspace.status-above"
        ~title:"Move status tile above"
        ~keywords:[ "position"; "dock"; "top" ]
        (Position_status Above)
    ; view
        ~id:"workspace.status-below"
        ~title:"Move status tile below"
        ~keywords:[ "position"; "dock"; "bottom" ]
        (Position_status Below)
    ; view
        ~id:"workspace.shrink-status"
        ~title:"Shrink status tile by 2"
        ~keywords:[ "size"; "smaller" ]
        (Adjust_status_size (-2))
    ; view
        ~id:"workspace.grow-status"
        ~title:"Grow status tile by 2"
        ~keywords:[ "size"; "bigger" ]
        (Adjust_status_size 2)
    ; view
        ~id:"workspace.toggle-zen"
        ~title:"Toggle zen mode"
        ~keywords:[ "distraction free"; "focus"; "hide" ]
         Toggle_zen
    ; view
        ~id:"workspace.toggle-bare"
        ~title:"Toggle bare mode"
        ~keywords:[ "distraction free"; "minimal"; "focus" ]
        Toggle_bare
     ; view
         ~id:"views.to-tab"
        ~title:"Move focused view to a tab"
        ~keywords:[ "placement"; "tab strip"; "major" ]
         (Place_view { view = None; placement = Tab })
     ; view ~id:"appearance.choose-theme" ~title:"Choose theme"
         ~keywords:[ "appearance"; "colors"; "dark"; "light" ] Open_theme_picker
    ; view
        ~id:"views.to-split"
        ~title:"Move focused view to the split"
        ~keywords:[ "placement"; "pane"; "side by side" ]
        (Place_view { view = None; placement = Split })
    ; view
        ~id:"views.to-band"
        ~title:"Move focused view to the bottom band"
        ~keywords:[ "placement"; "minor" ]
        (Place_view { view = None; placement = Band })
    ; view
        ~id:"views.close"
        ~title:"Close focused view"
        ~keywords:[ "placement"; "hide" ]
        (Place_view { view = None; placement = Hidden })
    ; view
        ~id:"split.next-file"
        ~title:"Split editor with next file tab"
        ~keywords:[ "pane"; "buffer"; "existing"; "side by side" ]
        Split_next_file
    ; view
        ~id:"split.open-file"
        ~title:"Split editor and pick a file"
        ~keywords:[ "pane"; "second editor"; "open"; "picker"; "side by side" ]
        Split_file_picker
    ; view
        ~id:"split.focus-other"
        ~title:"Focus other split pane"
        ~keywords:[ "pane"; "switch"; "window" ]
        Focus_other_pane
    ; view
        ~id:"split.swap"
        ~title:"Swap split sides"
        ~keywords:[ "pane"; "left"; "right" ]
        Swap_split
    ; view
        ~id:"split.grow-view"
        ~title:"Grow split view by 10%"
        ~keywords:[ "pane"; "ratio"; "size"; "wider" ]
        (Adjust_split 10)
    ; view
        ~id:"split.shrink-view"
        ~title:"Shrink split view by 10%"
        ~keywords:[ "pane"; "ratio"; "size"; "narrower" ]
        (Adjust_split (-10))
    ; view
        ~id:"split.close"
        ~title:"Close split"
        ~keywords:[ "pane"; "view"; "hide"; "unsplit" ]
        Close_split
    ; view
        ~id:"problems.toggle"
        ~title:"Toggle problems tile"
        ~keywords:[ "errors"; "diagnostics"; "warnings" ]
        (Toggle_view problems)
    ; view
        ~id:"problems.focus"
        ~title:"Focus problems"
        ~keywords:[ "errors"; "diagnostics"; "warnings" ]
        (Focus_view problems)
    ; view
        ~id:"problems.toggle-filter"
        ~title:"Toggle problems filter (workspace / current document)"
        ~keywords:[ "errors"; "diagnostics" ]
        Toggle_problems_filter
    ; view
        ~id:"problems.inspect"
        ~title:"Inspect next problem"
        ~keywords:[ "errors"; "details"; "cycle" ]
        Inspect_problems
    ; view
        ~id:"history.toggle"
        ~title:"Toggle notification history"
        ~keywords:[ "messages"; "log"; "notifications" ]
        (Toggle_view history)
    ; view
        ~id:"history.focus"
        ~title:"Focus notification history"
        ~keywords:[ "messages"; "log"; "notifications" ]
        (Focus_view history)
    ; view
        ~id:"report.toggle"
        ~title:"Toggle demo report"
        ~keywords:[ "demo" ]
        (Toggle_view demo_report)
    ; view
        ~id:"report.focus"
        ~title:"Focus demo report"
        ~keywords:[ "demo" ]
        (Focus_view demo_report)
    ; view
        ~id:"silver-overview.toggle"
        ~title:"Toggle Silver: Overview"
        ~keywords:[ "companion"; "run"; "status" ]
        ~priority_aliases:[ "Toggle Silver: Overview"; "Toggle Silver overview" ]
        (Toggle_view silver_overview)
    ; view
        ~id:"silver-overview.focus"
        ~title:"Focus Silver: Overview"
        ~keywords:[ "companion"; "run"; "status" ]
        ~priority_aliases:[ "ov"; "Focus Silver: Overview"; "Focus Silver overview" ]
        (Show_view silver_overview)
    ; view
        ~id:"vcs.open"
        ~title:"VCS: open or focus"
        ~keywords:[ "git"; "status"; "diff"; "magit"; "lazygit" ]
        (Focus_view vcs)
    ; view
        ~id:"vcs.to-tab"
        ~title:"VCS: move to a tab"
        ~keywords:[ "git"; "placement"; "tab strip" ]
        (Place_view { view = Some vcs; placement = Tab })
    ; view
        ~id:"vcs.to-split"
        ~title:"VCS: move to the split"
        ~keywords:[ "git"; "placement"; "pane"; "side by side" ]
        (Place_view { view = Some vcs; placement = Split })
    ; view
        ~id:"vcs.close"
        ~title:"VCS: close"
        ~keywords:[ "git"; "hide" ]
        (Place_view { view = Some vcs; placement = Hidden })
    ; view
        ~id:"vcs.commit-finish"
        ~title:"VCS: finish commit"
        ~keywords:[ "git"; "commit"; "message"; "amend" ]
        (Request_view { view = vcs; request = "commit-finish" })
    ; view
        ~id:"vcs.commit-abort"
        ~title:"VCS: abort commit"
        ~keywords:[ "git"; "commit"; "message"; "cancel" ]
        (Request_view { view = vcs; request = "commit-abort" })
    ; view
        ~id:"vcs.file-log"
        ~title:"VCS: history of this file"
        ~keywords:[ "git"; "log"; "history"; "file"; "follow" ]
        (Request_view { view = vcs; request = "file-log" })
    ; editor
        ~id:"conflict.keep-upper"
        ~title:"Conflict: keep upper (ours)"
        ~keywords:(conflict @ [ "ours"; "head"; "mine"; "upstream" ])
        (Keep_conflict Upper)
    ; editor
        ~id:"conflict.keep-lower"
        ~title:"Conflict: keep lower (theirs)"
        ~keywords:(conflict @ [ "theirs"; "other" ])
        (Keep_conflict Lower)
    ; editor
        ~id:"conflict.keep-both"
        ~title:"Conflict: keep both"
        ~keywords:(conflict @ [ "all"; "union" ])
        (Keep_conflict Both)
    ; editor
        ~id:"conflict.keep-base"
        ~title:"Conflict: keep base"
        ~keywords:(conflict @ [ "ancestor"; "original"; "diff3" ])
        (Keep_conflict Base)
    ; editor
        ~id:"conflict.next"
        ~title:"Conflict: next"
        ~keywords:(conflict @ [ "jump"; "go to" ])
        (Move { motion = Next_conflict; count = None })
    ; editor
        ~id:"conflict.previous"
        ~title:"Conflict: previous"
        ~keywords:(conflict @ [ "jump"; "go to" ])
        (Move { motion = Previous_conflict; count = None })
    ; view
        ~id:"source.restart"
        ~title:"Restart diagnostic source"
        ~keywords:[ "checker"; "lsp"; "diagnostics" ]
        Restart_source
    ; view
        ~id:"document.lines"
        ~title:"Search current document lines"
        ~keywords:[ "fuzzy"; "unsaved"; "jump" ]
        Open_line_picker
    ; view ~id:"project.contents" ~title:"Search project contents"
        ~keywords:[ "grep"; "literal"; "disk" ] Open_content_picker
    ; view ~id:"project.files" ~title:"Find project files"
        ~keywords:[ "fuzzy"; "open"; "picker" ] Open_file_picker
     ; view ~id:"directory.toggle-mark" ~title:"Toggle directory entry mark" Toggle_entry_mark
     ; view ~id:"directory.mark-selection" ~title:"Mark directory selection" Mark_selection
     ; view ~id:"directory.unmark-selection" ~title:"Unmark directory selection" Unmark_selection
     ; view ~id:"directory.clear-marks" ~title:"Clear directory marks" Clear_directory_marks
      ; view ~id:"directory.open-marked" ~title:"Open marked files" Open_marked_files
      ; view ~id:"directory.major" ~title:"Show directory in main area" Directory_major
      ; view ~id:"directory.side" ~title:"Show directory in sidebar" Directory_side
      ; view ~id:"directory.hide" ~title:"Hide directory browser" Hide_directory
      ; view ~id:"directory.focus" ~title:"Focus directory browser or editor" Focus_directory
      ; view ~id:"directory.grow" ~title:"Grow directory sidebar" (Adjust_directory_size 4)
      ; view ~id:"directory.shrink" ~title:"Shrink directory sidebar" (Adjust_directory_size (-4))
    ; view ~id:"terminal.toggle" ~title:"Toggle Tile Term" ~description:"Show or hide the selected Tile Term." ~keywords:[ "shell"; "toggleterm"; "float" ] Toggle_terminal
    ; view ~id:"terminal.grow" ~title:"Grow Tile Term" ~description:"Increase the selected Tile Term's preferred size." ~keywords:[ "shell"; "size" ] (Adjust_terminal_size 1)
    ; view ~id:"terminal.shrink" ~title:"Shrink Tile Term" ~description:"Decrease the selected Tile Term's preferred size." ~keywords:[ "shell"; "size" ] (Adjust_terminal_size (-1))
     ; view ~id:"terminal.reset-size" ~title:"Reset Tile Term size" ~description:"Restore the selected Tile Term's default size." ~keywords:[ "shell"; "default" ] Reset_terminal_size
    ; view ~id:"completion.toggle" ~title:"Toggle automatic completion"
        ~description:"Buffer words, snippets and language-server suggestions (enabled by default)"
        ~keywords:[ "suggestions"; "autocomplete" ] Toggle_completion
    ; view ~id:"completion.ghost" ~title:"Toggle completion ghost preview"
        ~keywords:[ "suggestions"; "inline"; "suffix" ] Toggle_completion_ghost
    ; view ~id:"configuration.open" ~title:"Open configuration"
        ~keywords:[ "settings"; "config.ml"; "preferences" ] Open_configuration
    ; view ~id:"snippets.insert" ~title:"Insert snippet"
        ~description:"Search applicable templates and insert at the cursor"
        ~keywords:[ "templates"; "placeholders"; "expand" ] Insert_snippet
    ; view ~id:"configuration.reload" ~title:"Reload configuration"
        ~description:"Apply a fresh defaults-based configuration snapshot"
        ~keywords:[ "settings"; "config.ml"; "preferences" ] Reload_configuration
    ; view ~id:"snippets.reload" ~title:"Reload snippets"
        ~description:"Reload user snippets from snippets.json"
        ~keywords:[ "templates"; "configuration"; "completion" ] Reload_snippets
    ; view ~id:"development.insert-demo-snippet" ~title:"Insert demo snippet"
        ~description:"Development utility: linked snippet fields in the current file (no server required)"
        ~keywords:[ "development"; "test"; "placeholders"; "linked fields" ] Insert_demo_snippet
    ; view ~id:"workspace.editor" ~title:"Restore and focus file editor workspace"
        ~priority_aliases:[ "ed" ] Restore_editor_workspace
    ; view ~id:"workspace.hide-tile" ~title:"Hide focused tile"
        ~priority_aliases:[ "hide"; "hide tile" ] Hide_focused_tile
    ; view ~id:"workspace.unhide-tile" ~title:"Unhide tile"
        ~priority_aliases:[ "unhide" ] Unhide_tile
    ; view ~id:"workspace.toggle-mouse" ~title:"Toggle mouse"
        ~priority_aliases:[ "mouse" ] Toggle_mouse
    ]
  |> Or_error.ok_exn
;;

let entries = Fn.id
let find t id = List.find t ~f:(fun (entry : Entry.t) -> Id.equal entry.id id)

let with_host_commands ?(delegate_aliases = []) t commands =
  let seen = Hash_set.create (module String) in
  List.iter t ~f:(fun entry -> Hash_set.add seen (Id.to_string (Entry.id entry)));
  let host_entries =
    List.filter_map commands ~f:(fun ({ id; title; aliases } : Host_command.t) ->
      let catalog_id = "host." ^ id in
      if not (Id.is_valid id)
         || String.is_empty (String.strip title)
         || Hash_set.mem seen catalog_id
      then None
      else (
        Hash_set.add seen catalog_id;
        Some (Entry.create_host ~id ~title ~aliases ())))
  in
  let delegated =
    List.filter_map delegate_aliases ~f:(fun (fallback, alias) ->
      Option.filter (find t fallback)
        ~f:(fun entry -> List.mem entry.priority_aliases alias ~equal:String.Caseless.equal)
      |> Option.bind ~f:(fun _ ->
        List.find host_entries ~f:(fun entry ->
          List.exists entry.keywords ~f:(fun keyword ->
            String.Caseless.equal (String.strip keyword) alias)))
      |> Option.map ~f:(fun entry -> fallback, Entry.id entry, alias))
  in
  List.filter t ~f:(fun entry ->
    not (List.exists delegated ~f:(fun (fallback, _, _) -> Id.equal (Entry.id entry) fallback)))
  @ List.map host_entries ~f:(fun entry ->
    let aliases = List.filter_map delegated ~f:(fun (_, host, alias) ->
      Option.some_if (Id.equal (Entry.id entry) host) alias) in
    if List.is_empty aliases then entry
    else { entry with priority_aliases = aliases; locks_priority_aliases = true })
;;

module Field = struct
  type t =
    | Title
    | Id
    | Keyword
  [@@deriving sexp_of, equal]
end

type result = (Entry.t, Field.t) Fuzzy.Match.t

let fields (entry : Entry.t) : Field.t Fuzzy.Field.t list =
  { tag = Title; text = entry.title; weight = 100 }
  :: { tag = Id; text = Id.to_string entry.id; weight = 80 }
  :: List.map entry.keywords ~f:(fun text -> { Fuzzy.Field.tag = Field.Keyword; text; weight = 70 })
;;

let exact_priority ~query (entry : Entry.t) =
  let exact candidate = String.Caseless.equal (String.strip candidate) query in
  if String.is_empty query
     || not (exact entry.title || exact (Id.to_string entry.id)
             || List.exists entry.keywords ~f:exact)
  then 2
  else
    match entry.target with
    | Native _ -> 0
    | Host _ -> 1
;;

let exact_alias ~query (entry : Entry.t) =
  not (String.is_empty query)
  && List.exists entry.priority_aliases ~f:(String.Caseless.equal query)
;;

let pinned_alias t ~query =
  let query = String.strip query in
  List.find_map t ~f:(fun (entry : Entry.t) ->
    Option.some_if (entry.locks_priority_aliases && exact_alias ~query entry) (Entry.id entry))
;;

let search_with_exact t context ~query =
  let query = String.strip query in
  let pinned = pinned_alias t ~query in
  let is_pinned entry = Option.exists pinned ~f:(Id.equal (Entry.id entry)) in
  let ranked =
    List.filter t ~f:(fun entry ->
      is_pinned entry
      || (Entry.is_available entry context && (not entry.exact_only || exact_alias ~query entry)))
    |> List.map ~f:(fun entry -> entry, fields entry)
    |> Fuzzy.rank ~query
  in
  let priority_matches, ranked =
    List.partition_tf ranked ~f:(fun (result : result) -> exact_alias ~query result.item)
  in
  let pinned_matches, priority_matches =
    List.partition_tf priority_matches ~f:(fun (result : result) -> is_pinned result.item)
  in
  let priority (result : result) = exact_priority ~query result.item in
  let has_host_exact =
    List.exists ranked ~f:(fun result ->
      match Entry.target result.item with
      | Native _ -> false
      | Host _ -> priority result = 1)
  in
  if Option.is_some pinned
  then pinned_matches @ priority_matches @ ranked, pinned
  else if not (List.is_empty priority_matches)
  then
    priority_matches @ ranked, Option.map (List.hd priority_matches) ~f:(fun result -> Entry.id result.item)
  else if not has_host_exact
  then ranked, None
  else (
    let native, rest = List.partition_tf ranked ~f:(fun result -> priority result = 0) in
    let host, fuzzy = List.partition_tf rest ~f:(fun result -> priority result = 1) in
    let sorted = native @ host @ fuzzy in
    sorted, Option.map (List.hd sorted) ~f:(fun result -> Entry.id result.item))
;;

let search t context ~query = fst (search_with_exact t context ~query)

let title_positions (result : result) =
  List.find_map result.positions ~f:(fun ((field : _ Fuzzy.Field.t), offsets) ->
    Option.some_if (Field.equal field.tag Title) offsets)
  |> Option.value ~default:[]
;;
