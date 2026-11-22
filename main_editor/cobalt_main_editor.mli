(** Opt-in, per-user standalone C1 forwarding. No endpoint is opened until
    [start] is explicitly called. *)

module Open_location : sig
  (** One-based line and one-based terminal display column. *)
  type position = { line : int; column : int }

  type request =
    { project_root : string
    ; relative_file : string
    ; position : position option
    }

  type failure =
    | Session_exited
    | Wrong_project of { expected : string; requested : string }
    | Invalid_relative_file of string
    | Target_unavailable of Core.Error.t
    | Invalid_position of Core.Error.t

  val to_error : failure -> Core.Error.t
end

type t

(** The first active owner for the absolute, lexically normalized project root
    wins. A second contender fails instead of replacing it. Return from the
    callback only after the C1 operation has been applied or rejected. The
    transport calls at most one callback at a time per listener. *)
val start
  :  project_root:string
  -> on_request:(Open_location.request -> (unit, Open_location.failure) Result.t Async.Deferred.t)
  -> (t, Core.Error.t) Result.t Async.Deferred.t

(** Close the listener and its connections and release ownership. Idempotent;
    does not wait for or cancel an already invoked application callback. *)
val stop : t -> unit Async.Deferred.t

(** The outer result is transport status, the inner result the editor's C1
    acknowledgement. A transport error does not prove the operation did not
    run, and [send] never retries. *)
val send
  :  Open_location.request
  -> ((unit, Open_location.failure) Result.t, Core.Error.t) Result.t Async.Deferred.t
