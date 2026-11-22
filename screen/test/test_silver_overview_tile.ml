open! Core
open Cobalt_screen
module Tile = Silver_overview_tile

let width = 160
let height = 30
let run ui keys = Helpers.run ~width ~height ui (Helpers.keys keys)
let render ui = Frame.to_string (Frame.render ui ~width ~height)
let focus ui = Ui_state.focused_view ui ~width ~height |> Cobalt_tile.View_id.to_string
let state ui = View_registry.find (Ui_state.views ui) Tile.key |> Option.value_exn
let controller () = Ui_state.controller (Helpers.ui "EDITABLE_DOCUMENT\n")
let editor_text ui =
  Cobalt_app.Controller.editor (Ui_state.controller ui)
  |> Cobalt_core.Editor.text |> Cobalt_core.Text_buffer.to_string
;;

let%test_unit "overview renders prepared rows, emits refresh intent, and closes without editing" =
  let rows = [ "Status: Fresh"; "Project: /selected/project"; "Run: attempt-fixture" ] in
  let extras = List.init 12 ~f:(sprintf "Detail %02d") in
  let ui = Ui_state.create ~views:[ Tile.entry (rows @ extras) ] (controller ()) in
  assert (String.equal (focus ui) "document");
  assert (List.for_all rows ~f:(fun substring -> String.is_substring (render ui) ~substring));
  let ui = run ui " vUG" in
  assert (String.equal (focus ui) "silver-overview");
  assert (String.is_substring (render ui) ~substring:"Detail 11");
  let ui = run ui "i" in
  assert (String.equal (editor_text ui) "EDITABLE_DOCUMENT\n");
  let ui = run ui "r" in
  let tile, intent = Tile.take_intent (state ui) in
  assert ([%equal: Tile.Intent.t option] intent (Some Refresh));
  assert (Option.is_none (snd (Tile.take_intent tile)));
  let ui = Ui_state.map_view ui Tile.key ~f:(fun _ -> Tile.with_rows tile [ "Status: Stale" ]) in
  assert (String.is_substring (render ui) ~substring:"Status: Stale");
  let ui = run ui " vS" in
  assert (not (Ui_state.view_visible ui Tile.id));
  assert (not (String.is_substring (render ui) ~substring:"Status: Stale"));
  assert (String.equal (focus ui) "document");
  assert (String.equal (editor_text ui) "EDITABLE_DOCUMENT\n");
  let ui = run ui " ccToggle Silver overview<CR>" in
  assert (String.is_substring (render ui) ~substring:"Status: Stale")
;;

let%test_unit "absent overview neither opens nor interrupts subsequent editing" =
  let ui = Ui_state.create (controller ()) |> Fn.flip run " vS" in
  assert (not (View_registry.installed (Ui_state.views ui) Tile.id));
  let ui = run ui "iX<Esc>" in
  assert (String.equal (editor_text ui) "XEDITABLE_DOCUMENT\n")
;;
