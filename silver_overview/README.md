# Optional Silver overview

`cobalt.silver_overview` (`Silver_overview`) provides a simulation status
adapter and a separate `Testing` quick-launch API. It uses Cobalt's existing
Core/Async dependencies; building it needs no Silver checkout, installation,
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

## Testing quick launch

`Silver_connection.lookup` lists the daemon advertised to Silver's own native
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
