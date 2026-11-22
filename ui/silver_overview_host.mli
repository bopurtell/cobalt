(** Frontend seam for the optional Silver adapter. The frontend gets display
    rows, never Silver protocol values. Only the composition root implements
    the callbacks. *)

type binding =
  { endpoint : string
  ; project_root : string
  ; run : string
  }

type t =
  { rows : unit -> string list
  ; show : unit -> unit
  ; hide : unit -> unit
  ; refresh : unit -> unit
  ; revision : unit -> int
  ; await_change : after:int -> unit Async.Deferred.t
  ; shutdown : unit -> unit
  }
(** [rows] and [revision] are synchronous cached reads. [hide] abandons local
    observation; [shutdown] permanently stops it and is idempotent. *)

type factory = (binding -> t) option

val entry : t option -> Cobalt_screen.View_registry.Entry.t
val take_intent : Cobalt_screen.Ui_state.t
  -> Cobalt_screen.Ui_state.t * Cobalt_screen.Silver_overview_tile.Intent.t option
