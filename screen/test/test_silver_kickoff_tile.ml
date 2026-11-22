open! Core
open Cobalt_screen
module Tile = Silver_kickoff_tile

let width = 140
let height = 34
let run ui keys = Helpers.run ~width ~height ui (Helpers.keys keys)
let focus ui = Ui_state.focused_view ui ~width ~height |> Cobalt_tile.View_id.to_string
let has ui text =
  Frame.to_string (Frame.render ui ~width ~height) |> String.is_substring ~substring:text
;;

let state ui = View_registry.find (Ui_state.views ui) Tile.key |> Option.value_exn

let take ui =
  let tile, intents = Tile.take_intents (state ui) in
  Ui_state.map_view ui Tile.key ~f:(fun _ -> tile), intents
;;

let present ui presentation =
  Ui_state.map_view ui Tile.key ~f:(fun tile -> Tile.with_presentation tile presentation)
;;

let target : Tile.Target.t =
  { id = "fast"; label = "Fast"; catalog = 3; fields = [ "Profile", "release"; "n", "10" ] }
;;

let choosing : Tile.Presentation.t =
  { targets = [ target ]
  ; draft = Error "Apply a named flow"
  ; kickoff = Error "Prepare a preview first"
  ; details = []
  }
;;

let create presentation =
  Ui_state.create ~views:[ Tile.entry presentation ]
    (Ui_state.controller (Helpers.ui "UNCHANGED\n"))
;;

let open_tile ui = run ui " ccFocus Silver flow kickoff<CR>"

let expect ui intents =
  let ui, actual = take ui in
  assert ([%equal: Tile.Intent.t list] actual intents);
  ui
;;

let%test_unit "open, edit/cancel, apply, prepare, and kickoff are distinct actions" =
  let ui = create choosing in
  assert (not (Ui_state.view_visible ui Tile.id));
  let ui = open_tile ui |> Fn.flip expect [] in
  assert (String.equal "silver-kickoff" (focus ui));
  let ui = run ui "Kp" |> Fn.flip expect [] in
  assert (has ui "Kickoff disabled");
  let ui = run ui "<CR>" in
  assert (String.equal "prompt" (focus ui));
  assert (has ui "Flow inputs · Fast");
  let ui = run ui "<Tab><C-u>99<Esc>" |> Fn.flip expect [] in
  assert (String.equal "silver-kickoff" (focus ui));
  let ui = run ui "<CR><Tab><C-u>50<CR>" in
  let ui = expect ui [ Apply (target, [ "Profile", "release"; "n", "50" ]) ] in
  assert (String.equal "silver-kickoff" (focus ui));
  let applied = { choosing with draft = Ok 17; details = [ "Draft: Fast" ] } in
  let ui = present ui applied in
  let ui = run ui "p" |> Fn.flip expect [ Prepare 17 ] in
  let ui = run (present ui { applied with kickoff = Error "Preview pending" }) "K" in
  let ui = expect ui [] in
  let reviewed =
    { applied with kickoff = Ok 23; details = [ "Preview: plan-23"; "n = 50" ] }
  in
  let ui = present ui reviewed in
  assert (has ui "Preview: plan-23" && has ui "n = 50");
  let ui = run ui "<CR>" |> Fn.flip expect [] in
  let ui = run ui "K" |> Fn.flip expect [ Kickoff 23 ] in
  assert (String.equal "silver-kickoff" (focus ui))
;;

let%test_unit "no kickoff adapter contributes no command or edit interception" =
  let ui = Helpers.ui "UNCHANGED\n" in
  let palette = run ui " ccSilver flow kickoff" in
  assert (not (has palette "Focus Silver flow kickoff"));
  let ui = run palette "<Esc>iX<Esc>" in
  let text =
    Cobalt_app.Controller.editor (Ui_state.controller ui)
    |> Cobalt_core.Editor.text |> Cobalt_core.Text_buffer.to_string
  in
  assert (String.equal text "XUNCHANGED\n")
;;

let%test_unit "the selected named flow is captured rather than the first row" =
  let alternate = { target with id = "slow"; label = "Slow"; fields = [] } in
  let ui = open_tile (create { choosing with targets = [ target; alternate ] }) in
  ignore (run ui "j<CR>" |> Fn.flip expect [ Apply (alternate, []) ] : Ui_state.t)
;;

let%test_unit "hide and reopen retains status without moving editor focus on late feedback" =
  let ui = open_tile (create choosing) in
  let ui = run ui " ccToggle Silver flow kickoff<CR>" in
  assert (not (Ui_state.view_visible ui Tile.id));
  let focus_before = focus ui in
  let ui = present ui { choosing with details = [ "Accepted: flow-run-9" ] } in
  assert (String.equal focus_before (focus ui));
  let ui = open_tile ui |> Fn.flip expect [] in
  assert (has ui "Accepted: flow-run-9");
  assert (String.equal "silver-kickoff" (focus ui))
;;

let%test_unit "a form with an asynchronous catalog change keeps its original capture" =
  let ui = run (open_tile (create choosing)) "<CR><Tab><C-u>80" in
  let newer = { target with catalog = 4; fields = [ "Profile", "debug"; "n", "20" ] } in
  let ui = present ui { choosing with targets = [ newer ] } in
  let ui = run ui "<CR>" |> Fn.flip expect [ Apply (target, [ "Profile", "release"; "n", "80" ]) ] in
  assert (String.equal "silver-kickoff" (focus ui));
  let ui = run ui "<CR>" in
  let ui = run ui "<CR>" |> Fn.flip expect [ Apply (newer, newer.fields) ] in
  assert (String.equal "silver-kickoff" (focus ui))
;;
