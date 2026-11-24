open! Core
open Cobalt_highlight
open Cobalt_highlight_tree_sitter

let rust =
  {|#![allow(dead_code)]
/// A borrowed greeting: é.
#[derive(Debug)]
pub struct Greeting<'a> { text: &'a str }

/* outer /* nested */ still outer */
fn show<'a>(greeting: &'a Greeting<'a>) {
    let raw = r##"quote " and /* not a comment */"##;
    let bytes = br#"bytes"#;
    let count = 0xff_u32;
    let line = "hello\n";
    let ch = 'é';
    println!("{raw}: {}", greeting.text);
}
|}
;;

(* Compile-ready package with an interface, a guarded rule and an action method. *)
let bsv =
  {|package DemoCounter;
import Vector::*;

// é: counter interface
interface Counter;
   method Action clear();
   method Bit#(8) readCount();
endinterface

/* implementation */
(* synthesize *)
module mkDemoCounter(Counter);
   Reg#(Bit#(8)) count <- mkReg(8'h00);
   rule tick (count != 8'hff);
      count <= count + 8'b1;
      $display("count = %0h", count);
   endrule

   method Action clear();
      count <= '0;
   endmethod

   method Bit#(8) readCount = count;
endmodule
endpackage
|}
;;

let expect_status status expected =
  if not (Provider.Status.equal status expected)
  then raise_s [%sexp "wrong provider status", (status : Provider.Status.t),
    (expected : Provider.Status.t)]
;;

let expect_token snapshot ~source ?(after = "") (text, category) =
  let start =
    String.substr_index_exn source ~pattern:(after ^ text) + String.length after
  in
  for offset = start to start + String.length text - 1 do
    let actual = Snapshot.category_at snapshot offset in
    if not (Category.equal actual category)
    then raise_s [%sexp "wrong syntax category", (text : string), (offset : int),
      (category : Category.t), (actual : Category.t)]
  done
;;

let highlight provider source =
  let key = Provider.key provider ~document:(Snapshot.Document_id.create ()) ~revision:0 in
  let result = Provider.highlight provider ~key ~source in
  assert (Snapshot.matches result.snapshot key);
  result
;;

let%test_unit "Rust highlights attributes, types, lifetimes, nested comments, raw strings and macros" =
  let provider = Provider.create ~language:Rust in
  let result = highlight provider rust in
  expect_status result.status (Highlighted { syntax_errors = false });
  List.iter
    [ "allow", Category.Property; "derive", Property; "/// A borrowed greeting: é.", Comment
    ; "pub", Keyword; "struct", Keyword; "Greeting", Type; "'a", Type
    ; "text", Property; "/* outer /* nested */ still outer */", Comment
    ; "show", Function; "r##\"quote \" and /* not a comment */\"##", String
    ; "br#\"bytes\"#", String; "0xff_u32", Number; "\\n", Escape; "'é'", String
    ; "println!", Function
    ] ~f:(expect_token result.snapshot ~source:rust);
  Provider.close provider
;;

let%test_unit "BSV highlights packages, interfaces, modules, rules, methods and literals" =
  let provider = Provider.create ~language:Bsv in
  let result = highlight provider bsv in
  expect_status result.status (Highlighted { syntax_errors = false });
  List.iter
    [ "package", Category.Keyword; "DemoCounter", Module; "import", Keyword
    ; "Vector", Module; "// é: counter interface", Comment
    ; "method", Keyword; "Action", Type; "clear", Function; "Bit", Type
    ; "readCount", Function; "/* implementation */", Comment; "synthesize", Property
    ; "module", Keyword; "mkDemoCounter", Module
    ; "mkReg", Function; "8'h00", Number; "rule", Keyword; "tick", Function
    ; "8'hff", Number; "8'b1", Number; "$display", Function
    ; "\"count = %0h\"", String; "'0", Number; "endmodule", Keyword
    ] ~f:(expect_token result.snapshot ~source:bsv);
  expect_token result.snapshot ~source:bsv ~after:"\n" ("interface", Keyword);
  expect_token result.snapshot ~source:bsv ~after:"interface " ("Counter", Type);
  Provider.close provider
;;

let%test_unit "Classic uses BH tokens and signatures instead of BSV or GHC syntax" =
  let source = {|package Pulse where
interface Pulse =
    pulse :: Action
mkPulse = module
    r <- mkReg 8'hff
    rules
      "tick": when r /= '0 ==> action { r := 0 }
--@ tick
{- outer {- nested -} still a comment -}
|} in
  let provider = Provider.create ~language:Classic in
  let result = highlight provider source in
  expect_status result.status (Highlighted { syntax_errors = false });
  List.iter
    [ "package", Category.Keyword; "Pulse", Module; "interface", Keyword
    ; "pulse", Function; "Action", Type; "module", Keyword; "8'hff", Number
    ; "rules", Keyword; "\"tick\"", String; "when", Keyword; "'0", Number
    ; "==>", Operator; "action", Keyword; "--@ tick", Comment
    ; "{- outer {- nested -} still a comment -}", Comment
    ] ~f:(expect_token result.snapshot ~source);
  Provider.close provider
;;

let%test_unit "Rust and BSV retain unrelated captures while incomplete; incremental results match fresh" =
  List.iter
    [ Language.Rust, rust, "let count = 0xff_u32;", "let count = ;",
      [ "println!", Category.Function; "Greeting", Type ]
    ; Bsv, bsv, "rule tick (count != 8'hff);", "rule tick (",
      [ "endmodule", Keyword; "DemoCounter", Module; "readCount", Function ]
    ; Bsv, bsv, "method Action clear();\n      count <= '0;\n   endmethod",
      "method Action clear(",
      [ "endmodule", Keyword; "$display", Function; "\"count = %0h\"", String ]
    ] ~f:(fun (language, initial, complete, incomplete, tokens) ->
      let provider = Provider.create ~language in
      let fresh = Provider.create ~language in
      let document = Snapshot.Document_id.create () in
      let broken = String.substr_replace_first initial ~pattern:complete ~with_:incomplete in
      List.iteri [ initial; broken; initial; "/* 界 */\n" ^ initial; initial ]
        ~f:(fun revision source ->
          let key = Provider.key provider ~document ~revision in
          let actual = Provider.highlight_incremental provider ~key ~source in
          let reference = Provider.highlight fresh ~key ~source in
          expect_status actual.status (Highlighted { syntax_errors = revision = 1 });
          expect_status actual.status reference.status;
          assert (Snapshot.matches actual.snapshot key);
          [%test_result: Snapshot.Range.t list] (Snapshot.ranges actual.snapshot)
            ~expect:(Snapshot.ranges reference.snapshot);
          List.iter tokens ~f:(expect_token actual.snapshot ~source));
      assert (Provider.incremental_count provider = 4);
      Provider.close provider;
      Provider.close fresh)
;;
