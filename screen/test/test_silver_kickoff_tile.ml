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
let review_state ui = View_registry.find (Ui_state.views ui) Tile.review_key |> Option.value_exn

let take ui =
  let tile, intents = Tile.take_intents (review_state ui) in
  Ui_state.map_view ui Tile.review_key ~f:(fun _ -> tile), intents
;;

let present ui presentation =
  Ui_state.map_view ui Tile.review_key ~f:(fun tile -> Tile.with_review_presentation tile presentation)
;;

let target : Tile.Target.t =
  { id = "fast"; label = "Fast"; catalog = 3; fields = [ "Profile", "release"; "n", "10" ] }
;;

let choosing : Tile.Presentation.t =
  { choices = [ { id = "fast"; label = "Fast"; catalog = 3 }; { id = "slow"; label = "Slow"; catalog = 3 } ]
  ; selected = Some "fast"
  ; active = Some "fast"
  ; notice = None
  ; targets = [ target ]
  ; draft = Error "Apply a named flow"
  ; kickoff = Error "Prepare a preview first"
  ; details = []
  }
;;

let create presentation =
  Ui_state.create ~views:[ Tile.entry presentation; Tile.review_entry presentation ]
    (Ui_state.controller (Helpers.ui "UNCHANGED\n"))
;;

let open_tile ui = run ui " ccSilver: Flow Review<CR>"

let expect ui intents =
  let ui, actual = take ui in
  assert ([%equal: Tile.Intent.t list] actual intents);
  ui
;;

let%test_unit "open, edit/cancel, apply, prepare, and kickoff are distinct actions" =
  let ui = create choosing in
  assert (not (Ui_state.view_visible ui Tile.review_id));
  let ui = open_tile ui |> Fn.flip expect [] in
  assert (String.equal "silver-kickoff-review" (focus ui));
  assert (has ui "Silver: Flow Review");
  let ui = run ui "Kp" |> Fn.flip expect [] in
  assert (has ui "Kickoff disabled");
  let ui = run ui "<CR>" in
  assert (String.equal "prompt" (focus ui));
  assert (has ui "Flow inputs · Fast");
  let ui = run ui "<Tab><C-u>99<Esc>" |> Fn.flip expect [] in
  assert (String.equal "silver-kickoff-review" (focus ui));
  let ui = run ui "<CR><Tab><C-u>50<CR>" in
  let ui = expect ui [ Apply (target, [ "Profile", "release"; "n", "50" ]) ] in
  assert (String.equal "silver-kickoff-review" (focus ui));
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
  assert (String.equal "silver-kickoff-review" (focus ui))
;;

let%test_unit "without an adapter only the exact Runner alias is offered" =
  let ui = Helpers.ui "UNCHANGED\n" in
  let palette = run ui " ccSilver flow kickoff" in
  assert (not (has palette "Silver: Flow Runner" || has palette "Silver: Flow Review"));
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

let%test_unit "the ordinary selector fits beside the editor and movement alone selects" =
  let ui = run (create choosing) " ccSilver: Flow Runner<CR>" in
  assert (String.equal "silver-kickoff" (focus ui));
  assert (has ui "Silver: Flow Runner" && has ui "UNCHANGED" && has ui "› Fast · active");
  assert (not (has ui "Kickoff disabled" || has ui "Flow inputs"));
  let _, opened = Tile.take_intents (state ui) in
  assert (List.is_empty opened);
  let ui = run ui "j<CR>Kp" in
  let tile, moved = Tile.take_intents (state ui) in
  let slow = List.last_exn choosing.choices in
  assert ([%equal: Tile.Intent.t list] moved [ Select slow ]);
  let ui = Ui_state.map_view ui Tile.key ~f:(fun _ -> tile) in
  let ui = Ui_state.map_view ui Tile.key ~f:(fun tile ->
    Tile.with_presentation tile { choosing with selected = Some "slow"; active = Some "slow" }) in
  assert (has ui "› Slow · active");
  let ui = run ui " ccToggle Silver: Flow Runner<CR>" in
  assert (not (Ui_state.view_visible ui Tile.id));
  assert (String.equal "document" (focus ui));
  assert (has (run ui "iX<Esc>") "XUNCHANGED")
;;

let%test_unit "hide and reopen retains status without moving editor focus on late feedback" =
  let ui = open_tile (create choosing) in
  let ui = run ui " ccToggle Silver: Flow Review<CR>" in
  assert (not (Ui_state.view_visible ui Tile.review_id));
  let focus_before = focus ui in
  let ui = present ui { choosing with details = [ "Accepted: flow-run-9" ] } in
  assert (String.equal focus_before (focus ui));
  let ui = open_tile ui |> Fn.flip expect [] in
  assert (has ui "Accepted: flow-run-9");
  assert (String.equal "silver-kickoff-review" (focus ui))
;;

let%test_unit "exact flow is pinned and idempotent without changing the active choice" =
  let assert_focused ui =
    assert (String.equal "silver-kickoff" (focus ui));
    assert (has ui "› Slow · active");
    assert (List.is_empty (snd (Tile.take_intents (state ui))));
    assert (List.is_empty (snd (Tile.take_intents (review_state ui))));
    assert (List.is_empty (snd (Ui_state.take_host_command_requests ui)))
  in
  let ui = create { choosing with selected = Some "slow"; active = Some "slow" } in
  let ui = Ui_state.with_host_commands ui [ { id = "other"; title = "flow"; aliases = [] } ] in
  let ui = run ui " ccflow" in
  let palette = Ui_state.palette ui |> Option.value_exn |> Palette_tile.palette in
  let module P = Cobalt_palette.Palette in
  let module C = Cobalt_palette.Catalog in
  let id = C.Id.of_string Tile.open_command_id in
  assert (C.Id.equal id (C.Entry.id (List.hd_exn (P.results palette)).item));
  assert (Option.equal C.Id.equal (P.selected palette) (Some id));
  let ui = run ui "<Tab><CR>" in
  assert (not (Ui_state.view_visible ui Tile.review_id));
  assert_focused ui;
  let ui = run ui " ccflow<CR>" in
  assert_focused ui;
  let ui = run ui " cchide<CR> vz" in
  assert (Ui_state.zen ui && not (Ui_state.view_visible ui Tile.id));
  let ui = run ui " ccflow<CR>" in
  assert (not (Ui_state.zen ui));
  assert_focused ui;
  let ui = open_tile ui in
  let ui = run ui " ccflow<CR>" in
  assert_focused ui
;;

let%test_unit "old command searches still open and toggle their corresponding tiles" =
  let ui = run (create choosing) " ccFocus Silver flow kickoff<CR>" in
  assert (String.equal "silver-kickoff" (focus ui));
  let ui = run ui " ccToggle Silver flow kickoff<CR>" in
  assert (not (Ui_state.view_visible ui Tile.id));
  let ui = run ui " ccReview Silver flow kickoff<CR>" in
  assert (String.equal "silver-kickoff-review" (focus ui));
  let ui = run ui " ccToggle Silver flow kickoff review<CR>" in
  assert (not (Ui_state.view_visible ui Tile.review_id))
;;

let%test_unit "a form with an asynchronous catalog change keeps its original capture" =
  let ui = run (open_tile (create choosing)) "<CR><Tab><C-u>80" in
  let newer = { target with catalog = 4; fields = [ "Profile", "debug"; "n", "20" ] } in
  let ui = present ui { choosing with targets = [ newer ] } in
  let ui = run ui "<CR>" |> Fn.flip expect [ Apply (target, [ "Profile", "release"; "n", "80" ]) ] in
  assert (String.equal "silver-kickoff-review" (focus ui));
  let ui = run ui "<CR>" in
  let ui = run ui "<CR>" |> Fn.flip expect [ Apply (newer, newer.fields) ] in
  assert (String.equal "silver-kickoff-review" (focus ui))
;;
