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
The checklist shows declared launch targets and unavailable reasons, not run
progress. It does not require a prior run. Exact palette queries `synth`,
`timing`, and `routing` resolve their named stages, independent of the checklist
selection, even while the checklist is hidden. An unavailable exact query
reports why and launches nothing. The aliases use Silver's declared mappings,
not inferred endpoint names.

Opening or browsing the checklist starts no runs. A stage launch preserves
applicable settings, uses saved project inputs, and leaves any watched attempt
unchanged. Applied flow kickoff inputs also supply the stage flow/profile and
explicit assignments; the checklist changes only the endpoint. An
acknowledgement includes the accepted run or workflow identity;
an unconfirmed acknowledgement is not retried. A stale selection must be
selected again. See [companion flow capability requirements](../silver_overview/FLOW.md).

## Kick off a named flow

Open **Focus Silver flow kickoff** from the command palette (**Space c c**).
Choose a declared flow with `j`/`k` and press Enter to edit its profile,
endpoint and parameters. Tab switches fields, Ctrl-U clears the current field,
Enter applies, and Escape cancels. Leave an unspecified parameter blank to use
Silver's project/profile settings. Use `p` to ask Silver for a preview. Check the
resolved chip/variant, flow, profile, endpoint and parameter values before pressing
`K` (**Kickoff**). Neither applying inputs nor previewing starts a run. Kickoff
uses saved project inputs; it never saves open buffers.

Use **Toggle Silver flow kickoff** to hide the tab; a pending reply remains
available on reopening. A changed project or catalog invalidates the draft and
preview. If delivery is unconfirmed, check Silver before preparing another
Kickoff: Cobalt does not retry. The UI requires Silver to advertise compatible
flow capabilities. Automated Cobalt coverage uses fixtures, not a live daemon.

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
