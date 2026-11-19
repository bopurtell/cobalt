external language_address : unit -> nativeint = "cobalt_markdown_block_language"

let language () = Tree_sitter.Language.of_address (language_address ())
