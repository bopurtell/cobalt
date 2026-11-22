(** The in-process Cobalt editor for a Bonsai_term host. The host owns the
    physical terminal and composes the editor's view with its own UI. *)

type startup

(** Open an existing project directory as the editor's startup surface.
    Prepare once per mounted editor. The root must be absolute and does not
    depend on the host's working directory. *)
val open_project : string -> startup Core.Or_error.t

module Open_location : sig
  (** One-based line and terminal display column. In [é界x], column 4 selects
      [x]; columns 2 and 3 select [界]. *)
  type position = { line : int; column : int }

  type request =
    { project_root : string
    ; relative_file : string
    ; position : position option
    }

  type buffer_id

  val equal_buffer_id : buffer_id -> buffer_id -> bool

  type failure =
    | Session_exited
    | Wrong_project of { expected : string; requested : string }
    | Invalid_relative_file of string
    | Target_unavailable of Core.Error.t
    | Invalid_position of Core.Error.t

  val to_error : failure -> Core.Error.t
end

type t =
  { view : Bonsai_term.View.t
  ; cursor : Bonsai_term.Cursor.t option
  ; handle_event : Bonsai_term.Event.t -> unit Bonsai_term.Effect.t
  ; open_location :
      Open_location.request ->
      (Open_location.buffer_id, Open_location.failure) result Bonsai_term.Effect.t
  ; shutdown : unit -> unit Bonsai_term.Effect.t
  ; closed : bool
  }

(** Mount once. Preserve the mount and supply a positive allocation while
    hidden. The view occupies exactly the requested allocation when visible
    and open; it is empty when hidden or closed. Route input only to the
    focused pane and translate the pane-local cursor into outer-terminal
    coordinates. [set_clipboard] delegates clipboard writes to the host;
    omitting it leaves Cobalt's own yank register in use.

    [on_toggle_terminal] replaces the local terminal pool. Cobalt calls it
    once per recognized ToggleTerm action, with [Some id] for [N Space /]
    or [None] for [Space /] so the host can use its own most-recent terminal.
    The host owns terminal visibility, focus and teardown. The editor retains
    its mode and cursor position when focus transfers; literal input and
    bracketed paste do not trigger the callback. Without this option, Cobalt
    toggles its own numbered shells.

    [open_location] works even while hidden: it opens an existing file below
    the bound project root or activates a retained buffer without reloading or
    losing unsaved edits. A failed request leaves the session unchanged. Path
    confinement is lexical; regular file access follows symlinks.

    [shutdown] discards unsaved edits, closes the session and waits for cleanup;
    await the effect before unmounting. Requests after closing return
    [Session_exited]. *)
val component
  :  ?set_clipboard:(string -> unit Bonsai_term.Effect.t) Bonsai.t
  -> ?on_toggle_terminal:(int option -> unit Bonsai_term.Effect.t) Bonsai.t
  -> startup
  -> dimensions:Bonsai_term.Dimensions.t Bonsai.t
  -> visible:bool Bonsai.t
  -> focused:bool Bonsai.t
  -> local_ Bonsai.graph
  -> t Bonsai.t
