(** Optional Silver simulation observation and test quick launch. All network
    operations are called on the Async scheduler. *)

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

(** One-shot Testing operations, independent of the overview's watched attempt.
    Keep a verified [project] for the editor session, not the tile lifetime. *)
module Testing : sig
  type project

  (** Verify loopback Silver v1 and open the explicitly selected canonical project
      root. A different root is rejected and no attempt is selected. If supplied,
      [expected_instance_id] must match [hello] before opening the project. *)
  val connect
    :  ?peer:peer
    -> ?timeout:Core.Time_ns.Span.t
    -> ?expected_instance_id:string
    -> endpoint:string
    -> project_root:string
    -> unit
    -> (project, string) result Async.Deferred.t

  (** Abandon local requests and invalidate this project's catalogs. Does not
      cancel attempts or shut down the daemon. *)
  val close : project -> unit
  val project_root : project -> string

  type parameter =
    { key : string
    ; label : string
    ; default : string
    ; choices : string list
    }

  type case = { id : string; label : string }

  type suite =
    { id : string
    ; label : string
    ; cases : case list
    ; parameters : parameter list
    ; default_seed : string
    }

  type catalog

  (** Read the current catalog, starting at most one provider discovery if needed.
      Polls only while discovery is in progress and only up to [discovery_timeout]
      (default 30 seconds). Does not start a simulation. *)
  val discover
    :  ?discovery_timeout:Core.Time_ns.Span.t
    -> project
    -> (catalog, string) result Async.Deferred.t

  val digest : catalog -> string
  val suites : catalog -> suite list

  type acceptance = { attempt_id : string; job_id : string }

  type launch_result =
    | Accepted of acceptance
    | Stale_catalog of string
    | Rejected of string
    | Uncertain of string

  (** Submit exactly the captured catalog digest and input values once, with a fresh
      submission key. Supply explicit nonempty case IDs, a seed, and every declared
      parameter. [Uncertain] means Silver may have reserved an attempt; do not retry
      automatically. A stale result requires discovery and a new selection. *)
  val launch
    :  catalog
    -> suite:string
    -> cases:string list
    -> seed:string
    -> parameters:(string * string) list
    -> launch_result Async.Deferred.t
end
