open! Core
open Cobalt_app
open Cobalt_core
open Cobalt_input
module Location = Session.Open_location

let width u = if Stdlib.Uchar.to_int u = 0x754c then 2 else 1
let original = "start\né界x\n"

let request ?position project_root relative_file : Location.request =
  { project_root; relative_file; position }
;;

let position line column : Location.position = { line; column }
let active session = Option.value_exn (Session.active_controller session)
let editor session = Controller.editor (active session)
let text session = Text_buffer.to_string (Editor.text (editor session))

let opened session request =
  match Session.open_location !session request with
  | Ok (next, id) ->
    session := next;
    assert (Option.equal Buffer_id.equal (Session.active_id next) (Some id));
    assert (Option.equal Buffer_id.equal (Session.context_id next) (Some id));
    id
  | Error failure -> Error.raise (Location.to_error failure)
;;

let rejected session request check =
  let before = !session in
  let buffers = Session.buffer_count before in
  match Session.open_location before request with
  | Ok (next, _) ->
    session := next;
    failwith "location request should have failed"
  | Error failure ->
    if not (check failure) then Error.raise (Location.to_error failure);
    assert (Session.buffer_count !session = buffers);
    assert (Session.same_file_lifetimes !session before)
;;

let key session input =
  let next, commands, status = Session.handle_input !session input in
  session := next;
  assert (List.is_empty commands);
  assert (Controller.Status.equal status Running)
;;

let char session c = key session (Key (Key.char c))
let unavailable_failure = function Location.Target_unavailable _ -> true | _ -> false
let position_failure = function Location.Invalid_position _ -> true | _ -> false
let file_failure = function Location.Invalid_relative_file _ -> true | _ -> false

let fixture f =
  let root = Core_unix.mkdtemp (Filename.concat Filename.temp_dir_name "cobalt-location-") in
  let nested = Filename.concat root "nested" in
  let first = Filename.concat nested "first.txt"
  and second = Filename.concat root "second.txt" in
  Core_unix.mkdir nested;
  Out_channel.write_all first ~data:original;
  Out_channel.write_all second ~data:"other\n";
  Exn.protect ~f:(fun () -> f root nested first second) ~finally:(fun () ->
    Core_unix.unlink first;
    Core_unix.unlink second;
    Core_unix.rmdir nested;
    Core_unix.rmdir root)
;;

let run () =
  fixture (fun root nested first second ->
    let start path = Startup.open_path ~cell_width:width path |> Or_error.ok_exn in
    let session = ref (Session.create ~cell_width:width (start root)) in
    Exn.protect ~finally:(fun () -> Session.dispose !session) ~f:(fun () ->
      assert (String.equal root (Session.project_root !session));
      assert (Session.buffer_count !session = 0);

      rejected session (request root "missing.txt") unavailable_failure;
      assert (Option.is_none (Session.find_resource !session "missing.txt"));
      printf "missing.txt -> Target_unavailable (no tab)\n";
      let wrong = root ^ "-other" in
      rejected session (request wrong "second.txt") (function
        | Wrong_project { expected; requested } ->
          String.equal expected root && String.equal requested wrong
        | _ -> false);
      printf "second.txt with a different root -> Wrong_project (no tab)\n";
      rejected session (request "relative-root" "second.txt") (function
        | Wrong_project _ -> true | _ -> false);
      List.iter [ second; ""; "."; "../outside.txt"; "nested\000" ] ~f:(fun path ->
        rejected session (request root path) file_failure);
      rejected session (request root "nested") unavailable_failure;
      rejected session (request root "nested/absent/file.txt") unavailable_failure;
      rejected session (request root ~position:(position 0 1) "second.txt") position_failure;
      assert (Option.is_none (Session.find_resource !session second));
      assert (Option.is_some (Session.input_directory !session));

      let first_id = opened session (request root "nested/first.txt") in
      let document = Controller.document_id (active !session) in
      assert (String.equal (text !session) original && Editor.cursor (editor !session) = 0);
      assert (Option.is_none (Session.directory_presentation !session));
      printf "nested/first.txt (file only) -> opened at byte 0\n";
      char session 'i';
      key session (Paste "unsaved ");
      assert (Mode.equal (Editor.mode (editor !session)) Insert);
      let cursor = Editor.cursor (editor !session) in
      rejected session (request root ~position:(position 2 99) "nested/first.txt") position_failure;
      assert (Mode.equal (Editor.mode (editor !session)) Insert);
      assert (Editor.cursor (editor !session) = cursor);
      assert (String.equal (text !session) ("unsaved " ^ original));

      let second_id = opened session (request root "second.txt") in
      assert (not (Buffer_id.equal first_id second_id));
      assert (String.equal (text !session) "other\n");
      printf "edited first, then second.txt (file only) -> opened a different buffer\n";
      let next, _ = Session.take_source_changes !session in
      session := next;
      let reopened = opened session (request (root ^ "/./")
        ~position:(position 2 3) "nested/./first.txt") in
      assert (Buffer_id.equal reopened first_id);
      assert (Controller.Document_id.equal (Controller.document_id (active !session)) document);
      assert (Editor.cursor (editor !session) = String.length "unsaved start\né");
      assert (Editor.cursor_line (editor !session) = 1);
      assert (Editor.is_dirty (editor !session));
      assert (String.equal (text !session) ("unsaved " ^ original));
      assert (String.equal (In_channel.read_all first) original);
      assert (Session.buffer_count !session = 2);
      assert (List.is_empty (snd (Session.take_source_changes !session)));
      printf "nested/./first.txt at (2, 3) -> same dirty buffer, on 界\n";

      assert (Buffer_id.equal (opened session (request root
        ~position:(position 2 4) "nested/first.txt")) first_id);
      let x = String.length "unsaved start\né界" in
      assert (Editor.cursor (editor !session) = x);
      ignore (opened session (request root "second.txt") : Buffer_id.t);
      ignore (opened session (request root "nested/first.txt") : Buffer_id.t);
      assert (Editor.cursor (editor !session) = x);
      char session 'u';
      assert (String.equal (text !session) original);
      assert (not (Editor.is_dirty (editor !session)));
      key session (Key (Ctrl 'r'));
      assert (String.equal (text !session) ("unsaved " ^ original));
      printf "file-only reopen preserves cursor; undo and redo still work\n";

      char session 'i';
      key session (Paste "!");
      (* Column 10 only exists in the unsaved first line. This also exercises
         same-buffer navigation while the target is still in Insert. *)
      ignore (opened session (request root ~position:(position 1 10) "nested/first.txt") : Buffer_id.t);
      assert (Mode.equal (Editor.mode (editor !session)) Normal);
      assert (Editor.cursor (editor !session) = 9);
      char session 'u';
      assert (String.equal (text !session) ("unsaved " ^ original));
      let next, status = Session.quit !session ~force:true in
      session := next;
      assert (Controller.Status.equal status Exit);
      rejected session (request root "second.txt") (function
        | Session_exited -> true | _ -> false));

    let overridden = ref (Session.create ~cwd:root ~project_root:"." ~cell_width:width (start first)) in
    Exn.protect ~finally:(fun () -> Session.dispose !overridden) ~f:(fun () ->
      assert (String.equal nested (Session.startup_directory !overridden));
      assert (String.equal root (Session.project_root !overridden));
      ignore (opened overridden (request root ~position:(position 1 2) "second.txt") : Buffer_id.t);
      assert (Editor.cursor (editor !overridden) = 1);
      rejected overridden (request nested "first.txt") (function
        | Wrong_project _ -> true | _ -> false)))
;;

let () = run ()
