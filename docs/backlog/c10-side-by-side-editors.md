# C10 — Side-by-side file editors

**Status:** Proposed. **Tracker:** [GitHub #7](https://github.com/bopurtell/cobalt/issues/7).

## Why

Cobalt can put a VCS view or directory browser beside a file editor, but
switching file tabs replaces the only file editor. Make it possible to work
on two files at once, such as an implementation and its tests.

## First release

- Show exactly two file editor panes, side by side. Provide keyboard and palette
  commands to open a second file from an existing tab or the file picker without
  replacing the first file. Subsequent file and tab selection targets the
  focused pane. If the requested file is already visible, focus its pane instead.
- Keep one session buffer per file and one session-wide tab list. Show which
  pane has focus. Each visible file keeps its own cursor, selection, viewport,
  and undo history. Editing, saving, and `:e!` target the focused file.
- Provide keyboard and palette commands to switch focus and close the split.
  Reuse existing split swap and width controls where practical. Closing the
  split keeps the focused file visible and does not close the other file's tab
  or discard its edits. Regular tab close and quit retain existing protections
  for dirty and missing buffers.
- Keep one major split slot in v1. If VCS already occupies it, explain how to
  free it rather than hiding VCS. Likewise, requesting a VCS split must not
  silently replace the second editor. Preserve directory sidebar behavior.
- In zen or at insufficient width, show one usable editor without discarding
  the split request or either file. Restore the second pane when space returns
  without moving focus away from the currently usable editor.

## Acceptance

- Open two files, edit both, and switch focus. Cursor position, scroll, and undo
  remain independent. Save or force-reload one file without affecting the other.
- Select an already-visible file and verify it focuses the existing pane.
  Close the split with a dirty file in the other pane; its tab and edits survive,
  and guarded quit still catches them.
- Narrow and widen the terminal and toggle zen; neither file is lost and focus
  never targets a hidden pane. Check that VCS and directory placement still work
  and a conflicting split request leaves the current layout intact.
- Add session and screen tests for focus and command routing, split close,
  and layout fallback.

## Boundaries

No simultaneous views of one file, stacked or nested splits, pane-local tab
groups, simultaneous editor and VCS major splits, mouse gestures, or
cross-session layout persistence. [C11](c11-mouse-support.md) does not block this
ticket.

Start with the [existing major split](major_minor_tiles.md), the split
commands in [`input/`](../../input/), the allocator in
[`screen/workspace.ml`](../../screen/workspace.ml), and buffer ownership in
[`app/session.ml`](../../app/session.ml).
