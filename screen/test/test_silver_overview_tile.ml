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
  let tile, intents = Tile.take_intents (state ui) in
  assert ([%equal: Tile.Intent.t list] intents [ Refresh ]);
  assert (List.is_empty (snd (Tile.take_intents tile)));
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

let suite = { Tile.Target.suite = "FIFO"; variant = None; digest = "catalog-a"; fields = [] }
let seeded =
  { suite with variant = Some "seeded"
  ; fields =
      [ { Tile.Field.name = "n"; value = "10"; default = "10" }
      ; { name = "seed"; value = "3"; default = "3" }
      ]
  }
;;

let test_ui ?(targets = [ suite; seeded ]) action =
  Ui_state.create ~views:[ Tile.entry ~targets [ "Watching: attempt-original" ] ] (controller ())
  |> Fn.flip Ui_state.with_silver_test action
;;

let take ui =
  let tile, intents = Tile.take_intents (state ui) in
  Ui_state.map_view ui Tile.key ~f:(fun _ -> tile), intents
;;

let has ui text = String.is_substring (render ui) ~substring:text

let%test_unit "suite R, variant Enter/apply, and cancel restore the row without launching" =
  let ui = test_ui Pick |> Fn.flip run " vUR" in
  assert (String.equal (focus ui) "silver-overview");
  let ui, intents = take ui in
  assert ([%equal: Tile.Intent.t list] intents [ Launch suite ]);
  let edit = run ui "j<CR>" in
  assert (String.equal (focus edit) "prompt");
  assert (has edit "Test settings · FIFO / seeded");
  assert (has edit "n (1/2)");
  let edit = run edit "<C-u>50<Tab>" in
  assert (has edit "seed (2/2)");
  let ui = run edit "<C-u>77<CR>" in
  assert (String.equal (focus ui) "silver-overview");
  let ui, intents = take ui in
  assert ([%equal: Tile.Intent.t list] intents [ Apply_settings (seeded, [ "n", "50"; "seed", "77" ]) ]);
  let seeded =
    { seeded with fields = List.map seeded.fields ~f:(fun field ->
        { field with value = if String.equal field.name "n" then "50" else "77" }) }
  in
  let ui = Ui_state.map_view ui Tile.key ~f:(fun tile -> Tile.with_targets tile [ suite; seeded ]) in
  let ui = run ui "<CR><C-u>999<Esc>" in
  assert (String.equal (focus ui) "silver-overview");
  let ui, intents = take ui in
  assert (List.is_empty intents);
  let ui = run ui "R" in
  assert ([%equal: Tile.Intent.t list] (snd (take ui)) [ Launch seeded ]);
  assert (has ui "Watching: attempt-original");
  assert (String.equal (editor_text ui) "EDITABLE_DOCUMENT\n")
;;

let palette ui =
  Ui_state.palette ui |> Option.value_exn |> Palette_tile.palette
;;

let top_and_selected ui =
  let module C = Cobalt_palette.Catalog in
  let p = palette ui in
  let first = List.hd_exn (Cobalt_palette.Palette.results p) in
  let selected = Option.value_exn (Cobalt_palette.Palette.selected p) in
  C.Id.to_string (C.Entry.id first.item), C.Id.to_string selected
;;

let%test_unit "exact test is first and selected, launch dispatch is shared even while the tile is hidden" =
  let seeded = { seeded with fields = [ { Tile.Field.name = "n"; value = "50"; default = "10" } ] } in
  let ui = test_ui ~targets:[ suite; seeded ] (Run seeded) |> Fn.flip run " vUjR" in
  let ui, from_row = take ui in
  (* Browsing back to the suite must not replace the host's resolved alias. *)
  let ui = run ui "k cctest" in
  assert ([%equal: string * string] (top_and_selected ui) ("host.silver.test", "host.silver.test"));
  assert (has ui "Run test · FIFO / seeded · n=50");
  let ui = run ui "<Esc>" in
  assert (String.equal (focus ui) "silver-overview");
  let ui = run ui " vS cctest<CR>" in
  assert (String.equal (focus ui) "document");
  assert (not (Ui_state.view_visible ui Tile.id));
  let ui, from_palette = take ui in
  assert ([%equal: Tile.Intent.t list] from_row [ Launch seeded ]);
  assert ([%equal: Tile.Intent.t list] from_row from_palette);
  assert (List.is_empty (snd (take ui)));
  let ui = Ui_state.with_silver_result ui (Ok "Accepted · attempt new-attempt") in
  assert (String.equal (focus ui) "document");
  assert (has ui "Accepted · attempt new-attempt");
  let ui = run ui " vS" in
  assert (has ui "Watching: attempt-original")
;;

let%test_unit "unavailable exact test cannot fall through; more text resumes search" =
  let ui = test_ui (Unavailable "Discovery is stale") |> Fn.flip run " vU cctest" in
  assert ([%equal: string * string] (top_and_selected ui) ("host.silver.test", "host.silver.test"));
  assert (has ui "Unavailable: Discovery is stale");
  let more = run ui " more" in
  assert (not (List.exists (Cobalt_palette.Palette.results (palette more)) ~f:(fun row ->
    String.equal (Cobalt_palette.Catalog.Id.to_string (Cobalt_palette.Catalog.Entry.id row.item)) "host.silver.test")));
  let ui = run ui "<Tab><CR>" in
  assert (String.equal (focus ui) "silver-overview");
  assert (has ui "Discovery is stale; nothing ran");
  assert (List.is_empty (snd (take ui)))
;;

let%test_unit "no resolved target opens a picker and captures the chosen digest" =
  let ui = test_ui Pick |> Fn.flip run " vS cctest<CR>" in
  assert (has ui "Choose a Silver test");
  let ui = run ui "seeded<CR>" in
  assert (String.equal (focus ui) "document");
  assert ([%equal: Tile.Intent.t list] (snd (take ui)) [ Launch seeded ])
;;

let%test_unit "exact test keeps the target displayed when the palette opened" =
  let ui = test_ui (Run seeded) |> Fn.flip run " cctest" in
  let latest = { seeded with digest = "catalog-b"; variant = Some "other" } in
  let ui = Ui_state.with_silver_test ui (Run latest) in
  assert (has ui "FIFO / seeded");
  let ui = run ui "<CR>" in
  let ui, intents = take ui in
  assert ([%equal: Tile.Intent.t list] intents [ Launch seeded ]);
  assert (has (run ui " cctest") "FIFO / other")
;;

let%test_unit "catalog changes require a new tile selection and drafts retain their original digest" =
  let ui = test_ui (Run seeded) |> Fn.flip run " vUj<CR>" in
  let new_suite = { suite with digest = "catalog-b" } in
  let new_seeded = { seeded with digest = "catalog-b" } in
  let ui =
    Ui_state.map_view ui Tile.key ~f:(fun tile -> Tile.with_targets tile [ new_suite; new_seeded ])
    |> Fn.flip Ui_state.with_silver_test (Run new_seeded)
  in
  let ui = run ui "<CR>R" in
  let ui, intents = take ui in
  assert ([%equal: Tile.Intent.t list] intents [ Apply_settings (seeded, [ "n", "10"; "seed", "3" ]) ]);
  assert (Option.equal String.equal (Ui_state.capture_notice ui)
    (Some "Silver catalog changed; select the test row again"));
  let ui = run ui "kjR" in
  assert ([%equal: Tile.Intent.t list] (snd (take ui)) [ Launch new_seeded ])
;;

let%test_unit "share picker captures identity, keeps the manual route, and fences old replies" =
  let module Connect = Tile.Connection in
  let ui = test_ui (Unavailable "Connect to a Silver project first") in
  let ui = Ui_state.with_silver_connection ui ~project_root:"/startup/project" in
  let open_picker ui =
    let ui = run ui " ccsilver connect<CR>" in
    match take ui with
    | ui, [ Connections generation ] -> ui, generation
    | _ -> assert false
  in
  let ui, generation = open_picker ui in
  assert (has ui "Looking for Silver shares");
  let a = Connect.Id.of_int 41 and b = Connect.Id.of_int 92 in
  let lookup : Connect.lookup =
    { rows =
        [ { id = a; title = "Offered · alpha · /startup/project" }
        ; { id = b; title = "Offered · beta · /other/project" }
        ]
    ; error = None
    }
  in
  let ui = Ui_state.receive_silver_connections ui ~generation lookup in
  assert (has ui "/startup/project" && has ui "/other/project");
  let ui = run ui "beta<CR>" in
  assert (String.equal (focus ui) "document");
  assert (Option.equal String.equal (Ui_state.capture_notice ui) (Some "Connecting to Silver…"));
  let ui, intents = take ui in
  assert ([%equal: Tile.Intent.t list] intents
    [ Connect { generation; selection = Share b } ]);
  let ui = run ui " vU" in
  let ui, later = open_picker ui in
  let ui = Ui_state.receive_silver_connections ui ~generation lookup in
  assert (not (has ui "/other/project"));
  let ui = Ui_state.receive_silver_connections ui ~generation:later
      { rows = []; error = Some "Malformed fixture" } in
  assert (has ui "Malformed fixture");
  let ui = run ui "http://127.0.0.1:4200<CR>" in
  let ui, intents = take ui in
  assert ([%equal: Tile.Intent.t list] intents
    [ Connect { generation = later
              ; selection = Manual { endpoint = "http://127.0.0.1:4200"
                                   ; project_root = "/startup/project" } } ]);
  let ui = Ui_state.receive_silver_connect_result ui ~generation (Ok "Stale success") in
  assert (Option.equal String.equal (Ui_state.capture_notice ui) (Some "Connecting to Silver…"));
  let ui = Ui_state.receive_silver_connect_result ui ~generation:later (Error "Unreachable") in
  assert (Option.equal String.equal (Ui_state.capture_notice ui) (Some "Unreachable"));
  assert (String.equal (focus ui) "silver-overview");
  let ui, cancelled = open_picker ui in
  let ui = Ui_state.receive_silver_connections ui ~generation:cancelled { rows = []; error = None } in
  assert (has ui "No Silver project shares");
  let ui = run ui "<Esc>" in
  let ui = Ui_state.receive_silver_connections ui ~generation:cancelled lookup in
  assert (String.equal (focus ui) "silver-overview" && not (has ui "/other/project"))
;;
