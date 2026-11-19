open! Core

(** Optional composition boundary. Native/parser sessions stay here, never in the
    screen model, history, render closure, or application/core libraries.
    Callback [Failure]/[Invalid_argument] exceptions are recoverable feature
    failures; other exceptions (including fatal exceptions and interrupts)
    propagate. Returned [Error] values use the same per-source failure latch. *)
module Session : sig
  type t =
    { key : document:Cobalt_decoration.Snapshot.Document_id.t
        -> revision:int -> Cobalt_decoration.Snapshot.Key.t
    ; decorate : key:Cobalt_decoration.Snapshot.Key.t -> source:string
        -> Cobalt_decoration.Snapshot.t Or_error.t
    ; close : unit -> unit
    }
end

module Factory : sig
  type t =
    { available : bool
    ; eligible_path : string option -> bool
    ; create : unit -> Session.t
    }
  val unavailable : t
end

type t
val create : Factory.t -> t

(** Synchronize only at input/host transitions, not from drawing. The default
    parses synchronously, with a strict 256KiB/4096-line budget before allocation
    or session creation. [parse:false] clears stale output/releases obsolete
    sessions between batched inputs, without parsing intermediate revisions.
    Production always supplies actual dimensions; defaults are 80x24 for headless
    callers. Major directories and allocated view-only tabs are not source files. *)
val follow : ?parse:bool -> ?width:int -> ?height:int
  -> t -> Cobalt_screen.Ui_state.t -> Cobalt_screen.Ui_state.t

(** Exact visible owner/source/revision/path check. Never creates a parser or prepares
    geometry. A stale, disabled, failed, or absent snapshot returns [None]. *)
val decorations : ?width:int -> ?height:int -> t -> Cobalt_screen.Ui_state.t
  -> (Cobalt_decoration.Snapshot.Key.t * Cobalt_screen.Decoration.t) option

(** Idempotent release, including on deactivation/shutdown. *)
val clear : t -> unit
