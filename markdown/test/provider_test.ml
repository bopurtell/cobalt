open! Core

module Provider = Cobalt_markdown.Provider
module Snapshot = Cobalt_decoration.Snapshot

let with_provider f =
  let provider = Provider.create () in
  Exn.protect ~f:(fun () -> f provider) ~finally:(fun () -> Provider.close provider)
;;

let key provider =
  Provider.key provider ~document:(Snapshot.Document_id.create ()) ~revision:0
;;

let decorate provider source =
  Provider.decorate provider ~key:(key provider) ~source
  |> Or_error.ok_exn
;;

let offset source text = Option.value_exn (String.substr_index source ~pattern:text)

let check_role snapshot source text role =
  assert (Option.equal Snapshot.Role.equal (Snapshot.style_at snapshot (offset source text)) (Some role))
;;

let only_styles snapshot =
  List.iter (Snapshot.operations snapshot) ~f:(function
    | Snapshot.Operation.Style _ -> ()
    | Replace _ -> failwith "Markdown must preserve every source byte")
;;

let%test_unit "path eligibility is ASCII-case-insensitive and suffix-only" =
  List.iter [ "README.md"; "/a/B.MARKDOWN"; "x.Md"; ".md" ] ~f:(fun path ->
    assert (Provider.eligible_path (Some path)));
  List.iter [ "a.md.txt"; "markdown"; "a.mdx"; "a.md/other"; "" ] ~f:(fun path ->
    assert (not (Provider.eligible_path (Some path))));
  assert (not (Provider.eligible_path None))
;;

let%test_unit "all heading levels, inline styles, lists and fences" =
  with_provider (fun provider ->
    assert (Provider.parse_count provider = 0);
    let source = Fixtures.features in
    let snapshot = decorate provider source in
    only_styles snapshot;
    List.iter
      [ "# First", Snapshot.Role.Heading_1
      ; "## Second", Heading_2
      ; "### Third", Heading_3
      ; "#### Fourth", Heading_4
      ; "##### Fifth", Heading_5
      ; "###### Sixth", Heading_6
      ; "Setext one", Heading_1
      ; "Setext two", Heading_2
      ; "*emphasis*", Emphasis
      ; "**strong**", Strong
      ; "`code|span`", Code_inline
      ; "label", Link
      ; "https://example.test/a?b=c", Link_destination
      ; "> quoted", Quote
      ; "- [x]", List_marker
      ; "[x]", Checkbox
      ; "[ ]", Checkbox
      ; "1. ordered", List_marker
      ; "2) parenthesized", List_marker
      ; "```ocaml", Code_block
      ; "*not emphasis*", Code_block
      ; "```\n", Code_block
      ]
      ~f:(fun (text, role) -> check_role snapshot source text role);
    assert (Provider.parse_count provider = 1);
    assert (Provider.inline_parse_count provider > 0))
;;

let%test_unit "Unicode ranges are document UTF-8 byte offsets" =
  with_provider (fun provider ->
    let source = Fixtures.unicode in
    let snapshot = decorate provider source in
    only_styles snapshot;
    List.iter
      [ "**é😀**", Snapshot.Role.Strong
      ; "*λ*", Emphasis
      ; "标签", Link
      ; "https://例子.test/路径", Link_destination
      ; "`é|界`", Code_inline
      ]
      ~f:(fun (text, role) -> check_role snapshot source text role);
    List.iter (Snapshot.operations snapshot) ~f:(fun operation ->
      let range = Snapshot.Operation.range operation in
      assert (range.start >= 0 && range.stop <= String.length source);
      assert (range.start < range.stop);
      let boundary index =
        index = String.length source || Char.to_int source.[index] land 0xc0 <> 0x80
      in
      assert (boundary range.start && boundary range.stop)))
;;

let%test_unit "multiline included ranges exclude quote and list continuations" =
  with_provider (fun provider ->
    let source = "> *one\n> two*\n\n- *three\n  four*\n" in
    let snapshot = decorate provider source in
    check_role snapshot source "one" Emphasis;
    check_role snapshot source "two" Emphasis;
    check_role snapshot source "> two" Quote;
    check_role snapshot source "three" Emphasis;
    check_role snapshot source "four" Emphasis;
    assert (Option.is_none (Snapshot.style_at snapshot (offset source "  four")));
    assert (Provider.inline_parse_count provider = 2))
;;

let%test_unit "fences and indented code never enter the inline grammar" =
  with_provider (fun provider ->
    let source = "```\n**raw**\n```\n\n    *also raw*\n" in
    let snapshot = decorate provider source in
    check_role snapshot source "**raw**" Code_block;
    check_role snapshot source "*also raw*" Code_block;
    assert (Provider.inline_parse_count provider = 0))
;;

let%test_unit "pinned block grammar has GFM pipe tables including escaped pipes" =
  let language = Cobalt_markdown_block_grammar.language () in
  assert (Tree_sitter.Language.version language = 15);
  let parser = Tree_sitter.Parser.create language in
  let tree = Tree_sitter.Parser.parse_string parser Fixtures.tables in
  assert (String.is_substring (Tree_sitter.Tree.root_sexp tree) ~substring:"pipe_table");
  with_provider (fun provider ->
    let snapshot = decorate provider Fixtures.tables in
    only_styles snapshot;
    check_role snapshot Fixtures.tables "*head*" Emphasis;
    check_role snapshot Fixtures.tables "**bold**" Strong;
    assert (Provider.inline_parse_count provider >= 6))
;;

let%test_unit "incomplete syntax, HTML and code-contained pipes remain safe source" =
  with_provider (fun provider ->
    List.iter Fixtures.malformed ~f:(fun source ->
      let snapshot = decorate provider source in
      only_styles snapshot;
      assert (Snapshot.source_length snapshot = String.length source)));
  with_provider (fun provider ->
    let snapshot = decorate provider "[unknown] [label][unknown]\n" in
    assert (not (List.exists (Snapshot.operations snapshot) ~f:(function
      | Style { role = Link; _ } -> true
      | _ -> false))))
;;

let%test_unit "key mismatch and invalid UTF-8 fail before any native parse" =
  with_provider (fun provider ->
    let document = Snapshot.Document_id.create () in
    let wrong_provider =
      Snapshot.Key.create ~document ~revision:0 ~provider:"other"
        ~configuration:Provider.configuration
    in
    let wrong_configuration =
      Snapshot.Key.create ~document ~revision:0 ~provider:"cobalt-markdown-v1"
        ~configuration:"wrong"
    in
    List.iter [ wrong_provider; wrong_configuration ] ~f:(fun key ->
      assert (Result.is_error (Provider.decorate provider ~key ~source:"# title\n")));
    List.iter [ "\xff"; "\xc0\xaf"; "\xed\xa0\x80"; "\xf4\x90\x80\x80"; "\xe2\x82" ]
      ~f:(fun source ->
        assert (Result.is_error (Provider.decorate provider ~key:(key provider) ~source)));
    assert (Provider.parse_count provider = 0);
    ignore (decorate provider "# valid\n" : Snapshot.t);
    assert (Provider.parse_count provider = 1))
;;

let%test_unit "source and line limits reject atomically before native entry" =
  with_provider (fun provider ->
    List.iter [ String.make (256 * 1024 + 1) 'x'; String.make 4096 '\n' ] ~f:(fun source ->
      assert (Result.is_error (Provider.decorate provider ~key:(key provider) ~source)));
    assert (Provider.parse_count provider = 0);
    let at_byte_limit = "```\n" ^ String.make (256 * 1024 - 8) 'x' ^ "\n```" in
    ignore (decorate provider at_byte_limit : Snapshot.t);
    assert (Provider.parse_count provider = 1))
;;

let%test_unit "operation and nesting limits fail without stale snapshots; recovery works" =
  with_provider (fun provider ->
    ignore (decorate provider "# previous\n" : Snapshot.t);
    let oversized = String.concat (List.init 4097 ~f:(fun _ -> "*a* ")) in
    assert (Result.is_error (Provider.decorate provider ~key:(key provider) ~source:oversized));
    assert (Provider.parse_count provider = 2);
    let delimiters = String.make 2200 '*' in
    let nested = delimiters ^ "x" ^ delimiters ^ "\n" in
    assert (Result.is_error (Provider.decorate provider ~key:(key provider) ~source:nested));
    let recovered = decorate provider "**fresh**\n" in
    check_role recovered "**fresh**\n" "fresh" Strong;
    only_styles recovered)
;;

let%test_unit "many table cells cap actual inline parser calls per document" =
  with_provider (fun provider ->
    let source =
      "| a | b |\n| --- | --- |\n"
      ^ String.concat (List.init 2048 ~f:(fun _ -> "| a | b |\n"))
    in
    assert (Result.is_error (Provider.decorate provider ~key:(key provider) ~source));
    assert (Provider.parse_count provider = 1);
    assert (Provider.inline_parse_count provider <= 4096);
    ignore (decorate provider "*recovered*\n" : Snapshot.t))
;;

let%test_unit "deep block quote recovery is safe even when grammar caps nesting" =
  with_provider (fun provider ->
    let source = String.concat (List.init 1100 ~f:(fun _ -> "> ")) ^ "text\n" in
    (match Provider.decorate provider ~key:(key provider) ~source with
     | Ok snapshot -> only_styles snapshot
     | Error _ -> ());
    assert (Provider.parse_count provider = 1);
    ignore (decorate provider "plain\n" : Snapshot.t))
;;

let%test_unit "close is idempotent and preserves actual parse counters" =
  let provider = Provider.create () in
  let key = key provider in
  ignore (Provider.decorate provider ~key ~source:"*text*\n" |> Or_error.ok_exn : Snapshot.t);
  let count = Provider.parse_count provider in
  Provider.close provider;
  Provider.close provider;
  assert (Result.is_error (Provider.decorate provider ~key ~source:"# closed\n"));
  assert (Provider.parse_count provider = count);
  let unused = Provider.create () in
  Provider.close unused;
  assert (Provider.parse_count unused = 0)
;;
