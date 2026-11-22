open! Core
open Cobalt_app
open Cobalt_screen

let width = 154
let height = 36
let run ?(width = width) ?(height = height) ui keys =
  Helpers.run ~width ~height ui (Helpers.keys keys)
;;

let command ui query = run ui (" cc" ^ query ^ "<CR>")
let focus ui = Ui_state.focused_view ui ~width ~height
let layout ui id = Ui_state.view_layout ui ~width ~height id
let has ui text =
  String.is_substring (Frame.to_string (Frame.render ui ~width ~height)) ~substring:text
;;

let palette_entry ui title =
  let palette = Ui_state.palette ui |> Option.value_exn |> Palette_tile.palette in
  List.find_map (Cobalt_palette.Palette.results palette) ~f:(fun row ->
    Option.some_if (String.equal (Cobalt_palette.Catalog.Entry.title row.item) title) row.item)
;;

let placements ui = View_registry.placements (Ui_state.views ui)
let band ui = View_registry.band (Ui_state.views ui)
let silver_band = [ Silver_overview_tile.id; Silver_stage_tile.id; Silver_kickoff_tile.id ]
let id_equal = Cobalt_tile.View_id.equal
let assert_band ui expected = assert (List.equal id_equal (band ui) expected)

let silver_views () =
  let stage = Silver_stage_tile.Snapshot.unavailable "Waiting for a bound project" in
  let kickoff = Silver_kickoff_tile.Presentation.unavailable "No flow loaded" in
  [ Silver_overview_tile.entry [ Silver_overview_tile.Display_row.message "SILVER_PROJECT_MARKER" ]
  ; Silver_stage_tile.entry stage
  ; Silver_kickoff_tile.entry kickoff
  ; Silver_kickoff_tile.review_entry kickoff
  ]
;;

let create ?(standalone_layouts = true) ?(views = silver_views ()) () =
  Ui_state.create ~standalone_layouts ~views (Ui_state.controller (Helpers.ui "MAIN_EDITOR"))
;;

let assert_no_silver_work ui =
  let views = Ui_state.views ui in
  let get key = View_registry.find views key |> Option.value_exn in
  assert (List.is_empty (snd (Silver_overview_tile.take_intents (get Silver_overview_tile.key))));
  assert (List.is_empty (snd (Silver_stage_tile.take_intents (get Silver_stage_tile.key))));
  assert (List.is_empty (snd (Silver_stage_tile.take_watches (get Silver_stage_tile.key))));
  List.iter [ Silver_kickoff_tile.key; Silver_kickoff_tile.review_key ] ~f:(fun key ->
    assert (List.is_empty (snd (Silver_kickoff_tile.take_intents (get key)))))
;;

let%test_unit "Silver from Zen reveals hidden band and Status without opening review or starting work" =
  let ui = create () in
  let connection = Status_field.Silver.Connected
    { project_root = "/fixture"; endpoint = "http://localhost:4000" } in
  let ui = Ui_state.with_silver_status ui (Some connection) in
  let ui = command ui "ov" |> Fn.flip command "hide" in
  assert (not (Ui_state.view_visible ui Silver_overview_tile.id));
  let ui = command ui "Silver: Flow Review" in
  assert (Option.equal id_equal (Ui_state.active_tab_view ui) (Some Silver_kickoff_tile.review_id));
  let ui = command ui "hide" in
  assert (not (Ui_state.view_visible ui Silver_kickoff_tile.review_id));
  let ui = run ui " vz" in
  assert (Ui_state.zen ui);
  let ui = command ui "Layout: Silver" in
  assert_band ui silver_band;
  assert (not (Ui_state.zen ui) && id_equal (focus ui) Ui_state.document_id);
  assert (has ui "MAIN_EDITOR" && has ui "SILVER_PROJECT_MARKER");
  assert (Option.is_some (layout ui Ui_state.status_id));
  assert (Option.is_none (Ui_state.active_tab_view ui));
  assert (List.is_empty (View_registry.tabs (Ui_state.views ui)));
  assert (not (Ui_state.view_visible ui Problems_tile.id));
  assert (not (Ui_state.view_visible ui History_tile.id));
  assert (Poly.equal (Ui_state.silver_status ui) (Some connection));
  assert_no_silver_work ui;
  let ui = command ui "unhide" in
  assert_band ui silver_band;
  assert (id_equal (focus ui) Ui_state.document_id);
  assert (not (Ui_state.view_visible ui Silver_kickoff_tile.review_id))
;;

let%test_unit "compact resize reflows Silver; Zen restores manual changes instead of the preset" =
  let ui = command (create ()) "Layout: Silver" in
  let compact = Helpers.run ~width:47 ~height:10 ui [ Ui_state.Input.Resize ] in
  assert_band compact silver_band;
  assert (Option.is_none
    (Ui_state.view_layout compact ~width:47 ~height:10 Silver_kickoff_tile.id));
  let compact_runner = run ~width:47 ~height:10 compact " ccflow<CR>" in
  assert (id_equal (Ui_state.focused_view compact_runner ~width:47 ~height:10)
    Silver_kickoff_tile.id);
  assert (Option.equal id_equal (Ui_state.active_tab_view compact_runner) (Some Silver_kickoff_tile.id));
  assert_no_silver_work compact_runner;
  let ui = Helpers.run ~width ~height compact [ Ui_state.Input.Resize ] in
  assert (List.for_all silver_band ~f:(fun id -> Option.is_some (layout ui id)));
  let ui = command ui "st" |> Fn.flip command "hide" in
  let ui = run ui " vt vz vz" in
  assert (not (Ui_state.view_visible ui Silver_stage_tile.id));
  assert (Option.is_none (layout ui Ui_state.status_id));
  let ui = command ui "unhide" in
  assert (id_equal (focus ui) Silver_stage_tile.id);
  let ui = run ui " st" in
  assert (Option.equal id_equal (Ui_state.active_tab_view ui) (Some Silver_stage_tile.id));
  let ui = command ui "Layout: Default" in
  assert_band ui [ Problems_tile.id; Silver_overview_tile.id ];
  assert (Option.is_some (layout ui Ui_state.status_id));
  assert (id_equal (focus ui) Ui_state.document_id);
  assert (not (Ui_state.view_visible ui History_tile.id));
  assert (Option.is_none (Ui_state.active_tab_view ui));
  assert_no_silver_work ui
;;

let%test_unit "layout presets retain dirty files, two-file splits, and a queued job" =
  Test_editor_split.with_files (fun _ a b _ ->
    let controller = Controller.open_file a ~cell_width:Cell_map.width |> Or_error.ok_exn in
    let ui = Ui_state.create ~standalone_layouts:true ~views:(silver_views ()) controller in
    let ui, _ = Ui_state.open_file ui ~width ~height b |> Or_error.ok_exn in
    let ui = run ui " sniX<Esc> sf" in
    let files = Session.buffers (Ui_state.session ui) in
    let editors = Session.editor_split (Ui_state.session ui) in
    let ui = run ui " sx s+" in
    let split = Ui_state.split ui in
    assert (Option.is_some editors);
    assert (List.exists files ~f:(fun (_, controller) ->
      Cobalt_core.Editor.is_dirty (Controller.editor controller)));
    let ui = command ui "Quick-Harness: New SV scratch" in
    let ui = command (command ui "Layout: Silver") "Layout: Default" in
    assert (Poly.equal (Session.editor_split (Ui_state.session ui)) editors);
    assert (Workspace.Major_split.equal split (Ui_state.split ui));
    let signature files = List.map files ~f:(fun (id, controller) ->
      let editor = Controller.editor controller in
      id, Cobalt_core.Editor.is_dirty editor) in
    assert (Poly.equal (signature files) (signature (Session.buffers (Ui_state.session ui))));
    assert (List.length (Ui_state.editor_panes ui ~width ~height) = 2);
    assert (List.length (snd (Ui_state.take_harness_requests ui)) = 1);
    assert (has ui "XALPHA");
    Session.dispose (Ui_state.session ui))
;;

let%test_unit "presets retain an unrelated manually hidden view split" =
  Test_editor_split.with_files (fun root a _ _ ->
    let controller = Controller.open_file a ~cell_width:Cell_map.width |> Or_error.ok_exn in
    let ui = Ui_state.create ~standalone_layouts:true
      ~views:(silver_views () @ [ Vcs_view.entry ~cwd:root () ]) controller in
    let ui = run ui " gs" in
    let ui = command ui "hide" in
    assert (not (Ui_state.view_visible ui Vcs_view.id));
    let ui = command ui "Layout: Silver" in
    assert (not (Ui_state.view_visible ui Vcs_view.id));
    assert (Option.equal id_equal (View_registry.split (Ui_state.views ui)) (Some Vcs_view.id));
    let ui = command ui "unhide" in
    assert (id_equal (focus ui) Vcs_view.id);
    let ui = command ui "Layout: Default" in
    assert (Ui_state.view_visible ui Vcs_view.id);
    assert (Option.equal id_equal (View_registry.split (Ui_state.views ui)) (Some Vcs_view.id));
    Session.dispose (Ui_state.session ui))
;;

let%test_unit "Silver is discoverable but unavailable without the adapter; hosted owns its layout" =
  let ui = run (create ~views:[] ()) " vz" in
  let before = placements ui in
  let ui = run ui " ccLayout: Silver" in
  let entry = palette_entry ui "Layout: Silver" |> Option.value_exn in
  assert (not (Cobalt_palette.Catalog.Entry.is_available entry { mode = Normal }));
  let ui = run ui "<CR>" in
  assert (Ui_state.zen ui && Poly.equal before (placements ui));
  assert (Option.exists (Ui_state.message ui) ~f:(fun message ->
    String.is_substring message.text ~substring:"Silver adapter"));
  let ui = command ui "Layout: Default" in
  assert (not (Ui_state.zen ui));
  assert_band ui [ Problems_tile.id ];
  let hosted = run (create ~standalone_layouts:false ()) " ccLayout: Silver" in
  assert (Option.is_none (palette_entry hosted "Layout: Silver"))
;;
