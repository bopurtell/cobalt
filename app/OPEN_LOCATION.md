# Open a location in a live session (C1)

Use `Cobalt_app.Session.open_location` on the **current** session snapshot.
It is a synchronous, in-process operation; there is no transport, Silver
dependency, or terminal requirement. On success, adopt the returned session and
present the file identified by the returned `Buffer_id.t`. On error, keep the
current session and use the failure variant (or `Session.Open_location.to_error`
for a human-readable diagnostic).

Bind the intended project once with `Session.create ~project_root`. If omitted,
the project defaults to the directory the session started in (the containing
directory for an initial file). For example, if the session starts at an
existing file under `src/`, pass the repository root explicitly to address
other parts of the project. Hosts can read the binding with `Session.project_root`.
Requests must name that absolute root (lexically normalized). File paths must
be relative and normalize to a file path below the root. Identity is lexical,
just like ordinary Cobalt file opens; symlinks follow normal open behavior.

## Example requests and replies

For a session bound to `/work/demo`:

```ocaml
open Cobalt_app

let request : Session.Open_location.request =
  { project_root = "/work/demo"
  ; relative_file = "nested/first.txt"
  ; position = Some { line = 2; column = 3 }
  }

let open_requested session = Session.open_location session request
```

| Request (changes relative to the example) | Result |
| --- | --- |
| `position = None` | `Ok (next_session, id)`; existing file opens, or the retained tab is activated at its current cursor. |
| Position `(2, 3)` with line 2 containing `é界x` | `Ok (next_session, id)`; with widths 1/2/1, the cursor is on `界`, at byte offset 2 **within that line**. |
| Position `(2, 4)` with that same text | `Ok (next_session, id)`; the cursor is on `x`, at byte offset 5 within that line. |
| `relative_file = "missing.txt"` with no file or retained tab | `Error (Target_unavailable _)`; no tab is created. |
| `project_root = "/work/other"` | `Error (Wrong_project { expected = "/work/demo"; requested = "/work/other" })`. |
| `relative_file = "../outside.txt"` | `Error (Invalid_relative_file "../outside.txt")`. |
| Position `(0, 1)` or column beyond the line's end | `Error (Invalid_position _)`; no tab or context change. |
| Session has already exited | `Error Session_exited`. |

Both coordinates are **one-based**. Columns count terminal display cells, not
bytes, Unicode scalars, or UTF-16 units. They use the editor's width function and
tab stops. Both cells of `界` select the same glyph. To open at a line without a
more precise column, use column `1`. Positions use the current editor text,
including unsaved edits, not a fresh disk read. A positioned open finishes the
target's Insert or Visual mode through the usual editor transition before
jumping. A file-only request does not move the target cursor. If the session
already owns the file's buffer, it is reused even if the backing file has since
gone away.

## Run the harness

From the repository root, in the usual Cobalt development environment:

```sh
dune runtest -j 4 app/test/open_location
```

To print the example replies on demand (even when Dune has cached the test):

```sh
dune exec -j 4 app/test/open_location/test_open_location.exe
```

The harness owns a temporary project. It opens two files, edits the first
through ordinary key input, then reopens it at a non-ASCII position. Assertions
check that the tab and document IDs, unsaved bytes, and undo/redo survive. It
also tests file-only opens, wrong roots, missing files, invalid paths and
positions, and an exited session.
