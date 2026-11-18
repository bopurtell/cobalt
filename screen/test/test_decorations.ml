open! Core
open Cobalt_core
open Cobalt_screen
open Helpers

module Snapshot = Cobalt_decoration.Snapshot
module Controller = Cobalt_app.Controller

let editor ui = Controller.editor (Ui_state.controller ui)
let source ui = Text_buffer.to_string (Editor.text (editor ui))

let key ?(document = Snapshot.Document_id.create ()) ?(provider = "synthetic-v1")
    ?(configuration = "fixture-v1") ui =
  Snapshot.Key.create ~document ~revision:(Editor.revision (editor ui))
    ~provider ~configuration
;;

let range start stop : Snapshot.Range.t = { start; stop }
let style start stop role = Snapshot.Operation.Style { range = range start stop; role }
let replace ?role start stop text =
  Snapshot.Operation.Replace { range = range start stop; text; role }
;;

let ok = function
  | Ok value -> value
  | Error _ -> failwith "synthetic decoration unexpectedly rejected"
;;

let prepare ui operations =
  let key = key ui in
  let snapshot = Snapshot.create ~key ~source:(source ui) operations |> ok in
  let prepared = Decoration.prepare ~source:(Editor.text (editor ui)) snapshot |> ok in
  key, prepared
;;

let render ?decorations ?(width = 40) ?(height = 8) ui =
  Frame.render ?decorations ui ~width ~height
;;

let same_frame expected actual =
  [%test_result: string]
    (Sexp.to_string ([%sexp_of: Frame.t] actual))
    ~expect:(Sexp.to_string ([%sexp_of: Frame.t] expected))
;;

let same_geometry (plain : Frame.t) (decorated : Frame.t) =
  [%test_result: int * int] (decorated.width, decorated.height)
    ~expect:(plain.width, plain.height);
  assert (Option.equal Frame.Cursor.equal decorated.cursor plain.cursor);
  [%test_result: (int * int) list] decorated.smear ~expect:plain.smear;
  [%test_result: int list]
    (List.map decorated.rows ~f:Span.total_width)
    ~expect:(List.map plain.rows ~f:Span.total_width);
  List.iter decorated.rows ~f:(fun row ->
    assert (Span.total_width row = decorated.width);
    List.iter row ~f:(fun span ->
      assert (Cell_map.total_width (Cell_map.glyphs span.text) = span.width)))
;;

let line_start ui line = Text_buffer.line_start (Editor.text (editor ui)) line

let document_row ui (frame : Frame.t) line =
  let geometry = Ui_state.geometry ui ~width:frame.width ~height:frame.height in
  let scroll = Ui_state.fitted_scroll ui ~width:frame.width ~height:frame.height in
  List.nth_exn frame.rows (geometry.text.y + line - scroll.top)
;;

let document_at ui frame line col =
  let geometry = Ui_state.geometry ui ~width:frame.Frame.width ~height:frame.height in
  let scroll = Ui_state.fitted_scroll ui ~width:frame.width ~height:frame.height in
  match Test_span.style_at (document_row ui frame line)
          (geometry.text.x + col - scroll.left) with
  | Style.Document document -> document
  | _ -> failwith "expected document cell"
;;

let row_text row = String.concat (List.map row ~f:(fun (span : Span.t) -> span.text))

let%test_unit "synthetic roles and a byte-length-changing bullet preserve source geometry" =
  let prefs = { Geometry.Prefs.default with line_numbers = Hybrid } in
  let ui = ui ~prefs "anchor\n- accent\nliteral\nmuted" in
  let first = line_start ui 1 in
  let literal = line_start ui 2 in
  let muted = line_start ui 3 in
  let decorations = prepare ui
      [ replace ~role:Accent first (first + 1) "•"
      ; style (first + 2) (first + 8) Accent
      ; style literal (literal + 7) Literal
      ; style muted (muted + 5) Muted
      ] in
  let plain = render ui in
  let decorated = render ~decorations ui in
  same_geometry plain decorated;
  [%test_result: string] (Frame.to_string decorated)
    ~expect:(String.substr_replace_all (Frame.to_string plain) ~pattern:"- accent" ~with_:"• accent");
  List.iter [ 1, 0, Style.Syntax.Keyword; 1, 2, Keyword; 2, 0, String; 3, 0, Comment ]
    ~f:(fun (line, col, expected) ->
      let document = document_at ui decorated line col in
      assert (Style.Syntax.equal document.syntax expected);
      assert (not document.current_line);
      assert (Option.is_none document.overlay));
  assert (Style.Syntax.equal (document_at ui decorated 1 8).syntax Plain);
  [%test_result: string] (source ui) ~expect:"anchor\n- accent\nliteral\nmuted"
;;

let%test_unit "styling preserves TAB expansion, combining text and escaped controls" =
  let ui = ui "anchor\n\t中é\001" in
  let decorations = prepare ui
      [ style (line_start ui 1) (String.length (source ui)) Literal ] in
  let plain = render ui in
  let decorated = render ~decorations ui in
  same_geometry plain decorated;
  [%test_result: string] (Frame.to_string decorated) ~expect:(Frame.to_string plain);
  let row = document_row ui decorated 1 in
  assert (String.is_substring (row_text row) ~substring:"中é^A");
  assert (Style.Syntax.equal (document_at ui decorated 1 8).syntax String);
  let control = document_at ui decorated 1 11 in
  assert control.special;
  [%test_result: string] (Style.to_string_hum (Style.Document control)) ~expect:"Special"
;;

let%test_unit "vertically scrolled decorations retain document-wide Unicode byte offsets" =
  let source = String.concat ~sep:"\n" (List.init 2000 ~f:(fun _ -> "é- tail")) in
  let ui = run (ui source) (keys "1000Gzt") in
  let at = line_start ui 1000 + String.length "é" in
  let decorations = prepare ui
      [ style 0 (String.length source) Muted
      ; replace ~role:Accent at (at + 1) "•" ] in
  let scroll = Ui_state.fitted_scroll ui ~width:40 ~height:8 in
  assert (scroll.top > 0);
  let frame = render ~decorations ui in
  same_geometry (render ui) frame;
  assert (String.is_substring (row_text (document_row ui frame 1000)) ~substring:"é• tail");
  assert (Style.Syntax.equal (document_at ui frame 1000 0).syntax Comment);
  assert (Style.Syntax.equal (document_at ui frame 1000 1).syntax Keyword);
  [%test_result: string]
    (row_text (document_row ui frame (Editor.cursor_line (editor ui))))
    ~expect:(row_text (document_row ui (render ui) (Editor.cursor_line (editor ui))))
;;

let%test_unit "entering the decorated line reveals raw text and leaving restores it" =
  let ui = ui "anchor\n- item\nlast" in
  let first = line_start ui 1 in
  let decorations = prepare ui
      [ replace ~role:Accent first (first + 1) "•"
      ; style (first + 2) (first + 6) Literal ] in
  assert (String.is_substring (Frame.to_string (render ~decorations ui)) ~substring:"• item");
  let on_line = run ui (keys "j") in
  same_frame (render on_line) (render ~decorations on_line);
  let away = run on_line (keys "j") in
  same_geometry (render away) (render ~decorations away);
  assert (String.is_substring (Frame.to_string (render ~decorations away)) ~substring:"• item")
;;

let%test_unit "Visual modes and block insertion reveal even unselected decorated lines" =
  let ui = ui "anchor\n- item\n- outside" in
  let first = line_start ui 1 in
  let last = line_start ui 2 in
  let decorations = prepare ui
      [ replace ~role:Accent first (first + 1) "•"
      ; replace ~role:Muted last (last + 1) "•" ] in
  List.iter [ "v"; "V"; "<C-v>"; "<C-v>jI"; "<C-v>jA" ] ~f:(fun input ->
    let raw = run ui (keys input) in
    same_frame (render raw) (render ~decorations raw);
    let normal = run raw (keys "<Esc>") in
    assert (String.is_substring (Frame.to_string (render ~decorations normal))
              ~substring:"• outside"))
;;

let%test_unit "search uses source offsets and its overlay wins over replacement roles" =
  let ui = ui "anchor\n- aa aa\n- aa" in
  let first = line_start ui 1 in
  let last = line_start ui 2 in
  let decorations = prepare ui
      [ replace ~role:Accent first (first + 1) "•"
      ; style (first + 2) (first + 7) Literal
      ; replace ~role:Muted last (last + 1) "•" ] in
  List.iter [ "/-<CR>gg", [ 1, 0; 2, 0 ]
            ; "/aa<CR>gg", [ 1, 2; 1, 5; 2, 2 ] ]
    ~f:(fun (input, positions) ->
      let searched = run ui (keys input) in
      let plain = render searched in
      let decorated = render ~decorations searched in
      same_geometry plain decorated;
      List.iter positions ~f:(fun (line, col) ->
        let before = document_at searched plain line col in
        let after = document_at searched decorated line col in
        assert (Option.is_some before.overlay);
        assert (Option.equal Style.Overlay.equal before.overlay after.overlay);
        [%test_result: string] (Style.to_string_hum (Style.Document after))
          ~expect:(Style.to_string_hum (Style.Document before)));
      assert (Style.Syntax.equal (document_at searched decorated 1 0).syntax Keyword);
      assert (String.is_substring (Frame.to_string decorated) ~substring:"• aa"))
;;

let%test_unit "replacement roles override styles, styles override syntax, and absent roles retain it" =
  let module Highlight = Cobalt_highlight.Snapshot in
  let ui = ui "anchor\n- value\n- other" in
  let first = line_start ui 1 in
  let last = line_start ui 2 in
  let highlight_key = Highlight.Key.create ~document:(Highlight.Document_id.create ())
      ~revision:(Editor.revision (editor ui)) ~language:Ocaml ~configuration:"fixture" in
  let snapshot = Highlight.create ~key:highlight_key ~source:(source ui)
      [ { Highlight.Range.start = first; stop = String.length (source ui); category = Type } ] in
  let highlights = highlight_key, snapshot in
  let decorations = prepare ui
      [ style first (first + 7) Muted
      ; replace ~role:Accent first (first + 1) "•"
      ; style (first + 2) (first + 7) Literal
      ; replace last (last + 1) "•" ] in
  let plain = Frame.render ~highlights ui ~width:40 ~height:8 in
  let decorated = Frame.render ~highlights ~decorations ui ~width:40 ~height:8 in
  same_geometry plain decorated;
  List.iter [ 1, 0, Style.Syntax.Keyword; 1, 1, Comment; 1, 2, String; 2, 0, Type; 2, 2, Type ]
    ~f:(fun (line, col, expected) ->
      assert (Style.Syntax.equal (document_at ui decorated line col).syntax expected));
  let on_line = run ui (keys "j") in
  let ordinary = Frame.render ~highlights on_line ~width:40 ~height:8 in
  let revealed = Frame.render ~highlights ~decorations on_line ~width:40 ~height:8 in
  [%test_result: string] (row_text (document_row on_line revealed 1))
    ~expect:(row_text (document_row on_line ordinary 1));
  assert (Style.Syntax.equal (document_at on_line revealed 1 0).syntax Type)
;;

let%test_unit "empty, disabled and wrong identity keys select the exact ordinary frame" =
  let ui = ui "anchor\n- item" in
  let document = Snapshot.Document_id.create () in
  let expected = key ~document ui in
  let snapshot = Snapshot.create ~key:expected ~source:(source ui)
      [ replace ~role:Accent 7 8 "•" ] |> ok in
  let prepared = Decoration.prepare ~source:(Editor.text (editor ui)) snapshot |> ok in
  assert (String.is_substring
            (Frame.to_string (render ~decorations:(expected, prepared) ui)) ~substring:"• item");
  List.iter [ key ui; key ~document ~provider:"synthetic-v2" ui
            ; key ~document ~configuration:"fixture-v2" ui ]
    ~f:(fun wrong ->
      same_frame (render ui) (render ~decorations:(wrong, prepared) ui));
  same_frame (render ui) (render ?decorations:None ui);
  same_frame (render ui) (render ~decorations:(prepare ui []) ui)
;;

let%test_unit "equal bytes and revisions from another buffer cannot reuse prepared provenance" =
  let original = ui "anchor\n- item" in
  let decorations = prepare original [ replace ~role:Accent 7 8 "•" ] in
  let prepared = snd decorations in
  let other = ui (source original) in
  assert (Decoration.matches_source prepared (Editor.text (editor original)));
  assert (not (Decoration.matches_source prepared (Editor.text (editor other))));
  [%test_result: int] (Editor.revision (editor other))
    ~expect:(Editor.revision (editor original));
  [%test_result: string] (source other) ~expect:(source original);
  (* Even a caller accidentally reusing the old expected key cannot bypass the
     renderer's independent source-object gate. *)
  same_frame (render other) (render ~decorations other);
  let fresh = prepare other [ replace ~role:Accent 7 8 "•" ] in
  assert (String.is_substring (Frame.to_string (render ~decorations:fresh other))
            ~substring:"• item")
;;

let%test_unit "edits and undo cannot revive a stale prepared snapshot" =
  let ui = ui "anchor\n- item" in
  let decorations = prepare ui [ replace ~role:Accent 7 8 "•" ] in
  let changed = run ui (keys "iX<Esc>") in
  assert (Editor.revision (editor changed) <> Snapshot.Key.revision (fst decorations));
  same_frame (render changed) (render ~decorations changed);
  let undone = run changed (keys "u") in
  [%test_result: string] (source undone) ~expect:(source ui);
  assert (Editor.revision (editor undone) > Editor.revision (editor changed));
  same_frame (render undone) (render ~decorations undone);
  let fresh = prepare undone [ replace ~role:Accent 7 8 "•" ] in
  assert (String.is_substring (Frame.to_string (render ~decorations:fresh undone)) ~substring:"• item");
  let redone = run undone (keys "<C-r>") in
  same_frame (render redone) (render ~decorations:fresh redone)
;;

let%test_unit "unsafe replacements reject the entire result including valid preceding styles" =
  List.iter
    [ "-", 0, 1, "界"          (* Different terminal-cell width. *)
    ; "\t", 0, 1, "-"         (* Source TABs depend on the starting column. *)
    ; "\001", 0, 1, "-"       (* Never conceal escaped source controls. *)
    ; "-", 0, 1, "\027"       (* No terminal-control injection. *)
    ; "-", 0, 1, "\t"
    ; "-", 0, 1, "́"          (* Zero-width replacement. *)
    ; "-", 0, 1, ""
    ; "-", 0, 1, "é"         (* V1 does not accept multiscalar display text. *)
    ; "界", 0, 3, "ab"        (* Equal aggregate width is not enough. *)
    ; "ab", 0, 2, "cd"        (* Nor are multiscalar source ranges supported. *)
    ; "é", 0, 1, "-"         (* Splits a base from its combining scalar. *)
    ; "́-", 2, 3, "•"         (* Adjacent zero-width context is unsupported. *)
    ]
    ~f:(fun (tail, start, stop, replacement) ->
      let ui = ui ("anchor\nstyled\n" ^ tail) in
      let at = line_start ui 2 in
      let key = key ui in
      let result =
        Snapshot.create ~key ~source:(source ui)
          [ style 7 13 Accent; replace (at + start) (at + stop) replacement ]
        |> Result.bind ~f:(Decoration.prepare ~source:(Editor.text (editor ui)))
      in
      assert (Result.is_error result);
      (* A host publishes only successful prepared values; failure clears the
         whole result rather than leaking the valid style before the error. *)
      let decorations = Result.ok result |> Option.map ~f:(fun prepared -> key, prepared) in
      same_frame (render ui) (render ?decorations ui))
;;

let%test_unit "context-sensitive source and display scalars are rejected atomically" =
  let thumbs = String.length "👍" in
  let regional = String.length "🇺" in
  let cjk = String.length "界" in
  List.iter
    [ "👍界x", [ thumbs, thumbs + cjk, "🏽" ]
    ; "🇺x", [ regional, regional + 1, "🇸" ]
    ; "🇺界x", [ regional, regional + cjk, "🇸" ]
    (* Independently positive-width endpoints must not compose into a new
       modifier/flag cluster after two neighboring replacements. *)
    ; "界界x", [ 0, cjk, "👍"; cjk, 2 * cjk, "🏽" ]
    ; "xx", [ 0, 1, "🇺"; 1, 2, "🇸" ]
    (* The conservative endpoint policy must apply to the original scalar,
       not only to the requested display scalar. *)
    ; "👍x", [ 0, thumbs, "界" ]
    ; "🏽x", [ 0, String.length "🏽", "界" ]
    ; "🇺x", [ 0, regional, "-" ]
    ; "ᄀx", [ 0, String.length "ᄀ", "界" ]
    ]
    ~f:(fun (tail, replacements) ->
      let ui = ui ("anchor\nstyled\n" ^ tail) in
      let at = line_start ui 2 in
      let key = key ui in
      let operations =
        style 7 13 Accent
        :: List.map replacements ~f:(fun (start, stop, text) ->
          replace (at + start) (at + stop) text)
      in
      (* These are valid generic source-range operations. It is specifically
         the screen's stricter Unicode endpoint policy that must reject them. *)
      let snapshot = Snapshot.create ~key ~source:(source ui) operations |> ok in
      let result = Decoration.prepare ~source:(Editor.text (editor ui)) snapshot in
      assert (Result.is_error result);
      let decorations = Result.ok result |> Option.map ~f:(fun prepared -> key, prepared) in
      same_frame (render ui) (render ?decorations ui))
;;

let%test_unit "safe endpoints still reject positive-width spacing marks and unsafe source neighbors" =
  (* U+093E DEVANAGARI VOWEL SIGN AA is a positive-width SpacingMark in
     Cobalt's width table. A zero-width-only adjacency guard misses it. *)
  let spacing_mark = "ा" in
  assert (Cell_map.total_width (Cell_map.glyphs spacing_mark) > 0);
  List.iter
    [ "a" ^ spacing_mark ^ "x", 0
    ; spacing_mark ^ "ax", String.length spacing_mark
    ; "a👍x", 0
    ; "👍ax", String.length "👍"
    ; "a🏽x", 0
    ; "🏽ax", String.length "🏽"
    ; "a🇺x", 0
    ; "🇺ax", String.length "🇺"
    ]
    ~f:(fun (tail, start) ->
      let ui = ui ("anchor\nstyled\n" ^ tail) in
      let at = line_start ui 2 + start in
      let key = key ui in
      let snapshot = Snapshot.create ~key ~source:(source ui)
          [ style 7 13 Accent; replace at (at + 1) "•" ] |> ok in
      let result = Decoration.prepare ~source:(Editor.text (editor ui)) snapshot in
      assert (Result.is_error result);
      let decorations = Result.ok result |> Option.map ~f:(fun prepared -> key, prepared) in
      same_frame (render ui) (render ?decorations ui))
;;

let%test_unit "safe CJK and box-drawing replacements use ordinary full and clipped glyph geometry" =
  let saw_clipped_cjk = ref false in
  List.iter
    [ "a界z", "中", "a中z", 1, String.length "a界"
    ; "a-z", "─", "a─z", 1, 2
    ; "a─z", "│", "a│z", 1, String.length "a─"
    ]
    ~f:(fun (raw, replacement, display, start, stop) ->
      let suffix = String.make 40 'x' in
      let prefs = { Geometry.Prefs.default with left_padding = 0 } in
      let base = ui ~prefs (String.make 50 'x' ^ "\n" ^ raw ^ suffix) in
      let at = line_start base 1 in
      let decorations = prepare base
          [ replace ~role:Accent (at + start) (at + stop) replacement ] in
      List.iter [ "0"; "l"; "2l"; "$" ] ~f:(fun motion ->
        List.iter [ 1; 2; 3; 4; 5; 8; 20; 40 ] ~f:(fun width ->
          let ui = run ~width ~height:8 base (keys motion) in
          let plain = render ~width ui in
          let decorated = render ~decorations ~width ui in
          same_geometry plain decorated;
          let geometry = Ui_state.geometry ui ~width ~height:8 in
          let scroll = Ui_state.fitted_scroll ui ~width ~height:8 in
          let expected = Span.of_glyphs (Cell_map.glyphs (display ^ suffix))
              ~left:scroll.left ~cols:geometry.text.width
              ~text:(Style.document ()) ~special:(Style.document ~special:true ()) in
          let expected_row = Span.overlay (document_row ui plain 1)
              ~x:geometry.text.x ~width:geometry.text.width expected in
          [%test_result: string] (row_text (document_row ui decorated 1))
            ~expect:(row_text expected_row);
          if String.equal raw "a界z"
             && List.exists expected ~f:(fun (span : Span.t) ->
               String.equal span.text "<" || String.equal span.text ">")
          then saw_clipped_cjk := true)));
  assert !saw_clipped_cjk
;;

let%test_unit "CJK neighbors, horizontal clipping and tiny viewports keep raw geometry" =
  let line = "中-界" ^ String.make 50 'x' in
  let ui = ui (line ^ "\n" ^ line) |> fun ui -> run ~width:20 ~height:6 ui (keys "20l") in
  let at = line_start ui 1 + String.length "中" in
  let decorations = prepare ui
      [ style (line_start ui 1) (line_start ui 1 + String.length line) Muted
      ; replace at (at + 1) "•" ] in
  List.iter [ 40, 8; 20, 6; 5, 3; 1, 2; 0, 0; 0, 5; 5, 0 ] ~f:(fun (width, height) ->
    let plain = render ~width ~height ui in
    let decorated = render ~decorations ~width ~height ui in
    same_geometry plain decorated;
    let geometry = Ui_state.geometry ui ~width ~height in
    let scroll = Ui_state.fitted_scroll ui ~width ~height in
    List.iteri (List.zip_exn plain.rows decorated.rows) ~f:(fun y (before, after) ->
      let expected = row_text before in
      let expected =
        if y >= geometry.text.y && y < geometry.text.y + geometry.text.height
           && y = geometry.text.y + 1 - scroll.top
        then String.substr_replace_all expected ~pattern:"-" ~with_:"•"
        else expected
      in
      [%test_result: string] (row_text after) ~expect:expected));
  let left = run ui (keys "0") in
  assert (String.is_substring (row_text (document_row left (render ~decorations left) 1))
            ~substring:"中•界");
  let scroll = Ui_state.fitted_scroll ui ~width:20 ~height:6 in
  assert (scroll.left > 0)
;;

let observable ui =
  let editor = editor ui in
  [%sexp
    (source ui : string),
    (Editor.revision editor : int),
    (Editor.is_dirty editor : bool),
    (Editor.cursor editor : int),
    (Editor.mode editor : Mode.t),
    (Editor.selection editor : Editor.Selection.t option),
    (Editor.unnamed_register editor : Register.t option),
    (Editor.block_insert_points editor : (int * int) list),
    (snd (Editor.request_save editor) : Effect.t list)]
;;

let%test_unit "prepare, resize and toggle preserve state, registers, save effects and undo" =
  let initial = ui "anchor\n- item\n- tail" in
  let dirty = run initial (keys "iX<Esc>jylk") in
  assert (Editor.is_dirty (editor dirty));
  assert (Option.is_some (Editor.unnamed_register (editor dirty)));
  List.iter [ dirty; run dirty (keys "v"); run dirty (keys "<C-v>jI") ] ~f:(fun ui ->
    let before = observable ui in
    let at = line_start ui 2 in
    let decorations = prepare ui [ replace ~role:Accent at (at + 1) "•" ] in
    List.iter [ 40, 8; 12, 4; 0, 0; 80, 24 ] ~f:(fun (width, height) ->
      ignore (render ~decorations ~width ~height ui : Frame.t);
      ignore (render ~width ~height ui : Frame.t));
    assert (Sexp.equal before (observable ui)));
  let undone = run dirty (keys "u") in
  [%test_result: string] (source undone) ~expect:(source initial);
  let redone = run undone (keys "<C-r>") in
  [%test_result: string] (source redone) ~expect:(source dirty);
  assert (Option.equal Register.equal
            (Editor.unnamed_register (editor redone)) (Editor.unnamed_register (editor dirty)))
;;

let%test_unit "saving after decorated renders writes source bytes, not display bytes" =
  let dir = scratch_dir "cobalt-decorations" in
  let path = dir ^/ "source.txt" in
  Exn.protect
    ~finally:(fun () ->
      if Sys_unix.file_exists_exn path then Core_unix.unlink path;
      Core_unix.rmdir dir)
    ~f:(fun () ->
      let ui = ui ~path "anchor\n- persisted" |> fun ui -> run ui (keys "iX<Esc>") in
      let at = line_start ui 1 in
      let decorations = prepare ui [ replace ~role:Accent at (at + 1) "•" ] in
      assert (String.is_substring (Frame.to_string (render ~decorations ui)) ~substring:"• persisted");
      let saved = run ui (keys " w") in
      [%test_result: string] (In_channel.read_all path) ~expect:(source ui);
      assert (not (Editor.is_dirty (editor saved)));
      [%test_result: int] (Editor.revision (editor saved))
        ~expect:(Editor.revision (editor ui));
      [%test_result: string] (source (run saved (keys "u"))) ~expect:"anchor\n- persisted")
;;

let%test_unit "warm plain and decorated long-line rendering retain sparse window work" =
  let line = String.make 100_000 'x' in
  let ui = ui (line ^ "\n" ^ line) |> fun ui -> run ~width:160 ~height:8 ui (keys "$") in
  let at = line_start ui 1 + 99_950 in
  let decorations = prepare ui [ replace ~role:Accent at (at + 1) "•" ] in
  let layout = Text_buffer.line_layout (Editor.text (editor ui)) ~width:Cell_map.width 1 in
  ignore (render ~decorations ~width:160 ~height:8 ui : Frame.t);
  List.iter [ None; Some decorations ] ~f:(fun decorations ->
    let before = Cell_layout.Index.steps layout in
    for _ = 1 to 10 do
      let frame = render ?decorations ~width:160 ~height:8 ui in
      List.iter frame.rows ~f:(fun row -> assert (Span.total_width row = 160))
    done;
    assert (Cell_layout.Index.steps layout - before < 10 * 2500));
  assert (String.is_substring
            (row_text (document_row ui (render ~decorations ~width:160 ~height:8 ui) 1))
            ~substring:"•")
;;
