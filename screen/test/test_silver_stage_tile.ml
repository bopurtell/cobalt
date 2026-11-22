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
let open_stage ui = run ui " ccSilver: Stage Checklist<CR>"

let intent token : Tile.Intent.t =
  { token; selection = token; summary = "chip/v1 · f/p · endpoint " ^ token }
;;
let synth = intent "handed-off-synth"
let timing = intent "post-cts"
let routing = intent "post-global-route"
let routing_reason = "No routing endpoint for this profile"

let snapshot ?(routing_action = Tile.Action.Ready routing) () : Tile.Snapshot.t =
  { empty = "No stages"
  ; context = Some "chip/v1 · f/p"
  ; watch_context = None
  ; rows =
      [ { id = "s"; label = "Synthesis"; status = Unknown; action = Ready synth }
      ; { id = "t"; label = "Timing"; status = Running; action = Ready timing }
      ; { id = "r"; label = "Routing"; status = Completed; action = routing_action }
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

let%test_unit "run observation commands never enqueue a launch" =
  let ui = open_stage (ui { (snapshot ()) with watch_context = Some "Latest ASIC run run-42" }) in
  assert (has ui "Latest ASIC run run-42");
  let ui = run ui "[]Lr" in
  assert (String.equal (focus ui) "silver-stage");
  let tile = View_registry.find (Ui_state.views ui) Tile.key |> Option.value_exn in
  let tile, watches = Tile.take_watches tile in
  assert (Poly.equal watches [ Tile.Watch.Older; Newer; Latest; Refresh ]);
  let _, intents = Tile.take_intents tile in
  assert (List.is_empty intents)
;;

let%test_unit "checklist and all three aliases dispatch captured actions with focus intact" =
  let initial = run (ui (snapshot ())) " vz" in
  assert (Ui_state.zen initial);
  let ui = open_stage initial in
  assert (String.equal (focus ui) "silver-stage");
  assert (has ui "? Synthesis: not reported");
  assert (has ui "chip/v1 · f/p");
  assert (not (has ui "Available"));
  assert (not (has ui "endpoint handed-off-synth"));
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
  let ui = run ui " ccToggle Silver: Stage Checklist<CR>" in
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
  assert (has ui "› ✓ Routing:   completed");
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
  assert (has ui "›!⣷ Timing:    running");
  assert (has ui "Reselect");
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

let%test_unit "new run evidence updates the selected row without changing its launch intent" =
  let original = snapshot () in
  let ui = ui original |> open_stage |> Fn.flip run "j" in
  let refreshed =
    { original with
      rows = List.map original.rows ~f:(fun row ->
        if String.equal row.id "t" then { row with status = Completed } else row)
    }
  in
  let ui = Ui_state.with_silver_stage ui refreshed in
  assert (has ui "› ✓ Timing:    completed");
  assert (not (has ui "Reselect"));
  assert ([%equal: Tile.Intent.t list] (snd (take (run ui "R"))) [ timing ])
;;

let%test_unit "an explicit flow change preserves the stage ID but never replaces a withdrawn stage" =
  let original = snapshot () in
  let ui = ui original |> open_stage |> Fn.flip run "j" in
  let new_timing = intent "timing-in-explore-flow" in
  let switched =
    { original with rows = List.map original.rows ~f:(fun row ->
        if String.equal row.id "t" then { row with action = Ready new_timing } else row) }
  in
  let ui = Ui_state.with_selected_silver_flow ui switched in
  let ui, captured = take (run ui "R") in
  assert ([%equal: Tile.Intent.t list] captured [ new_timing ]);
  let dropped = { switched with rows = List.filter switched.rows ~f:(fun row -> not (String.equal row.id "t")) } in
  let ui = Ui_state.with_selected_silver_flow ui dropped in
  let ui = run ui "R" in
  assert (has ui "select a stage again");
  assert (List.is_empty (snd (take ui)))
;;

let%test_unit "stage evidence has native status roles and stays aligned across scrolling" =
  let ready id label status : Tile.Row.t = { id; label; status; action = Ready (intent id) } in
  let stages : Tile.Snapshot.t =
    { empty = "No stages"
    ; aliases = []
    ; context = Some "chip/v1 · f/p"
    ; watch_context = None
    ; rows =
        [ ready "synthesis" "Synthesis" Unknown
        ; ready "floorplan" "Floorplan" Pending
        ; ready "placement" "Placement" Running
        ; ready "cts" "Clock tree synthesis" Completed
        ; { id = "routing"; label = "Routing"; status = Failed; action = Blocked routing_reason }
        ; ready "timing" "Timing" Not_requested
        ; ready "signoff" "Signoff" Skipped
        ; ready "custom" "Custom 界界界界界界界界界界界界 stage" Cancelled
        ; ready "interrupt" "Interrupt" Interrupted
        ; ready "cancel" "Cancel" Cancelling
        ; ready "unsupported" "Unsupported" Unsupported
        ; ready "unknown" "Unknown" (Unrecognized "observation_unavailable")
        ]
    }
  in
  let ui = ui stages |> open_stage in
  let body ui ~width ~rows ~focused =
    (View_registry.render (Ui_state.views ui) Tile.id (Ui_state.controller ui)
       ~hotkey_hints:false ~focused ~notice:None ~pending:None ~width ~rows
     |> Option.value_exn).body
  in
  let field row ~left ~cols =
    Span.of_glyphs (Cell_map.glyphs (Test_span.text row)) ~left ~cols
      ~text:Status ~special:Status_special
    |> Test_span.text
  in
  let check text expected = [%test_eq: string] text expected in
  let status_labels : (string * Style.t) list =
    [ "not reported", Stale; "pending", Warning; "running", Pending; "completed", Diff_added
    ; "failed", Error; "not requested", Stale; "skipped", Warning; "cancelled", Warning
    ; "interrupted", Warning; "cancelling…", Pending; "unsupported", Stale; "unconfirmed", Stale ]
  in
  List.iter [ 21, 9; 27, 14; 54, 30; 90, 30 ] ~f:(fun (width, status_col) ->
    let all = body ui ~width ~rows:13 ~focused:true in
    let header, rows = List.hd_exn all, List.tl_exn all in
    assert (String.is_prefix (Test_span.text header) ~prefix:"chip/v1 · f/p");
    List.iter2_exn rows status_labels ~f:(fun row (status, style) ->
      [%test_eq: int] (Span.total_width row) width;
      let expected = Tile_text.row style status ~width:(width - status_col) |> Test_span.text in
      check (field row ~left:status_col ~cols:(width - status_col)) expected;
      [%test_eq: bool] (Style.equal (Test_span.style_at row status_col) style) true;
      [%test_eq: bool] (Style.equal (Test_span.style_at row 2) style) true);
    let cts = List.nth_exn rows 3 in
    check (field (List.hd_exn rows) ~left:0 ~cols:4) "› ? ";
    check (field cts ~left:0 ~cols:8) "  ✓ CTS:";
    let selected_routing = run ui "jjjj" in
    let selected = List.last_exn (body selected_routing ~width ~rows:3 ~focused:true) in
    check (field selected ~left:0 ~cols:4) "› ! ";
    check (field selected ~left:status_col ~cols:6) "failed";
    [%test_eq: bool] (Style.equal (Test_span.style_at selected 0) Pending) true;
    [%test_eq: bool] (Style.equal (Test_span.style_at selected status_col) Error) true;
    let unfocused = List.nth_exn (body selected_routing ~width ~rows:2 ~focused:false) 1 in
    check (field unfocused ~left:0 ~cols:4) "  ? ";
    let custom = List.nth_exn rows 7 in
    if width >= 54 then check (field custom ~left:(status_col - 5) ~cols:3) "界>";
    let joined = String.concat ~sep:"\n" (List.map rows ~f:Test_span.text) in
    List.iter [ "Available"; "endpoint"; routing_reason; "Clock tree synthesis" ] ~f:(fun substring ->
      assert (not (String.is_substring joined ~substring))));
  let tiny = body (run ui "jjj") ~width:3 ~rows:1 ~focused:true |> List.hd_exn in
  check (Test_span.text tiny) "› ✓";
  assert (List.is_empty (snd (take (run ui "jjjjR"))));
  assert ([%equal: Tile.Intent.t list] (snd (take (run ui "jjjR"))) [ intent "cts" ])
;;

let%test_unit "elapsed checklist frames repaint only active markers without changing UI state" =
  let original = snapshot () in
  let stages =
    { original with
      rows = original.rows @
        List.map
          ([ "Cancelling", Tile.Status.Cancelling; "Pending", Pending; "Failed", Failed
           ; "Skipped", Skipped; "Cancelled", Cancelled; "Interrupted", Interrupted
           ; "Unsupported", Unsupported; "Idle", Not_requested
           ; "Raw", Unrecognized "running passed" ])
          ~f:(fun (label, status) ->
            { Tile.Row.id = label; label; status; action = Blocked "No endpoint" })
    }
  in
  let ui = open_stage (ui stages) |> Fn.flip run "j" in
  let at elapsed_ms =
    Tile.Spinner.at (Time_ns.add Time_ns.epoch (Time_ns.Span.of_ms elapsed_ms))
  in
  let cache = Frame.Cache.create () in
  let builds = ref 0 in
  let render elapsed =
    Frame.Cache.get ~stage_spinner:(at elapsed) cache ui ~width ~height ~draw_base:(fun frame ->
      incr builds;
      Frame.to_string frame)
  in
  let first, base = render 0. in
  let _, same_base = render 99. in
  [%test_eq: string] base same_base;
  [%test_eq: int] !builds 1;
  let frames = [ "⣷"; "⣯"; "⣟"; "⡿"; "⢿"; "⣻"; "⣽"; "⣾"; "⣷" ] in
  let normalize text glyph = String.substr_replace_all text ~pattern:glyph ~with_:"⣷" in
  (* Render out of order and skip frames: the phase depends on time, not calls. *)
  List.iter [ 1; 7; 4; 2; 3; 5; 6; 8 ] ~f:(fun step ->
    let frame, current_base = render (100. *. Int.to_float step) in
    let glyph = List.nth_exn frames step in
    let has marker label =
      assert (String.is_substring current_base ~substring:(marker ^ " " ^ label ^ ":"))
    in
    has glyph "Timing";
    has glyph "Cancelling";
    has "◷" "Pending";
    [%test_eq: string] base (normalize current_base glyph);
    [%test_eq: string] (Frame.to_string_styled first)
      (normalize (Frame.to_string_styled frame) glyph));
  [%test_eq: int] !builds 9;
  [%test_eq: string] (focus ui) "silver-stage";
  assert (List.is_empty (snd (take ui)));
  let tile = Option.value_exn (View_registry.find (Ui_state.views ui) Tile.key) in
  assert (List.is_empty (snd (Tile.take_watches tile)));
  assert ([%equal: Tile.Intent.t list] (snd (take (run ui "R"))) [ timing ])
;;

let%test_unit "the checklist only requests a clock while an active marker can be painted" =
  let original = snapshot () in
  let initial = ui original in
  let ticking ui = Ui_state.silver_stage_spinner_visible ui ~width ~height in
  assert (not (ticking initial));
  let shown = open_stage initial in
  assert (ticking shown);
  assert (not (Ui_state.silver_stage_spinner_visible shown ~width ~height:2));
  let tile = Option.value_exn (View_registry.find (Ui_state.views shown) Tile.key) in
  let visible ~rows ~width ~covered = Tile.spinner_visible tile ~focused:false ~rows ~width ~covered in
  let uncovered ~column:_ ~row:_ = false in
  assert (not (visible ~rows:2 ~width:40 ~covered:uncovered));
  assert (not (visible ~rows:3 ~width:2 ~covered:uncovered));
  assert (visible ~rows:3 ~width:3 ~covered:uncovered);
  assert (not (visible ~rows:3 ~width:40 ~covered:(fun ~column ~row -> column = 2 && row = 2)));
  let inactive =
    { original with rows = List.map original.rows ~f:(fun row ->
        if Tile.Status.equal row.status Running then { row with status = Pending } else row) }
  in
  assert (not (ticking (Ui_state.with_silver_stage shown inactive)));
  assert (not (ticking (run shown " ccToggle Silver: Stage Checklist<CR>")))
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
