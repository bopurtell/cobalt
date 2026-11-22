(** Frontend seam for the optional Silver adapter. The frontend gets display
    rows and captured test selections, never Silver protocol values. *)

module Field = Cobalt_screen.Silver_overview_tile.Field
module Target = Cobalt_screen.Silver_overview_tile.Target
module Test_action = Cobalt_screen.Silver_overview_tile.Test_action

type binding =
  { endpoint : string
  ; project_root : string
  ; run : string option
  }

type t =
  { rows : unit -> string list
  ; targets : unit -> Target.t list
  ; status_first : unit -> bool
  ; test_action : unit -> Test_action.t
  ; apply_settings : Target.t -> (string * string) list -> (unit, string) result
  ; launch : Target.t -> (string, string) result Async.Deferred.t
  ; connections : unit -> string list Async.Deferred.t
  ; connect : binding -> (unit, string) result Async.Deferred.t
  ; show : unit -> unit
  ; hide : unit -> unit
  ; refresh : unit -> unit
  ; revision : unit -> int
  ; await_change : after:int -> unit Async.Deferred.t
  ; shutdown : unit -> unit
  }
(** [rows], [targets], [test_action], and [revision] are synchronous cached reads.
    [apply_settings] atomically updates session settings without running a test.
    [launch] is the single dispatch for both tile and palette. Both must validate
    the captured digest against the current binding and catalog. Launch results
    are display-ready and distinguish rejection from unconfirmed delivery.
    [connect] verifies a new binding before replacing the current one. [hide]
    may abandon local observation, but not the command binding or pending launches.
    [shutdown] permanently stops local observation and is idempotent. *)

type factory = (test_default:(string * string option) option -> binding option -> t) option

val entry : t option -> Cobalt_screen.View_registry.Entry.t
val synchronize : Cobalt_screen.Ui_state.t -> t -> Cobalt_screen.Ui_state.t
val take_intents : Cobalt_screen.Ui_state.t
  -> Cobalt_screen.Ui_state.t * Cobalt_screen.Silver_overview_tile.Intent.t list
