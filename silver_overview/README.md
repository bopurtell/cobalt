# Optional Silver overview

`cobalt.silver_overview` provides a simulation status adapter, a separate
`Testing` quick-launch API, and a [companion flow adapter](FLOW.md) for stage
launch and flow Kickoff. Building it needs no Silver checkout, installation,
or daemon. An editor composition can omit it.

The standalone overview takes an explicit Silver endpoint, canonical project
root (`pwd -P` in the project), and simulation attempt ID (not a job ID):

```sh
cobalt --silver-endpoint http://127.0.0.1:8080 \
  --silver-project /absolute/canonical/project \
  --silver-run ATTEMPT_ID /path/to/file
```

Cobalt never starts a daemon. The native transport accepts
`http://127.0.0.1:PORT`, `http://localhost:PORT` (mapped to IPv4 loopback), and
`http://[::1]:PORT`. It does not use proxies, DNS, or redirects.

## Binding and wire contract

The adapter implements a small subset of Silver v1 S-expression RPC. It uses
`GET /api/hello` to require protocol v1 and the simulation capability, and
`POST /api/v1/open-project` with `Inherit_daemon` to open the explicit root and
acquire its per-instance project ID. This registers a Silver session; it does
not launch a simulation. If Silver returns a different canonical root, the
binding is rejected rather than silently redirected.

Status reads send both IDs to `POST /api/v1/simulation`. A project-level binding
(`run = None` in the API) uses `Get`. An attempt binding uses `Observe` and
requires an exact root and attempt match in the returned detail; it never falls
back to a different or most recent attempt. The model keeps the attempt ID,
suite, lifecycle, and outcome (separate from lifecycle; `None` means Silver's
outcome is unknown). At most 25 rows are retained and pagination is exposed as
`truncated`, not followed automatically. Reads are capped at 2 MiB, with
separate header/framing caps and bounded display labels and error messages.

See Silver's `native_http/client.ml`, `protocol/v1.ml`, `protocol/simulation.ml`,
and `backend/simulation_service.ml` for the source contract. No Silver code is
linked or loaded.

## Observation lifecycle

`create` is idle. Call `rebind` on the Async scheduler to begin background
polling; `latest` is a synchronous cache read and does no I/O. `revision` and
`await_change` allow consumers to react without polling the cache themselves.

Each request has a five-second default deadline. Successful status refreshes
once per second; failed reads cause reconnect with exponential backoff from
250 ms to five seconds. The last same-binding snapshot is **stale** after a
failure; without a snapshot the status is **unavailable**. If reconnect reveals a
different daemon instance or project session, the previous snapshot is dropped.
Explicit `rebind`, including identical arguments, always drops the old snapshot
and ignores all late work from the old binding.

`unbind` stops observation and clears the snapshot without disposing the adapter;
`shutdown` stops it permanently. These operations abandon local I/O only: the
observation loop never sends a launch, cancel, workspace mutation, or daemon
shutdown request. The peer injection in `create` permits deterministic request sequencing
and late-reply tests without any daemon.

## Discover/Connect (WB-094)

With an adapter-enabled build, **Silver: Discover/Connect…** is available in
the standalone palette without Silver flags or a prior run. Lookup reads only
`editor-shares/v1/` under Silver's native runtime directory:
`$XDG_RUNTIME_DIR/hardcaml-workbench`, falling back to
`$XDG_STATE_HOME/hardcaml-workbench`, then `$HOME/.local/state/hardcaml-workbench`.
It never contacts a daemon during lookup, searches ports, or infers a share from
editor files. Native `daemon.sexp` alone is not a project share. For manual use,
enter a loopback URL to open the editor's startup root, or use `--silver-endpoint`
and `--silver-project` together for another root.

Published `<32-lowercase-hex-id>.sexp` files use this format:

```scheme
(silver-editor-share-v1
 ((offer_id 0123456789abcdef0123456789abcdef)
  (endpoint http://127.0.0.1:44123)
  (instance_id daemon-id)
  (project_id project-id)
  (project_root "/work/project with spaces")
  (mode attached)))
```

Live lookup is bounded to 256 registry entries and 16 KiB per record. It checks
private same-user directories, mode-0600 regular files without symlinks or
additional hard links, and the same named inode with the publisher's exclusive
BSD `flock` still held. Unlocked crash leftovers never become selectable.

### Discover/Connect fixture (WB-094)

The optional `COBALT_SILVER_SHARE_FIXTURE` absolute path overrides live lookup
for tests. The fixture is a Cobalt-only seam, not a Silver file format. It is a
single S-expression, read up to 8 KiB and at most 32 rows. Use a regular file
owned by the effective user, not group/other writable, in a same-owner private
directory (e.g. mode `0700`). A test publisher writes the following shape,
substituting its own fake peer endpoint, instance ID, project ID and canonical
absolute root:

```scheme
(cobalt-share-fixture-v1
 ((offer_id publisher-a-1)
  (endpoint http://127.0.0.1:44123)
  (instance_id fixture-daemon)
  (project_id fixture-project)
  (project_root "/work/project with spaces")))
```

Publish and withdraw by replacing the file atomically or unlinking it. Use a
fresh `offer_id` for each publication lifetime. Independent offers can name the
same project root or endpoint. Duplicate offer IDs are rejected rather than
silently picking a winner; malformed rows are omitted with a visible diagnosis.
Rows show an offer and its advertised identity, not a preverified connection.

The picker passes an opaque, session-local candidate ID back to composition.
On selection the adapter re-reads the exact offer, checks `GET /api/hello`
for v1, `simulation`, and the advertised instance ID, then verifies the exact
project ID and root in `POST /api/v1/snapshot`. That RPC reads already-open
projects; the share path never calls `open-project`. It re-reads the offer again
before committing the binding. A newer connect supersedes a pending one; failed,
withdrawn, mismatched and superseded selections do not replace the current
binding. Once bound, withdrawing the share changes discoverability, not the
existing connection. The share path reads the Testing catalog without starting
provider discovery; this may show no catalog until Silver prepares it.

Run `dune runtest -j4 silver_overview screen bin` for the locked registry,
injected-peer, headless picker and standalone PTY checks. The live-format
fixtures use `/tmp`, or `COBALT_TEST_SHARE_TMPDIR` if supplied; that parent must
pass the same path checks as the production registry. `bin/test_silver_share_cli.py`
creates its own private fixture source and fake peer, checks a selection outside
the editor root, races a late reply against a newer connection, and asserts no
project-open, provider-discovery or launch RPC occurs. For real two-app history,
launch, competing offers, and withdrawal tests, use Silver's
`scripts/test-editor-project-sharing.py`. Fake-peer checks are not evidence
of live integration. Loopback alone is not evidence of same-machine/same-user
publisher or backend identity.

## Testing quick launch

Separately from project shares, `Silver_connection.lookup` lists the daemon advertised to Silver's own native
client, plus caller-supplied known endpoints. It reads only `daemon.sexp` in
`$XDG_RUNTIME_DIR/hardcaml-workbench`, or (if unset or empty)
`${XDG_STATE_HOME:-$HOME/.local/state}/hardcaml-workbench`. An explicit discovery
directory can be passed to `lookup` to match a daemon's `--discovery-dir`.
There is no registry of all daemon processes or port scanning: a daemon
without an advertisement in that directory must be known to the caller or
entered explicitly. `Silver_connection.explicit` validates a loopback HTTP URL
without contacting it. Lookup only lists candidates; `Silver_connection.connect`
verifies the selected endpoint with `hello` and, for an advertised candidate,
requires the live instance ID to match the file before opening the project.

`Testing.connect` uses the same v1 handshake and exact project-root check as
observation. It needs no attempt ID. `Testing.discover` reads `Get` first and
only schedules `Discover` if the configured project has no usable catalog or
in-progress discovery. It polls `Get` for that job up to a bounded deadline. The
catalog carries the verified connection and Silver's digest. Silver's `cases`
are the variants shown to the user. Parameter defaults and choices retain
their exact values; display labels are bounded and sanitized.

`Testing.launch` sends exactly one `Launch` with a new submission key, the
captured discovery digest, explicit case IDs and seed, and every declared
parameter. It does not inspect editor buffers or automatically save them: Silver
runs the configured provider against project files. The acknowledgement must
carry the requested project and captured inputs before it is considered
`Accepted`; the reply identifies the attempt and job separately. A
`Stale_catalog` requires a newly discovered catalog and fresh selection.
`Rejected` reports a local validation failure or an explicit Silver rejection.
`Uncertain` means delivery was not confirmed, including a timeout, malformed or
mismatched reply, or an internal failure after a possible reservation. Do not
automatically resubmit; consult Silver's attempt history first. Closing a local
connection abandons local I/O without sending any cancellation or affecting
the independent watched attempt.

Run `dune runtest silver_overview` for fake-peer tests that replay the real
parameterized catalog and launch acknowledgement captured under
`examples/silver_overview/wire/`.
