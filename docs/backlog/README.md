# Backlog

## Ticket IDs

Use **`CB-NNN`** for every Cobalt ticket: uppercase `CB`, a hyphen, and a
number padded to at least three digits. Use one sequence across all topics.
Assign the next unused number here when creating a ticket, put it in the ticket
heading, and keep it when the ticket moves or closes. Don't reuse closed IDs.
Silver's `WB-` identifiers refer to Silver tickets and remain separate.

| Assigned IDs | Tickets | Previous IDs (same order) |
| --- | --- | --- |
| CB-001–CB-009 | [Silver integration](silver_integration.md) | C1–C9 |
| CB-010–CB-012 | [Side-by-side editors](c10-side-by-side-editors.md), [mouse support](c11-mouse-support.md), [source install](c12-source-install.md) | C10–C12 |
| CB-013–CB-015 | [VCS performance](vcs_large_diffs.md) | VCS-PERF-01–03 |
| CB-016–CB-021 | [Language support](language_support.md) | LANG-01–06 |
| CB-022–CB-031 | [Snippet collections](snippet_collections.md) | SNIP-01–10 |
| CB-032 | [Symbol rename](symbol_rename.md) | Previously unnumbered |

## Silver integration

- [Cobalt-side work queue](silver_integration.md): CB-001–CB-009 are closed, including
  the stage checklist and aliases (CB-008) and the Flow Runner (CB-009).

## Language-aware editing

- [Rust, Haskell, and Bluespec support](language_support.md): tickets and status
  for Rust and Haskell editing, Bluespec SystemVerilog and Classic highlighting,
  and language feedback validated on real Bluespec projects.
- [Symbol rename](symbol_rename.md): deferred ticket for LSP-driven rename,
  reviewed multi-file edits, unsaved-buffer application, and an explicit undo policy.

## Snippet catalog and organization

- [Snippet collections and hardware-development catalog](snippet_collections.md):
  proposed ticket backlog for SV design/verification, Xilinx register terminology,
  core/testing/Jane Street OCaml, Signal-first Hardcaml design/verification, and
  collection discovery and activation.

## Editor and workspace tickets

| Ticket | Status | Scope |
| --- | --- | --- |
| [CB-010: Side-by-side file editors](c10-side-by-side-editors.md) | Closed | Two keyboard-accessible file editor panes in the existing workspace |
| [CB-011: Basic mouse support](c11-mouse-support.md) | Closed | Click-to-focus, cursor placement, file tab activation, wheel scrolling, and runtime reporting toggle |

The Oil/Dired-style directory refresh already exists: focus the listing and
press `Space r` in Normal mode. It rereads a clean listing from disk and
refuses pending directory edits. Cached revisits do not refresh automatically;
`:e!` reloads files, not directory listings. See the
[directory workspace reference](../directory_workspace.md#navigation-tabs-and-opening).

## Version control

- [Large staged diffs: startup, redraws, and switching files](vcs_large_diffs.md):
  CB-013–CB-015 implemented and tested against Silver's 417-file change set.

## Installation

- [CB-012: Install Cobalt from a clone](c12-source-install.md) (closed):
  build and install the native commands into a user-owned prefix with one
  Silver-style `./install.sh` invocation once prerequisites are available.

## Deferred workspace work

Work deferred from the workspace-tiles feature set ([`workspace_tiles_design.md`](../workspace_tiles_design.md),
phases 1–10, all human-accepted). On 2026-10-06 the owner chose to close that feature
set and push the following to a later milestone. Each item still needs a concrete
assignment (scope, owner decisions, acceptance) before implementation.

| File | What |
| --- | --- |
| [external_views.md](external_views.md) | Externally computed views: producers supplying data or cell frames to tiles, transport, freshness, protocol |
| [major_minor_tiles.md](major_minor_tiles.md) | Generalizing the tile system: a minor-view registry instead of per-tile wiring, the shell's library boundary, specialized major tiles, open 7B comfort questions |

## Other open decisions (from the design doc's "Remaining decisions")

- Whether status follows the focused pane or also retains a pinned document summary.
- Which workspace/session/layout settings should persist across launches.
