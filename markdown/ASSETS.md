# Optional Markdown provider assets

## Provenance and licenses

Both grammars are from
[tree-sitter-grammars/tree-sitter-markdown](https://github.com/tree-sitter-grammars/tree-sitter-markdown),
commit **`41ff24a6c775492c543b09228aeb98d1cd2b3a0f`**.
Their generated `src/parser.c`, external `src/scanner.c`,
`src/tree_sitter/parser.h`, and `src/node-types.json` are vendored unchanged.
The generated parsers are stored as deterministic-timestamp gzip files, matching
the existing GAS/SystemVerilog C/Dune convention. No grammar generation, network,
Node, Tree-sitter CLI, or sibling checkout is needed to build or run this feature.
No upstream highlighting queries are copied; the structural adapter is
Cobalt-authored.

- `LICENSE.markdown`: upstream MIT license, copyright Matthias Deiml.
- `LICENSE.tree-sitter`: upstream Tree-sitter MIT notice for generated parser
  headers and the public runtime API header (also verified against Tree-sitter
  v0.25.10's license).
- `LICENSE.tree-sitter-binding`: ISC notice shipped with the installed
  `tree-sitter.0.1.0` OCaml binding.
- `tree_sitter/api.h`: copied unchanged from the installed package source's
  `tree-sitter/include/tree_sitter/api.h`, SHA-256 recorded below. This is the
  matching public header, not the runtime implementation or a private OCaml
  binding header. The runtime continues to come from the normal `tree-sitter`
  package dependency.

The build expands each `parser.c.gz` using gzip and compiles its parser, scanner
and tiny language-address binding. Everything new is inside `markdown/`.
`cobalt_markdown` is standalone; the host may optionally select it by library
availability, and the whole directory may be removed without introducing any
required language to Cobalt core.

## ABI and included ranges

Both pinned parsers use **language ABI 15**. The installed `tree-sitter.0.1.0`
runtime public header accepts ABIs **13–15**. Its OCaml interface already exposes
`Parser.set_included_ranges` and `Tree.included_ranges`, with document-wide byte
offsets and byte-column points. No mandatory binding changes are needed.

The feature-local native adapter uses public runtime APIs rather than relying on
the OCaml binding's private representation. This adds explicit parser deletion
for `Provider.close` and parser timeouts, which the installed OCaml API lacks.
Its finalizer is an idempotent fallback. Creation is lazy; parsers are allocated
only after key, size, line and UTF-8 validation. All native trees are deleted
before returning; no node/tree/native handle escapes into a snapshot.

The block grammar runs first. Each `inline` node and each `pipe_table_cell`
receives one inline parse with included ranges in the **original document**,
excluding grammar-provided `block_continuation` children. All inline spans are
clipped back to those ranges so emphasis/code spanning lines does not style
excluded quote/list continuation prefixes. This preserves multiline context
without reparsing individual lines or inventing offset translations. Fenced and
indented code blocks never enter the inline grammar. There is no regex Markdown
parser and no query engine/capture buffer.

## Behavior and bounds

`Cobalt_markdown.Provider` exposes the API in `provider.mli`. It emits only
generic `Snapshot.Operation.Style` ranges. It never hides punctuation/URLs,
replaces text, fetches images/HTML, embeds languages, highlights code internals,
or changes formatting. Reference links are conservative: explicit inline links
have distinct label/destination styles; unresolved shortcut/reference link
labels are not guessed. Explicit definition destinations can be styled without
resolving references.

The pinned generated grammar includes GFM **pipe tables and task lists**.
Table cells receive normal inline parsing, but table geometry, alignment,
concealment and virtual rows remain deferred. Escaped and code-contained pipes
are kept verbatim, including malformed table input; parser recovery is not a
promise of complete CommonMark/GFM conformance.

Every decoration has hard bounds of:

- 256 KiB UTF-8 source, 4096 logical lines (LF count plus one);
- 4096 style operations, 65536 syntax visits, cursor depth 1024;
- 4096 inline parser calls and 8192 included-range fragments per document;
- 4097 fragments in any one inline block;
- a shared 100 ms native parse/walk deadline using a monotonic clock and
  Tree-sitter timeouts. Timeout checks are cooperative, not a real-time guarantee
  for one indivisible scanner/runtime step.

AST walks are iterative in C, not recursive OCaml walkers. Failures return a
single `Error`, not partial captures or a previous snapshot. Expected
`Failure`/`Invalid_argument` exceptions are converted; fatal exceptions such as
out-of-memory are not swallowed. Parser state is reset after failure and the
same provider may recover on the next valid document.

`parse_count` counts actual block parse attempts (including failed native
parses); `inline_parse_count` counts actual included-range inline parse attempts.
Validation rejections do not increment either counter. The provider deliberately
does not cache snapshots: document identity/revision, cursor/resize reuse and
provider lifecycle are the host's responsibility.

## Tests and latency probe

After obtaining the shared Dune build lock, from the repository root:

```sh
opam exec --switch=5.2.0+ox -- dune build -j4 markdown/cobalt_markdown.cmxa
opam exec --switch=5.2.0+ox -- dune runtest -j4 markdown/test
opam exec --switch=5.2.0+ox -- dune exec -j4 markdown/probe/latency.exe
```

Tests cover heading levels, setext, emphasis/strong, source punctuation, link
label/destination separation, checkboxes/lists, fences, UTF-8 byte offsets,
multiline quote/list continuations, GFM tables, escaped/code-contained pipes,
malformed syntax, invalid UTF-8 and keys, source/line/operation/nesting limits,
recovery and idempotent close. The probe prints cold/warm synchronous wall/CPU
timings with **actual** block/inline parse deltas, including failure cases.
Timing results should be measured on the target machine; they are not implied
by the configured deadline.

### Measured validation (2026-11-18)

Targeted `dune runtest -j4 markdown/test` passed all **13** tests against the
installed OCaml 5.2.0+ox / tree-sitter 0.1.0 environment. The synchronous probe
reported the following single-run wall/CPU timings; these are observations, not
a performance guarantee or statistical benchmark:

| Probe | Bytes | Wall ms | CPU ms | Block / inline parses | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| Representative cold | 6090 | 7.461 | 6.958 | 1 / 81 | 481 styles |
| Representative warm | 6090 | 6.311 | 6.309 | 1 / 81 | 481 styles |
| Multiline quote | 36 | 0.054 | 0.054 | 1 / 1 | 4 styles |
| Fenced only | 21 | 0.020 | 0.020 | 1 / 0 | 1 style |
| Invalid UTF-8 | 1 | 0.002 | 0.001 | 0 / 0 | Validation error |
| Over byte limit | 262145 | 0.002 | 0.001 | 0 / 0 | Source limit error |
| Operation limit | 16388 | 30.974 | 30.173 | 1 / 1 | Operation limit error |
| Inline-call limit | 20504 | 16.045 | 15.621 | 1 / 4096 | Inline parse limit error |
| Deep inline nesting | 4402 | 86.001 | 84.109 | 1 / 1 | Syntax depth limit error |
| Deep blockquote | 2202 | 2.321 | 2.320 | 1 / 1 | 254 quote styles |

The last case exercises the upstream block scanner's own nesting ceiling: it
stops opening additional blocks and treats remaining markers as text. The inline
nesting case exercises the adapter's independent cursor-depth gate. Every failed
decoration returns an error without stale/partial output; tests verify recovery
with a subsequent valid parse.

## SHA-256

Expanded parser hashes are authoritative independently of gzip/zlib versions.
The gzip timestamp is zero.

| Asset | SHA-256 |
| --- | --- |
| block expanded `parser.c` | `65f50b1ecda5978d4926690cf69a2b655d53b2523de2cc4d98ff11c3e0831dd9` |
| `block_grammar/parser.c.gz` | `cefc9e7849477fe768f70489e36549179aea99b157cf3665641a7aa4640cae6f` |
| `block_grammar/scanner.c` | `b4db01bb55acba0c1ccacf78450d1f58cde4a1bcbf4de0ea0afe64c39fc6b311` |
| `block_grammar/node-types.json` | `a31703f82a614503639321fc75f34b121fb81086ba1f0b213df63f410d4ca94f` |
| inline expanded `parser.c` | `d3522438b8bd46b519ba243c9ba84b83803feee77607a38105c3a2b63caac49c` |
| `inline_grammar/parser.c.gz` | `d90b28fddcaae8e83cef9f21496872468dbb664ea83cf56ec1355a2b8be7d643` |
| `inline_grammar/scanner.c` | `d356c4bbd9c3b3f4785476124c8b2322030eb876dd525b761e0fc51253001060` |
| `inline_grammar/node-types.json` | `701b6163dced608181dd633b4e548d8fe1520ae9ad40d7d584cb0c814c056a2c` |
| each grammar's `tree_sitter/parser.h` | `180b893c8734778fd32f372dfbc27bd6ad1cd2221f26150b31256ff6716320d2` |
| `tree_sitter/api.h` | `937c5389713f99318ac7adbdb3a95e9976bbd211e35e37ed5df878f29aa86c30` |
