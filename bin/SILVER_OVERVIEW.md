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

You can also open **Silver: Connect…** in the command palette. It offers known
session endpoints and Silver's local `daemon.sexp` advertisement, or accepts
an explicit loopback HTTP URL. This command opens the editor's startup project
root (not the currently edited buffer's directory). It does not start a daemon,
and a failed handshake leaves the previous binding unchanged.

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
