type t

external create : unit -> t = "cobalt_markdown_native_create"
external close : t -> unit = "cobalt_markdown_native_close"
external counts : t -> int * int = "cobalt_markdown_native_counts"
external parse : t -> string -> (int * int * int) array
  = "cobalt_markdown_native_parse"
