(** Presents Silver display rows and captures test selections and opaque share
    choices. No connection or freshness decisions are made here. *)
open! Core

val id : Cobalt_tile.View_id.t
val title : string

module Field : sig
  type t = { name : string; value : string; default : string } [@@deriving sexp_of, equal]
end

module Target : sig
  type t =
    { suite : string
    ; variant : string option
    ; digest : string
    ; fields : Field.t list
    }
  [@@deriving sexp_of, equal]

  val name : t -> string
  val summary : t -> string
end

module Test_action : sig
  type t = Run of Target.t | Pick | Unavailable of string [@@deriving sexp_of, equal]
  val title : t -> string
end

module Connection : sig
  module Id : sig
    type t [@@deriving sexp_of, equal]
    val of_int : int -> t
  end

  type row = { id : Id.t; title : string }
  type lookup = { rows : row list; error : string option }

  type selection =
    | Share of Id.t
    | Manual of { endpoint : string; project_root : string }
  [@@deriving sexp_of, equal]
end

module Intent : sig
  type t =
    | Refresh
    | Launch of Target.t
    | Apply_settings of Target.t * (string * string) list
    | Connections of int
    | Connect of { generation : int; selection : Connection.selection }
  [@@deriving sexp_of, equal]
end

type t

val key : t Type_equal.Id.t
val entry : ?targets:Target.t list -> ?status_first:bool -> string list -> View_registry.Entry.t
val with_rows : t -> string list -> t
val with_targets : t -> Target.t list -> t
val with_status_first : t -> bool -> t
val targets : t -> Target.t list
val enqueue : t -> Intent.t -> t
val take_intents : t -> t * Intent.t list
