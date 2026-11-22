open! Core
open Cobalt_app
open Cobalt_core
open Cobalt_screen

let width = 100
let height = 12
let run ?(width = width) ?(height = height) ui notation =
  Helpers.run ~width ~height ui (Helpers.keys notation)
;;

let pointer ?(width = width) ?(height = height) ui action ~x ~y =
  Helpers.run ~width ~height ui [ Ui_state.Input.Pointer { action; x; y } ]
;;

let click ui ~x ~y = pointer ui `Left_click ~x ~y

let editor ui = Controller.editor (Ui_state.controller ui)
let mode ui = Editor.mode (editor ui)
let cursor ui = Editor.cursor (editor ui)
let line ui = Editor.cursor_line (editor ui)
let ordinary = List.init 45 ~f:(fun i -> sprintf "file-row-%02d\n" i) |> String.concat
let active ui = Session.active_id (Ui_state.session ui) |> Option.value_exn
let active_is ui id = Buffer_id.equal (active ui) id
let layout ui = Ui_state.geometry ui ~width ~height
let redraw ui = Frame.render ui ~width ~height

let%test_unit "standalone mouse reporting gates pointer input without taking over hosted terminals" =
  let hosted = Helpers.ui ordinary in
  assert (Option.is_none (Ui_state.mouse_reporting hosted));
  assert (phys_equal hosted (Ui_state.toggle_mouse hosted));
  let ui = Ui_state.with_mouse_reporting hosted ~enabled:true in
  let g = layout ui in
  let click ui = click ui ~x:(g.text.x + 4) ~y:(g.text.y + 1) in
  let off = Ui_state.toggle_mouse ui in
  assert (Option.equal Bool.equal (Ui_state.mouse_reporting off) (Some false));
  assert (cursor (click off) = cursor off);
  let scrolled = pointer off `Wheel_down ~x:g.text.x ~y:g.text.y in
  assert ((Ui_state.fitted_scroll scrolled ~width ~height).top = 0);
  let on = Ui_state.toggle_mouse off in
  assert (Option.equal Bool.equal (Ui_state.mouse_reporting on) (Some true));
  assert (line (click on) = 1)
;;

let%test_unit "tab layout and hits share display-cell widths and exclude separators" =
  let tabs =
    [ { Tab_strip.Item.label = "界"; active = false; modified = false; missing = false }
    ; { label = "a"; active = true; modified = false; missing = false }
    ] in
  let hits = File_tabs.hit tabs ~width:20 in
  assert (Span.total_width (File_tabs.render_items tabs ~width:20) = 20);
  assert (Option.is_none (hits ~column:0));
  assert (Option.equal Int.equal (hits ~column:3) (Some 0));
  assert (Option.equal Int.equal (hits ~column:4) (Some 0));
  assert (Option.is_none (hits ~column:5));
  assert (Option.equal Int.equal (hits ~column:6) (Some 1));
  assert (Option.is_none (hits ~column:19))
;;

let%test_unit "file pointer cells use the rendered viewport, including UTF-8, gutter and EOL" =
  let prefs = { Geometry.Prefs.default with line_numbers = Absolute } in
  let ui = Helpers.ui ~prefs "a\t界z\nshort\n" in
  let g = layout ui in
  let x = g.text.x and y = g.text.y in
  assert (g.border && g.gutter.width > 0);
  let ui = click ui ~x:(x + 6) ~y in
  assert (cursor ui = 1);
  let ui = click ui ~x:(x + 9) ~y in
  assert (cursor ui = 2);
  assert (phys_equal ui (click ui ~x:g.gutter.x ~y:(y + 1)));
  assert (phys_equal ui (click ui ~x ~y:g.tile.y));
  assert (phys_equal ui (click ui ~x ~y:(y + 4)));
  let ui = click ui ~x:(x + 15) ~y in
  assert (cursor ui = 5 && Mode.equal (mode ui) Normal);
  let ui = run ui "v0" in
  assert (Option.is_some (Editor.selection (editor ui)));
  let ui = click ui ~x:(x + 12) ~y in
  assert (cursor ui = 5 && Mode.equal (mode ui) Normal);
  assert (Option.is_none (Editor.selection (editor ui)));
  let ui = run ui "i" in
  let ui = click ui ~x:(x + 15) ~y in
  assert (cursor ui = 6 && Mode.equal (mode ui) Insert);
  let ui = Helpers.run ~width ~height ui
    ([ Ui_state.Input.Paste_start; Pointer { x; y = y + 1; action = `Left_click } ]
     @ Helpers.keys "!" @ [ Paste_end ]) in
  assert (String.equal (Text_buffer.to_string (Editor.text (editor ui))) "a\t界z!\nshort\n");
  let ui = run ui "<Esc>u" in
  assert (String.equal (Text_buffer.to_string (Editor.text (editor ui))) "a\t界z\nshort\n")
;;

let%test_unit "left offset comes from the horizontally scrolled renderer" =
  let ui = Helpers.ui (String.make 150 'a' ^ "\t界XYZ") |> fun ui -> run ui "$" in
  let g = layout ui in
  let fitted = Ui_state.fitted_scroll ui ~width ~height in
  assert (fitted.left > 0);
  let ui = click ui ~x:(g.text.x + 153 - fitted.left) ~y:g.text.y in
  assert (cursor ui = 151);
  let fitted = Ui_state.fitted_scroll ui ~width ~height in
  let ui = click ui ~x:(g.text.x + 151 - fitted.left) ~y:g.text.y in
  assert (cursor ui = 150)
;;

let%test_unit "wheel preserves Visual and history; prefixes do not follow but a boundary motion does" =
  let ui = Helpers.ui ordinary |> fun ui -> run ui "i!<Esc>v" in
  let g = layout ui in
  let old = editor ui in
  let ui = pointer ui `Wheel_down ~x:g.text.x ~y:g.text.y in
  assert (phys_equal (editor ui) old);
  assert ((Ui_state.fitted_scroll ui ~width ~height).top = 3);
  assert (Option.is_none (redraw ui).cursor);
  assert (String.is_substring (Frame.to_string (redraw ui)) ~substring:"file-row-03");
  let ui = run ui "2" in
  assert ((Ui_state.fitted_scroll ui ~width ~height).top = 3);
  let ui = run ui "k" in
  assert (line ui = 0);
  assert ((Ui_state.fitted_scroll ui ~width ~height).top = 0);
  assert (Option.is_some (redraw ui).cursor);
  let ui = run ui "<Esc>u" in
  assert (String.equal (Text_buffer.to_string (Editor.text (editor ui))) ordinary);
  let ui = run ui "i" |> fun ui -> pointer ui `Wheel_down ~x:g.text.x ~y:g.text.y in
  let ui = run ui "x" in
  assert ((Ui_state.fitted_scroll ui ~width ~height).top = 0)
;;

let with_files f =
  let dir = Helpers.scratch_dir "cobalt-pointer-" in
  let paths = List.init 26 ~f:(fun i ->
    Filename.concat dir (sprintf "entry-with-a-long-label-%02d.txt" i)) in
  List.iter paths ~f:(fun path -> Out_channel.write_all path ~data:ordinary);
  Exn.protect ~f:(fun () -> f dir paths)
    ~finally:(fun () ->
      List.iter paths ~f:Core_unix.unlink;
      Core_unix.rmdir dir)
;;

let load path =
  Ui_state.create ~tiles_visible:false
    (Cobalt_app.Startup.open_path ~cell_width:Cell_map.width path |> Or_error.ok_exn)
;;

let open_ ui path = Ui_state.open_file ui ~width ~height path |> Or_error.ok_exn
let directory ui = Session.directory_buffer (Ui_state.session ui) |> Option.value_exn

let dir_geometry ui =
  let side = Ui_state.side_layout ui ~width ~height |> Option.value_exn in
  Ui_state.geometry_in (Ui_state.surface ui ~directory:true)
    ~allocation:side.content ~reserve_status_row:false
;;

let%test_unit "a major directory click only selects the row; an empty listing is not a target" =
  with_files (fun root paths ->
    let ui = load root in
    let g = layout ui in
    let ui = click ui ~x:(g.text.x + 3) ~y:(g.text.y + 2) in
    assert (line ui = 2 && Session.buffer_count (Ui_state.session ui) = 0);
    assert (Set.is_empty (directory ui).marks && not (Directory_buffer.is_dirty (directory ui)));
    let ui = run ui "<CR>" in
    assert (Option.equal String.equal (Editor.path (editor ui)) (Some (List.nth_exn paths 2)));
    Session.dispose (Ui_state.session ui));
  let empty = Helpers.scratch_dir "cobalt-pointer-empty-" in
  Exn.protect ~finally:(fun () -> Core_unix.rmdir empty) ~f:(fun () ->
    let ui = load empty in
    let g = layout ui in
    assert (phys_equal ui (click ui ~x:g.text.x ~y:g.text.y));
    Session.dispose (Ui_state.session ui))
;;

let%test_unit "wheel over focused and unfocused side panes leaves editor and directory intent intact" =
  with_files (fun root _ ->
    let ui = load root |> fun ui -> run ui " ds<CR>" in
    let id = active ui and file = editor ui and dir = directory ui in
    let fg = layout ui and dg = dir_geometry ui in
    let ui = pointer ui `Wheel_down ~x:dg.text.x ~y:dg.text.y in
    assert (active_is ui id && phys_equal (editor ui) file);
    assert (phys_equal (directory ui) dir);
    let side_offset ui =
      let side = Ui_state.side_layout ui ~width ~height |> Option.value_exn in
      Ui_state.fitted_scroll_in (Ui_state.surface ui ~directory:true)
        ~allocation:side.content ~reserve_status_row:false in
    assert ((side_offset ui).top = 3);
    assert ((Ui_state.fitted_scroll ui ~width ~height).top = 0);
    let ui = pointer ui `Wheel_down ~x:fg.text.x ~y:fg.text.y in
    assert (phys_equal (editor ui) file && phys_equal (directory ui) dir);
    assert (Option.is_none (redraw ui).cursor);
    let ui = click ui ~x:(dg.text.x + 1) ~y:(dg.text.y + 1) in
    assert (Cobalt_tile.View_id.equal (Ui_state.focused_view ui ~width ~height) Ui_state.directory_id);
    assert (line ui = 4 && Editor.cursor_column (editor ui) = 0);
    assert (active_is ui id && Session.buffer_count (Ui_state.session ui) = 1);
    let dir_after = directory ui in
    assert (not (Directory_buffer.is_dirty dir_after) && Set.is_empty dir_after.marks);
    assert (phys_equal (Editor.text (Controller.editor dir.controller)) (Editor.text (editor ui)));
    let side_top = (side_offset ui).top in
    let ui = pointer ui `Wheel_up ~x:fg.text.x ~y:fg.text.y in
    assert (line ui = 4 && (side_offset ui).top = side_top);
    let ui = pointer ui `Wheel_down ~x:dg.text.x ~y:dg.text.y
      |> fun ui -> pointer ui `Wheel_down ~x:dg.text.x ~y:dg.text.y in
    assert (line ui = 4 && Option.is_none (redraw ui).cursor);
    let ui = run ui "j" in
    assert (line ui = 5 && Option.is_some (redraw ui).cursor);
    let ui = run ui "<CR>" in
    assert (not (active_is ui id));
    assert (Session.buffer_count (Ui_state.session ui) = 2);
    List.iter dir.entries ~f:(fun entry ->
      assert (String.equal (In_channel.read_all (Filename.concat root entry.name)) ordinary));
    Session.dispose (Ui_state.session ui))
;;

let tab_position ui ~width target =
  let w = Ui_state.workspace ui ~width ~height in
  let rect = Ui_state.workspace_tab_rect ui w |> Option.value_exn in
  let items = Ui_state.tab_items ui in
  let entries = Ui_state.tab_entries ui in
  List.find_map (List.range 0 rect.width) ~f:(fun column ->
    match Option.bind (File_tabs.hit items ~width:rect.width ~column) ~f:(List.nth entries) with
    | Some (File id) when Buffer_id.equal id target -> Some (rect.x + column, rect.y)
    | _ -> None)
;;

let%test_unit "tab overflow, padding, live resize and modal captures are not stale targets" =
  with_files (fun _ paths ->
    let ui = load (List.hd_exn paths) in
    let ui, ids = List.fold_map (List.take (List.tl_exn paths) 4) ~init:ui ~f:open_ in
    let ui = Ui_state.activate_buffer ui ~width ~height (List.nth_exn ids 1) |> Or_error.ok_exn in
    let current = active ui and other = List.hd_exn ids in
    assert (Option.is_none (tab_position ui ~width:24 other));
    let x, y = tab_position ui ~width other |> Option.value_exn in
    let wide = redraw ui in
    assert (String.is_substring (Frame.to_string wide) ~substring:"2:entry");
    let w = Ui_state.workspace ui ~width:24 ~height in
    let strip = Ui_state.workspace_tab_rect ui w |> Option.value_exn in
    assert (phys_equal ui (pointer ~width:24 ui `Left_click ~x:strip.x ~y:strip.y));
    assert (phys_equal ui (pointer ~width:24 ui `Left_click ~x:(strip.x + strip.width - 1) ~y:strip.y));
    let shell = layout ui in
    let modal = run ui " cc" in
    assert (Option.is_some (Ui_state.palette modal));
    assert (phys_equal modal (click modal ~x ~y));
    assert (phys_equal modal (pointer modal `Wheel_down ~x:shell.text.x ~y:shell.text.y));
    let ui = run modal "<Esc>" in
    let searching = run ui "/" in
    assert (phys_equal searching (click searching ~x ~y));
    let ui = run searching "<Esc>" in
    assert (active_is ui current);
    let ui = click ui ~x ~y in
    assert (active_is ui other);
    Session.dispose (Ui_state.session ui))
;;

let%test_unit "C10 visible split click, independent wheel, divider, tab focus and hidden resize" =
  with_files (fun _ paths ->
    let other_path = List.nth_exn paths 1 in
    Out_channel.write_all other_path
      ~data:(String.concat (List.init 45 ~f:(fun i -> sprintf "other-row-%02d\n" i)));
    let ui = load (List.hd_exn paths) in
    let a = active ui in
    let ui, b = open_ ui other_path in
    let ui = run ui " sn" in
    let find ui id =
      List.find_exn (Ui_state.editor_panes ui ~width ~height)
        ~f:(fun (pane : Ui_state.editor_pane) -> Buffer_id.equal pane.buffer id) in
    let pane_a = find ui a and pane_b = find ui b in
    let a_rect = pane_a.geometry.text and b_rect = pane_b.geometry.text in
    let ui = run ui "2jv" in
    let a_before = editor ui in
    let ui = pointer ui `Wheel_down ~x:b_rect.x ~y:b_rect.y in
    assert (active_is ui a && phys_equal (editor ui) a_before);
    assert ((find ui a).scroll.top = 0 && (find ui b).scroll.top = 3);
    let frame = redraw ui in
    let top =
      List.nth_exn frame.rows b_rect.y |> List.map ~f:(fun span -> span.Span.text) |> String.concat in
    assert (String.is_substring top ~substring:"file-row-00");
    assert (String.is_substring top ~substring:"other-row-03");
    let left = List.hd_exn (Ui_state.editor_panes ui ~width ~height) in
    let gap = left.allocation.x + left.allocation.width in
    assert (phys_equal ui (click ui ~x:gap ~y:a_rect.y));
    let ui = click ui ~x:b_rect.x ~y:(b_rect.y + 1) in
    assert (active_is ui b && line ui = 4);
    assert (Option.is_some (Editor.selection (Controller.editor
      (Session.find (Ui_state.session ui) a |> Option.value_exn))));
    let x, y = tab_position ui ~width a |> Option.value_exn in
    let ui = click ui ~x ~y in
    assert (active_is ui a && line ui = 2 && Mode.equal (mode ui) (Visual `Characterwise));
    let narrow_width = 20 in
    assert (List.length (Ui_state.editor_panes ui ~width:narrow_width ~height) = 1);
    let narrow = Frame.render ui ~width:narrow_width ~height |> Frame.to_string in
    assert (not (String.is_substring narrow ~substring:"other-row"));
    let ui = pointer ~width:narrow_width ui `Left_click ~x:b_rect.x ~y:b_rect.y in
    assert (active_is ui a);
    Session.dispose (Ui_state.session ui))
;;
