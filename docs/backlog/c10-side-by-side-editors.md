# C10 — Side-by-side file editors

**Status:** Closed — verified and accepted by the owner. **Tracker:** [GitHub #7](https://github.com/bopurtell/cobalt/issues/7).

The first-release rules below are historical. For current tab targeting,
same-file views, and resizing controls, see [Side-by-side file editors](../editor_reference.md#side-by-side-file-editors).

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

## Implementation and verification

- [Editor reference](../editor_reference.md#side-by-side-file-editors): shortcuts,
  focus, coexistence with the directory sidebar, and compact fallback.
- [`app/test/test_editor_split.ml`](../../app/test/test_editor_split.ml):
  single buffer identity, preserved Visual selection, focused save/reload/undo,
  split and tab close, and guarded quit.
- [`screen/test/test_editor_split.ml`](../../screen/test/test_editor_split.ml):
  shared tab strip, pane geometry and cursor, independent scroll, split commands
  and picker, VCS conflicts, directory sidebar, and narrow/zen fallback.
- Passed `dune build -j4 @app/test/runtest @screen/test/runtest @palette/test/runtest
  @ui/picker_test/runtest @file_picker/host/runtest` with a private temp directory.
- Real PTY check with the standalone editor: opened the second file from the
  production picker, saved just the focused file, narrowed to 31 columns and
  widened without changing focus, force-reloaded the other pane, and confirmed
  guarded quit still caught unsaved edits after closing the split.
- C11 can use `Ui_state.editor_panes` for rendered file identities, geometry and
  scroll, and `Ui_state.activate_buffer` to activate a file by ID.
