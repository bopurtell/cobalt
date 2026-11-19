open! Core
open Cobalt_core
open Cobalt_screen
open Helpers

module Snapshot = Cobalt_decoration.Snapshot
module Fixture = Test_decorations

let roles : Snapshot.Role.t list =
  [ Heading_1; Heading_2; Heading_3; Heading_4; Heading_5; Heading_6
  ; Emphasis; Strong; Code_inline; Code_block; Link; Link_destination
  ; Quote; List_marker; Checkbox ]
;;

let document = function Style.Document document -> document | _ -> assert false
let cell spans col = document (Test_span.style_at spans col)

let spans ?highlight ?(left = 0) ?(cols = 12) role source =
  Span.of_glyphs (Cell_map.glyphs source) ~left ~cols
    ~syntax:(fun _ -> Number) ~decoration:(fun _ -> Some role) ?highlight
    ~text:(Style.document ()) ~special:(Style.document ~special:true ())
;;

let%test_unit "decoration is independent of syntax, overlays and undecorated sexps" =
  let base = Style.document ~syntax:Type ~current_line:true ~overlay:Search_current () in
  [%test_result: string] (Sexp.to_string (Style.sexp_of_t (Style.document ())))
    ~expect:"(Document((syntax Plain)(current_line false)(special false)(overlay())))";
  List.iter roles ~f:(fun role ->
    let decorated = document (Style.with_decoration base role) in
    assert (Style.Syntax.equal decorated.syntax Type);
    assert decorated.current_line;
    assert (Option.equal Style.Overlay.equal decorated.overlay (Some Search_current));
    assert (Option.equal Snapshot.Role.equal decorated.decoration (Some role));
    assert (Style.equal (Style.Document { decorated with decoration = None }) base);
    assert (String.equal (Style.to_string_hum (Style.Document decorated)) "Search_match_current"))
;;

let%test_unit "rich source cells and attached marks retain text and geometry without decorating padding" =
  List.iter roles ~f:(fun role ->
    let source = "\t界é\001" in
    let actual = spans ~cols:16 role source in
    let plain = Span.of_glyphs (Cell_map.glyphs source) ~left:0 ~cols:16
        ~text:(Style.document ()) ~special:(Style.document ~special:true ()) in
    [%test_result: string] (Test_span.text actual) ~expect:(Test_span.text plain);
    [%test_result: int] (Span.total_width actual) ~expect:16;
    List.iter [ 0; 7; 8; 9; 10 ] ~f:(fun col ->
      let doc = cell actual col in
      assert (Style.Syntax.equal doc.syntax Number);
      assert (Option.equal Snapshot.Role.equal doc.decoration (Some role)));
    List.iter [ 11; 12 ] ~f:(fun col ->
      let doc = cell actual col in
      assert doc.special;
      assert (Option.is_none doc.decoration));
    List.iter [ 13; 14; 15 ] ~f:(fun col ->
      assert (Style.equal (Test_span.style_at actual col) (Style.document ())));
    assert (List.exists actual ~f:(fun span ->
      String.is_substring span.text ~substring:"é"
      && Option.equal Snapshot.Role.equal (document span.style).decoration (Some role))))
;;

let%test_unit "wide and unsafe clip markers ignore decoration and combining marks cannot escape clipping" =
  List.iter roles ~f:(fun role ->
    List.iter [ "界́", 0, ">"; "界́", 1, "<"; "\001́", 1, "A" ]
      ~f:(fun (source, left, expected) ->
        let actual = spans role source ~left ~cols:1 ~highlight:(fun _ -> Some `Selection) in
        [%test_result: string] (Test_span.text actual) ~expect:expected;
        assert (Style.equal (Test_span.style_at actual 0) (Style.document ~special:true ())));
    let clipped_tab = spans role "\t" ~left:3 ~cols:2 ~highlight:(fun _ -> Some `Match) in
    let doc = cell clipped_tab 0 in
    assert (Option.equal Snapshot.Role.equal doc.decoration (Some role));
    assert (Option.equal Style.Overlay.equal doc.overlay (Some Search_match));
    [%test_result: string] (Test_span.text clipped_tab) ~expect:"  ";
    [%test_result: string] (Test_span.text (spans role "́a" ~cols:1)) ~expect:"a")
;;

let%test_unit "decorated combining marks yield to every interaction overlay" =
  List.iter roles ~f:(fun role ->
    List.iter
      [ `Match, Style.Overlay.Search_match; `Current, Search_current
      ; `Selection, Selection; `Insert_cursor, Insert_cursor; `Insert_point, Insert_point ]
      ~f:(fun (highlight, overlay) ->
        let actual = spans role "é" ~cols:1 ~highlight:(fun _ -> Some highlight) in
        [%test_result: string] (Test_span.text actual) ~expect:"é";
        List.iter actual ~f:(fun span ->
          let doc = document span.style in
          assert (Option.equal Snapshot.Role.equal doc.decoration (Some role));
          assert (Option.equal Style.Overlay.equal doc.overlay (Some overlay)))))
;;

let%test_unit "all rich roles preserve frame text, cursor, source, registers and save effects" =
  List.iter roles ~f:(fun role ->
    let ui = ui "anchor\nstyled\t界é\001\nlast" in
    let before = Fixture.observable ui in
    let decorations = Fixture.prepare ui
        [ Fixture.style (Fixture.line_start ui 1) (Fixture.line_start ui 2) role ] in
    List.iter [ 40, 8; 12, 5; 1, 2; 0, 0 ] ~f:(fun (width, height) ->
      let plain = Fixture.render ~width ~height ui in
      let decorated = Fixture.render ~decorations ~width ~height ui in
      Fixture.same_geometry plain decorated;
      [%test_result: string] (Frame.to_string decorated) ~expect:(Frame.to_string plain));
    assert (Sexp.equal before (Fixture.observable ui));
    let rendered = Fixture.render ~decorations ui in
    assert (Option.equal Snapshot.Role.equal
      (Fixture.document_at ui rendered 1 0).decoration (Some role));
    assert (Option.is_none (Fixture.document_at ui rendered 1 14).decoration);
    assert (Option.is_none (Fixture.document_at ui rendered 2 0).decoration))
;;

let%test_unit "rich roles reveal on active line and all Visual and block insertion modes" =
  List.iter roles ~f:(fun role ->
    let ui = ui "anchor\nstyled\noutside" in
    let decorations = Fixture.prepare ui
        [ Fixture.style 0 (String.length (Fixture.source ui)) role ] in
    List.iter [ ""; "j"; "jj" ] ~f:(fun motion ->
      let active = run ui (keys motion) in
      let plain = Fixture.render active in
      let decorated = Fixture.render ~decorations active in
      let line = Editor.cursor_line (Fixture.editor active) in
      [%test_result: string]
        (Sexp.to_string ([%sexp_of: Span.t list] (Fixture.document_row active decorated line)))
        ~expect:(Sexp.to_string ([%sexp_of: Span.t list] (Fixture.document_row active plain line))));
    List.iter [ "v"; "V"; "<C-v>"; "<C-v>jI"; "<C-v>jA" ] ~f:(fun motion ->
      let active = run ui (keys motion) in
      Fixture.same_frame (Fixture.render active) (Fixture.render ~decorations active)))
;;

let%test_unit "syntax and rich roles coexist under source-based search overlays" =
  let module Highlight = Cobalt_highlight.Snapshot in
  List.iter roles ~f:(fun role ->
    let ui = ui "anchor\nvalue value\nlast" in
    let start = Fixture.line_start ui 1 in
    let key = Highlight.Key.create ~document:(Highlight.Document_id.create ())
        ~revision:(Editor.revision (Fixture.editor ui)) ~language:Ocaml ~configuration:"fixture" in
    let snapshot = Highlight.create ~key ~source:(Fixture.source ui)
        [ { Highlight.Range.start; stop = start + 11; category = Number } ] in
    let highlights = key, snapshot in
    let decorations = Fixture.prepare ui [ Fixture.style start (start + 11) role ] in
    let searched = run ui (keys "/value<CR>gg") in
    let plain = Frame.render ~highlights searched ~width:40 ~height:8 in
    let decorated = Frame.render ~highlights ~decorations searched ~width:40 ~height:8 in
    Fixture.same_geometry plain decorated;
    [%test_result: string] (Frame.to_string decorated) ~expect:(Frame.to_string plain);
    List.iter [ 0; 6 ] ~f:(fun col ->
      let before = Fixture.document_at searched plain 1 col in
      let after = Fixture.document_at searched decorated 1 col in
      assert (Style.Syntax.equal after.syntax Number);
      assert (Option.equal Snapshot.Role.equal after.decoration (Some role));
      assert (Option.is_some after.overlay);
      assert (Option.equal Style.Overlay.equal before.overlay after.overlay)))
;;
