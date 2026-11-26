# Development

[Documentation index](README.md) · [Architecture](architecture.md) · [Project status](project_status.md)

## Toolchain

Development uses the OxCaml opam switch `5.2.0+ox` and Jane Street
`v0.18~preview` packages. The project declares Dune language version 3.17 and
pins `tree-sitter` to 0.1.0. This is a locally maintained toolchain rather than a
general-purpose installation recipe; package declarations live in
[`dune-project`](../dune-project).

The bundled SystemVerilog and GAS parsers require a C compiler and `gzip` at
build time. The GAS grammar is GPLv3, with local patches; see
[`ASSETS.md`](../highlight_tree_sitter/gas_grammar/ASSETS.md) for provenance,
notices, regeneration, and distribution implications.

Picker libraries additionally use Async, Yojson, and Base64. File/content
provider tests and probes require `rg` on `PATH`; neither `fzf` nor ripgrep is
needed for ordinary editing or the command palette. Tile Terms vendor libvterm
0.3.3 and do not require a system libvterm installation; see its
[provenance](../terminal/VENDOR.md).

## Build and run

With the local switch active, run from the repository root:

```sh
dune build -j 12
dune runtest -j 12
dune exec -j 12 cobalt -- PATH
```

The executable is `_build/default/bin/cobalt.exe`. A local shell command or symlink
can expose it as `cobalt`.

For relocatable Linux download archives, use
`python3 scripts/package_release.py --version snapshot --strip -j 6`.
See [release packaging](releases.md) for platform requirements, source selection,
verification, optional runtime tools and remaining distribution-audit work.

`cobalt.opam` is generated from `dune-project`; package metadata changes belong in
`dune-project`.

For a regular user install, see [Install Cobalt from source](source-install.md).
The opt-in installer smoke builds from a fresh private source copy, keeps HOME
and XDG state private, and uses your existing switch read-only. It exercises the
real installed commands and checks the separate hosted consumer (requires
`bonsai_test` in that switch) and a terminal edit from an unrelated directory:

```sh
python3 -B scripts/source_install_smoke.py --switch 5.2.0+ox --jobs 4
```

This Linux smoke uses Python 3.11+ and PTYs. Use `--scratch-dir` to choose a
filesystem with enough space for the fresh build.

Keep the combined job pool at **20 or fewer** across concurrent commands. The
commands here leave headroom; reduce `-j` further when other builds are running.

## Native CI

[Cobalt native CI](https://github.com/bopurtell/cobalt/actions/workflows/ci.yml)
runs on pull requests and pushes to `oxcaml`. Updating a PR cancels its
superseded run. On Ubuntu 24.04, CI restores an exact match for the compiled
OxCaml switch or provisions it using the
[pinned repository snapshots](../scripts/ci/toolchain.sh) and
[Cobalt's package manifest](../cobalt.opam). Only the dedicated opam root is cached, under
the same absolute path and runner identity. Every run builds the checked-out
source into a fresh `_build` and tests that binary.

To reproduce the build and regression steps with the
[development switch](source-install.md#prerequisites), install the test
dependencies if needed, then run the same check as CI:

```sh
opam install --switch=5.2.0+ox --deps-only --with-test .
opam exec --readonly --switch=5.2.0+ox -- bash scripts/ci/check.sh
```

The timed commands, in order, are:

```sh
dune build --root . -j 2
dune runtest --root . -j 1 --force
dune build --root . -j 1 @smoke @scripts/smoke-markdown
python3 -B -m unittest discover -s packaging/tests -p test_package_release.py
```

The terminal suites use tmux and PTYs; the check script gives them an empty
`XDG_CONFIG_HOME` so personal Cobalt settings do not change the screens under
test. The LSP and Silver checks use local
fixtures, without a graphical desktop or running service. For interoperability
with a separately built Silver daemon and client, see the
[live acceptance commands](../examples/silver_overview/README.md).
Run `python3 -B scripts/ci/test_cache.py` for the offline CI policy checks and
`actionlint .github/workflows/ci.yml` for workflow lint.

**Confirm a miss and a hit:** the first push to `oxcaml` with a new toolchain
key should miss in **Restore exact toolchain**, run **Provision compiler and
third-party dependencies**, and report a successful save. After it finishes,
choose **Actions → Cobalt native CI → Run workflow**, select `oxcaml`, and leave
**Benchmark cold provisioning** unchecked. Look for the same key, an exact
restore hit, **Verify restored toolchain** instead of provisioning, and a fresh
build and test. A source-only push can serve as the second run too. Compare
total job durations (including cache transfer) and the individual phase timings.
If the keys differ, check for runner image or system package updates as well
as changes to the dependency inputs.
PRs can restore eligible caches; only non-PR `oxcaml` runs publish misses.
For a cold timing independent of existing caches, check the benchmark box:
that run neither restores nor saves.

## Terminal smoke tests

The headless test suite covers editing, input, file I/O, highlighting, screen
geometry, terminal emulation, and frontend behavior. Real-terminal smoke tests
are separate from `dune runtest` and exercise screen output, saved bytes, process
cleanup, and outer-terminal restoration.

They use tmux or PTYs and require the relevant tools on `PATH`: `tmux`, Python 3,
Bash, Git, ripgrep, and a UTF-8 locale. Some scenarios also use fake language-server
fixtures built by Dune.

```sh
# Every smoke suite, serialized by a shared lock:
dune build -j 4 @smoke

# Headless tests plus all smoke suites:
dune build -j 4 @test-all

# Individual suites:
dune build -j 4 @scripts/smoke-terminal
dune build -j 4 @scripts/smoke-theme
dune build -j 4 @scripts/smoke-embedded-terminal
dune build -j 4 @scripts/smoke-directory
dune build -j 4 @scripts/smoke-picker
dune build -j 4 @scripts/smoke-vcs
dune build -j 4 @scripts/smoke-lsp

# Optional Markdown styling and the explicit no-provider executable:
dune build -j 4 @scripts/smoke-markdown
```

The Markdown smoke isolates HOME/XDG state and uses a private tmux server. It is
a separate opt-in target, not part of the historical default `@smoke` aggregate.
`python3 scripts/smoke_no_markdown.py --jobs 6` additionally builds a temporary
source copy without `markdown/` and exercises the stub-selected CLI. Neither
command edits source files or personal configuration.

Run `python3 -B scripts/smoke_no_silver.py --jobs 4` to build the production
executable in a temporary source tree without `silver_overview/` and exercise
ordinary editing, saving, quitting, and the handling of Silver-only flags.

After building, scripts can also be run directly:

```sh
scripts/smoke.sh
scripts/smoke.sh --bare-only
scripts/smoke.sh --palette-only
python3 scripts/directory_workspace_smoke.py
python3 scripts/picker_smoke.py
python3 scripts/theme_smoke.py
python3 scripts/terminal_smoke.py
python3 scripts/vcs_smoke.py
python3 scripts/lsp_smoke.py
```

The LSP smoke uses deterministic fake servers by default. To exercise installed
`ocamllsp` and `slang-server` together through the real frontend, run
`python3 scripts/lsp_smoke.py --real`. To check only the managed backend inventory,
run `dune exec -j 6 source/bench/mixed_lsp_probe.exe`.

With Rust, Cargo, and `rust-analyzer` installed, run
`dune exec source/bench/rust_lsp_probe.exe` to exercise diagnostics, hover,
completion, and cross-crate definition navigation on real projects. For BSV,
see the [Blues/BSC probe and Cobalt terminal smoke](backlog/bsv_language_server_evaluation.md#reproduce).

The VCS smoke suite uses a sandbox repository created by
[`scripts/vcs_sandbox.sh`](../scripts/vcs_sandbox.sh). Its scenarios exercise
staging, commits, a conflict-stopped rebase pull, pushing, and history, and check
the resulting Git state. See [VCS manual tests](testing/vcs_manual.md) for remaining
human checks.

Visual checks and the `ppx_expect` source-path workaround are documented in the
[editor reference](editor_reference.md#terminal-smoke-test). Historical validation
and outstanding acceptance work are recorded in [project status](project_status.md#validation-and-handoff).
