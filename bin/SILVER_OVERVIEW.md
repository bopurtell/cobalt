# Watch a Silver simulation from Cobalt

Start Cobalt with the endpoint of an already-running Silver daemon, the
canonical absolute Silver project root (`pwd -P` in the project), and the
simulation **attempt ID** shown by Silver (not a job ID):

```sh
cobalt --silver-endpoint http://127.0.0.1:30900 \
  --silver-project /work/my-project --silver-run ATTEMPT_ID path/to/file
```

All three flags are required together. The file or directory being edited
doesn't select or change the Silver binding; switching editor buffers likewise
doesn't change it.

The overview starts in the bottom band, with focus still in the editor. Use
**Space v S** to hide or show it (**Toggle Silver overview** in the command
palette), or **Space v U** to focus it. In the tile, `j`/`k` scroll, `r` refreshes
the observation, and Escape returns to the editor. To see long scope values,
focus the tile and use **Space s t** to move it to a full-width tab. In Zen,
**Space v z** restores the workspace band. To quit, return to the editor and
press **Space q**.

- **Fresh**: Silver returned the status of that exact attempt.
- **Stale**: the last matching status is retained while Cobalt retries.
- **Unavailable**: Cobalt has no matching status for the current observation.

`Lifecycle` and `Outcome` are separate; an `Unknown` outcome does not by
itself mean the run is pending.

Hiding the tile abandons local reads. Reopening starts a new observation.
Quitting stops observation as well. None of these operations cancels, launches,
or otherwise changes a run. Cobalt and the Silver window have independent
focus and scroll state.

The adapter is selected at build time; a build without `silver_overview/`
still edits normally. Those builds reject an explicit Silver binding.
