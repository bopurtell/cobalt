let source = {|
(comment) @comment
[(string_literal) (raw_string_literal) (char_literal) (system_lib_string)] @string
(escape_sequence) @escape
(number_literal) @number
[(true) (false) (null)] @constant
[(primitive_type) (type_identifier) (sized_type_specifier) (auto)] @type
(namespace_identifier) @module
(field_identifier) @property
(identifier) @variable

(function_declarator declarator: [(identifier) (field_identifier)] @function)
(function_declarator declarator: (qualified_identifier name: (identifier) @function))
(call_expression function: (identifier) @function)
(call_expression function: (qualified_identifier name: (identifier) @function))
(call_expression function: (field_expression field: (field_identifier) @function))
(template_function name: (identifier) @function)
(template_method name: (field_identifier) @function)

["#include" "#define" "#if" "#ifdef" "#ifndef" "#elif" "#else" "#endif"
 "extern" "const" "constexpr" "consteval" "constinit" "volatile" "static"
 "inline" "typedef" "class" "struct" "union" "enum" "template" "typename"
 "namespace" "using" "public" "private" "protected" "virtual" "override" "final"
 "friend" "mutable" "explicit" "operator" "noexcept" "new" "delete" "sizeof"
 "if" "else" "for" "while" "do" "switch" "case" "default" "break" "continue"
 "return" "goto" "try" "catch" "throw" "concept" "requires" "decltype"
 "co_await" "co_return" "co_yield"] @keyword
["=" "+" "-" "*" "/" "%" "&" "|" "^" "~" "!" "&&" "||" "==" "!=" "<=" ">="
 "++" "--" "+=" "-=" "->" "."] @operator
["(" ")" "[" "]" "{" "}" ";" "," "::"] @punctuation
|}
