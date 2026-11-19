external language_address : unit -> nativeint = "cobalt_markdown_inline_language"

let language () = Tree_sitter.Language.of_address (language_address ())
