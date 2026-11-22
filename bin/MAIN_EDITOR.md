# Open a location in a running Cobalt

Start an editor explicitly as the main destination, then send it a location
from another terminal:

```sh
cobalt --main-editor /absolute/path/to/project
cobalt-open --project /absolute/path/to/project src/example.ml 12 5
```

From a source checkout, use `dune exec -j4 bin/cobalt.exe --` and
`dune exec -j4 main_editor_sender/cobalt_open.exe --` in place of the installed
commands. If you only have the standalone `cobalt` binary, build or install
`cobalt-open` separately.

`--main-editor` uses the session's startup directory: the path itself for a
directory, or the parent for a file. Start with the project directory to use
that root when editing files in subdirectories. The root remains fixed as
you switch buffers or browse directories. `--project` takes that absolute
root; matching is lexical (no symlink resolution).

Only one editor per local user and root may opt in at a time. A second opt-in
for the same root fails rather than replacing the first. Normal editor launches
do not listen. On quit or process shutdown the listener stops; if the
destination is unavailable, the sender reports failure and does not start an
editor or try another one.

The file is relative to the root and must normalize below it. Ordinary file
opens follow symlinks; this is not a filesystem sandbox. New buffers are
opened from existing files; an already-open buffer is reused without rereading
disk, including when dirty. Unsaved text does not move between instances.
The optional line and terminal display column are one-based; omitting the
column defaults to 1, and omitting both leaves the retained cursor alone.
The sender returns 0 once the editor accepts the request, 1 on editor
rejection (such as a missing file or invalid location), and 2 for invalid CLI
arguments or an unavailable/failed transport. A lost acknowledgement does not
prove the editor did not apply the request; the sender does not retry.
