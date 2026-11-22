# C11 — Basic mouse support

**Status:** Closed — verified and accepted by the owner.

This ticket records the initial mouse behavior. For current split focus and
divider gestures, see [Mouse input](../editor_reference.md#mouse-input).

## Why

Let the user point at a pane, cursor position, or file tab and scroll the
pane under the pointer without changing Cobalt's keyboard-first workflow.

## Behavior

Standalone Cobalt enables mouse reporting by default. Choose **Toggle mouse**
in the command palette to switch between editor controls and terminal-native
selection. Start with `cobalt --no-mouse .` to begin with reporting off. Hosted
editors leave terminal reporting to their host.

| Gesture | Behavior |
| --- | --- |
| Left-click file text | Focus that editor and place the cursor. Preserve Normal or Insert mode; in Visual mode, end the selection and place the cursor. |
| Left-click an Oil/Dired row | Focus the directory and move the cursor to the row. Do not open, mark, rename, or apply anything. `Enter` still opens the entry. |
| Left-click a visible file tab | Activate it as if selected by keyboard. Once [C10](c10-side-by-side-editors.md) lands, target the focused editor pane and follow C10's rule for files already visible. |
| Wheel over file text or a directory listing | Scroll the pane under the pointer without moving its cursor, changing its selection, or stealing focus. The cursor may go offscreen. The next keyboard command that moves the cursor or edits text brings it back into view. |
| Click a gutter, border, divider, or unsupported tile | Do nothing. A modal overlay blocks mouse events from reaching the workspace underneath it. |

## Design

- **Hit-test what was drawn.** Use the same pane geometry and visible tab spans
  as rendering, including after resize. Hidden panes and tabs, overflow
  indicators, and gaps are not targets. Resolve modal capture before checking
  workspace targets.
- **Map terminal cells to text positions.** Use the pane's text rectangle and
  both viewport offsets. Inside a tab or wide glyph, land on that character,
  never in the middle of its encoded bytes. Past end of line lands at the
  mode-appropriate end; below the last line does nothing.
- **Keep wheel scrolling separate from keyboard scrolling.** The current
  keyboard scroll path may move the cursor to keep it visible. Wheel scrolling
  changes only the target viewport; rendering must not snap it back merely
  because the cursor is offscreen. Preserve existing keyboard scroll behavior.
  Use three rows per wheel step and retain the viewport per buffer, independent
  of focus. A cursor-motion command (even at a boundary) or edit restores
  cursor-follow; an incomplete keyboard prefix does not.
- Carry pointer inputs from [`ui/terminal_input.ml`](../../ui/terminal_input.ml)
  to the screen layer. Manage standalone terminal reporting through
  [`ui/editor_view.ml`](../../ui/editor_view.ml). Keep hit testing and
  routing in the screen layer rather than the terminal adapter.

## Acceptance

- Test click placement with gutters, tabs, wide characters, horizontal scroll,
  end of line, and clicks below EOF. Check Normal, Insert, and Visual behavior.
- In a file editor plus directory sidebar, scroll both the focused and unfocused
  panes. Focus, cursor, selection, buffer text, and undo history are unchanged;
  a later keyboard edit or cursor motion restores cursor visibility. Confirm
  a directory click never performs a filesystem operation.
- Verify resize, tab overflow, and modal overlays do not leave stale targets.
  Confirm keyboard input and bracketed paste still work with mouse enabled.
- Smoke-test a real terminal: normal launches receive click and wheel events;
  `--no-mouse` and toggling off allow native text selection; toggling back on
  restores editor controls; quitting restores terminal behavior.

## Follow-ups, not v1

Drag selection, double-click actions, dragging split dividers, mouse controls
for VCS and pickers, and forwarding mouse input to embedded terminals. C11
can ship before C10; verify targeting across both editors once both land.

## Headless evidence

[`screen/test/test_pointer.ml`](../../screen/test/test_pointer.ml) drives
zero-based pointer input through the screen transition and checks rendered
frames. It covers character-cell mapping, modal and paste capture, directory
row selection without opening or marking, independent sidebar and file
viewports, keyboard re-follow and undo, tab overflow, and visible/hidden editor
targeting with C10. Run the headless suites with `dune runtest -j4 screen app core`
and the standalone PTY suite with `dune build -j4 @bin/mouse-cli-test`.
