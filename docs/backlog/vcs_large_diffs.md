# VCS performance: browsing a large staged change set

**Status:** CB-013, CB-014 and CB-015 implemented and tested.

## Reproduction and baseline

Stage changes across hundreds of files with several MB of combined patch text.
Open the VCS view with only staged changes, move from **Staged changes** to its
first filename, then return to the header and scroll the aggregate diff. Compare
opening the panel, switching targets, and scrolling *after* a target has loaded.

Observed in Silver: 417 staged paths, 265 Markdown files, 50,613 patch lines.
The patch can be recovered without changing Silver's index:
`git -C /path/to/silver diff --find-renames 724893d a5d6bc6 --`.

| Component | First file (2.3 KB) | Aggregate (3.0 MB) |
| --- | ---: | ---: |
| Git produces patch (median of five runs) | 1.8 ms | 89 ms |
| Cobalt parses patch and builds diff text | 0.07 ms | 73 ms |
| Initial display glyph construction | 0.2 ms | 311 ms |
| Layout work for one Files-focused redraw | ~0.23 ms | 153–196 ms |

Layout timings used Cobalt's compiled `Text_view` functions at 80 columns × 32
rows: two `fit` calls and one `rows` call, before terminal painting. The aggregate
probe peaked at ~438 MiB RSS. These are component timings, not end-to-end input
latency. They explain lag on the aggregate and while switching away from it;
they do not establish a bottleneck on an already-loaded small-file preview.

<a id="vcs-perf-01--open-files-on-an-individual-change"></a>

### CB-013 — Open Files on an individual change

Before this change, `Panel.Cursor.reconcile` (`vcs/panel.ml`) selected the first row, a
section header. `diff_target` (`vcs/git/backend.ml`) maps the staged header to
`Staged []`: an unrestricted `git diff --cached`. A filename requests only its
own patch. Opening the panel therefore used to load the aggregate before the
user asked to see it.

**Acceptance:** With 400+ staged paths and no previous selection, the first
preview job is scoped to the first changed file; no aggregate job precedes it.
Explicitly selecting the header still shows the aggregate. Refresh preserves
an existing valid selection, including an explicitly selected header.

**Verification:** `screen/test/test_vcs_view.ml` opens a 401-file staged
fixture and checks the first preview job, explicit header selection and
refresh. A second case covers folded sections when files reappear.

<a id="vcs-perf-02--reuse-wrapped-rows-across-redraws"></a>

### CB-014 — Reuse wrapped rows across redraws

Before caching, `layout` in `tile/text_view.ml` walked every glyph and allocated
wrapped rows for the entire diff. `fit`, `diff_body`, and the footer in
`screen/vcs_view.ml` repeated that work: three layouts per Files-focused render with the preview shown,
five with Diff focused. Only then did the renderer slice out the visible rows.

**Acceptance:** Share one layout for unchanged text and wrap width. Cursor
movement, scrolling, focus changes and footer counts reuse it; the renderer
reads the visible slice without copying the entire row array into a list.
Changing text or width produces correct new wraps, cursor, selection and
scroll counts. Repeat the baseline and report cold layout separately from
warm redraw time; verify zero full rewraps on warm redraws.

**Verification:** On the same Silver patch at 80×32, a repeat comparison measured
262.5 ms for the old aggregate redraw layout, 40.1 ms for the new first wrap,
and 0.578 µs for a warm layout. The first-file equivalents were 0.282 ms,
0.017 ms and 0.365 µs. These medians exclude Git, initial glyph construction,
span rendering and terminal painting. Tile tests verify reuse across cursor and
scroll changes, invalidation on text/width changes, and visible row slices.

<a id="vcs-perf-03--drop-the-stale-preview-when-switching-targets"></a>

### CB-015 — Drop the stale preview when switching targets

Previously, `request_diff` in `screen/vcs_view.ml` changed the target to `Loading` but kept
the previous `diff_view`. Moving from the staged header to a small file showed
the small filename above the aggregate patch and incurred another layout of the
old patch while the file loaded.

**Acceptance:** On a target change, show a lightweight loading row instead of
rendering or acting on the previous patch. With delayed jobs, move from the
header to file A and then B: no aggregate layout is requested by the loading
view and only B's result is displayed. A refresh of the *same* target still
preserves the user's position.

**Verification:** `screen/test/test_vcs_diff_loading.ml` delays file previews,
delivers them in both orders, and checks the loading display, stale actions,
rows with no diff, and cursor/scroll preservation on a same-target refresh.
