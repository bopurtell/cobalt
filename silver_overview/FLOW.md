# Silver companion flow adapter (C8/C9)

[`Silver_flow`](silver_flow.mli) is the optional, editor-session launch model.
Composition binds it to `production verified_project` after project verification,
or to a typed `service` in fixtures, and explicitly calls `refresh`. The model
owns the cached catalog, stage inputs, kickoff draft and acknowledgements. None
of this state is owned by a tile; there is no watched attempt API in this module.
The production factory shares the verified connection (including its capabilities,
endpoint, instance ID, and project ID); it does not open another project or
start a daemon. Use `unbind` to fence old results on teardown. Keep any
already-dispatched submission's verified project alive until its reply if you
want that acknowledgement; closing a transport only abandons local I/O, not
the Silver job.

## Supported native operations

The current sibling Silver source exposes the v1 S-expression request
`{instance_id; project; operation}` on `POST /api/v1/asic`. This adapter uses
its existing `In_context` with the stable, reserved `cobalt-companion-v1` key
and no initial chip selection. That confines pending catalog/plan/staging
state to the companion instead of editing Main or a native workspace. Two
Cobalt sessions can supersede one another's pending preparation in that
context; they cannot substitute another selection or preview. The catalog
  uses the context's discovered target, not a native window's transient target
or a watched historical run. No native target or selection-setting mutation
is sent by Cobalt.

The handshake must advertise `asic` and `source-bundle-preparation-v1` for
launching. The ASIC project must be configured and `POST /api/v1/preparation`
`Get` must report `Available`. Discover and Describe schedule provider
queries; only `Get` is polled for bounded completion. No polling, file access,
or process creation is performed while projecting cached state. Discovery
may expose a project/catalog even when preparation is unavailable; stage rows
give the reason and Kickoff remains blocked.

| Surface | Resolve / prepare | Explicit submit |
| --- | --- | --- |
| Stage checklist and exact `synth`, `timing`, `routing` | Use the advertised `fresh_stage_endpoints` for the current recipe. `synth` names public endpoint `synthesis`; Timing and Routing use `timing` and `routing` only when advertised. Explicit current settings win; otherwise use the target's declared catalog default flow/profile. Stage selection changes only the endpoint. `Stage_fresh` uses `elaboration_only=false` and no expected plan identity. It captures an input intent and configuration scope, not emitted RTL or a frozen plan. Compare its receipt against the exact selection and fence it against a subsequent `Get` before submission. | `Launch_fresh {key; intent_id}` once, after a local binding/catalog/settings check. Silver re-checks intent identity and scope. |
| Kickoff | Use the public `Describe` `hardcaml-asic.flow-describe` v1 entry, configurable keys and typed enum/boolean descriptors, restricted to the discovery-advertised executable endpoints. Entering the editor or applying a draft does not call `Plan`. Explicit Prepare uses `Plan` and waits for a matching `Asic.Preview`; the methodology plan's reported selection, request and effective winning assignments populate the review. Missing or incompatible descriptors/plans disable only the affected flow. | Recheck the exact preview via `Get` and the local review generation before sending `Run {key; preview}` once with the full, exact preview (including opaque `plan_json`). On the current Silver backend, `Run` reserves a fresh workflow and checks the expected plan identity before physical execution. |

OCaml inline-record operations carry their fields directly after the tag:
`(In_context (context ...) (initial_target ()) (operation ...))`.
This also applies to `Stage_fresh`, `Launch_fresh` and `Run`. Ordinary
record payloads such as the selection in `(Plan ((flow ...) ...))` retain
their own list.

The `j`/`k` kickoff selector writes only local active-flow settings, not a
preview or execution request. It uses the current catalog's scoped target and
the flow's declared profile unless explicit settings for that flow were applied
in the same catalog. Applying a draft in the separate review view also makes
those settings active for checklist/alias resolution. Unchanged displayed defaults
remain implicit, avoiding an override of native recipe/project preferences.
For parameters whose declared defaults differ by profile, the form leaves the
value unspecified until the service resolves it. Cobalt does not present a
descriptor's documented backend default as an observed runtime value.
Endpoint initialization follows the native editor's preference for advertised
synthesis, otherwise the first supported declared endpoint. It is not claimed
as a provider-selected default. Changed/stale explicit settings require
explicit reselection rather than falling back.

A valid reservation reply must match the one-shot key and exact captured
selection plus the expected intent/plan identity. A workflow ID is sufficient
to acknowledge the reservation, but is not a physical run ID or proof of
successful execution. Show the returned run ID separately if already allocated.
In particular, after `Run` reserves a workflow, changes in saved source or
provider scope can still cause the later preparation to fail its expected
plan identity check before physical execution.
Timeout, malformed acknowledgement, or delivery loss is **unconfirmed**:
consult Silver history, never automatically resubmit. A new explicit action
captures a new token; even reopening a tile or reconnecting cannot replay an
old action. Superseded plans and submissions cannot update a new project.
Neither accepted work nor any local view change retargets a watched attempt.
Silver reads saved project inputs; neither action saves editor buffers.

## ASIC checklist observation

[`Silver_stage_observation`](silver_stage_observation.mli) independently watches
the verified project while the checklist is visible. Its bind target is an
exact ASIC run/workflow, an explicitly requested latest match for the active
chip/variant, flow and profile, or no selection. Native Silver resolves the
checklist's workspace selection or pin exactly; a missing pin never means the
latest run. Cobalt's latest-match mode is its own policy, not a read or write of
that workspace selection. The native registry orders runs by update, so the
companion compares producer start times and workflow reservation times instead.
The simulation attempt configured for the status tile is not an ASIC identity.

Observation uses plain project ASIC `Get`, exact `Observe` for eligible
unowned runs, and bounded `Load_summary` for eligible evidence. It never
registers or launches a run, changes a launch context, or reads from rendering.
Exact workflow linkage can show elaboration before physical allocation.
The captured endpoint is unconfirmed until there is explicit stage evidence;
neither overall run completion nor a current catalog implies any historical
stage result. Historical post-PNR STA remains distinct from a physical Timing
stage. A physical row may report an explicit native action mapping; only its
scope and endpoint are exposed, for comparison with the fresh launch catalog.
Historical action assignments are never replayed. Reader errors, missing
summary sources, stale transport snapshots, and
no matching run have distinct representations. A verified project/selection
change drops old evidence and abandons local requests, without cancelling
anything in Silver.

## Verification and remaining limits

`dune runtest -j4 silver_overview` includes `test_flow.ml`, which drives the
in-process service through stale planning and acknowledgement races, then
drives the production factory through offline protocol-shaped exchanges.
The latter verifies request order and IDs, rejected Routing when only the
description names it, exact Timing intent and reservation, unchanged reviewed
preview bytes on Kickoff, separate workflow/run identity, no launch when a
staged receipt is superseded, and no retry or simulation request. A simulation-only
hello is also checked to cause no ASIC calls. `test_recorded_flow.ml` separately
replays the captured C8 and C9 success exchanges in `test/wb095-*.sexp`. Those
fixtures preserve the actual request variants and reply fields used by the
adapter, including the opaque plan, but omit unrelated snapshots/polls and
replace each generated submission key at runtime. Silver's WB-095 ticket records
the independent live two-PTY evidence; replay is not itself a live check.
`test_stage_observation.ml` exercises a fake bound peer for progression while
visible, exact pins, scope matching, reader negotiation, stale status, and
late-reply fences without routing requests through the launch service.

No Silver extension is required for the supported paths above. A small
optional enhancement for tighter parity would be a **read-only, target-scoped
companion capability receipt** that names the selected target, authoritative
stage/alias meanings, current catalog generation and configured launch mode.
That would let clients identify unsupported older servers up front and fence
server-side catalog revisions without inferring them from public snapshots.
Cross-window reuse of Silver's current native workspace target/preferences
needs its own explicit attachment contract; do not infer those settings from
run evidence. Legacy providers without fresh endpoint advertisements, and
projects without source preparation, are intentionally not launched through
guesswork or historical `Stage.action` fallback.

Implementation references: Silver `protocol/{asic,preparation}.ml`,
`daemon/rpc_server.ml`, `backend/{asic_service,asic_public}.ml`,
`terminal/{stage_action,stage_launch_commands,launch_preferences,main}.ml`,
and the provider's `lib/{flow/spec,methodology_plan}.ml`.
