# C11 — Basic mouse support

**Status:** Proposed.

## Why

Let the user point at a pane, cursor position, or file tab and scroll the
pane under the pointer without changing Cobalt's keyboard-first workflow.
Cobalt currently disables terminal mouse reporting and ignores mouse events.

## First release

Mouse reporting is opt-in at launch; proposed invocation: `co --mouse .`.
Plain `co .` keeps terminal-native selection and copying. No runtime toggle in v1.

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
- Carry pointer inputs from [`ui/terminal_input.ml`](../../ui/terminal_input.ml)
  to the screen layer. Enable terminal reporting only for opted-in launches
  through [`ui/editor_view.ml`](../../ui/editor_view.ml). Keep hit testing and
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
- Smoke-test a real terminal: normal launches still allow native text
  selection, opted-in launches receive click and wheel events, and quitting
  restores terminal mouse behavior.

## Follow-ups, not v1

Drag selection, double-click actions, dragging split dividers, mouse controls
for VCS and pickers, and forwarding mouse input to embedded terminals. C11
can ship before C10; verify targeting across both editors once both land.
