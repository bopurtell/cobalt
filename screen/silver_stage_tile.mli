(** Optional Silver checklist. The frontend only receives prepared display
    rows and opaque tokens; it never resolves an endpoint or starts a run on
    render, selection, or opening the view. *)

val id : Cobalt_tile.View_id.t
val title : string
val adapter_unavailable : string

module Alias : sig
  type t = Synth | Timing | Routing [@@deriving sexp_of, equal]

  val all : t list
  val query : t -> string
  val command_id : t -> string
end

module Intent : sig
  type t = { token : string; selection : string; summary : string } [@@deriving sexp_of, equal]
end

module Action : sig
  type t = Ready of Intent.t | Blocked of string [@@deriving sexp_of, equal]

  val title : Alias.t -> t -> string
end

module Row : sig
  type t = { id : string; label : string; action : Action.t } [@@deriving sexp_of]
end

module Snapshot : sig
  type t =
    { rows : Row.t list
    ; empty : string
    ; aliases : (Alias.t * Action.t) list
    }
  [@@deriving sexp_of]

  val unavailable : string -> t
  val alias : t -> Alias.t -> Action.t
end

type t

val key : t Core.Type_equal.Id.t
val entry : Snapshot.t -> View_registry.Entry.t
val with_snapshot : ?flow_selected:bool -> t -> Snapshot.t -> t
val enqueue : t -> Intent.t -> t
val take_intents : t -> t * Intent.t list
