external language_address : unit -> nativeint = "cobalt_tree_sitter_classic_language"

let language () = Tree_sitter.Language.of_address (language_address ())
