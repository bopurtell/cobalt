(** Cached ASIC checklist evidence, independent of launch intents and simulation
    observation. A binding is a verified Silver project, not a watched attempt. *)

type selection =
  { target : Silver_flow.target option
  ; flow : string
  ; profile : string
  }

type subject =
  | No_selection
  | Exact_run of string
  | Exact_matching_run of selection * string
      (** Like [Exact_run], but require the run still matches this scope. *)
  | Exact_workflow of string
  | Latest_matching of selection
      (** Compare recorded producer start times, using workflow reservation
          time before allocation. A sole matching legacy record needs no
          timestamp; a tie is not resolved by registry update order. *)

type status =
  | Pending
  | Running
  | Cancelling
  | Completed
  | Failed
  | Skipped
  | Cancelled
  | Interrupted
  | Not_requested
  | Unsupported
  | Unconfirmed
  | Unavailable
  | Unknown of string

type duration =
  | Measured of float
  | Since of Core.Time_ns.t
      (** A live estimate may use this start, not the poll time. *)

type origin = Physical | Elaboration | Supplementary_timing | Requested_endpoint

type stage =
  { id : string
  ; label : string
  ; origin : origin
  ; status : status
  ; duration : duration option
  ; reason : string option
  ; launch_destination : (selection * string) option
      (** The physical stage's explicit Silver action scope and endpoint, when
          reported. This is mapping evidence, not a launch intent. Consumers
          must require the current catalog, scope, and row eligibility to
          agree; never interpret an explicit mismatched mapping as absent.
          Historical assignments are not part of this mapping. *)
  }

type freshness = Validated | Cached_unverified | Missing_source | Refresh_failed of string

type snapshot =
  { subject : subject
  ; run_id : string option
  ; workflow_id : string option
  ; process_status : string option
  ; stages : stage list
  ; summary_freshness : freshness option
  ; notice : string option
  ; matching_run_ids : string list
      (** Dated runs ordered newest first for scoped browsing. An undated
          run is included only if it is the sole matching run. *)
  }

type availability =
  | Not_available of string
  | Fresh of snapshot
  | Stale of snapshot * string

type t

val create
  :  ?poll_interval:Core.Time_ns.Span.t
  -> ?idle_interval:Core.Time_ns.Span.t
  -> unit
  -> t

(** Change project/subject and immediately discard old evidence. Reapplying the
    same project object and subject is a no-op. Does not own the project. *)
val bind : t -> Silver_overview.Testing.project -> subject -> unit
val unbind : t -> unit

(** Only visible interests are polled. Hiding preserves the cache, but fences
    in-flight replies and does not cancel any Silver execution. *)
val set_visible : t -> bool -> unit

(** Request a new read cycle, coalesced with in-flight requests. Does not refresh
    the flow catalog or invalidate a prepared launch. *)
val refresh : t -> unit

val latest : t -> availability
val revision : t -> int
val await_change : t -> after:int -> unit Async.Deferred.t
val shutdown : t -> unit
