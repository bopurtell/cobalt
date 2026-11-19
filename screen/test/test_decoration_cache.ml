open! Core
open Cobalt_core
open Cobalt_screen
open Helpers

module Snapshot = Cobalt_decoration.Snapshot

let prepared ui =
  let editor = Cobalt_app.Controller.editor (Ui_state.controller ui) in
  let source = Editor.text editor in
  let key = Snapshot.Key.create ~document:(Snapshot.Document_id.create ())
    ~revision:(Editor.revision editor) ~provider:"cache-fixture" ~configuration:"v1" in
  let snapshot = Snapshot.create ~key ~source:(Text_buffer.to_string source)
    [ Style { range = { start = 7; stop = 11 }; role = Accent } ] |> Or_error.ok_exn in
  key, (Decoration.prepare ~source snapshot |> Or_error.ok_exn)
;;

let%test_unit "cache keys include expected key, prepared identity and removal" =
  let ui = ui "anchor\nbody" in
  let first = prepared ui in
  let second = prepared ui in
  let cache = Frame.Cache.create () in
  let draws = ref 0 in
  let get ?decorations model =
    Frame.Cache.get ?decorations cache model ~width:40 ~height:8
      ~draw_base:(fun frame -> incr draws; Frame.to_string_styled frame) in
  let _, original = get ~decorations:first ui in
  ignore (get ~decorations:first ui : Frame.t * string);
  assert (!draws = 1);
  let stale_key = fst second, snd first in
  let actual, _ = get ~decorations:stale_key ui in
  assert (!draws = 2);
  assert (String.equal (Frame.to_string_styled actual)
    (Frame.to_string_styled (Frame.render ui ~width:40 ~height:8)));
  ignore (get ~decorations:first ui : Frame.t * string);
  assert (!draws = 3);
  let _, restored = get ~decorations:first ui in
  assert (String.equal original restored && !draws = 3);
  ignore (get ui : Frame.t * string);
  assert (!draws = 4);
  ignore (get ~decorations:second ui : Frame.t * string);
  assert (!draws = 5);
  (* Same key and source, independently prepared immutable payload. *)
  let source = Editor.text (Cobalt_app.Controller.editor (Ui_state.controller ui)) in
  let key = fst second in
  let snapshot = Snapshot.create ~key ~source:(Text_buffer.to_string source)
    [ Style { range = { start = 7; stop = 11 }; role = Accent } ] |> Or_error.ok_exn in
  let replacement = key, (Decoration.prepare ~source snapshot |> Or_error.ok_exn) in
  ignore (get ~decorations:replacement ui : Frame.t * string);
  assert (!draws = 6);
  (* An equal-content/revision but distinct buffer must fail the provenance gate
     BEFORE cache lookup, even when the caller repeats a formerly valid pair. *)
  let other = Helpers.ui "anchor\nbody" in
  let actual, _ = get ~decorations:replacement other in
  assert (!draws = 7);
  assert (String.equal (Frame.to_string_styled actual)
    (Frame.to_string_styled (Frame.render other ~width:40 ~height:8)))
;;

let%test_unit "unchanged decorations retain animation base work" =
  let ui = Ui_state.create ~smear_enabled:true ~tiles_visible:false
    (Ui_state.controller (ui "anchor\nbody")) in
  let decorations = prepared ui in
  let cache = Frame.Cache.create () in
  let draws = ref 0 in
  let get model = Frame.Cache.get ~decorations cache model ~width:40 ~height:8
    ~draw_base:(fun _ -> incr draws) in
  ignore (get ui : Frame.t * unit);
  let model = ref ui in
  for i = 1 to 20 do
    let at = Time_ns.add Time_ns.epoch (Time_ns.Span.of_ms (Float.of_int (i * 17))) in
    model := fst (Frame.Cache.apply_inputs cache !model ~width:40 ~height:8 [ Animation_tick at ]);
    ignore (get !model : Frame.t * unit)
  done;
  assert (!draws = 1)
;;
