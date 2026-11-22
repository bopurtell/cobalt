(** Numbered interactive shells, independent of the editor and the physical
    terminal. Call from the Async scheduler. *)

module Model = Cobalt_terminal.Model

type t

(** Create an empty pool. [Model.Start] launches a shell for its number; Start
    while that shell is running is a no-op. *)
val create : unit -> t

(** Numbers must be positive, but need not be consecutive. Invalid numbers
    raise [Invalid_argument] before any request in the batch is applied.
    Requests for the same number are submitted as one ordered batch.
    A closed pool ignores all submissions. *)
val submit : t -> (int * Model.request) list -> unit

(** One consumer, with at most one outstanding read. An update carries the
    terminal number and its generation; a generation advances on every Start
    attempt while idle, including failed starts. Ignore updates older than the
    most recent generation seen for that number when delivering asynchronously.

    Each number retains at most one snapshot and one failure, preserving which
    kind arrived first in a new generation. Ready numbers are served round-robin.
    No visibility or focus signal is needed: output is drained even with no
    consumer. Keep snapshots yourself if a previously delivered screen must be
    redrawn. Do not abandon an outstanding read; it may consume an update.
    Pending reads return [None] when the pool closes. *)
val next_update : t -> (int * int * Model.event) option Async.Deferred.t

(** Request that all running shells stop, without closing the pool. To stop one
    shell, submit [Model.Stop] for its number. *)
val stop : t -> unit

(** Permanently close the pool, discard buffered updates, and terminate all
    shells. Idempotent; resolves after the direct children are reaped and the
    PTYs are closed. *)
val shutdown : t -> unit Async.Deferred.t
