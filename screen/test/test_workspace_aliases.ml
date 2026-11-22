open! Core
open Cobalt_app
open Cobalt_screen

let width = 140
let height = 34
let run ui keys = Helpers.run ~width ~height ui (Helpers.keys keys)
let focus ui = Ui_state.focused_view ui ~width ~height |> Cobalt_tile.View_id.to_string
let shown ui substring = String.is_substring (Frame.to_string (Frame.render ui ~width ~height)) ~substring
let command ui query = run ui (" cc" ^ query ^ "<Tab><CR>")

let editors ui =
  List.map (Ui_state.editor_panes ui ~width ~height) ~f:(fun pane -> pane.buffer)
;;

let assert_first ui id =
  let palette = Ui_state.palette ui |> Option.value_exn |> Palette_tile.palette in
  let module P = Cobalt_palette.Palette in
  let module C = Cobalt_palette.Catalog in
  let first = List.hd_exn (P.results palette) in
  assert (String.equal id (C.Id.to_string (C.Entry.id first.item)));
  assert (String.equal id (C.Id.to_string (Option.value_exn (P.selected palette))))
;;

let%test_unit "ed restores editors behind a generically hidden kickoff tab, preserving order and edits" =
  Test_editor_split.with_files (fun _ a b _ ->
    let kickoff = Silver_kickoff_tile.Presentation.unavailable "Fixture has no named flows" in
    let ui = Test_editor_split.create
        ~views:[ Silver_kickoff_tile.entry kickoff; Silver_kickoff_tile.review_entry kickoff ] a in
    let ui, _ = Test_editor_split.open_ ui b in
    let ui = run ui " sniX<Esc>" in
    let before = editors ui in
    let focused_buffer ui = List.find (Ui_state.editor_panes ui ~width ~height)
        ~f:(fun pane -> pane.focused) |> Option.map ~f:(fun pane -> pane.buffer) in
    assert (List.length before = 2);
    let ui = command ui "hide" in
    let survivor = focused_buffer ui in
    let ui = command ui "hide" in
    assert (List.is_empty (editors ui));
    let ui = command ui "Silver: Flow Review" in
    assert (String.equal (focus ui) "silver-kickoff-review");
    assert (Option.equal View_registry.Placement.equal
      (View_registry.placement (Ui_state.views ui) Silver_kickoff_tile.review_id) (Some Tab));
    let tabs = Ui_state.tab_entries ui in
    let ui = command ui "hide" in
    assert (shown ui "No tile shown");
    let ui = run ui " cc ED " in
    assert_first ui "workspace.editor";
    let ui = run ui "<Tab><CR>" in
    assert (String.equal (focus ui) "document");
    assert (List.equal Buffer_id.equal before (editors ui));
    assert (Option.equal Buffer_id.equal survivor (focused_buffer ui));
    assert (List.equal Tab_strip.Entry.equal tabs (Ui_state.tab_entries ui));
    assert (not (Ui_state.view_visible ui Silver_kickoff_tile.review_id));
    let tile = View_registry.find (Ui_state.views ui) Silver_kickoff_tile.review_key |> Option.value_exn in
    let _, intents = Silver_kickoff_tile.take_intents tile in
    assert (List.is_empty intents);
    let ui = run ui " sfiY<Esc>" in
    assert (shown ui "YX");
    Session.dispose (Ui_state.session ui))
;;

let%test_unit "ed restores a file from a major directory and focuses it from a minor tile" =
  Test_editor_split.with_files (fun root a _ _ ->
    let ui = Test_editor_split.create a in
    let ui = Ui_state.show_directory ui ~width ~height root |> Or_error.ok_exn in
    assert (Option.is_some (Session.input_directory (Ui_state.session ui)));
    let ui = command ui "ed" in
    assert (Option.is_none (Session.input_directory (Ui_state.session ui)));
    assert (shown ui "ALPHA");
    let ui = run ui " vo" in
    assert (String.equal (focus ui) "problems");
    let ui = command ui "ed" in
    assert (String.equal (focus ui) "document");
    assert (Ui_state.view_visible ui Problems_tile.id);
    assert (shown (run ui "iX<Esc>") "XALPHA");
    Session.dispose (Ui_state.session ui))
;;

let%test_unit "ov and st are pinned destinations from other tiles, and never launch" =
  let snapshot = Silver_stage_tile.Snapshot.unavailable "Fixture has no stages" in
  let ui = Ui_state.create
      ~views:[ Silver_overview_tile.entry [ Silver_overview_tile.Display_row.message "OVERVIEW_MARKER" ]
             ; Silver_stage_tile.entry snapshot ]
      (Ui_state.controller (Helpers.ui "FILE_MARKER"))
    |> Fn.flip Ui_state.with_silver_stage snapshot in
  let ui = command ui "OV" in
  assert (String.equal (focus ui) "silver-overview");
  let ui = command ui "hide" in
  assert (not (Ui_state.view_visible ui Silver_overview_tile.id));
  let ui = run ui " ccst" in
  assert_first ui "silver.stage.open";
  let ui = run ui "<Tab><CR>" in
  assert (String.equal (focus ui) "silver-stage");
  let ui = command ui "st" in
  assert (String.equal (focus ui) "silver-stage");
  let ui = command ui "ov" in
  assert (String.equal (focus ui) "silver-overview");
  assert (shown ui "OVERVIEW_MARKER");
  let stage = View_registry.find (Ui_state.views ui) Silver_stage_tile.key |> Option.value_exn in
  assert (List.is_empty (snd (Silver_stage_tile.take_intents stage)));
  let overview = View_registry.find (Ui_state.views ui) Silver_overview_tile.key |> Option.value_exn in
  assert (List.is_empty (snd (Silver_overview_tile.take_intents overview)))
;;

let%test_unit "unavailable Silver destinations do not fall through to matching host commands" =
  let ui = Helpers.ui "FILE_MARKER" in
  let ui = Ui_state.with_host_commands ui
      [ { id = "competing-ov"; title = "ov"; aliases = [] }
       ; { id = "competing-st"; title = "st"; aliases = [] }
       ; { id = "competing-flow"; title = "Flow provider"; aliases = [ "flow" ] }
       ] in
  let ui = run ui " ccov" in
  assert_first ui "silver-overview.focus";
  let ui = run ui "<Tab><CR>" in
  assert (shown ui "nothing ran");
  let ui = run ui " ccst" in
  assert_first ui "silver.stage.open";
  let ui = run ui "<Tab><CR>" in
  assert (shown ui "nothing ran");
  let ui = run ui " cc FLOW " in
  assert_first ui "silver-kickoff.focus";
  assert (shown ui "Silver: Flow Runner");
  let ui = run ui "<Tab>" in
  assert_first ui "silver-kickoff.focus";
  let ui = run ui "<S-Tab>" in
  assert_first ui "silver-kickoff.focus";
  let ui = run ui "<CR>" in
  assert (shown ui "Silver: Flow Runner is unavailable here; nothing ran");
  assert (String.equal (focus ui) "document");
  assert (List.is_empty (snd (Ui_state.take_host_command_requests ui)))
;;

let%test_unit "ed is reserved even in a workspace without any file buffer" =
  Test_editor_split.with_files (fun root _ _ _ ->
    let ui = Ui_state.create (Startup.open_path ~cell_width:Cell_map.width root |> Or_error.ok_exn) in
    let ui = Ui_state.with_host_commands ui
        [ { id = "competing-ed"; title = "ed"; aliases = [] } ] in
    let ui = run ui " cced" in
    assert_first ui "workspace.editor";
    let ui = run ui "<Tab><CR>" in
    assert (Option.exists (Ui_state.message ui) ~f:(fun message ->
      String.is_prefix message.text ~prefix:"No file editor to restore"));
    assert (Option.is_some (Session.input_directory (Ui_state.session ui)));
    assert (List.is_empty (snd (Ui_state.take_host_command_requests ui)));
    Session.dispose (Ui_state.session ui))
;;
