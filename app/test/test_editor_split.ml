open! Core
open Cobalt_app
open Cobalt_core
open Cobalt_input

let with_files f =
  let dir = Core_unix.mkdtemp (Filename.concat (Stdlib.Filename.get_temp_dir_name ()) "cobalt-editor-split-") in
  let a = Filename.concat dir "a" and b = Filename.concat dir "b" and c = Filename.concat dir "c" in
  List.iter [ a; b; c ] ~f:(fun path -> Out_channel.write_all path ~data:(Filename.basename path ^ "\n"));
  Exn.protect ~f:(fun () ->
    let cell_width _ = 1 in
    let first = Controller.open_file a ~cell_width |> Or_error.ok_exn in
    f (Session.create ~cell_width first) a b c)
    ~finally:(fun () -> List.iter [ a; b; c ] ~f:Core_unix.unlink; Core_unix.rmdir dir)
;;

let active t = Option.value_exn (Session.active_id t)
let split t = Option.value_exn (Session.editor_split t)
let editor t id = Session.find t id |> Option.value_exn |> Controller.editor
let text t id = Text_buffer.to_string (Editor.text (editor t id))
let is = Buffer_id.equal
let activate t id = Session.activate t id |> Or_error.ok_exn
let dispatch t command = let t, _, _ = Session.dispatch t [ Keymap.Action.Editor command ] in t
let key t c = let t, _, _ = Session.handle_input t (Keymap.Input.Key (Key.char c)) in t
let insert t text = dispatch (dispatch (key t 'i') (Insert_text text)) Exit_insert

let%test_unit "second editor uses the original tab, keeps Visual, and routes save/reload/undo to one file" =
  with_files (fun t a b _ ->
    let aid = active t in
    let t = key t 'v' in
    let selected = Editor.selection (editor t aid) in
    assert (Option.is_some selected);
    assert (Result.is_error (Session.split_open_file t a));
    assert (Result.is_error (Session.split_open_file t (b ^ "-missing")));
    let t, bid = Session.split_open_file t b |> Or_error.ok_exn in
    assert (is (active t) bid && is (split t).other aid && (split t).active_secondary);
    assert (Session.buffer_count t = 2);
    assert (Poly.equal (Editor.selection (editor t aid)) selected);
    let t = insert t "B-" |> fun t -> activate t aid in
    assert (not (split t).active_secondary && is (split t).other bid);
    assert (Poly.equal (Editor.selection (editor t aid)) selected);
    let t = insert (dispatch t Exit_visual) "A-" in
    let t = Session.save_current t in
    assert (String.equal (In_channel.read_all a) "A-a\n");
    assert (String.equal (In_channel.read_all b) "b\n");
    Out_channel.write_all a ~data:"on disk\n";
    let t = dispatch t Reload in
    assert (String.equal (text t aid) "on disk\n"
      && String.equal (text t bid) "B-b\n" && Editor.is_dirty (editor t bid));
    let t = activate t bid |> fun t -> dispatch t Undo in
    assert (String.equal (text t aid) "on disk\n" && String.equal (text t bid) "b\n");
    let t = insert t "new-" |> fun t -> activate t aid |> Session.close_editor_split in
    assert (is (active t) aid && Option.is_none (Session.editor_split t));
    assert (Session.buffer_count t = 2 && String.equal (text t bid) "new-b\n");
    let t, status = Session.quit t ~force:false in
    assert (Controller.Status.equal status Running);
    let t, closed = Session.close_buffer t bid ~force:false in
    assert (not closed);
    Session.dispose t)
;;

let%test_unit "replacing and closing tabs never leaves duplicate or dangling pane identities" =
  with_files (fun t a b c ->
    let aid = active t in
    let t, bid = Session.split_open_file t b |> Or_error.ok_exn in
    let t, cid = Session.open_or_activate t c |> Or_error.ok_exn in
    assert (is (active t) cid && is (split t).other aid && (split t).active_secondary);
    let t, a_again = Session.open_or_activate t a |> Or_error.ok_exn in
    assert (is a_again aid && is (active t) aid && is (split t).other cid && not (split t).active_secondary);
    let t, closed = Session.close_buffer t bid ~force:false in
    assert (closed && is (split t).other cid);
    let t, closed = Session.close_current t ~force:false in
    assert (closed && is (active t) cid && Option.is_none (Session.editor_split t));
    Session.dispose t)
;;
