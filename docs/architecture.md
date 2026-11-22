# Architecture

[Documentation index](README.md) · [Development](development.md)

Cobalt separates editing state from the terminal frontend. The core returns a new
state and effects; the application controller performs file I/O and updates
highlighting. A screen model handles geometry, focus, scrolling, and rendered
frames. Bonsai_term adapts terminal events and displays those frames.

## Source layout

| Directory | Responsibility |
| --- | --- |
| `core/` | Text storage, motions, selections, registers, and undo history |
| `input/` | Terminal-independent keys, bindings, and modal keymap |
| `app/` | Session/buffer ownership, filesystem apply, file I/O, and highlight cache |
| `highlight/` | Provider-independent highlight ranges and snapshots |
| `highlight_tree_sitter/` | Tree-sitter providers, grammars, and queries |
| `decoration/` | Pure, provider-independent display decoration snapshots; no Markdown or terminal dependency |
| `markdown/` | Optional source-preserving Markdown provider and pinned block/inline grammars |
| `error/` | Notifications, active problems, and bounded history |
| `source/` | Asynchronous diagnostic sources and language-server completion/hover/navigation client |
| `completion/` | Pure completion sessions, buffer-word candidates, cycling, and edit plans |
| `navigation_preview/` | Bounded source-window extraction and target highlights for navigation result pickers |
| `config/` | Settings defaults/validation and isolated executable OCaml configuration loading |
| `tile/` | Shared tile host, focus, and input routing |
| `palette/` | Command catalog and fuzzy matching |
| `theme/` | Immutable semantic RGB palettes, built-in registry, and Base16 adapter |
| `file_picker/` | Project file discovery/matching and Async floating-picker runtime |
| `line_picker/` | Bounded fuzzy search over current in-memory document lines |
| `content_picker/` | On-disk literal search provider and Async floating-picker runtime |
| `vcs/` | VCS model, Git command builders and parsers, and Async job runner |
| `terminal/` | PTY shell host, vendored libvterm emulator, and UI-independent terminal protocol |
| `screen/` | Screen geometry, workspace state, and frame rendering |
| `ui/` | Bonsai_term frontend, event adapter, theme, and asynchronous host integration |
| `bin/` | Command-line entry point |

## Boundaries

The editing core, input layer, and application controller have no Bonsai or
terminal-library dependencies. The screen model is also independent of Bonsai;
it uses Notty's character-width table to keep editing and rendering aligned.
These boundaries allow most behavior to be tested headlessly.

Document decorations are an optional presentation input, not part of editing
state. The screen accepts prepared, current decoration data and otherwise uses
its ordinary indexed source renderer. Preparation validates cell geometry outside
frame rendering; neither parsing nor provider callbacks run while drawing. The
editing core and input layer have no decoration dependency.

The generic layer supports semantic range styling and conservative same-width
glyph substitutions. Markdown adds only source-preserving style ranges, and is
off by default. `ui/document_decoration_host.ml` owns injected sessions outside
editor state and synchronizes source changes at input transitions, not while
drawing. The frame cache includes expected keys and prepared-source identity.

`bin/composition/` selects the concrete provider or a no-provider adapter. No
concrete Markdown dependency enters core, input, app, screen or the generic UI
host. The explicit no-provider executable shares the CLI/UI; removing the entire
`markdown/` subtree also selects the stub for the default executable. See the
[decoration and Markdown plan](plans/markdown_decorations.md) for scope and the
tested absent-library build.

Asynchronous producers deliver events into the UI state transition. Requests
leave as data and are submitted to their hosts after the transition. File and
content pickers, diagnostic sources, the VCS runner, and Tile Terms use these
boundaries to keep process and I/O ownership separate from screen rendering.

The optional [Silver overview](../silver_overview/README.md) follows the same
boundary. `bin/composition/` selects the Silver adapter or a stub. The adapter
owns the daemon connection, project and attempt identity, retries, and cached
status. The tile receives display rows and returns a refresh request; rendering
or scrolling it never performs a network read.

Tile Terms pair numbered UI sessions with a lazy pool of single-shell PTY
runtimes. Hidden sessions continue draining output; snapshots and failures carry
their terminal number and generation to prevent cross-session delivery. See the
[terminal backend guide](../terminal/README.md) for lifecycle and emulation details.

For deeper rationale, see the [workspace design](workspace_tiles_design.md),
[rendering design](rendering_design.md), and [project direction](cobalt_editor_prototype_brief.md).
