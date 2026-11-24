let source = {|
[(keyword) (package_keyword) (pragma_delimiter)] @keyword
(identifier) @variable
(capitalized) @type
(package_name) @module
((identifier) @function . (signature_op))
(system_task) @function
[(signature_op) (operator)] @operator
(punctuation) @punctuation
(number) @number
[(string) (character)] @string
[(line_comment) (block_comment)] @comment
|}
