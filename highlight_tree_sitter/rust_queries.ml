(* Structural query against the pinned Rust grammar; no text predicates. *)
let source =
  {|
  [(line_comment) (block_comment)] @comment
  [(string_literal) (raw_string_literal) (char_literal)] @string
  (escape_sequence) @escape
  [(integer_literal) (float_literal)] @number
  (boolean_literal) @constant

  [(type_identifier) (primitive_type) (lifetime)] @type
  (label) @property
  (field_identifier) @property
  [(self) (metavariable)] @variable
  (mod_item name: (identifier) @module)
  (const_item name: (identifier) @constant)
  (static_item name: (identifier) @constant)
  (enum_variant name: (identifier) @constructor)
  (let_declaration pattern: (identifier) @variable)
  (parameter pattern: (identifier) @variable)

  (function_item name: (identifier) @function)
  (function_signature_item name: (identifier) @function)
  (call_expression function: (identifier) @function)
  (call_expression function: (field_expression field: (field_identifier) @function))
  (call_expression function: (scoped_identifier name: (identifier) @function))
  (generic_function function: (identifier) @function)
  (generic_function function: (scoped_identifier name: (identifier) @function))
  (generic_function function: (field_expression field: (field_identifier) @function))
  (macro_definition name: (identifier) @function)
  (macro_invocation macro: (identifier) @function "!" @function)
  (macro_invocation macro: (scoped_identifier name: (identifier) @function) "!" @function)
  (attribute (identifier) @property)
  (attribute (scoped_identifier name: (identifier) @property))

  [(crate) (super) (mutable_specifier)] @keyword
  ["as" "async" "await" "break" "const" "continue" "default" "dyn" "else"
   "enum" "extern" "fn" "for" "gen" "if" "impl" "in" "let" "loop"
   "macro_rules!" "match" "mod" "move" "pub" "raw" "ref" "return"
   "static" "struct" "trait" "try" "type" "union" "unsafe" "use"
   "where" "while" "yield"] @keyword
  ["=" "->" "=>" "?" ".." "..="] @operator
  (binary_expression operator: _ @operator)
  (compound_assignment_expr operator: _ @operator)
  (unary_expression ["!" "-" "*"] @operator)
  (reference_expression "&" @operator)
  ["(" ")" "[" "]" "{" "}" ";" "," "." ":" "::" "#"] @punctuation
  (type_arguments ["<" ">"] @punctuation)
  (type_parameters ["<" ">"] @punctuation)
  (inner_attribute_item "!" @punctuation)
  |}
