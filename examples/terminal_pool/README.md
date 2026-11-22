# Use the numbered terminal pool without the editor

Add `cobalt.terminal` to your Dune `libraries`. On the Async scheduler:

```ocaml
module Pool = Cobalt_terminal_pool
module Model = Pool.Model

let pool = Pool.create ()
let open_two ~cwd =
  Pool.submit pool [ 2, Model.Start { cwd; rows = 24; cols = 80 } ]
```

Run one consumer of `Pool.next_update pool`. Route each `Some (number,
generation, event)` to that number; keep the last delivered snapshot so you
can redraw it when the pane is shown again. Hiding a pane does not require
any request. A `Start` for an already-running number leaves its shell and state
intact; after exit, it starts a fresh generation. Submit `Model.Stop` to stop
just one number. When closing your host, await `Pool.shutdown pool`; the
consumer then sees `None`. The outer host owns rendering, focus, input, and
the physical terminal. See the [full contract](../../terminal/pool/cobalt_terminal_pool.mli).

## Automated example

```sh
dune runtest -j 4 examples/terminal_pool
```

[`smoke.ml`](smoke.ml) runs two real shells on Linux. Without reading any
updates, it lets one shell write far more output than the PTY can buffer,
then checks the retained screen. Reopening preserves shell state; stopping
and restarting one number leaves the other running. Shutdown reaps both
shells even when they ignore SIGHUP, kills their background jobs, and
closes the update stream.

## Link from a separate project

From Cobalt's root, with its build dependencies available, install into a
temporary prefix and build the same example outside the source tree:

```sh
work=$(mktemp -d)
unset DUNE_BUILD_DIR
dune build -j 4 @install
dune install --prefix "$work/prefix" cobalt
mkdir "$work/consumer"
cp examples/terminal_pool/{dune,smoke.ml} "$work/consumer/"
printf '(lang dune 3.17)\n(name terminal_pool_smoke)\n(implicit_transitive_deps false)\n' \
  > "$work/consumer/dune-project"
cd "$work/consumer"
export OCAMLPATH="$work/prefix/lib${OCAMLPATH:+:$OCAMLPATH}"
dune exec --root . -j 4 ./smoke.exe
if nm _build/default/smoke.exe | grep -E 'caml(Cobalt_ui|Cobalt_screen|Cobalt_app|Cobalt_hosted|Bonsai)'; then
  echo "Unexpected editor UI linkage" >&2
  exit 1
fi
```

Expected: `numbered terminal pool smoke passed` and no editor UI symbols.
The Cobalt opam package still ships the editor; the `cobalt.terminal` library
does not link it or depend on Bonsai/Bonsai_term.
