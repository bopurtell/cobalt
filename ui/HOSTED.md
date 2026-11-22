# Hosting Cobalt

Link `cobalt.hosted` from Silver or another Bonsai_term app. Call
`Cobalt_hosted.open_project` once with the absolute project root, then mount
`Cobalt_hosted.component` with the returned startup handle. Supply reactive pane
`dimensions : Dimensions.t`, `visible : bool`, and `focused : bool`.

The library wrapper forwards to Cobalt's `Cobalt_ui.Editor_view.hosted`, which
also supports supplying an already-open controller and custom runtime handles.
That internal component returns `Editor_view.hosted Bonsai.t`, where:

```ocaml
type hosted =
  { view : Bonsai_term.View.t
  ; cursor : Bonsai_term.Cursor.t option
  ; handle_event : Bonsai_term.Event.t -> unit Bonsai_term.Effect.t
  ; open_location :
      Cobalt_app.Session.Open_location.request ->
      (Cobalt_app.Buffer_id.t,
       [ `Closed | `Open of Cobalt_app.Session.Open_location.failure ])
        Result.t Bonsai_term.Effect.t
  ; shutdown : unit -> unit Bonsai_term.Effect.t
  ; closed : bool
  }
```

The public wrapper re-exports the [C1 request and failure shapes](../app/OPEN_LOCATION.md)
and maps a closed pane to `Error Session_exited`. For example, an open request
`{ project_root = "/work/demo"; relative_file = "src/example.ml"; position =
Some { line = 2; column = 4 } }` selects `x` when line 2 contains `é界x`.
A successful reply returns the live buffer ID, not a snapshot of its text.

Use `visible=false` rather than removing the component or setting its
allocation to 0×0. Keep supplying a positive allocation while hidden. The view
is exactly the requested area while visible. Hidden and unfocused input is
ignored; changing outer focus alone doesn't switch Cobalt's internal view or
editor mode. C1 opens still work while hidden. The cursor is pane-local and absent
while unfocused or hidden. Translate it to the pane origin and install it in the
outer host; don't install a cursor per pane. The host routes bracketed paste to
its original owner or consumes the remainder after focus loss. Cobalt discards
an unfinished paste when it loses input ownership, rather than committing a
partial paste. Only the host starts the TUI or writes to the physical TTY. An
optional `set_clipboard` effect receives plain text; otherwise Cobalt retains
its own yank register without touching the system clipboard.

## Initial tile layout

Omit `layout` to use the standard Cobalt workspace. To start with the source
above a full-width Problems band and no History or Status pane, pass:

```ocaml
let layout =
  Core.Sexp.of_string "((views ((Problems Band))))"
  |> Cobalt_hosted.Layout.t_of_sexp
in
Cobalt_hosted.component ~layout startup ~dimensions ~visible ~focused graph
```

Supported hosted views are `Problems`, `History`, `Language_servers`, and `Vcs`.
Use `Band` for the bottom band, `Tab` for an initially inactive tab, `Split` for
a single pane beside the document, and `Hidden` (or omit the view) to start
closed. Band and tab order follows the list. Optional `status` and `split`
fields set Status placement and the split's side and sizing; see
`Cobalt_hosted.Layout`. This sets the initial layout only: the existing
shortcuts still move, reopen, and hide views, and Zen and Bare remain available.

## Editor appearance

Omit `appearance` to keep Cobalt-managed colors and its normal theme picker.
Pass `~appearance` as a `Cobalt_hosted.Theme.t Bonsai.t` to make the host
authoritative. A host can follow its own palette reactively, or keep the editor
independent using a constant Cobalt preset such as:

```ocaml
let appearance =
  Cobalt_hosted.Theme.find "abyss" |> Core.Option.value_exn |> Bonsai.return
in
Cobalt_hosted.component ~appearance startup ~dimensions ~visible ~focused graph
```

For custom colors use `Theme.of_base16` and, where needed, `Theme.with_colors`
to set individual semantic RGB roles. The same palette colors the editor,
panels, syntax, and overlays. Palette changes repaint the existing session;
they do not change focus or reopen buffers. While the host owns the palette,
the editor's theme picker is unavailable.

## Hosting the numbered terminals

Omit `on_toggle_terminal` to keep Cobalt's own numbered terminal pool, just
like standalone Cobalt. To share the outer host's terminals instead, pass a
Bonsai value of type `(int option -> unit Bonsai_term.Effect.t) Bonsai.t`:

```ocaml
let on_toggle_terminal =
  let%arr toggle = host_toggle in
  function
  | Some id -> toggle (`Number id)
  | None -> toggle `Most_recent
in
Cobalt_hosted.component ~on_toggle_terminal startup ~dimensions ~visible ~focused graph
```

Cobalt invokes the callback once per recognized action, not once per key:
`2 Space /` sends `Some 2`, and `Space /` sends `None`. The host resolves
`None` against its own most-recent selection, including selections made
outside Cobalt. With a callback, the editor creates no terminal pool and
does not show a terminal tile. The host owns the shell lifecycle, terminal
layout and focus transfer. To return to editing, restore the pane's `focused`
input; the editor retains its Insert mode and pane-local cursor.

The editor still owns recognition and its existing 200 ms Insert-mode timing.
A slow prefix is entered literally, bracketed paste never invokes the callback,
and input pending in the timed recognizer is dropped on loss of pane focus
rather than replayed into another pane. The host continues to route input only
to the focused pane.

Run `dune runtest -j4 hosted/test` for the hosted API tests, including the
numbered handoff, literal and pasted input, and a no-handler test that reopens
the same live shell.

## Session lifecycle

Await `shutdown` before unmounting or exiting the outer TUI. It discards unsaved
changes, disposes the session and waits for PTY, Git (bounded), picker and
configuration cleanup. Editor quit uses the usual dirty checks and then closes
only the editor session; delegated shells stay under the host's ownership.
Unmounting also starts cleanup, but does not wait for
it; mount a new component with a fresh startup handle to start a new session.

Both standalone and hosted modes use the same tile composition and commands,
including Git (`Space g g`). No Cobalt commands need registration in the host.
Hosted Cobalt also uses standalone's workspace LSP defaults: it starts a
language server only when a supported document opens, and `Space l i` shows
the live inventory. Hiding the pane keeps the servers and their open documents
alive; closing the session initiates each server's graceful shutdown, with
the same kill deadline as standalone. See [the editor reference](../docs/editor_reference.md)
for server discovery and language bindings.
The internal component can accept startup configuration already loaded through
`Configuration_host.startup`, like `Editor_view.app`.

See the [sample host](../examples/hosted_editor/README.md) for the interactive
demo and PTY acceptance tests, and the
[external consumer](../examples/hosted_consumer/README.md) for a build and smoke
run against an isolated installation of `cobalt.hosted`.
