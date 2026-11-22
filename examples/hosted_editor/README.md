# Hosted Cobalt editor

This sample embeds the real Cobalt editor beside a host-owned pane in one
`Bonsai_term` application. It does not launch the standalone Cobalt binary, give
it a second terminal, or register any of Cobalt's commands in the host.
See [the hosted API notes](../../ui/HOSTED.md) for the application boundary.

From the Cobalt checkout, run in an interactive terminal (use at least 100
columns to see the full demo comfortably):

```sh
demo=$(mktemp -d)
printf 'First file\n' > "$demo/first.txt"
printf 'Other line\n界Second file\n' > "$demo/second.txt"
dune exec examples/hosted_editor/hosted_editor.exe -- "$demo" first.txt second.txt
```

Paths passed after the project root are relative to that root. The first file
must be directly under it. The second file's jump target is line 2, column 3
(one-based display cells), immediately after `界` in this fixture.

| Key | Host action |
| --- | --- |
| F2 | Transfer keyboard focus between the editor and the sibling pane. |
| F3 | Hide Cobalt and give its space to the sibling; press again to restore it. |
| F4 | Open the first file, without supplying a position. |
| F5 | Open the second file at the requested position. |
| F6 | Request a nonexistent file and display the open error in the sibling. |
| F10 | Shut down the whole demo, discarding any unsaved edits. |

Try F5, then `i`, type an edit, and press Escape. F4 then F5 returns to
the same unsaved buffer. F2 lets you type into the sibling's key counter
instead of into Cobalt. Resize the terminal with Cobalt visible or hidden:
the header reports both sizes. After restoring Cobalt, verify your edit is
still there, undo it with `u`, and restore it with `Ctrl-R`.

With Cobalt focused, `Space v n` toggles absolute line numbers just as it does
in standalone Cobalt. In a Git worktree, `Space g g` opens the native Git view.
`Space q` uses Cobalt's normal unsaved-change check; `Space Q` closes just the
editor session and leaves the sibling running. F10 (unlike F3) ends the editor
session, shuts down its child terminals, and exits the host.

## Running acceptance tests

```sh
dune runtest -j 4 examples/hosted_editor
```

The Python 3 stdlib test drives both executables through real PTYs, so it does not
require a graphical terminal, language server, or Silver installation.
