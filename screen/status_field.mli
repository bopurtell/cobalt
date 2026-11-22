(** Status information as data: each field's content and how a layout may fit it.
    {!Status.fields} computes them from the UI state, layouts in {!Status} arrange
    them in a rectangle, and {!Geometry} decides which rectangle gets which layout and
    fields. *)

open! Core

module Id : sig
  type t =
    | Mode
    | Filename
    | Dirty
    | Pending (** Keys of an incomplete sequence. *)
    | Position (** One-based line and code-point column. *)
    | Message
    | Instance
    | Silver_connection
    | Silver_target
  [@@deriving sexp_of, equal, enumerate]
end

module Silver : sig
  (** The last verified, still active binding, not a candidate being checked. *)
  type binding =
    { project_root : string
    ; endpoint : string
    }
  [@@deriving equal]

  type t =
    | Disconnected
    | Connecting of binding option
    | Connected of binding
    | Failed of binding option
  [@@deriving equal]
end

(** How a field may be shortened when it does not fit. *)
type fit =
  | Whole (** Shown completely or not at all. *)
  | Cut_left (** Keeps its end, marked with [<]. *)
  | Cut_right (** Keeps its start, marked with [>]. *)
[@@deriving sexp_of]

(** Which end of a row the field belongs to. *)
type side =
  | Left
  | Right
[@@deriving sexp_of]

type t =
  { id : Id.t
  ; spans : Span.t list
  ; priority : int (** Lower is more important: kept longer as space runs out. *)
  ; fit : fit
  ; side : side
  }
[@@deriving sexp_of]
