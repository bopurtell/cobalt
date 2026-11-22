# C5 live handoff: Cobalt overview and Silver Testing

Run `check_live.py` to compare **two real terminal clients** against one
private Silver daemon. The check launches a PDK-free fixture attempt, then
asserts that Silver’s Testing window and Cobalt’s read-only Silver overview
tile display the same full attempt ID, suite, lifecycle, and outcome.

## Run the check

From the Cobalt root, in the appropriate build environment:

```sh
dune build -j 4 bin/cobalt.exe
silver_checkout="$(realpath ../jane/silver)"
# Point this at a working Silver build. In a Silver development environment
# with its own dependencies (including cobalt.hosted) installed:
# (cd "$silver_checkout" && dune build -j 4 --build-dir _build_workbench daemon/main.exe terminal/main.exe)
silver_bin="$silver_checkout/_build_workbench/default"

python3 -O examples/silver_overview/check_live.py \
  --silver-checkout "$silver_checkout" \
  --daemon "$silver_bin/daemon/main.exe" \
  --silver-client "$silver_bin/terminal/main.exe" \
  --cobalt "$PWD/_build/default/bin/cobalt.exe"
```

The check takes paths to already built binaries. It does not build either
checkout, look for an existing daemon, or use your project/configuration.
All fixture files, user-state directories, and the daemon state live in a new
`/tmp/opencode/c5-live-*` directory. The daemon binds an ephemeral loopback
port; the checker closes only the processes it started and leaves its evidence
directory behind. The Silver checkout supplies the fixture provider, S-expression
fixture codec, and PTY screen helper. No Silver checkout or daemon is needed
for the default Cobalt build.

The test checks `Get` and `Observe` over HTTP first. Then it opens Silver in
Testing, selects full identifiers, and starts Cobalt bound to the same root and
attempt. It checks the reconstructed screens (not matches anywhere in the
terminal byte stream). Zooming and unzooming a Silver pane leaves the Cobalt
tile unchanged. Hiding and reopening the tile, then quitting Cobalt, leaves
Silver on the same attempt. The final Silver read and provider log still show
one attempt and exactly one fixture discovery and launch.

Look for `"acceptance": "two-windows"` in `result.json`. The two PTY directories
contain `.txt` screen snapshots and raw `.ansi` captures. To capture only the
HTTP exchange, pass `--wire-only` instead of `--silver-client` and `--cobalt`;
that mode reports `"acceptance": "wire-only"`, not a two-window pass.

## Captured v1 wire

The files under [`wire/`](wire/) record unedited HTTP messages from one isolated
fixture, including request and response headers and the exact body strings
decoded from bytes. The IDs, timestamp, temporary path (deliberately containing
spaces), and port are specific to that run; rerun the check to get usable
values. The transient daemon behind this capture is stopped.

| Exchange | What to use |
| --- | --- |
| [`GET /api/hello`](wire/hello.json) | Bare record with `protocol_versions` containing `1`, `capabilities` containing `simulation`, and the daemon `instance_id`. |
| [`POST /api/v1/open-project`](wire/open-project.json) | Send that instance, an absolute canonical project root and `Inherit_daemon`. Use the returned `project.id` for simulation requests; check the returned `project.root.path` matches the bound project. |
| [`Get`](wire/get.json) | Project snapshot: `attempts` contains summaries, `detail` is `()`. |
| [`Observe`](wire/observe.json) | Same project snapshot plus `detail` of the **exact** attempt ID, not the job ID. |
| [`Observe` an unknown ID](wire/observe-not-found.json) | HTTP 200 application-level `(Error((kind Not_found)…))`, not an HTTP 404 and not an empty successful snapshot. |

Both reads use `POST /api/v1/simulation` with `Content-Type: application/sexp`
and `X-Workbench-Protocol: 1`. This capture omits the optional declaration and
execution-timing headers that the native Silver client negotiates. The
recorded attempt is
`sim-d16c900b597f84a37835459f75045b4b13eced64c6148707765b41b0d8a408c2`,
suite `fixture`, seed `42`, lifecycle `Finished`, outcome `Passed`. Lifecycle
and outcome are separate fields; `Finished` alone does not mean `Passed`.

The Cobalt tile does not discover, launch, rerun, or cancel simulations. In the
test, only fixture setup sends `Discover` and `Launch` to its private daemon.
