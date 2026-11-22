open! Core
open Cobalt_screen
open Cobalt_app

let width = 100
let height = 20
let run t keys = Helpers.run ~width ~height t (Helpers.keys keys)
let hide t = run t " cchide<CR>"
let unhide t = run t " ccunhide<CR>"
let frame t = Frame.render t ~width ~height
let shown t text = String.is_substring (Frame.to_string (frame t)) ~substring:text
let focus t id = Cobalt_tile.View_id.equal (Ui_state.focused_view t ~width ~height) id
let problems_shown t = Option.is_some (Ui_state.minor_layout t ~width ~height Problems_tile.id)
let editor t = Controller.editor (Ui_state.controller t)
let contents t = Cobalt_core.Text_buffer.to_string (Cobalt_core.Editor.text (editor t))
let active t = Option.value_exn (Session.active_id (Ui_state.session t))

let%test_unit "last tile leaves a non-editable surface with palette access and retained undo" =
  let t = run (Helpers.ui "keep this text") "iX<Esc>" in
  let original = editor t in
  let t = hide t in
  assert (Ui_state.has_hidden_tile t);
  assert (shown t "No tile shown");
  assert (not (shown t "keep this text"));
  assert (Option.is_none (frame t).cursor);
  assert (List.for_all (frame t).rows ~f:(fun row -> Span.total_width row = width));
  let t = run t "ixx<Esc>" in
  assert (phys_equal original (editor t));
  let t = unhide t in
  assert (not (Ui_state.has_hidden_tile t));
  assert (phys_equal original (editor t));
  assert (shown t "Xkeep this text");
  assert (String.equal (contents (run t "u")) "keep this text")
;;

let%test_unit "independent workspace tiles restore in reverse hide order" =
  let t = run (Helpers.ui "main contents") " vo" in
  assert (focus t Problems_tile.id);
  let t = hide t in
  assert (not (problems_shown t));
  assert (shown t "main contents");
  let t = hide t in
  assert (shown t "No tile shown");
  let t = unhide t in
  assert (shown t "main contents");
  assert (not (problems_shown t));
  let t = unhide t in
  assert (focus t Problems_tile.id);
  assert (shown t "Problems");
  assert (not (Ui_state.has_hidden_tile t))
;;

let%test_unit "hiding Problems keeps the current selection and details open" =
  let t = run (Test_problem_navigation.create ()) " vojjjje" in
  let selected t = (Ui_state.problem_navigation t ~width ~height).selected in
  let before = selected t in
  assert (Option.is_some before);
  assert (Ui_state.problem_details t);
  let t = hide t in
  assert (Option.is_none (Ui_state.minor_layout t ~width ~height Problems_tile.id));
  let t = unhide t in
  assert (focus t Problems_tile.id);
  assert (Option.equal Problems.Key.equal before (selected t));
  assert (Ui_state.problem_details t)
;;

let%test_unit "resizing away the invoking tile never redirects hide to the editor" =
  let t = run (Helpers.ui "retained editor") " vo cchide" in
  let t = Helpers.run ~width ~height:4 t [ Resize ] in
  assert (Option.is_some (Ui_state.palette t));
  assert (Option.is_none (Ui_state.minor_layout t ~width ~height:4 Problems_tile.id));
  let t = Helpers.run ~width ~height:4 t (Helpers.keys "<CR>") in
  assert (Option.is_none (Ui_state.palette t));
  assert (not (Ui_state.has_hidden_tile t));
  assert (shown t "retained editor");
  assert (shown t "Problems")
;;

let%test_unit "a split view and its editor do not replace one another when hidden" =
  let t = run (Helpers.ui "editor content") " vo ss" in
  let workspace t = Ui_state.workspace t ~width ~height in
  let original = workspace t in
  assert (Option.is_some (Workspace.minor original Problems_tile.id));
  let t = hide t in
  assert (Option.is_none (Workspace.minor (workspace t) Problems_tile.id));
  assert (shown t "editor content");
  let t = unhide t in
  assert (Workspace.equal (workspace t) original);
  assert (focus t Problems_tile.id);
  let t = run t " sf" |> hide in
  assert (not (shown t "editor content"));
  assert (focus t Problems_tile.id);
  let t = unhide t in
  assert (Workspace.equal (workspace t) original);
  assert (shown t "editor content")
;;

let%test_unit "major view tab hide keeps its slot, order and background editor" =
  let t = run (Helpers.ui "underlying file") " vo st" in
  assert (focus t Problems_tile.id);
  let entries = Ui_state.tab_entries t in
  let t = hide t in
  assert (not (shown t "underlying file"));
  assert (not (problems_shown t));
  assert (List.equal Tab_strip.Entry.equal entries (Ui_state.tab_entries t));
  let t = unhide t in
  assert (focus t Problems_tile.id);
  assert (List.equal Tab_strip.Entry.equal entries (Ui_state.tab_entries t))
;;

let%test_unit "popup dismissal never hides or restores the popup itself" =
  let t = run (Test_view_popup.create ()) " vxc" in
  assert (Option.is_some (Ui_state.popup t));
  let t = hide t in
  assert (Option.is_none (Ui_state.popup t));
  assert (not (Ui_state.view_visible t Test_view_popup.Kiln.id));
  assert (String.is_empty (Test_view_popup.log t));
  let t = unhide t in
  assert (Option.is_none (Ui_state.popup t));
  assert (focus t Test_view_popup.Kiln.id);
  assert (String.is_empty (Test_view_popup.log t))
;;

let%test_unit "a hidden view keeps receiving its job and restoration does not resubmit" =
  let module Worker = Test_view_jobs in
  let t = run (Worker.create ()) " vx" in
  let t, jobs = Ui_state.take_vcs_jobs t in
  let job = List.hd_exn jobs in
  let t = hide t in
  assert (not (Ui_state.view_visible t Worker.alpha));
  let t = Worker.feed t [ Worker.started job; Worker.succeeded job ] in
  let t = unhide t in
  assert (focus t Worker.alpha);
  assert (shown t "finished");
  assert (List.is_empty (snd (Ui_state.take_vcs_jobs t)))
;;

let%test_unit "the sidebar restores the same directory buffer and keeps file context" =
  Test_editor_split.with_files (fun _ a _ _ ->
    let t = run (Test_editor_split.create a) " ds" in
    let directory t = Session.directory_buffer (Ui_state.session t) |> Option.value_exn in
    let original = directory t in
    assert (focus t Ui_state.directory_id);
    let t = hide t in
    assert (Option.is_none (Ui_state.side_layout t ~width ~height));
    assert (shown t "ALPHA");
    assert (Buffer_id.equal original.id (directory t).id);
    let t = unhide t in
    assert (focus t Ui_state.directory_id);
    assert (Option.is_some (Ui_state.side_layout t ~width ~height));
    assert (Buffer_id.equal original.id (directory t).id);
    Session.dispose (Ui_state.session t))
;;

let%test_unit "a hidden major directory can be restored after navigating to a file" =
  Test_editor_split.with_files (fun root a b _ ->
    let t = Test_editor_split.create a in
    let t = Ui_state.show_directory t ~width ~height root |> Or_error.ok_exn in
    let directory t = Session.input_directory (Ui_state.session t) |> Option.value_exn in
    let original = directory t in
    let t = hide t in
    assert (shown t "No tile shown");
    assert (not (shown t "ALPHA"));
    let t, _ = Test_editor_split.open_ t b in
    assert (shown t "BETA");
    let t = unhide t in
    assert (Buffer_id.equal original.id (directory t).id);
    assert (not (shown t "BETA_00"));
    Session.dispose (Ui_state.session t))
;;

let%test_unit "hide either editor split pane and restore its position, focus and edits" =
  Test_editor_split.with_files (fun _ a b _ ->
    let t = Test_editor_split.create a in
    let aid = active t in
    let t, bid = Test_editor_split.open_ t b in
    let t = run t " sn" in
    let panes t = Ui_state.editor_panes t ~width ~height in
    let order t = List.map (panes t) ~f:(fun p -> p.buffer) in
    let initial_order = order t in
    let t = run t "iX<Esc>" in
    let shown_id = active t in
    let other = if Buffer_id.equal shown_id aid then bid else aid in
    let t = hide t in
    assert (List.equal Buffer_id.equal (order t) [ other ]);
    assert (Buffer_id.equal (active t) other);
    let t = hide t in
    assert (List.is_empty (panes t));
    assert (shown t "No tile shown");
    let t = unhide t in
    assert (List.equal Buffer_id.equal (order t) [ other ]);
    let t = unhide t in
    assert (List.equal Buffer_id.equal (order t) initial_order);
    assert (Buffer_id.equal (active t) shown_id);
    assert (String.is_prefix (contents t) ~prefix:"X");
    Session.dispose (Ui_state.session t))
;;

let%test_unit "unhide reactivates the hidden editor after selecting a different file" =
  Test_editor_split.with_files (fun _ a b _ ->
    let t = Test_editor_split.create a in
    let aid = active t in
    let t = hide t in
    let t, bid = Test_editor_split.open_ t b in
    assert (Buffer_id.equal (active t) bid);
    assert (shown t "BETA_00");
    let t = unhide t in
    assert (Buffer_id.equal (active t) aid);
    assert (shown t "ALPHA_00");
    Session.dispose (Ui_state.session t))
;;

let%test_unit "unhide reactivates the hidden registered tab after selecting a file" =
  let t = run (Helpers.ui "file contents") " vo st" in
  let entries = Ui_state.tab_entries t in
  let t = hide t in
  let file = active t in
  let t = Ui_state.activate_buffer t ~width ~height file |> Or_error.ok_exn in
  assert (shown t "file contents");
  let t = unhide t in
  assert (focus t Problems_tile.id);
  assert (problems_shown t);
  assert (List.equal Tab_strip.Entry.equal entries (Ui_state.tab_entries t))
;;

let%test_unit "a terminal caller can hide from normal inspection without restarting PTY" =
  let t = run (Helpers.ui "main") " /" in
  let t, requests = Ui_state.take_terminal_requests t in
  assert (not (List.is_empty requests));
  let snapshot = Test_terminal.snapshot () in
  let t = Helpers.run ~width ~height t [ Terminal (Snapshot snapshot); Test_terminal.ctrl ' ' ] in
  let inspection = Ui_state.terminal_inspection t |> Option.value_exn in
  let t = run t " cc" in
  assert (Option.is_some (Ui_state.palette t));
  assert (shown t "Commands");
  let t = run t "hide<CR>" in
  assert (not (Ui_state.terminal_visible t));
  assert (shown t "main");
  let t = unhide t in
  assert (Ui_state.terminal_visible t);
  assert (phys_equal inspection (Option.value_exn (Ui_state.terminal_inspection t)));
  assert (phys_equal snapshot (Option.value_exn (Ui_state.terminal_snapshot t)));
  assert (List.is_empty (snd (Ui_state.take_terminal_requests t)))
;;
