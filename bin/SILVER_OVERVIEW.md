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

**Silver: Overview** starts in the bottom band, with focus still in the editor.
Use **Space v S** to hide or show it (**Toggle Silver: Overview** in the command
palette), or **Space v U** to focus it. In the tile, `j`/`k` move, `r` refreshes
the current view, and Escape returns to the editor. To see long scope values,
focus the tile and use **Space s t** to move it to a full-width tab. In Zen,
**Space v z** restores the workspace band. To quit, return to the editor and
press **Space q**.

Labels and values stay aligned as you scroll. Lifecycle and outcome keywords
use theme colors; identifiers and paths remain ordinary text.

## Show the Silver workspace

Open the command palette (**Space c c**) and choose **Layout: Silver** to show
Status and put **Silver: Overview**, **Silver: Stage Checklist**, and
**Silver: Flow Runner** in the bottom band. Choose **Layout: Default** to restore
the default workspace; of the Silver tiles, only **Silver: Overview** remains
visible. Both presets leave Zen and return focus to the editor. Toggling Zen
itself preserves the current layout. The presets do not change your Silver
binding, start a daemon or launch a run.
If no project is connected, the Silver tiles explain what is unavailable.
Use **Silver: Discover/Connect…** separately to establish a binding.
In a build without the Silver adapter, **Layout: Silver** reports that it is
unavailable and leaves your layout unchanged.

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

Open **Silver: Stage Checklist** in the command palette (**Space c c**).
Use `j`/`k` to select a stage and `R` to run the active flow through it.
Escape returns to the editor; **Toggle Silver: Stage Checklist** hides it.
The checklist follows ASIC execution for the verified project and active flow
selection, separately from the Testing attempt shown by `--silver-run`.
Use `[` and `]` to pin an older or newer matching retained ASIC run, or `L`
to resume following latest. A pin is local to this project, chip/variant,
flow, and profile; changing any of those clears the pin. Hiding the checklist
pauses observation, not Silver execution.

Statuses update while the checklist is visible, without a keypress; `r`
requests a progress refresh without changing launch settings. Reported stages
appear in Silver's order, followed by additional launch destinations.
Muted rows have no confirmed progress: a requested endpoint does not prove
that it or its prerequisites ran. **CTS** is clock tree synthesis.
When latest is ambiguous, `[` can choose from the available dated matches.

`›` marks the selected row. What the observed run did is separate from what
`R` can launch now: evidence-only stages cannot be launched, and an allowed
fresh launch does not need a prior run. The observed run never supplies
launch settings.

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

Open **Silver: Flow Runner** from the command palette (**Space c c**), or type
the exact query `flow`. The alias shows and focuses the compact selector even
if hidden or in Zen, and stays on it if already focused. If there is no room
in the bottom band, the same selector opens as a tab. The alias neither
switches flows nor starts a run. `j`/`k` immediately makes the highlighted
flow active using Silver's declared profile and defaults (or previously applied
overrides for that flow). Selecting a flow starts no jobs and needs no Enter.
Open the stage checklist (`st` in the palette) and press `R` to run through
the highlighted stage. **Toggle Silver: Flow Runner** hides the selector and
returns focus to the editor; Escape returns without hiding it.

For explicit inputs and plan review, open the separate **Silver: Flow Review** tab.
Pick a flow and press Enter to edit; Tab switches fields, Ctrl-U clears a field,
Enter applies, and Escape cancels. Leave an unspecified parameter blank to use
Silver's settings. Press `p` for a preview, check the resolved target, flow,
profile, endpoint and parameters, then press `K` to submit that exact preview.
Applying and previewing start no physical run and never save open buffers.
**Toggle Silver: Flow Review** closes the review tab. A changed catalog
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
