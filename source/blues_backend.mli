(** Opt-in Blues ([blues-lsp]) support for configured Bluespec SystemVerilog projects. *)
val source : string

val prog : string
val args : string list
val language_id : string -> string
val root_markers : string list

(** Honors [BLUES_LSP] when set; otherwise the driver searches PATH for {!prog}. *)
val resolve_program : unit -> string

(** Only [.bsv] files beneath a Blues config or compilation database. *)
val applies_to : string -> bool
