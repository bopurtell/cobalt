# Backlog

## Silver integration

- [Cobalt-side work queue](silver_integration.md): C1–C6 are closed. Start with
  C7 for no-flags discovery, C8 for the stage checklist and aliases, or C9 for
  the flow kickoff tile. Each lists the Silver handoff needed for live acceptance.

## Language-aware editing

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
| [C10: Side-by-side file editors](c10-side-by-side-editors.md) | Implemented and verified | Two keyboard-accessible file editor panes in the existing workspace |
| [C11: Basic mouse support](c11-mouse-support.md) | Implemented and verified | Click-to-focus, cursor placement, file tab activation, wheel scrolling, and runtime reporting toggle |

The Oil/Dired-style directory refresh already exists: focus the listing and
press `Space r` in Normal mode. It rereads a clean listing from disk and
refuses pending directory edits. Cached revisits do not refresh automatically;
`:e!` reloads files, not directory listings. See the
[directory workspace reference](../directory_workspace.md#navigation-tabs-and-opening).

## Installation

- [C12: Install Cobalt from a clone](c12-source-install.md) (implemented):
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
