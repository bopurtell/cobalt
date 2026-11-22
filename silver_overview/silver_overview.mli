(** Optional read-only view of an explicitly named Silver simulation project/attempt.
    All operations on the adapter are called on the Async scheduler. *)

type binding =
  { endpoint : string
  ; project_root : string
    (** Canonical absolute root on the daemon's host, e.g. from [pwd -P]. *)
  ; run : string option
    (** Exact simulation attempt ID, or [None] for a project-level view. *)
  }

type attempt =
  { id : string
  ; suite : string
  ; lifecycle : string
  ; outcome : string option
    (** [None] means Silver reports [Unknown], not necessarily still running. *)
  }

type snapshot =
  { binding : binding
  ; instance_id : string
  ; project_id : string
  ; attempts : attempt list
  ; truncated : bool
  }

type availability =
  | Unavailable of string
  | Fresh of snapshot
      (** Last successful status, with no failure observed since. *)
  | Stale of snapshot * string
      (** Status from this binding, retained after a failed refresh. *)

type request =
  { meth : [ `Get | `Post ]
  ; path : string
  ; headers : (string * string) list
  ; body : string
  }

type response = { status : int; body : string }

(** A transport injection point; [stop] signals only local request abandonment.
    A peer must not wait synchronously on the Async scheduler. A result returned
    after [stop] or the deadline is ignored. *)
type peer =
  endpoint:string ->
  timeout:Core.Time_ns.Span.t ->
  stop:unit Async.Deferred.t ->
  request ->
  (response, string) result Async.Deferred.t

type t

val create
  :  ?peer:peer
  -> ?timeout:Core.Time_ns.Span.t
  -> ?poll_interval:Core.Time_ns.Span.t
  -> ?retry_initial:Core.Time_ns.Span.t
  -> ?retry_max:Core.Time_ns.Span.t
  -> unit
  -> t

(** Replace the current binding even when the arguments are unchanged. Drops the
    old snapshot immediately and fences every reply from the previous binding. *)
val rebind : t -> binding -> unit

(** Drop the binding without disposing the adapter. *)
val unbind : t -> unit

(** Synchronous cached read. Does no network or filesystem work. *)
val latest : t -> availability

(** Revision and awaitable notification for consumers that do not already tick. *)
val revision : t -> int
val await_change : t -> after:int -> unit Async.Deferred.t

(** Permanently stop observation. Never changes the state of a Silver run. *)
val shutdown : t -> unit
