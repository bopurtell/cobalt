# CB-020: Bluespec SystemVerilog language server evaluation

**Decision:** Ship opt-in `.bsv` completion and cross-package definition jumps
with [Blues](https://docs.rs/crate/blues-lsp/0.1.4) (`blues-lsp` **0.1.4**).
Defer the ticket's open-rdma candidate, hover, and live diagnostics. Keep
highlighting and explicit BSC findings independent. This does not add a
Bluespec Classic (`.bs`) server.

## Real-project results

Tested 2026-11-22 on BSC's upstream
[AmbaAdapters](https://github.com/B-Lang-org/bsc/tree/d0ecddfd19e5b39f9d27427b7f865fbcdb14642e/testsuite/bsc.bsv_examples/AmbaAdapters)
example. `TBbaseline.bsv` instantiates an AMBA bus, two slaves and a master;
BSC 2026.07.1 (`63665af1`) built `sysM1_25` after compiling dependencies
`Interfaces`, `Buses`, `AmbaAdapters`, `Slaves` and `Masters`. The probe makes
a scratch copy with dependencies in a separate `lib/` directory, explicitly
on the BSC package path. It compares real BSC builds of saved text with LSP
requests against equivalent edits sent as unsaved, full-text overlays.

| Check | [open-rdma/bluespec-lsp at `c6e519a`](https://github.com/open-rdma/bluespec-lsp/tree/c6e519a7f852d8d990e1747d74ce3cbac3ad9fba) | Blues 0.1.4 |
| --- | --- | --- |
| Hover on `bus` declaration and imported `slaveSel3` usage | Both returned null, even with `Buses.bsv` open | Not advertised; direct request returns method-not-found |
| Definition from `slaveSel3` call in `TBbaseline.bsv:11` | No result with dependency closed; `lib/Buses.bsv:25:18` when already open | `LocationLink` to `lib/Buses.bsv:25:18` with dependency still unopened |
| Completion in the bus instantiation | Three local module names, no imported matches or `bus` | 58 distinct labels including local `bus`, imported `slaveSel3`, `bus_1m_2s`, `B1m2s` and `mkADPSlave` |
| Incomplete `mkADPSlave(` in unsaved buffer | Two parser errors; same three completions, no unopened-dependency jump | Five parser errors; same imported/local completion and unopened-dependency jump still worked at the intact bus instantiation |
| Complete `bus_2m_2` at the end of an unsaved incomplete instantiation | No imported match | Offers `bus_2m_2s` from `Buses.bsv` |
| Restore original unsaved text | Parse errors cleared | Parse errors cleared and definition still worked |

Both servers returned no diagnostics for `mkADPSlave("oops")`; BSC reported
type error `T0031` at `TBbaseline.bsv:15:31`. BSC reported one parse error
`P0005` at `TBbaseline.bsv:16:10` for the incomplete call, and the clean build
reported unused imports (`T0157`), a removed rule (`G0023`), and rule
action-shadowing (`G0117`). Neither server returned those compiler warnings.
Blues uses pull diagnostics, which Cobalt does not request for this backend.
Blues acknowledged `shutdown` but did not exit after `exit` plus closed stdin;
Cobalt's normal bounded shutdown kills an unresponsive server.

## Cobalt setup

Install Blues with `cargo install --locked --version 0.1.4 blues-lsp`. Cobalt
starts `blues lsp` over stdio for `.bsv` beneath `blues_compdb.json` or
`blues.toml`. The nearer marker directory is the root; unconfigured BSV stays
server-free. Use `BLUES_LSP=/absolute/path/to/blues` to override PATH discovery.

Add a `blues_compdb.json` in the project root with the project's own BSC
arguments. For the split AmbaAdapters layout:

```json
[
  {
    "directory": ".",
    "arguments": [
      "bsc", "-u", "-verilog", "-g", "sysM1_25", "-p", "+:lib",
      "-bdir", "build", "-vdir", "build", "-info-dir", "build", "TBbaseline.bsv"
    ]
  }
]
```

Blues uses the command to read source paths/flags and locate the installation's
`lib/`; use the real `bin/bsc` on PATH (or its absolute path in the database).
The compile database is not a request for Cobalt to run a build, and is not
generated automatically. `blues.toml` can select an alternate database via
`compdb_path`. In Cobalt, use `gd`/`gD` on an imported name, `Ctrl-n` in Insert
mode for completion, and `Space l i` to see whether Blues is attached. Do not
expect compiler-equivalent validation, type-aware completion, or hover.

## Integrated Cobalt verification

With the built Cobalt binary, Blues 0.1.4 and BSC 2026.07.1 (tmux 3.6), the
terminal smoke showed `blues#1` running at the configured root with only
`TBbaseline.bsv` attached. In the incomplete unsaved bus instantiation, the
menu showed `bus_2m_2s [LSP]`; accepting it changed the editor buffer without
saving the file. After undo, `gD` on `slaveSel3` opened the previously unopened
`lib/Buses.bsv` at `25:18`. `Ctrl-o` returned to `TBbaseline.bsv:11:30`.
Cobalt exited with code 0, restored the PTY settings, and left both files
unchanged. Captures: `/tmp/opencode/cobalt-bsv-smoke-a2cfn9ks`.

The backend selection test passed with `BLUES_LSP` unset and with an explicit
invalid override. It also verifies that unconfigured `.bsv` and Classic `.bs`
select no server, `.sv` still selects Slang, and a nearer `blues.toml` overrides
an ancestor `blues_compdb.json`.

## Reproduce

With a BSC source checkout and the released compiler separately installed:

```sh
export BSC_EXAMPLE=/path/to/bsc/testsuite/bsc.bsv_examples/AmbaAdapters
export BSC_BIN=/path/to/bsc-install/bin/bsc
python3 scripts/bsv_lsp_probe.py --expect-blues --example "$BSC_EXAMPLE" \
  --bsc "$BSC_BIN" -- blues lsp --log stderr
dune build bin/cobalt.exe
python3 scripts/bsv_lsp_smoke.py --example "$BSC_EXAMPLE" --bsc "$BSC_BIN"
```

For the open-rdma comparison, build its pinned `bsv-language-server` crate
with `cargo build --release --locked` (Tree-sitter CLI 0.20.8 and Node on PATH),
then pass that executable after `--` without `--expect-blues`. The probe
prints the retained scratch directory containing `bsc-*.txt`,
`server.stderr`, `wire.jsonl`, and `report.json`. The real comparison runs used
`/tmp/opencode/cobalt-bsv-lsp-snosqz57` (Blues) and
`/tmp/opencode/cobalt-bsv-lsp-4y95_a0w` (open-rdma). The Cobalt smoke uses
`tmux` and retains screenshots as pane text in its scratch directory.
