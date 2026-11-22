# Consume the installed Cobalt editor

For a separate Dune project (such as Silver), depend on package `cobalt`
and add `cobalt.hosted` to the host executable's `libraries`. The public
OCaml module is `Cobalt_hosted`; the session, screen, and UI implementation
libraries are private. This is an in-process interface, not a child process
or a protocol. Build Cobalt and the host with a compatible OCaml toolchain
and the same Bonsai/Bonsai_term dependencies.

Use `Cobalt_hosted.open_project` with the absolute project root, then mount
`Cobalt_hosted.component` once per session on the host's Bonsai graph.
Feed the editor its allocation, visibility, and focus. Embed the returned
view beside the host's own view, translate the optional editor cursor from
pane-local coordinates, and forward events to the focused owner. When
hidden, keep the component mounted. The host owns the terminal, including
the routing of complete bracketed pastes. Follow the API contract in
[`cobalt_hosted.mli`](../../hosted/cobalt_hosted.mli).

From the latest component result, call `open_location` with the same root,
a relative file, and an optional one-based line and display column. For
example, `{ line = 2; column = 4 }` opens `x` on a line containing `é界x`.
Handle the typed reply before reporting success. Call and await `shutdown`
before permanently removing the component; this discards unsaved changes.

## Isolated build and run

This directory is a separate Dune project. Copy it outside both the Cobalt
and Silver source trees. Install Cobalt into a fresh prefix, leaving your
opam switch unchanged and exposing only installed Cobalt artifacts to the
smoke. Run the following from Cobalt's root with its build dependencies
available (the smoke also uses `bonsai_test`):

```sh
cache="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$cache"
work=$(mktemp -d "$cache/cobalt-hosted-consumer.XXXXXX")
mkdir "$work/tmp"
export TMPDIR="$work/tmp"
unset DUNE_BUILD_DIR
dune build -j 4 @install
dune install --prefix "$work/prefix" cobalt

mkdir -p "$work/consumer" "$work/project/src"
cp examples/hosted_consumer/dune examples/hosted_consumer/dune-project \
  examples/hosted_consumer/smoke.ml "$work/consumer/"
printf 'first file\n' > "$work/project/src/first.txt"
printf 'second file\né界x\n' > "$work/project/second.txt"

cd "$work/consumer"
export OCAMLPATH="$work/prefix/lib"
dune build --root . -j 4 smoke.exe
dune exec --root . -j 4 ./smoke.exe -- "$work/project" </dev/null
```

Expected: `external C1/C2 smoke passed`. This checks the installed public API
against the real mounted editor without starting a physical terminal. It
opens two files, injects a modal edit, checks typed failures and stable
buffer identity, reopens while hidden, resizes and restores focus, verifies
the edit still renders, and awaits shutdown. For the interactive sibling-pane
demo and terminal acceptance, see [`../hosted_editor`](../hosted_editor).

Verified with Dune 3.24.2 and OCaml 5.2.0+ox: a clean standard `_build`
installed to an absolute prefix via `dune install`. The independent consumer
linked from that prefix and printed `external C1/C2 smoke passed`.

### Absolute build directory caveat

Dune 3.24.2 can fail in `Obj_dir.External.encode` when `dune install`
rewrites `dune-package` metadata for libraries with private interface
directories and an **absolute** `--build-dir` (or `DUNE_BUILD_DIR`). It
tries to make the interface paths relative to the library directory, but
its descendant check does not handle paths classified as external. The
destination prefix can be absolute; it does not trigger this error.
Use standard `_build` or a relative build directory inside the workspace.

If an absolute build directory is necessary, install the generated manifest
instead. Use `/` as the installer's working directory so the manifest's
absolute source paths resolve with older `opam-installer` versions.
This copies files into the new prefix without changing the switch:

```sh
dune build --build-dir "$work/cobalt-build" -j 4 @install
(cd / && opam-installer --prefix "$work/prefix" \
  "$work/cobalt-build/default/cobalt.install")
```

The manifest workaround passed the same test on that toolchain.
