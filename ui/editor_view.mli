(** The editor as a Bonsai_term app.

    All UI state lives in one [Bonsai.state_machine_with_input] over
    {!Cobalt_screen.Ui_state}, so each terminal event is applied to the current state,
    never to the state of the last frame. The component only adapts events, runs the
    transition, draws {!Cobalt_screen.Frame}, and places the terminal cursor. *)

open! Core
open Bonsai_term

module File_picker_host : sig
  (** Explicit assembly/test boundary. The caller opens [initial_ui] through the
      Async runtime and overrides the production session consumer. Without this
      override, Space f f / Find project files open existing session buffers.
      The frontend yields and chains bounded work
      independently of redraws, and delivers intents only after capture release.
      Deactivation closes the filtering session and cancels discovery; the owner
      may await [Runtime.finished] at teardown. [initial_ui] must own the controller/source configuration supplied
      to [app], rather than an unrelated document. *)
  type t =
    { initial_ui : Cobalt_screen.Ui_state.t
    ; runtime : Cobalt_file_picker_host.Runtime.t
    ; consume : Cobalt_tile.View_id.t Cobalt_file_picker.Model.Request.t -> unit
    }
end

module Content_picker_host : sig
  (** Optional assembly/test override for the production runtime and consumer.
      By default Space f g / Search project contents validates current target text,
      opens or activates a session buffer and reveals the display-cell location. *)
  type t =
    { initial_ui : Cobalt_screen.Ui_state.t
    ; runtime : Cobalt_content_picker_host.Runtime.t
    ; consume : Cobalt_tile.View_id.t Cobalt_content_picker.Model.intent -> unit
    }
end

type hosted =
  { view : View.t
    (** Exactly the positive allocation while visible and running; otherwise empty. *)
  ; cursor : Cursor.t option
    (** Pane-local; only available with input focus. The host translates and places it. *)
  ; handle_event : Event.t -> unit Effect.t
    (** Events are ignored unless this mounted pane is visible and focused. *)
  ; open_location : Cobalt_app.Session.Open_location.request
      -> (Cobalt_app.Buffer_id.t, [ `Closed | `Open of Cobalt_app.Session.Open_location.failure ]) Result.t Effect.t
    (** Serialized with host input, using the live session, including while hidden. *)
  ; shutdown : unit -> unit Effect.t
    (** Ends this session without saving, and waits for its shutdown. Idempotent. *)
  ; closed : bool
    (** The session has ended, either by explicit shutdown or editor quit. *)
  }

(** Mount once per editor session, including while hidden. The component owns the
    startup controller and supplied runtime handles, and does not start or write to
    the physical terminal. [set_clipboard] optionally delegates plain-text clipboard
    copies to the host. [on_toggle_terminal] delegates recognized toggles
    ([Some id] for an explicit number, [None] for the host's current terminal)
    instead of running an editor terminal. The default [vcs] is a fresh Git runner. Without a [source]
    override, the editor owns a workspace LSP source that starts servers only for
    supported documents as they open. Treat unmounting as
    permanent teardown, not as hiding; await [shutdown] before unmounting when the
    host needs to wait for child cleanup. See [HOSTED.md] for integration details. *)
val hosted
  :  ?terminal:Terminal_host.t
  -> ?snippets:Snippet_host.t
  -> ?configuration:Configuration_host.t
  -> ?startup_configuration:Configuration_host.configuration
  -> ?configuration_path:(string, string) Result.t
  -> ?document_decorations:Document_decoration_host.Factory.t
  -> ?document_decorations_enabled:bool
  -> ?smear_enabled:bool
  -> ?zen:bool
  -> ?bare:bool
  -> ?theme:Cobalt_theme.Theme.t
  -> ?buffer_presentation:Cobalt_input.View_command.Buffer_presentation.t
  -> ?report:Cobalt_screen.Report_tile.Item.t list
  -> ?source:Cobalt_source.Source.t
  -> ?vcs:Vcs_host.t
  -> ?font:(Cobalt_screen.Style.t -> Theme.Font.t list)
  -> ?file_picker:File_picker_host.t
  -> ?content_picker:Content_picker_host.t
  -> ?on_toggle_terminal:(int option -> unit Effect.t) Bonsai.t
  -> ?set_clipboard:(string -> unit Effect.t) Bonsai.t
  -> Cobalt_app.Controller.t
  -> dimensions:Dimensions.t Bonsai.t
  -> visible:bool Bonsai.t
  -> focused:bool Bonsai.t
  -> local_ Bonsai.graph
  -> hosted Bonsai.t

(** [font] gives the font styles of each part of the screen; the default is
    {!Theme.Font.default}. Current-document line work is always scheduled through
    yielded bounded turns; [file_picker] is an optional file-consumer override.
    File scope is resolved once from startup and retained across tab activation.
    Each instance owns a lazy pool of numbered terminal runtimes: requests are
    submitted after transitions, tagged snapshots enter asynchronously, and
    deactivation shuts down all children. [zen] defaults to false for assembly
    compatibility; true enters Zen on startup unless [bare] is true. Explicit
    picker hosts retain their supplied initial UI state. *)
val app
  :  ?terminal:Terminal_host.t
   -> ?snippets:Snippet_host.t
        (** Optional runtime override. Each app otherwise owns one asynchronous
            snippet loader, drained after transitions and stopped on deactivation. *)
   -> ?configuration:Configuration_host.t
        (** Reload worker override. Creating an app never runs startup config. *)
   -> ?startup_configuration:Configuration_host.configuration
        (** Explicit preloaded startup result; errors apply defaults and notify. *)
   -> ?configuration_path:(string, string) Result.t
        (** Path/error for Open configuration. Defaults to the loader's XDG/HOME
            resolution, once per app, without reading or executing configuration.
            Also installed on explicit picker hosts' initial UI state. *)
    -> ?document_decorations:Document_decoration_host.Factory.t
    -> ?document_decorations_enabled:bool
         (** Session-only opt-in, applied after startup configuration; false by
             default. Without an available factory, requests notify once. *)
    -> ?smear_enabled:bool
   -> ?zen:bool
   -> ?bare:bool
   -> ?theme:Cobalt_theme.Theme.t
  -> ?buffer_presentation:Cobalt_input.View_command.Buffer_presentation.t
  -> ?report:Cobalt_screen.Report_tile.Item.t list
       (** Installs a static report view (see {!Cobalt_screen.Ui_state.create}). *)
  -> ?source:Cobalt_source.Source.t
       (** A running diagnostic source: its events become [Source] inputs, and
           {!Cobalt_screen.Ui_state.take_source_requests} is sent to it after each
           transition. *)
  -> ?vcs:Vcs_host.t
       (** The runner for registered views' jobs: the default initial state installs
           the VCS view ({!Cobalt_screen.Vcs_view.entry}, from the startup directory),
           {!Cobalt_screen.Ui_state.take_vcs_jobs} is submitted to it after each
           transition, its batches become [Vcs] inputs, and it is stopped on exit.
           Without it the VCS view is unavailable ("VCS unavailable in this
           session") and any job is answered as never started. *)
   -> ?font:(Cobalt_screen.Style.t -> Theme.Font.t list)
    -> ?file_picker:File_picker_host.t
    -> ?content_picker:Content_picker_host.t
  -> Cobalt_app.Controller.t
  -> exit:(unit -> unit Effect.t)
  -> dimensions:Dimensions.t Bonsai.t
  -> local_ Bonsai.graph
  -> view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t

(** Draws a frame. Each span is forced to its computed width, so a grapheme cluster
    that the terminal library measures differently cannot shift the layout. *)
val draw : ?theme:Cobalt_theme.Theme.t -> ?font:(Cobalt_screen.Style.t -> Theme.Font.t list) -> Cobalt_screen.Frame.t -> View.t

(** Static rows and animation overlay split, used with [Frame.Cache]. *)
val draw_base : ?theme:Cobalt_theme.Theme.t -> ?font:(Cobalt_screen.Style.t -> Theme.Font.t list) -> Cobalt_screen.Frame.t -> View.t
val draw_overlay : ?theme:Cobalt_theme.Theme.t -> ?font:(Cobalt_screen.Style.t -> Theme.Font.t list)
  -> base:View.t -> Cobalt_screen.Frame.t -> View.t

type open_location_listener =
  project_root:string
  -> on_request:
       (Cobalt_app.Session.Open_location.request
        -> (unit, Cobalt_app.Session.Open_location.failure) Result.t Async.Deferred.t)
  -> (unit -> unit Async.Deferred.t) Async.Deferred.Or_error.t
(** Optional standalone-only adapter. Started after mounting, with the actual session
    root and a request handler serialized with terminal input. Return an idempotent
    stop function for editor exit or process shutdown. Startup errors end [run]
    with the error after restoring the terminal. *)

(** Runs the editor in the terminal until it exits, then stops [source] and waits for
    [vcs]'s children ({!Vcs_host.shutdown}, at most its default cap). SIGTERM,
    SIGHUP, SIGINT and SIGQUIT end the process with status 1, discarding unsaved
    changes, after restoring the terminal (and after the same bounded wait for [vcs]).
    The embedded terminal is stopped and its shutdown awaited on both editor exit
    and process shutdown. Before mounting the interactive app, loads configuration
    through [configuration] (a fresh production host by default), unless an explicit
    [startup_configuration] result was supplied. Failed startup uses defaults and
    reports the diagnostic. Explicit [theme] overrides config and is retained on
    reload; omitting it allows the configuration theme. *)
val run
  :  ?configuration:Configuration_host.t
   -> ?startup_configuration:Configuration_host.configuration
   -> ?configuration_path:(string, string) Result.t
    -> ?document_decorations:Document_decoration_host.Factory.t
    -> ?document_decorations_enabled:bool
    -> ?smear_enabled:bool (** Disabled by default; Space v s toggles at runtime. *)
   -> ?zen:bool (** Start in Zen; false by default. [bare] takes precedence. *)
   -> ?bare:bool (** Start in borderless document presentation. *)
   -> ?theme:Cobalt_theme.Theme.t (** Initial theme; Space v T previews and chooses themes. *)
  -> ?font:(Cobalt_screen.Style.t -> Theme.Font.t list)
  -> ?buffer_presentation:Cobalt_input.View_command.Buffer_presentation.t
  -> ?report:Cobalt_screen.Report_tile.Item.t list
  -> ?source:Cobalt_source.Source.t
   -> ?vcs:Vcs_host.t
   -> ?open_location_listener:open_location_listener
   -> Cobalt_app.Controller.t
   -> unit Async.Deferred.Or_error.t
