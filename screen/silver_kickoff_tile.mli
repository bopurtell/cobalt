(** Headless presentation and explicit intents for Silver named flows. The optional
    adapter owns the draft, preparation and submission; this view never runs I/O. *)
open! Core

val id : Cobalt_tile.View_id.t
val title : string
val palette_entries : Cobalt_palette.Catalog.Entry.t list

module Target : sig
  type t =
    { id : string
    ; label : string
    ; catalog : int
    ; fields : (string * string) list
    }
  [@@deriving sexp_of, equal]
end

module Intent : sig
  type t =
    | Apply of Target.t * (string * string) list
    | Prepare of int
    | Kickoff of int
  [@@deriving sexp_of, equal]
end

module Presentation : sig
  type t =
    { targets : Target.t list
    ; draft : (int, string) result
    ; kickoff : (int, string) result
    ; details : string list
    }
  [@@deriving sexp_of, equal]

  val unavailable : string -> t
end

type t

val key : t Type_equal.Id.t
val entry : Presentation.t -> View_registry.Entry.t
val with_presentation : t -> Presentation.t -> t
val take_intents : t -> t * Intent.t list
