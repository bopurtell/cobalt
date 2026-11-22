open! Core
open Cobalt_screen
module Tile = Silver_stage_tile
module Catalog = Cobalt_palette.Catalog
module Palette = Cobalt_palette.Palette

let width = 180
let height = 36
let run ui keys = Helpers.run ~width ~height ui (Helpers.keys keys)
let has ui substring = String.is_substring (Frame.to_string (Frame.render ui ~width ~height)) ~substring
let focus ui = Ui_state.focused_view ui ~width ~height |> Cobalt_tile.View_id.to_string
let controller () = Ui_state.controller (Helpers.ui "EDITABLE_DOCUMENT\n")
let open_stage ui = run ui " ccsilver stage checklist<CR>"

let intent token : Tile.Intent.t =
  { token; selection = token; summary = "chip/v1 · f/p · endpoint " ^ token }
;;
let synth = intent "handed-off-synth"
let timing = intent "post-cts"
let routing = intent "post-global-route"
let routing_reason = "No routing endpoint for this profile"

let snapshot ?(routing_action = Tile.Action.Ready routing) () : Tile.Snapshot.t =
  { empty = "No stages"
  ; rows =
      [ { id = "s"; label = "Synthesis"; action = Ready synth }
      ; { id = "t"; label = "Timing"; action = Ready timing }
      ; { id = "r"; label = "Routing"; action = routing_action }
      ]
  ; aliases = [ Synth, Ready synth; Timing, Ready timing; Routing, routing_action ]
  }
;;

let ui snapshot =
  Ui_state.create ~views:[ Tile.entry snapshot ] (controller ())
  |> Fn.flip Ui_state.with_silver_stage snapshot
;;

let take ui =
  let tile = View_registry.find (Ui_state.views ui) Tile.key |> Option.value_exn in
  let tile, intents = Tile.take_intents tile in
  Ui_state.map_view ui Tile.key ~f:(fun _ -> tile), intents
;;

let palette ui = Ui_state.palette ui |> Option.value_exn |> Palette_tile.palette
let item_ids ui =
  Palette.results (palette ui)
  |> List.map ~f:(fun row -> Catalog.Id.to_string (Catalog.Entry.id row.item))
;;

let assert_top ui query =
  let id = "host.silver.stage." ^ query in
  assert (String.equal (List.hd_exn (item_ids ui)) id);
  assert (String.equal (Catalog.Id.to_string (Option.value_exn (Palette.selected (palette ui)))) id)
;;

let%test_unit "checklist and all three aliases dispatch captured actions with focus intact" =
  let initial = run (ui (snapshot ())) " vz" in
  assert (Ui_state.zen initial);
  let ui = open_stage initial in
  assert (String.equal (focus ui) "silver-stage");
  assert (has ui "Synthesis · Ready");
  let ui = run ui "jR" in
  assert (String.equal (focus ui) "silver-stage");
  let ui, row = take ui in
  assert ([%equal: Tile.Intent.t list] row [ timing ]);
  let ui = List.fold [ "synth", synth; "timing", timing; "routing", routing ] ~init:ui
    ~f:(fun ui (query, expected) ->
      let shown = run ui (" cc" ^ query) in
      assert_top shown query;
      assert (has shown expected.token);
      assert (String.equal (focus (run shown "<Esc>")) "silver-stage");
      let ui, dispatched = take (run shown "<Tab><CR>") in
      assert (String.equal (focus ui) "silver-stage");
      assert ([%equal: Tile.Intent.t list] dispatched [ expected ]);
      ui)
  in
  let ui = run ui " ccToggle Silver: Stage checklist<CR>" in
  assert (not (Ui_state.view_visible ui Tile.id));
  let ui, hidden = take (run ui " cctiming<CR>") in
  assert ([%equal: Tile.Intent.t list] hidden row);
  assert (String.equal (focus ui) "document");
  assert (not (Ui_state.view_visible ui Tile.id))
;;

let%test_unit "disabled named stage locks exact Enter and disabled checklist does not launch" =
  let ui = ui (snapshot ~routing_action:(Blocked routing_reason) ()) |> open_stage in
  let ui = Ui_state.with_host_commands ui
    [ { id = "fixture.routing-more"; title = "Routing more"; aliases = [] } ] in
  let ui = run ui "GR" in
  assert (has ui "Routing · Unavailable");
  assert (has ui (routing_reason ^ "; nothing ran"));
  let ui, intents = take ui in
  assert (List.is_empty intents);
  let shown = run ui " ccrouting" in
  assert_top shown "routing";
  assert (List.mem (item_ids shown) "host.fixture.routing-more" ~equal:String.equal);
  let more = run shown " more" in
  assert (not (List.mem (item_ids more) "host.silver.stage.routing" ~equal:String.equal));
  assert (List.mem (item_ids more) "host.fixture.routing-more" ~equal:String.equal);
  let ui = run shown "<Tab><CR>" in
  assert (String.equal (focus ui) "silver-stage");
  assert (has ui (routing_reason ^ "; nothing ran"));
  assert (List.is_empty (snd (Ui_state.take_host_command_requests ui)));
  assert (List.is_empty (snd (take ui)))
;;

let%test_unit "catalog changes do not replace a selected intent or an open palette snapshot" =
  let ui = ui (snapshot ()) |> open_stage |> Fn.flip run "j cctiming" in
  let next = intent "new-catalog-timing" in
  let replacement = snapshot () in
  let replacement =
    { replacement with
      rows = List.map replacement.rows ~f:(fun row ->
        if String.equal row.id "t" then { row with action = Ready next } else row)
    ; aliases = [ Timing, Ready next ]
    }
  in
  let ui = Ui_state.with_silver_stage ui replacement in
  let ui, captured = take (run ui "<CR>") in
  assert ([%equal: Tile.Intent.t list] captured [ timing ]);
  let ui = run ui "R" in
  assert (has ui "select a stage again");
  assert (List.is_empty (snd (take ui)));
  assert ([%equal: Tile.Intent.t list] (snd (take (run ui "kjR"))) [ next ])
;;

let%test_unit "a new dispatch token for the same inputs keeps the selected row actionable" =
  let ui = ui (snapshot ()) |> open_stage |> Fn.flip run "GR" in
  let ui, first = take ui in
  assert ([%equal: Tile.Intent.t list] first [ routing ]);
  let refreshed = { routing with token = "next-submit" } in
  let ui = Ui_state.with_silver_stage ui (snapshot ~routing_action:(Ready refreshed) ()) in
  let ui, second = take (run ui "R") in
  assert (String.equal (focus ui) "silver-stage");
  assert ([%equal: Tile.Intent.t list] second [ refreshed ])
;;

let%test_unit "no adapter gives an exact reason and returns to ordinary editing" =
  let ui = Ui_state.create (controller ()) |> Fn.flip run " ccsynth" in
  assert_top ui "synth";
  assert (has ui Tile.adapter_unavailable);
  let ui = run ui "<CR>" in
  assert (Option.equal String.equal (Ui_state.capture_notice ui)
    (Some (Tile.adapter_unavailable ^ "; nothing ran")));
  assert (String.equal (focus ui) "document");
  assert (has (run ui "iX<Esc>") "XEDITABLE_DOCUMENT")
;;
