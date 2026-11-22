(** The in-process Cobalt editor for a Bonsai_term host. The host owns the
    physical terminal and composes the editor's view with its own UI. *)

type startup

module Layout = Cobalt_screen.Hosted_layout

(** The shared Cobalt palette API: resolve a named theme with [find], or build a
    custom theme with [of_base16] and [with_colors]. *)
module Theme = Cobalt_theme.Theme

module Host_command : sig
  type t = { id : string; title : string; aliases : string list }
end

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

    [layout] overrides the initial workspace tile placements, not their
    commands. Omit it for Cobalt's standard workspace. It is applied once
    per mount; the user can then move or toggle tiles as usual.

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
    [Session_exited].

    [appearance] gives the host ownership of the editor palette, including
    chrome, syntax and overlays. Changes repaint the mounted editor without
    replacing its session. The Cobalt theme picker is unavailable while the
    host owns appearance. Omit this option for Cobalt-managed appearance.

    Supply both [host_commands] and [on_host_command] to append this mount's
    commands to Cobalt's Normal-mode [Space c c] palette. Use a visible host
    prefix in each title (for example, ["Silver: Overview"]). IDs must be stable
    within the mount and consist of lowercase ASCII letters, digits, dots and
    hyphens. Invalid entries are skipped; the first row for each ID wins.
    Exact matches are case-insensitive; exact native matches win over exact
    host matches, but both rows remain selectable. The list is captured on open;
    a removed ID won't dispatch from an already-open palette. Accepting a host
    row closes the palette and invokes the callback once with the ID. Cobalt's
    [:] prompt is unchanged. *)
val component
  :  ?layout:Layout.t
  -> ?set_clipboard:(string -> unit Bonsai_term.Effect.t) Bonsai.t
  -> ?on_toggle_terminal:(int option -> unit Bonsai_term.Effect.t) Bonsai.t
  -> ?appearance:Theme.t Bonsai.t
  -> ?host_commands:Host_command.t list Bonsai.t
  -> ?on_host_command:(string -> unit Bonsai_term.Effect.t) Bonsai.t
  -> startup
  -> dimensions:Bonsai_term.Dimensions.t Bonsai.t
  -> visible:bool Bonsai.t
  -> focused:bool Bonsai.t
  -> local_ Bonsai.graph
  -> t Bonsai.t
