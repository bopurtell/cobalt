(** A running diagnostic source, as Cobalt sees it: requests go in with {!send}, coalesced
    events come out of {!next_batch}. A producer (the {!Synthetic} checker now, a
    language-server client) is built with {!create}; Cobalt never learns which
    one it holds. *)
open! Core
open! Async

type t

(** What a producer does with Cobalt's requests. *)
module Driver : sig
  type t =
    { handle : Cobalt_error.Source_request.t -> unit
    ; stop : unit -> unit (** Cobalt is quitting; release timers and processes. *)
    }
end

(** [create f] gives [f] the function a producer reports with ([emit]), and keeps the
    driver [f] returns. Events emitted while [f] runs are kept. *)
val create : (emit:(Cobalt_error.Source_event.t -> unit) -> Driver.t) -> t

val send : t -> Cobalt_error.Source_request.t -> unit

(** Idempotent. Pending events are discarded, later ones ignored, and {!next_batch}
    never becomes determined again. *)
val stop : t -> unit

(** The pending events, at most {!max_batch} and oldest first, once there is at least
    one. Taking a bounded batch lets keys be handled between the batches of a long
    burst. Not to be called again before the previous result is determined. *)
val next_batch : t -> Cobalt_error.Source_event.t list Deferred.t

val max_batch : int

(** The pending events now, at most {!max_batch} and oldest first, without waiting; for
    tests and measurements that step time themselves. *)
val poll : t -> Cobalt_error.Source_event.t list

(** Snapshots dropped by coalescing so far (see {!Event_queue}); reset by {!stop}. *)
val dropped : t -> int
