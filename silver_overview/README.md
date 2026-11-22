# Optional Silver overview

`cobalt.silver_overview` (`Silver_overview`) is a read-only simulation status
adapter. It uses Cobalt's existing Core/Async dependencies; building it needs no
Silver checkout, installation, or daemon. An editor composition can omit it.

The standalone overview takes an explicit Silver endpoint, canonical project
root (`pwd -P` in the project), and simulation attempt ID (not a job ID):

```sh
cobalt --silver-endpoint http://127.0.0.1:8080 \
  --silver-project /absolute/canonical/project \
  --silver-run ATTEMPT_ID /path/to/file
```

Cobalt does not find or start a daemon. The native transport accepts
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

## Lifecycle

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
adapter never sends a launch, cancel, workspace mutation, or daemon shutdown
request. The peer injection in `create` permits deterministic request sequencing
and late-reply tests without any daemon.
