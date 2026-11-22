open! Core
open Cobalt_app
open Cobalt_screen
open Test_editor_split

let widths ?width ?height ui =
  List.map (panes ?width ?height ui) ~f:(fun pane -> pane.allocation.width)
;;

let%test_unit "keyboard and palette resizing follow focus on either side of a swap" =
  with_files (fun _ a b _ ->
    let ui, _ = open_ (create a) b in
    let ui = run ui " sn" in
    let first = active ui in
    let initial id = (pane ui id).allocation.width in
    let first_width = initial first in
    let ui = run ui "2 s+" in
    assert ((pane ui first).allocation.width = first_width + 20);
    let ui = run ui " sf" in
    let second = active ui in
    assert (not (Buffer_id.equal first second));
    assert ((pane ui second).allocation.width = initial second - 20);
    let ui = run ui " ccGrow split pane by 10%<CR>" in
    assert ((pane ui second).allocation.width = initial second - 10);
    let before = widths ui in
    let ui = run ui " sx" in
    assert ([%equal: int list] (widths ui) (List.rev before));
    assert (Buffer_id.equal (active ui) second);
    let ui = run ui " ccShrink split pane by 10%<CR>" in
    assert ((pane ui second).allocation.width = initial second - 20);
    let ui = run ui " s=" in
    assert (List.equal Int.equal (List.sort (widths ui) ~compare:Int.compare) [ 49; 50 ]);
    let ui = run ui "999999 s-" in
    assert ((pane ui second).allocation.width = Workspace.min_document_width);
    let ui = run ui " ccEqualize split panes<CR>" in
    assert (List.equal Int.equal (List.sort (widths ui) ~compare:Int.compare) [ 49; 50 ]);
    dispose ui)
;;

let%test_unit "resizing follows pane focus even when both panes show the same file" =
  with_files (fun _ a b _ ->
    let ui, bid = open_ (create a) b in
    let ui = run ui " sn bn" in
    let before = widths ui in
    let ui = run ui " s+" in
    assert (List.for_all (panes ui) ~f:(fun pane -> Buffer_id.equal bid pane.buffer));
    assert ([%equal: int list] (widths ui) (List.map2_exn before [ -10; 10 ] ~f:( + )));
    let ui = run ui " sf s+" in
    assert ([%equal: int list] (widths ui) before);
    dispose ui)
;;

let%test_unit "absolute divider uses physical columns, clamps, and retains its ratio" =
  with_files (fun _ a b _ ->
    let ui, _ = open_ (create a) b in
    let ui = run ui " sn ds sx" in
    let left ui = (List.hd_exn (panes ui)).allocation in
    let x = (left ui).x in
    assert (x > 0);
    let drag ui column = Ui_state.resize_editor_divider ui ~width ~height ~column in
    let area = width - x - Workspace.gap in
    let min_width = Workspace.min_document_width in
    let widen = area - min_width in
    let ui = drag ui Int.max_value in
    assert ([%equal: int list] (widths ui) [ widen; min_width ]);
    let ui = drag ui Int.min_value in
    assert ([%equal: int list] (widths ui) [ min_width; widen ]);
    let ui = drag ui (x + 23) in
    assert ([%equal: int list] (widths ui) [ 23; area - 23 ]);
    let resize ui ~width ~height = Helpers.run ~width ~height ui [ Ui_state.Input.Resize ] in
    let wider = x + (area * 2) + Workspace.gap in
    let ui = resize ui ~width:wider ~height in
    assert ([%equal: int list] (widths ~width:wider ui) [ 46; (area - 23) * 2 ]);
    let narrow = x + (2 * min_width) + Workspace.gap in
    let ui = resize ui ~width:narrow ~height in
    assert ([%equal: int list] (widths ~width:narrow ui) [ min_width; min_width ]);
    let too_narrow = narrow - 1 in
    let ui = resize ui ~width:too_narrow ~height in
    assert (List.length (widths ~width:too_narrow ui) = 1);
    let ui = run ui ~width:too_narrow " s+ s- s=" in
    let ui = Ui_state.resize_editor_divider ui ~width:too_narrow ~height ~column:x in
    let ui = resize ui ~width ~height:3 in
    assert (List.length (widths ~height:3 ui) = 1);
    let ui = resize ui ~width ~height |> fun ui -> run ui " vz vz" in
    assert ([%equal: int list] (widths ui) [ 23; area - 23 ]);
    dispose ui)
;;
