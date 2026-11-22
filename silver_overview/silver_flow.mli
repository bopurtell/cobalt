(** Companion flow launch, independent of test launch and watched attempts. Keep
    the session at composition scope, not at tile or palette scope. *)

type binding =
  { endpoint : string
  ; project_root : string
  ; instance_id : string
  ; project_id : string
  }

type target = { chip : string; variant : string }

type inputs =
  { target : target option
  ; flow : string
  ; profile : string
  ; endpoint : string
  ; assignments : (string * string) list
  }

type parameter =
  { key : string
  ; label : string
  ; default : string option
  ; choices : string list
  }

type 'a availability =
  | Available of 'a
  | Unavailable of string

type alias = Synth | Timing | Routing

type stage =
  { id : string
  ; label : string
  ; alias : alias option
  ; endpoint : string availability
  }

type schema =
  { endpoints : string list
  ; default_endpoint : string option
  ; parameters : parameter list
  }

type flow =
  { id : string
  ; label : string
  ; profiles : string list
  ; default_profile : string
  ; stages : stage list
  ; kickoff : schema availability
  }

type catalog =
  { target : target option
  ; flows : flow list
  ; default_flow : (string * string) option  (** Declared flow/profile pair. *)
  ; stage_launch : unit availability
  }

type accepted =
  | Run of string
  | Workflow of { workflow_id : string; run_id : string option }

type outcome =
  | Accepted of accepted
  | Rejected of string
  | Stale of string
  | Unconfirmed of string

type preview =
  { identity : string
  ; inputs : inputs
  }

(** An in-process service, not a wire protocol. Its prepared value closes over
     the exact native submission operation; the session invokes it at most once.
     After any asynchronous revalidation, [submit] must check [still_current]
     before sending the execution request, and return [Stale] if no longer current.
     [prepare] may do planning, but must not start execution. [Stage] preparation
    may capture an intent rather than an exact physical plan. *)
type request = Stage of inputs | Kickoff of inputs
type prepared =
  { preview : preview
  ; submit : still_current:(unit -> bool) -> outcome Async.Deferred.t
  }

type service =
  { binding : binding
  ; catalog : unit -> (catalog, string) result Async.Deferred.t
  ; prepare : request -> (prepared, string) result Async.Deferred.t
  }

(** Reuse an already verified project; never reopen it or infer it from a
    watched attempt. The caller owns the verified project's lifetime. *)
val production : Silver_overview.Testing.project -> service

type t
type view
type stage_intent
type draft
type ready

val create : unit -> t
val bind : t -> service -> unit
val unbind : t -> unit
val refresh : t -> unit Async.Deferred.t
val revision : t -> int
val await_change : t -> after:int -> unit Async.Deferred.t

val catalog_view : t -> (view, string) result
val catalog : view -> catalog

(** Set explicit stage settings for this view. Unavailable or stale explicit
    settings block stage resolution rather than silently selecting defaults.
    [None] explicitly clears them. No planning or submission. *)
val set_stage_inputs : t -> view -> inputs option -> (unit, string) result

(** Select a flow within the captured chip/variant and catalog, keeping that
    flow's applied overrides if present. Otherwise use its native profile and
    no explicit assignments. Does not require a kickoff preview or start work. *)
val select_flow : t -> view -> flow:string -> (unit, string) result
val active_flow : t -> view -> string option

(** The last scoped choice, even if invalidated by a catalog refresh. For
    highlighting only; do not use this to enable launch. *)
val selected_flow : t -> view -> string option

(** Why the selected flow cannot supply fresh stage inputs, if applicable. *)
val stage_selection_error : t -> view -> string option

val stages : t -> view -> (stage * (stage_intent, string) result) list
val resolve_stage : t -> view -> id:string -> (stage_intent, string) result
val resolve_alias : t -> view -> alias -> (stage_intent, string) result
val stage_inputs : stage_intent -> inputs

(** Only UI selection continuity. Unlike [equal_stage_intent], ignores the
    one-shot dispatch generation; never use this to validate a submission. *)
val equal_stage_selection : stage_intent -> stage_intent -> bool
val equal_stage_intent : stage_intent -> stage_intent -> bool
val launch_stage : t -> stage_intent -> outcome Async.Deferred.t

(** Local kickoff draft. Editing is pure; discard edits by retaining the old
    draft. Applying makes its explicit settings active for stage resolution
    and invalidates the old ready preview without submitting.
    The draft values expose declared defaults for editing/display. Unchanged
    defaults are not sent as explicit overrides; the service resolves them. *)
val draft : t -> view -> flow:string -> (draft, string) result
val draft_inputs : draft -> inputs
val edit : draft -> inputs -> draft
val apply : t -> draft -> (unit, string) result

type preparation =
  | Not_prepared of string
  | Preparing
  | Ready of ready

val prepare : t -> unit Async.Deferred.t
val preparation : t -> preparation
val preview : ready -> preview
val kickoff : t -> ready -> outcome Async.Deferred.t

(** Project-scoped status remains available while either tile is hidden.
    Late results return to the original caller but cannot replace newer status. *)
type submission =
  | Idle
  | Pending of inputs
  | Finished of inputs * outcome

val submission : t -> submission
