open! Core

type action = Check | Build [@@deriving sexp_of, equal]

type request =
  { id : int
  ; action : action
  ; directory : string
  ; dirty : string list
  }

type command = { program : string; args : string list }

type result =
  { root : string
  ; findings : (string * Cobalt_error.Error.Diagnostics.Finding.t) list
  ; success : bool
  ; status : string
  }

val config_name : string
val action_name : action -> string
val source : int -> string
val is_source : string -> bool
val command : action -> string -> command Or_error.t
val findings : root:string -> string -> (string * Cobalt_error.Error.Diagnostics.Finding.t) list

(** Convert a BSC source position to an editor offset. BSC reports BSV columns
    one-based and Classic columns zero-based. Both lexers use 8-wide tabs. *)
val offset : path:string -> Cobalt_core.Text_buffer.t -> line:int -> column:int -> int Or_error.t
