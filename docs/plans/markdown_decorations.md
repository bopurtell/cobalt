# Optional document decorations and Markdown rendering

[Implementation plans](README.md) · [Architecture](../architecture.md)

Status: milestone 1 implemented, 2026-11-17; verification recorded below.
Milestones 2–4 remain proposed and outside the current implementation scope.

## Goal and architectural decision

Make Markdown more pleasant to read inside the editor: styled headings and links,
code-block backgrounds, and eventually visually aligned pipe tables and shortened
links. Preserve normal source editing, not a second rich-text document model.

**Build a small display-only decoration layer first. Put Markdown interpretation
in a separate, optional feature library.** This need not be a dynamically loaded
plugin, but it must not become a vital organ of the editor.

The first implementation should stop after milestone 1 below. Later milestones
are separately reviewable work, not permission to implement the entire plan.

## Binding constraints

1. No Markdown or decoration dependency in `core/` or `input/`. Motions,
   transactions, registers, undo, source offsets, save, and LSP positions retain
   their existing meanings. Decorations never rewrite or format the buffer.
2. Normal editing works with the feature disabled, failed, unsupported, or not
   compiled into the executable. Disabled is not the same test as unlinked.
3. Plain rendering remains an explicit path using the existing indexed layout.
   Do not make an empty decoration provider run before every plain-text redraw.
4. Provider output is immutable, revision-keyed data. No parser trees, callbacks,
   I/O, or arbitrary provider code inside the frame renderer.
5. A failed provider may remove decoration, never the ability to edit, save,
   navigate, or open the document. Do not display stale decorations on new text.
6. Reuse Cobalt's cell widths, control-character escaping, theme semantics,
   selection precedence, and clipping. Do not introduce another Unicode-width
   implementation or interpret source/provider text as terminal escape sequences.
7. No general plugin manager, scripting runtime, dynamic loading, global event
   bus, or broad editor refactor as a prerequisite.

## Existing integration points

These observations describe the code inspected for this plan:

- `screen/frame.ml` renders document lines from `Text_buffer.line_layout` through
  `Cell_layout.Index.window` and `Span.of_glyphs`, applying syntax and interaction
  styles using source positions.
- `screen/span.mli` defines styled cell runs and clipping/overlay operations.
  It is a rendering primitive, not a source-to-screen mapping.
- `screen/ui_state.ml` computes cursor cells, fitted scrolling, and screen cursor
  placement from the raw source layout. Changing only drawn text would break this
  agreement.
- `screen/scroll.mli` represents vertical position in document lines and horizontal
  position in display cells. Preserve the line-based vertical model initially.
- `core/cell_layout.mli` is also used for editing semantics. Extend presentation
  beside it, not by teaching this core module about Markdown.
- `highlight/language.ml` currently has no Markdown case. Existing highlighting
  snapshots describe syntax styles, not insertions, concealment, or table layout.
- `highlight_tree_sitter/provider.mli` keeps native parsing private and publishes
  immutable, freshness-keyed snapshots. Reuse that ownership pattern, not
  necessarily its syntax-only result types or language dispatch.
- `docs/long_line_rendering.md` and `screen/test/test_long_line.ml` establish
  sparse/windowed rendering guarantees that the plain path must keep.

## Proposed boundaries

Names and exact signatures are provisional; the dependency directions are not.

| Piece | Responsibility | Must not own |
| --- | --- | --- |
| `decoration/` (`cobalt_decoration`) | Small pure snapshot/range/operation model and validation | Markdown, parsers, terminal APIs, mutable editor state |
| `screen/` adapter | Convert validated operations into existing spans; later project positions | Parsing, Markdown syntax recognition, provider callbacks |
| `markdown/` (`cobalt_markdown`, optional) | Recognize Markdown and emit generic decoration data | Screen geometry, editor commands, file saving |
| Feature host/composition adapter | Own provider sessions, request work, validate freshness, deliver snapshots | Core editing rules |
| Executable wiring | Choose Markdown-enabled or no-provider composition | Mandatory imports of Markdown from baseline libraries |

Suggested flow:

```text
current source + identity/revision -> optional Markdown provider
                                   -> immutable decoration snapshot
                                   -> validation/freshness gate -> screen adapter
raw source ----------------------------------------------------> plain rendering
```

The screen may depend on the small generic data model, just as it depends on span
and geometry types. It must not depend on `cobalt_markdown` or Markdown grammars.
The model must remain usable without any provider. The host belongs at the
composition boundary; do not add Markdown dispatch to the mandatory application
controller just because highlighting is currently coordinated there.

Start with one optional snapshot per document and one provider. No extensible
registry or multi-provider arbitration until a real second consumer needs it.

### Actual optionality

- **Runtime off:** no Markdown parser creation, parse work, or projection-cache
  allocation. Ignore/discard in-flight results after disabling.
- **Runtime failure:** reject stale/invalid output, clear affected decoration,
  retain ordinary rendering. Surface a bounded feature-status message rather
  than one notification per redraw.
- **Build without Markdown:** a tiny no-provider adapter implements the host
  boundary and returns no snapshots. No Markdown parser/grammar dependency is
  reachable from this executable's dependency closure.
- Select the real or no-provider wiring at build/composition time. Prototype and
  test the Dune wiring before committing to a particular `select`/target scheme;
  library absence alone is not a sufficient feature-selection design.
- Config for an unavailable optional feature should produce an "unavailable in
  this build" status, not abort startup or invalidate unrelated settings.
- No dependency on the reference checkouts in `~/devel/`. If a grammar is adopted,
  pin/package it explicitly and include licenses and release assets normally.

The removability test is concrete: remove the Markdown library and grammars from
the build inputs, select the no-provider adapter, then build and exercise baseline
editing. Do not claim optionality from a Boolean toggle alone.

## Milestone 1 — the small decoration layer, and nothing more

Deliver a parser-independent foundation with synthetic fixtures. No real Markdown
provider, grammar integration, table alignment, link concealment, new user config,
or plugin framework in this slice.

### Minimal data contract

- Snapshot key: document identity, source revision, provider identity/version.
  Reopening, switching buffers, or reconfiguring must not reuse the wrong result.
- Sorted half-open UTF-8 source-byte ranges, with an explicit document-wide
  coordinate convention.
- Two operations only: style a source range; replace a same-line range with
  display-only text occupying **exactly the same cell width**.
- A small closed vocabulary of presentation roles mapped to screen/theme styles.
  No hard-coded provider RGB, mandatory Nerd Font, or serialized terminal attrs.
- Validate bounds, UTF-8 boundaries, operation counts, replacement lengths, and
  overlap rules. First version rejects overlapping replacements instead of
  inventing a priority system. Define stable precedence for style overlap.
- The screen validates same-cell-width replacements using its width function and
  the original starting column. Initially exclude replacements touching tabs,
  escaped controls, or combining-sequence boundaries; fall back rather than
  guessing at these cases.

Implementation scope refinement: the first screen adapter accepts only one source
scalar replaced by one display scalar of the same positive cell width, and both
must belong to a conservative context-free glyph subset. Width equality alone
does not prevent forming a new emoji/grapheme cluster with adjacent text or
another replacement. Preserve the original glyph's source offset and column
without introducing a multi-character projection; reject unsupported geometry
atomically even if the pure model accepts it. Generic roles start as
`Accent`, `Literal`, and `Muted`, mapped to existing semantic syntax colors rather
than adding Markdown-specific theme fields.

Replacement preparation also checks immediate same-line source neighbors against
the conservative glyph subset. Some combining/spacing marks have positive cell
width, so checking only for zero-width neighbors is not enough. This restriction
applies to substitutions, not to ordinary source rendering or range styling.

Keep source provenance alongside replacement display text. Do not manufacture a
new `Text_buffer`, reuse rendered offsets as source offsets, or place virtual
characters in the editor's text cache. Drawing a replacement is not an edit.

### Rendering and interaction

- No/empty/rejected snapshot selects the existing plain renderer.
- Valid snapshots are intersected with visible source lines and clipped using
  existing span/cell rules. Do not materialize all glyphs of long lines.
- Width-preserving replacements leave source cursor geometry unchanged. Reveal
  the original range on the cursor line; use raw presentation throughout Visual
  mode and block insertion for this first slice.
- Interaction overlays remain authoritative: selection, search matches, insert
  points, and cursor visibility must not be masked by decoration colors.
- No change to document-line count, gutter numbering, status cursor columns,
  scrolling semantics, or editor preferred-column behavior.

### Acceptance gate

- Synthetic range styling and a one-cell bullet substitution render correctly.
- No-provider, disabled, empty, stale, invalid, and failed results produce the
  same frame and cursor as the undecorated baseline for the same editor state.
- Rendering/toggling changes no buffer bytes, revision, dirty flag, history,
  selection, register, or saved output.
- Existing Unicode, clipping, scroll, selection, snippet/block insertion,
  completion-anchor, and long-line regressions pass.
- Warm plain rendering performs no provider work and keeps existing bounded
  window-allocation behavior.
- Headless tests run without Markdown grammars or reference repositories.

**Stop here and review the API and dependency graph.** A useful decoration seam
is the outcome; Markdown polish is not required to justify this slice.

### Milestone 1 implementation notes

The generic API lives in `Cobalt_decoration.Snapshot`:

- Opaque document identities and keys covering revision, provider/version, and
  configuration/generation.
- Atomic snapshot construction from source bytes and bounded operations. Default
  limits are 16 MiB source, 4096 operations, 4096 bytes per replacement, and 65536
  total replacement bytes; callers can supply other nonnegative limits.
- Immutable operation and style indexes. Overlapping replacements are rejected;
  the shortest covering Style wins, then `Accent`, `Literal`, `Muted`. Input
  ordering does not affect precedence.
- No source bytes, parser, or terminal types retained in the pure model.

`Cobalt_screen.Decoration.prepare ~source snapshot` accepts the actual immutable
`Text_buffer.t`, validates the conservative substitution geometry, and returns
either prepared data or an error. Unlike the pure model, the prepared value keeps
a reference to that exact buffer object as provenance; callers must release
obsolete prepared values. No global cache or editor-history reference is added.

`Frame.render ~decorations:(expected_key, prepared)` is the explicit opt-in seam.
Omitting the argument is the no-provider/disabled/failed path. Key/revision/source
object mismatches and empty snapshots fall back to normal rendering; equal-length
or even equal-byte independently reconstructed buffers are not sufficient.
The caller still owns the independent current document/configuration key.

The active source line, Visual modes, block insertion, and directory surfaces
stay raw. Replacement roles override range styles, which override existing syntax
colors; interaction overlays remain authoritative. Existing `Style` and frontend
theme types are unchanged.

The initial substitution allowlist is printable ASCII, Latin letters in
U+00C0–00D6/U+00D8–00F6/U+00F8–02AF, bullet U+2022, box drawing U+2500–257F,
and CJK unified ideographs U+3400–4DBF/U+4E00–9FFF. It applies to both substitution
endpoints and their immediate source neighbors on the same line. Unsupported
characters remain fully editable/renderable as ordinary source and can still
receive range styles; unsupported substitution snapshots are rejected as a unit.
Tests cover the emoji-modifier, regional-indicator, adjacent-substitution, and
positive-width SpacingMark cases that motivated this conservative restriction.

There is intentionally no production provider, user toggle, parser dependency,
or decoration-aware `Frame.Cache` lifecycle yet. Normal launches remain
undecorated. A future host must explicitly supply data and address caching and
no-provider build wiring in milestone 2, rather than silently expanding this API
into a global service.

### Milestone 1 verification

- `dune runtest -j 4 test` passed for baseline core/input/application behavior.
- `opam exec --switch=5.2.0+ox -- dune runtest -j4 screen/test` passed, including
  18 synthetic decoration integration tests.
- `dune build -j 6 @all` passed. Existing `unsafe_multidomain` alerts in
  `source/test/test_lsp_client.ml` concern environment mutation in that unchanged
  test file.
- `dune runtest -j 4` passed across the project. The preceding `-j 6` run hit a
  startup-configuration PTY timeout while waiting for exit; both its isolated
  `python3 bin/test_configuration_cli.py _build/default/bin/cobalt.exe` rerun and
  the subsequent full test invocation passed without source/test changes.
- Terminal and theme smoke suites passed with personal configuration isolated as
  described below. The full terminal script reported `smoke: all checks passed`.
- `git diff --check` and whitespace checks on new files passed.

The tests cover semantic role precedence, source-offset search overlays, cursor
line/mode reveal, key/revision/buffer provenance, save bytes and undo/register
invariants, unsafe Unicode/context rejection, CJK/box-drawing clipping, tiny
viewports, and bounded warm long-line index work. Pure snapshot tests cover
validation/budgets, ordering, overlap rejection, and index/lookup oracles.

For a focused rerun, use `dune runtest -j 4 decoration/test screen/test`.
The synthetic examples are in `screen/test/test_decorations.ml`; no Markdown
checkout, parser installation, or user configuration is needed.

The existing terminal/theme smoke scripts inherit personal configuration.
An initial smoke run failed because the local configuration starts with hybrid
line numbers enabled, whereas the scripts assume numbers start off. Their
setup toggles consequently disabled the gutter and invalidated later cursor
assertions. The theme smoke also observed configured Bare-mode line numbers.
No personal settings or smoke scripts were changed. The theme smoke passed with
an empty temporary configuration directory:

```sh
config_home=$(mktemp -d /tmp/opencode/cobalt-smoke-config.XXXXXX)
trap 'rmdir "$config_home"' EXIT
XDG_CONFIG_HOME="$config_home" dune build -j 4 @scripts/smoke-theme
```

`scripts/smoke.sh` additionally starts its shell with `env -i HOME=$HOME ...`,
which drops `XDG_CONFIG_HOME` and reintroduces the personal HOME fallback. Setting
only `XDG_CONFIG_HOME` therefore did not isolate that suite. Its successful
isolated rerun used the already-built executable and fake LSP fixture with a
temporary HOME:

```sh
smoke_home=$(mktemp -d /tmp/opencode/cobalt-smoke-home.XXXXXX)
HOME="$smoke_home" TMPDIR=/tmp/opencode bash scripts/smoke.sh _build/default/bin/cobalt.exe
```

Allow more than 120 seconds for both suites; the first bounded invocation was
interrupted by the outer command timeout before the scripts completed.

## Milestone 2 — optional Markdown styles, still source-shaped

Add the optional provider and prove no-provider build wiring before enabling it.
Initially opt-in. Recognize `.md`/`.markdown` at the feature boundary, with an
explicit future override for extensionless documents; do not make core know file
types. File-name changes must invalidate eligibility.

Start with heading levels, emphasis, inline code, fenced code backgrounds,
link-label/destination styling, quotes, and bullets/checkboxes where geometry
stays unchanged. Keep source punctuation and URLs visible. No image fetching,
external helpers, arbitrary HTML rendering, or automatic link opening.

Use Tree-sitter Markdown as an editing-oriented parser, not an authoritative
CommonMark renderer. It has separate block and inline grammars: first verify
included-range support in Cobalt's installed OCaml binding, offset translation,
grammar ABI compatibility, and GFM pipe-table configuration. Isolate any needed
binding adapter in the optional parser feature; do not solve this by regular
expressions pretending to parse all Markdown.

Keep native parser sessions outside editor history and render state. Separate
source-dependent parse results from view-dependent reveal/render policy so a
cursor move or resize does not reparse unchanged text.

## Milestone 3 — explicit display projection

This is the real complexity increase. Add width-changing insertions/replacements
and concealment only after defining and testing a presentation projection.

The projection associates displayed cells with source ranges or anchored virtual
content. Specify source-byte-to-display-cell lookup, synthetic-cell anchors, EOL
behavior, and boundary bias for concealed ranges. Reverse lookup, if exposed,
must return an anchor/range rather than pretend the mapping is one-to-one.

One effective projection/policy must drive drawing, cursor/overlay placement, and
any display-based scroll calculation. Do not let frame drawing and
`Ui_state.cursor_position_in` independently decide what is hidden. Cache by
document/revision, provider configuration, width rules, and relevant view policy;
resize must not reuse width-dependent layout from another viewport.

Conservative first policy:

- Normal mode: decorate away from the active source line.
- Inside a table: reveal the **entire table** as raw text, not one unaligned row.
- Insert, Visual modes, block insertion, and active search prompt: raw document.
- Invalid/unknown block boundaries: raw presentation for the uncertain content.
- No soft wrapping, virtual rows, collapsed blocks, or changed document-line
  numbering. Retain one source line per screen row.

Core motions and preferred columns remain source-based. Moving onto a decorated
line reveals it before cursor placement, so the cursor never edits invisible
punctuation. This may cause visible reflow; document and test it rather than
quietly redefining `j`/`k`, block selections, or status columns.

Do not hide the visible escape forms Cobalt uses for unsafe/control characters.
Whole-replacement display text must pass the same safety mapping as source text.

## Milestone 4 — shortened links and aligned tables

### Links

Render labels with link styling, optionally concealing destination/punctuation
away from the cursor. Cover inline, reference, autolink, escaped, and nested
inline-content cases incrementally; uncertain syntax stays raw.

Link following is a separate command/security feature, not part of rendering.
No browser launch, network request, or terminal hyperlink escape generation is
needed for this milestone.

### Pipe tables

- Parse the containing table, including header/delimiter/body rows, alignment
  markers, missing cells, escaped pipes, and code spans containing pipes.
- Compute column widths from **effective rendered cell content**, including
  concealed links, using Cobalt's cell-width rules rather than string length.
- Pad visually and replace existing separators with border characters. Do not
  pad/reformat the actual Markdown or add top/bottom virtual border rows yet.
- Prefer minimal expansion: preserve content and alignment; clip/horizontally
  scroll wide output. Never silently truncate source data to fit the viewport.
- Cap table size, cell width, generated padding, and decoration count before
  allocating output. Oversized or ambiguous tables fall back as a whole.
- When only part of a table is visible, measure its bounded containing block,
  not only the visible rows. Crossing a context limit must fall back, not produce
  inconsistent column widths.
- Avoid alignment jumpiness by keeping all table rows raw while the cursor is in
  the table. Table-editing commands and automatic formatting are separate work.

## Freshness, work budgets, and failure containment

- A result is publishable only for the current document identity, revision,
  provider/configuration generation, and enabled state. Test out-of-order results,
  undo/reload, rapid edits, tab switches, close/reopen, and disable/re-enable.
- Bound eligible file bytes/lines, parse captures, decoration operations, table
  context, output cells, and retained per-document cache memory. Choose numerical
  defaults from probes before enabling the provider by default.
- Full-document parsing can initially be allowed only below an explicit source
  size limit. "Visible rendering only" does not mean parsing was bounded.
- Never parse in `Frame.render`. Initially use bounded eligible inputs and
  measure latency; if parsing blocks input, use a host worker/coalesced requests.
  A synchronous parser call cannot be made safely interruptible by merely
  checking elapsed time after it returns.
- Reject malformed snapshots atomically; valid but unsupported blocks can stay
  raw. Expected provider errors clear its output and disable/retry the feature
  without catching unrelated editor failures.
- In-process error handling cannot contain a native parser crash. Optional
  linkage limits the dependency, not crash damage. A separate parser process is
  deferred unless actual stability/isolation requirements justify it.

## Verification for subsequent milestones

1. Pure model tests: ranges, ordering, overlap rejection, stale keys, bounded
   operation/output sizes, unknown roles, invalid UTF-8, and source provenance.
2. Projection tests: tabs, CJK, combining marks, emoji width caveats, escapes,
   synthetic padding, concealed ranges, EOL, narrow/zero viewports, and horizontal
   clipping. Reuse Cobalt's existing width oracle.
3. Screen tests: reveal policy across modes, search/selection precedence, resize,
   scrolling, popups anchored to the cursor, active-table entry/exit, and undo.
4. Markdown fixtures: unfinished fences/links/tables, lists and blockquotes,
   reference links, inline code/pipes, Unicode cells, and partial table viewports.
5. Build matrix: real provider enabled; linked but runtime off; no-provider
   executable with Markdown dependencies absent. Baseline editing must pass all
   three; only provider-specific tests may require its grammars.
6. Performance probes: plain-path differential measurements, unchanged-source
   cursor movement, large eligible files, huge rejected files/tables, bounded
   allocations, and repeated enable/disable/close cycles.
7. Manual terminal review when rendering exists: dark/light themes, no Nerd Font,
   narrow terminals, rapid editing, and raw/decorated transitions. Automated
   snapshots do not establish perceived cursor stability.

Use the established build/test toolchain in `docs/development.md`; implement a
reproducible no-provider smoke target as part of milestone 2. Milestone 1 validation
does not establish acceptance of the unimplemented provider/projection milestones.

## Reference checkouts and reading order

Cloned into `~/devel/` on 2026-11-17; these are study material, not dependencies.

| Repository | Inspected commit |
| --- | --- |
| [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim) | `a67f826164c38c836fc6060f32b275c4c43317a7` |
| [markview.nvim](https://github.com/OXY2DEV/markview.nvim) | `a6dbc5a4a4828b474c81fbcec11546cbd9000e3b` |
| [tree-sitter-markdown](https://github.com/tree-sitter-grammars/tree-sitter-markdown) | `41ff24a6c775492c543b09228aeb98d1cd2b3a0f` |

Start with:

1. `~/devel/render-markdown.nvim/lua/render-markdown/lib/marks.lua` and
   `lib/extmark.lua`: display-only operations anchored to source positions.
2. Its `render/inline/link.lua`, `parser/table.lua`, and
   `render/markdown/table.lua`: concrete decorations and table measurements.
3. Its `core/ui.lua`, `request/conceal.lua`, and `doc/limitations.md`:
   reveal/update behavior and conceal/wrapping pitfalls.
4. `~/devel/markview.nvim/lua/markview/actions.lua`,
   `parsers/markdown.lua`, `parsers/markdown_inline.lua`, and
   `renderers/markdown/`: compare hybrid-mode policy and separation of parsing
   from presentation.
5. `~/devel/tree-sitter-markdown/README.md`, both grammars' node types/queries,
   and the included-range example linked from the README.

Borrow the architecture and UX lessons, not Neovim's exact extmark API or every
workaround its renderer requires. Review upstream licenses before copying code.

## Explicitly deferred

Dynamic plugins; arbitrary custom renderer callbacks; Org-mode workflows; document
wrapping/reflow; virtual lines/folding; image or LaTeX rendering; embedded-language
highlighting inside fences; HTML/CSS layout; table-editing commands; automatic
formatting; link activation; rendered-text yanking; and a public configuration
surface for every visual detail.

The first success criterion is modest: **Cobalt can accept a small decoration
snapshot, ignore it safely, and keep editing exactly the same source.**
