(** Read-only Silver overview, built entirely from prepared display rows. No
    binding, connection or freshness decisions are made here. *)

open! Core

val id : Cobalt_tile.View_id.t
val title : string

module Intent : sig
  type t = Refresh [@@deriving sexp_of, equal]
end

type t

val key : t Type_equal.Id.t
val entry : string list -> View_registry.Entry.t
val with_rows : t -> string list -> t
val take_intent : t -> t * Intent.t option
