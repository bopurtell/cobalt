open! Core

(* Tree-sitter can tokenize a block boundary as an identifier during recovery
   when the current parse state cannot accept that keyword. Restore the color
   of these unambiguous boundaries, not contextual keywords such as "ready". *)
let block_keywords =
  String.split ~on:' '
    "package endpackage interface endinterface module endmodule method endmethod \
     rule endrule rules endrules function endfunction typeclass endtypeclass \
     instance endinstance begin end action endaction actionvalue endactionvalue \
     case endcase seq endseq par endpar"
;;

let block_keyword_set = String.Hash_set.of_list block_keywords
let is_block_keyword text = Hash_set.mem block_keyword_set text

(* Structural query against the pinned Bluespec SystemVerilog grammar. *)
let source =
  {|
  (comment) @comment
  [(stringLiteral) "\"BDPI\"" "\"BVI\""] @string
  [(intLiteral) (realLiteral) (typeNat)] @number
  (boolLiteral) @constant
  (exprPrimary dont_care: "?" @constant)

  (identifier) @variable
  (packageIde (identifier) @module)
  (typeIde (identifier) @type)
  ["Action" "ActionValue" "bit" "string" "void"] @type
  (typedefEnumElement (identifier) @constructor)
  (moduleProto (identifier) @module)
  (moduleApp (identifier) @function)
  (rule (identifier) @function)
  (methodDef (identifier) @function)
  (methodProto (identifier) @function)
  (functionType (identifier) @function)
  (functionCall (exprPrimary (identifier) @function))
  (methodCall "." (identifier) @property)
  (attrSpec (identifier) @property)
  [(displayTaskName) (systemFunctionCall)] @function
  ["$fopen" "$format" "$fclose"] @function

  ["export" "import" "let" "match" "matches" "provisos" "return" "type"
   "typedef" "deriving" "numeric" "tagged" "enum" "struct" "union"
   "determines" "dependencies" "if" "else" "default" "for" "while"
   "repeat" "break" "continue" "noAction" "valueOf" "valueof"
   "parameter" "port" "enable" "ready" "schedule" "path" "inout" "ifc_inout"
   "default_clock" "default_reset" "input_clock" "input_reset" "output_clock"
   "output_reset" "clocked_by" "reset_by" "ancestor" "same_family"] @keyword

  [(binop) (unop) "=" "<-" "<=" "&&&"] @operator
  ["(" ")" "[" "]" "{" "}" ";" "," "." ":" "::" "#" "(*" "*)"] @punctuation
  |}
  ^ sprintf "[%s] @keyword" (String.concat ~sep:" " (List.map block_keywords ~f:(sprintf "%S")))
