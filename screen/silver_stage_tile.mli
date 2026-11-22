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

module Status : sig
  (** Display evidence, independent of whether a stage can be launched. [Unknown]
      means no stage observation was reported; [Unrecognized] preserves a status
      reported by Silver that this frontend does not know. *)
  type t =
    | Unknown
    | Not_requested
    | Pending
    | Running
    | Cancelling
    | Completed
    | Failed
    | Skipped
    | Cancelled
    | Interrupted
    | Unsupported
    | Unrecognized of string
  [@@deriving sexp_of, equal]
end

module Row : sig
  type t = { id : string; label : string; status : Status.t; action : Action.t }
  [@@deriving sexp_of]
end

module Snapshot : sig
  type t =
    { rows : Row.t list
    ; empty : string
    ; aliases : (Alias.t * Action.t) list
    ; context : string option (** Active flow/profile and variant, not a stage endpoint. *)
    ; watch_context : string option (** Independently scoped ASIC observation. *)
    }
  [@@deriving sexp_of]

  val unavailable : string -> t
  val alias : t -> Alias.t -> Action.t
end

type t

module Spinner : sig
  type t [@@deriving equal]

  val period : Core.Time_ns.Span.t
  val at : Core.Time_ns.t -> t
end

val with_spinner : t -> Spinner.t -> t

val spinner_visible
  :  t
  -> focused:bool
  -> rows:int
  -> width:int
  -> covered:(column:int -> row:int -> bool)
  -> bool

module Watch : sig
  type t = Older | Newer | Latest | Refresh [@@deriving sexp_of]
end

val key : t Core.Type_equal.Id.t
val entry : Snapshot.t -> View_registry.Entry.t
val with_snapshot : ?flow_selected:bool -> t -> Snapshot.t -> t
val enqueue : t -> Intent.t -> t
val take_intents : t -> t * Intent.t list
val take_watches : t -> t * Watch.t list
