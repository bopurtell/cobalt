open! Core
open Cobalt_app
open Cobalt_screen

let width = 100
let height = 16
let run ?(width = width) ?(height = height) ui keys =
  Helpers.run ~width ~height ui (Helpers.keys keys)
;;
let with_files f =
  let root = Helpers.scratch_dir "cobalt-split-screen-" in
  let a = Filename.concat root "alpha.txt"
  and b = Filename.concat root "beta.txt"
  and c = Filename.concat root "gamma.txt" in
  let write path label =
    Out_channel.write_all path ~data:(String.concat (List.init 60 ~f:(fun i -> sprintf "%s_%02d\n" label i))) in
  write a "ALPHA"; write b "BETA"; write c "GAMMA";
  Exn.protect ~f:(fun () -> f root a b c)
    ~finally:(fun () -> List.iter [ a; b; c ] ~f:Core_unix.unlink; Core_unix.rmdir root)
;;
let create ?(views = []) a =
  let controller = Controller.open_file a ~cell_width:Cell_map.width |> Or_error.ok_exn in
  Ui_state.create ~tiles_visible:false ~views controller
;;
let active ui = Option.value_exn (Session.active_id (Ui_state.session ui))
let open_ ui path = Ui_state.open_file ui ~width ~height path |> Or_error.ok_exn
let panes ?(width = width) ?(height = height) ui = Ui_state.editor_panes ui ~width ~height
let pane ui id = List.find_exn (panes ui) ~f:(fun p -> Buffer_id.equal p.buffer id)
let rendered ui = Frame.to_string (Frame.render ui ~width ~height)
let contains s sub = String.is_substring s ~substring:sub
let view ui = Ui_state.focused_view ui ~width ~height
let dispose ui = Session.dispose (Ui_state.session ui)
let show_pair ui left right ~focused =
  let ids = List.map (panes ui) ~f:(fun pane -> pane.buffer, pane.focused) in
  let expected = List.map [ left; right ] ~f:(fun id -> id, Buffer_id.equal focused id) in
  assert ([%equal: (Buffer_id.t * bool) list] ids expected)
;;

let%test_unit "only the focused split title has one trailing title-colored cell" =
  with_files (fun _ a b _ ->
    let ui = create a in
    let aid = active ui in
    let ui, bid = open_ ui b in
    let ui = run ui " sn" in
    let check ui id path ~focused =
      let frame = Frame.render ui ~width ~height in
      let allocation = (pane ui id).allocation in
      let tabs = Ui_state.workspace_tab_rect ui (Ui_state.workspace ui ~width ~height) in
      let row = List.nth_exn frame.rows (allocation.y + Bool.to_int (Option.is_some tabs)) in
      let rec from x = function
        | (span : Span.t) :: rest when x > 0 -> from (x - span.width) rest
        | spans when x = 0 -> spans
        | _ -> failwith "expected a title at the start of the pane" in
      let label = (if focused then "> " else "  ") ^ Filename.basename path
        ^ (if focused then " " else "") in
      match from allocation.x row with
      | title :: background :: _ ->
        assert (String.equal title.text label && title.width = String.length label);
        assert (Style.equal title.style (if focused then Title else Hint));
        assert (Style.equal background.style Status && background.width > 0)
      | _ -> failwith "expected a title followed by header background" in
    check ui aid a ~focused:true;
    check ui bid b ~focused:false;
    let ui = run ui " sf" in
    check ui aid a ~focused:false;
    check ui bid b ~focused:true;
    dispose ui)
;;

let%test_unit "file split frame, palette, focus, swap/width, tab replacement and independent scroll" =
  with_files (fun _ a b c ->
    let ui = create a in
    let aid = active ui in
    let ui, bid = open_ ui b in
    let ui = run ui "32G vN ccSplit editor with next file tab<CR>" in
    show_pair ui bid aid ~focused:aid;
    let frame = Frame.render ui ~width ~height in
    assert (List.for_all frame.rows ~f:(fun row -> Span.total_width row = width));
    assert (contains (Frame.to_string frame) "ALPHA_00" && contains (Frame.to_string frame) "BETA_30");
    let first_row = List.hd_exn frame.rows |> List.map ~f:(fun span -> span.Span.text) |> String.concat in
    assert (contains first_row "[1:alpha.txt]" && contains first_row "2:beta.txt");
    let cursor = Option.value_exn frame.cursor in
    let viewport = (pane ui aid).geometry.text in
    assert (cursor.x >= viewport.x && cursor.x < viewport.x + viewport.width);
    let before = (pane ui bid).scroll in
    assert (before.top > 0 && (pane ui aid).scroll.top = 0);
    let ui = run ui "17G sf" in
    assert (Buffer_id.equal (active ui) bid && Scroll.equal (Ui_state.scroll ui) before);
    assert ((pane ui aid).scroll.top > 0);
    let ui = run ui " sx s+" in
    show_pair ui aid bid ~focused:bid;
    assert ((pane ui bid).allocation.width > (pane ui aid).allocation.width);
    let ui, cid = open_ ui c in
    show_pair ui aid cid ~focused:cid;
    assert (Session.buffer_count (Ui_state.session ui) = 3);
    let ui = run ui " bn" in
    assert ([%equal: (Buffer_id.t * bool) list]
      (List.map (panes ui) ~f:(fun p -> p.buffer, p.focused))
      [aid, false; aid, true]);
    let ui, again = open_ ui c in
    assert (Buffer_id.equal again cid);
    show_pair ui aid cid ~focused:cid;
    let ui = run ui "iX<Esc> sf sc" in
    assert (List.length (panes ui) = 1 && Buffer_id.equal (active ui) aid);
    let ui, status = Ui_state.apply_all ui ~width ~height (Helpers.keys " q") in
    assert (Controller.Status.equal status Running);
    assert (contains (rendered ui) "Unsaved changes" && Session.buffer_count (Ui_state.session ui) = 3);
    dispose ui)
;;

let%test_unit "resize, zen, directory sidebar and major VCS slot are independent" =
  with_files (fun root a b _ ->
    let ui = create ~views:[ Vcs_view.entry ~cwd:root () ] a in
    let aid = active ui in
    let ui, bid = open_ ui b in
    let ui = run ui " gs sn" in
    let split_view ui = View_registry.split (Ui_state.views ui) in
    assert (Option.equal Cobalt_tile.View_id.equal (split_view ui) (Some Vcs_view.id));
    assert (Option.is_none (Session.editor_split (Ui_state.session ui)));
    assert (contains (rendered ui) "occupies the split");
    let ui = run ui " gh sn gs" in
    show_pair ui bid aid ~focused:aid;
    assert (Option.is_none (split_view ui) && contains (rendered ui) "occupy the split");
    let resize ~width ~height ui = Helpers.run ~width ~height ui [ Ui_state.Input.Resize ] in
    let ui = resize ui ~width:32 ~height in
    let ui = run ui ~width:32 " sf" in
    assert (List.length (panes ui ~width:32) = 1 && Buffer_id.equal (active ui) aid);
    assert (contains (Frame.to_string (Frame.render ui ~width:32 ~height)) "ALPHA"
      && not (contains (Frame.to_string (Frame.render ui ~width:32 ~height)) "BETA"));
    let ui = resize ui ~width ~height:3 in
    assert (List.length (panes ui ~height:3) = 1);
    let ui = resize ui ~width ~height in
    show_pair ui bid aid ~focused:aid;
    let ui = run ui " vz sf" in
    assert (List.length (panes ui) = 1 && Buffer_id.equal (active ui) aid);
    let ui = run ui " vz ds" in
    assert (Option.is_some (Ui_state.side_layout ui ~width ~height));
    assert (Cobalt_tile.View_id.equal (view ui) Ui_state.directory_id);
    assert (List.length (panes ui) = 2 && not (List.exists (panes ui) ~f:(fun pane -> pane.focused)));
    let frame = rendered ui in
    assert (contains frame "Directory" && contains frame "ALPHA" && contains frame "BETA");
    let ui = run ui " df" in
    show_pair ui bid aid ~focused:aid;
    dispose ui)
;;

let%test_unit "split picker opens a second file and ordinary picker replaces the focused pane" =
  with_files (fun root a b _ ->
    let module Model = Cobalt_file_picker.Model in
    let ui = create a in
    let aid = active ui in
    let pick ui ~split path serial =
      let request : Model.Discovery.request = { root; run_id = Model.Run_id.of_int serial } in
      let candidate = Model.Candidate.create ~root ~relative_path:(Filename.basename path) |> Or_error.ok_exn in
      let discovery : Model.Discovery.t = { request; status = Complete { truncated = false }; candidates = [candidate] } in
      let ui = Ui_state.open_file_picker ~split ui ~width ~height ~discovery ~release:(fun () -> ()) in
      let rec finish ui n =
        let interaction = File_picker_tile.session (Option.value_exn (Ui_state.file_picker ui)) in
        if not (Cobalt_file_picker.Interaction.busy interaction) then ui
        else if n = 0 then failwith "picker did not converge"
        else finish (Helpers.run ~width ~height ui [ File_picker_work request ]) (n - 1) in
      let ui = run (finish ui 100) "<CR>" in
      let ui, requests = Ui_state.take_file_requests ui in
      let request = match requests with [request] -> request | _ -> failwith "expected one picker request" in
      assert (Option.is_none (Ui_state.file_picker ui));
      Helpers.run ~width ~height ui [ File_picker_accept request ] in
    let ui, intent = Ui_state.take_file_picker_activation (run ui " so") in
    assert (Poly.equal intent (Some `Split));
    let ui = pick ui ~split:true a 1 in
    assert (Option.is_none (Session.editor_split (Ui_state.session ui)) && Buffer_id.equal (active ui) aid);
    let ui = pick ui ~split:true b 2 in
    let bid = active ui in
    show_pair ui aid bid ~focused:bid;
    let ui = pick ui ~split:false a 3 in
    assert ([%equal: (Buffer_id.t * bool) list]
      (List.map (panes ui) ~f:(fun p -> p.buffer, p.focused))
      [aid, false; aid, true]);
    dispose ui)
;;

let%test_unit "cycling to the other pane's file keeps focus and allows independent cursor and scroll" =
  with_files (fun _ a b c ->
    let module Editor = Cobalt_core.Editor in
    let ui = create a in
    let aid = active ui in
    let ui = run ui "12G" in
    let ui, bid = open_ ui b in
    let ui, cid = open_ ui c in
    let ui = run ui " sn" in
    show_pair ui cid aid ~focused:aid;
    let ui = run ui " bp" in
    let by_slot ui secondary = List.find_exn (panes ui) ~f:(fun p -> Bool.equal p.secondary secondary) in
    let assert_pair ui primary secondary ~focused_secondary =
      List.iter [false, primary; true, secondary] ~f:(fun (slot, id) ->
        let p = by_slot ui slot in
        assert (Buffer_id.equal p.buffer id && Bool.equal p.focused (Bool.equal slot focused_secondary))) in
    assert_pair ui cid cid ~focused_secondary:true;
    let ui = run ui "45G" in
    assert ((by_slot ui true).scroll.top > (by_slot ui false).scroll.top);
    let ui = run ui " sf" in
    assert_pair ui cid cid ~focused_secondary:false;
    let cursor ui = Editor.cursor_line (Controller.editor (Ui_state.controller ui)) in
    assert (cursor ui = 0);
    let ui = run ui "22G sf" in
    assert_pair ui cid cid ~focused_secondary:true;
    assert (cursor ui = 44);
    let ui = run ui " bn bn" in
    assert_pair ui cid bid ~focused_secondary:true;
    let ui = run ui " bn sf" in
    assert_pair ui cid cid ~focused_secondary:false;
    assert (cursor ui = 21);
    let ui = run ui " bn" in
    assert_pair ui aid cid ~focused_secondary:false;
    let ui = Ui_state.activate_buffer ui ~width ~height cid |> Or_error.ok_exn in
    assert_pair ui cid cid ~focused_secondary:false;
    assert (cursor ui = 21);
    let ui = run ui " sf sc" in
    assert (List.length (panes ui) = 1 && cursor ui = 44);
    assert ((List.hd_exn (panes ui)).scroll.top > 25);
    dispose ui)
;;

let%test_unit "closing a shared file tab refuses unsaved edits unless forced" =
  with_files (fun _ a b _ ->
    let ui = create a in
    let aid = active ui in
    let ui, bid = open_ ui b in
    let ui = run ui " sn bniX<Esc>" in
    assert (List.length (String.substr_index_all (rendered ui) ~pattern:"XBETA_00" ~may_overlap:false) = 2);
    let ui = run ui " bc" in
    assert (List.length (panes ui) = 2 && Buffer_id.equal (active ui) bid);
    assert (contains (rendered ui) "Unsaved buffer");
    let ui = run ui " bC" in
    assert (List.length (panes ui) = 1 && Buffer_id.equal (active ui) aid);
    assert (Session.buffer_count (Ui_state.session ui) = 1);
    assert (String.is_prefix (In_channel.read_all b) ~prefix:"BETA");
    dispose ui)
;;

let%test_unit "keyboard save and force reload affect only the focused editor" =
  with_files (fun _ a b _ ->
    let ui = create a in
    let aid = active ui in
    let ui, bid = open_ ui b in
    let ui = run ui " sniLEFT<Esc> w sfiRIGHT<Esc>" in
    show_pair ui bid aid ~focused:bid;
    assert (String.is_prefix (In_channel.read_all a) ~prefix:"LEFTALPHA_00");
    assert (String.is_prefix (In_channel.read_all b) ~prefix:"BETA_00");
    Out_channel.write_all b ~data:"new from disk\n";
    let ui = run ui ":e!<CR>" in
    let frame = rendered ui in
    assert (contains frame "LEFTALPHA_00" && contains frame "new from disk" && not (contains frame "RIGHT"));
    dispose ui)
;;
