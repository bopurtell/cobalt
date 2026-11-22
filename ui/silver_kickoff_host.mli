(** Optional named-flow view seam. Dispatch starts only captured intents, not reads
    of presentation or changes to the view's placement. *)
type t =
  { presentation : unit -> Cobalt_screen.Silver_kickoff_tile.Presentation.t
  ; dispatch : Cobalt_screen.Silver_kickoff_tile.Intent.t -> bool
  (** True for an intentional change of active flow made by the selector. *)
  }

val entry : t option -> Cobalt_screen.View_registry.Entry.t
val review_entry : t option -> Cobalt_screen.View_registry.Entry.t
val synchronize : Cobalt_screen.Ui_state.t -> t -> Cobalt_screen.Ui_state.t
val dispatch
  : Cobalt_screen.Ui_state.t
  -> t
  -> stages:(unit -> Cobalt_screen.Silver_stage_tile.Snapshot.t)
  -> Cobalt_screen.Ui_state.t
