# Connect to Silver from Cobalt

Start Cobalt with the endpoint of an already-running Silver daemon and the
canonical absolute Silver project root (`pwd -P` in the project):

```sh
cobalt --silver-endpoint http://127.0.0.1:30900 \
  --silver-project /work/my-project path/to/file
```

`--silver-endpoint` and `--silver-project` are required together. No attempt
is needed. Add `--silver-run ATTEMPT_ID` to put that attempt's status above
the test catalog; use the attempt ID, not a job ID.
The file or directory being edited never selects or changes the Silver binding.

From ordinary standalone Cobalt, open **Silver: Discover/Connect…** in the
command palette (**Space c c**, query `silver connect`). Choose a listed
project with Tab and press Enter. The share determines the project; it need
not match the editor's startup root. For a manual connection, type a loopback
HTTP URL instead: this opens the editor's startup root, not the current buffer's
directory. Use the paired CLI flags above to enter a different root manually.
Neither path starts a daemon. A failed connection leaves the previous binding
unchanged.

On the Silver side, open **Share with Cobalt…** for the current project and
confirm. Cobalt lists live offers only, showing the project name and root, mode
(embedded or attached), and a short offer ID to distinguish Silver windows.
Stopping sharing removes that offer for new connections; existing Cobalt
connections and Silver jobs continue. The overview shows the verified project
and retained attempts; use `r` to refresh them. Silver's native `daemon.sexp`
is a daemon address, not a project share.

The overview starts in the bottom band, with focus still in the editor. Use
**Space v S** to hide or show it (**Toggle Silver overview** in the command
palette), or **Space v U** to focus it. In the tile, `j`/`k` move, `r` refreshes
the current view, and Escape returns to the editor. To see long scope values,
focus the tile and use **Space s t** to move it to a full-width tab. In Zen,
**Space v z** restores the workspace band. To quit, return to the editor and
press **Space q**.

## Quick launch a test

In the project catalog, `R` runs the selected suite or variant. A suite runs
all its cases. Enter opens settings; Tab moves between fields, Ctrl-U clears
a field, Enter applies, and Escape cancels. Applying never starts a run.

From code, open the command palette (**Space c c**) and type exactly `test`.
It offers the configured target (`--silver-test-default SUITE[/VARIANT]`) or
the last acknowledged target for that project. With neither, it opens a
picker. The launch uses the settings for that exact target; suite and variant
overrides are independent and remain available when the tile is hidden.
Silver runs saved project inputs, not unsaved editor buffers.

An accepted launch records its attempt and job IDs in History (**Space v M**;
use **Space s t** or Enter to see a long entry). **Delivery unconfirmed**
means Silver may already be running the test; check Silver before trying
again. Cobalt never resubmits automatically. When Silver reports a stale
catalog, choose the target again from the refreshed catalog.

## Launch through a stage

Open **Silver: Stage checklist** in the command palette (**Space c c**).
Use `j`/`k` to select a stage and `R` to run the active flow through it.
Escape returns to the editor; **Toggle Silver: Stage checklist** hides it.
The checklist shows launch availability for the active flow, not run progress.
`›` marks the selected row; `+` means available, `-` means unavailable, and `!`
means the selection changed and must be chosen again. The detail column shows
the exact endpoint for available rows or the reason a row is unavailable, as
space permits. **CTS** is clock tree synthesis; the display label does not
change the endpoint Silver receives. No prior run is required.

Exact palette queries `synth`, `timing`, and `routing` resolve their named
stages, independent of the checklist selection, even while the checklist is
hidden. An unavailable exact query reports why and launches nothing. The aliases
use Silver's declared mappings, not inferred endpoint names.

Opening or browsing the checklist starts no runs. A stage launch preserves
applicable settings, uses saved project inputs, and leaves any watched attempt
unchanged. The flow selector supplies the flow/profile and any applied
assignments; the checklist changes only the endpoint. An
acknowledgement includes the accepted run or workflow identity;
an unconfirmed acknowledgement is not retried. A stale selection must be
selected again. See [companion flow capability requirements](../silver_overview/FLOW.md).

## Kick off a named flow

Open **Focus Silver flow kickoff** from the command palette (**Space c c**) for
a flow selector beside the editor. `j`/`k` immediately makes the highlighted
flow active using Silver's declared profile and defaults (or previously applied
overrides for that flow). Selecting a flow starts no jobs and needs no Enter.
Open the stage checklist (`st` in the palette) and press `R` to run through
the highlighted stage. **Toggle Silver flow kickoff** hides the selector and
returns focus to the editor; Escape returns without hiding it.

For explicit inputs and plan review, open **Review Silver flow kickoff**.
Pick a flow and press Enter to edit; Tab switches fields, Ctrl-U clears a field,
Enter applies, and Escape cancels. Leave an unspecified parameter blank to use
Silver's settings. Press `p` for a preview, check the resolved target, flow,
profile, endpoint and parameters, then press `K` to submit that exact preview.
Applying and previewing start no physical run and never save open buffers.
**Toggle Silver flow kickoff review** closes the review tab. A changed catalog
invalidates the preview; if delivery is unconfirmed, check Silver before
trying again. Cobalt does not retry.

## Watch an attempt

- **Fresh**: Silver returned the status of that exact attempt.
- **Stale**: the last matching status is retained while Cobalt retries.
- **Unavailable**: Cobalt has no matching status for the current observation.

`Lifecycle` and `Outcome` are separate; an `Unknown` outcome does not by
itself mean the run is pending.

Hiding the tile abandons attempt observation, not the project binding,
settings, or pending launch acknowledgements. Reopening starts a fresh
observation of the same attempt. Quitting stops local work but does not
cancel Silver runs. Cobalt and Silver have independent focus and scroll state.

The adapter is selected at build time; a build without `silver_overview/`
still edits normally. Those builds reject an explicit Silver binding.
