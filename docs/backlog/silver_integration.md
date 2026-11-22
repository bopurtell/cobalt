# Silver integration: Cobalt-side tickets

**Status:** C1–C7 are **closed** for their Cobalt-side scope. C5 and C6 passed
live two-window checks for simulation observation and test quick launch,
respectively. C8–C9 are live-verified implementation slices, not duplicate feature
trackers. Silver's `docs/cobalt_editor_roadmap.md` and the named WB tickets own
the user workflows and end-to-end acceptance. “Ready for Silver” means the
Cobalt interface works against a local harness, not that the two apps have been
integrated. The WB records live under Silver's `docs/features/integrations/`.
Keep fixture exchanges and harness instructions with their adapter.

## Ticket status and handoffs

| Ticket | Status | Handoff |
| --- | --- | --- |
| [C1: Session open](#c1--open-a-location-in-a-live-session) | Closed | Silver WB-087/088: generic location, including test declarations |
| [C2: Hosted view](#c2--host-the-real-editor-view) | Closed | WB-087: persistent embedded editing |
| [C3: Terminal handoff](#c3--expose-toggleterm-as-a-host-action) | Closed | WB-089/090: numbered shells and focus |
| [C4: Main editor destination](#c4--address-an-opted-in-standalone-editor) | Closed | Silver navigation: second destination for the same location |
| [C5: Companion overview](#c5--optional-silver-module-and-overview-tile) | Closed | Cobalt-first monitoring against a real Silver endpoint |
| [C6: Test quick launch](#c6--run-a-silver-test-from-the-editor) | Closed | WB-093: tile `R` and exact `test`; no stage launch |
| [C7: Discover/connect wizard](#c7--discover-and-connect-to-a-shared-silver-project) | Closed | WB-094: owner-accepted after live embedded and attached verification |
| [C8: Stage checklist and aliases](#c8--stage-checklist-and-palette-aliases) | Open — owner testing | WB-095: native launch parity verified; verify aligned, colored rows and flow-selector handoff |
| [C9: Flow kickoff tile](#c9--flow-kickoff-tile) | Open — owner testing | WB-095: reviewed launch verified; compact flow selection is the primary interaction |

**Verification:** C7 reads Silver's locked share registry; C8 and C9 share
one flow adapter and can also use an explicit project binding. To rerun the
two-app checks, use Silver's `scripts/test-editor-project-sharing.py` (C7)
and `scripts/test-companion-flow-launch.py --slice c8|c9` (one slice per run).
Point `--cobalt` at the binary under test. Both harnesses create private projects
and state; WB-094 and WB-095 record the commands and expected results.

## C1 — Open a location in a live session

**Owner:** session/buffer management (`app/`, with UI navigation where needed).
Expose a typed operation for an existing editor session: project root, relative
file, optional position → opened or a specific failure. Specify line base and
column unit with a non-ASCII example. Reuse the normal buffer lookup and
navigation path. The editor knows nothing about test IDs or timing paths.

**Ready for Silver:** a harness opens two files, edits one, and reopens it at a
line. Buffer identity, unsaved bytes and undo survive. File-only requests work;
a missing target or wrong project returns a failure without creating a buffer.

**Handoff (WB-087/088):** [API, coordinate examples, and automated session
harness](../../app/OPEN_LOCATION.md). The API uses one-based display columns;
convert source byte offsets before handing them to Cobalt.

## C2 — Host the real editor view

**Owner:** UI/composition. Exercise a bounded editor surface with size, focus,
input, open-location and shutdown. Choose a hosted component or supervised
child based on a small host demo. Only the outer host owns the physical
terminal. Keep Cobalt's tile composition, commands and Git view inside the
surface; hiding the view is distinct from ending the session.

**Ready for Silver:** a sample host puts a sibling pane beside Cobalt, opens a
file via C1, resizes, transfers focus, then hides and restores the editor without
losing edits. A Cobalt-only binding works unchanged in hosted and standalone
mode; no host-side command registration. Document how Silver runs this demo.

**Handoff (WB-087):** Silver and Cobalt both use Bonsai_term. Mounting the
editor on the host's graph lets the panes share one layout, input router, and
cursor without a child PTY or a separate open/acknowledgement protocol. See
the [`cobalt.hosted` API](../../ui/HOSTED.md), [two-pane demo and automated
PTY test](../../examples/hosted_editor/README.md), and [external Dune
consumer](../../examples/hosted_consumer/README.md).

## C3 — Expose ToggleTerm as a host action

**Owner:** input/UI emits the *recognized* numbered toggle. An injected handler
chooses standalone Cobalt's usual pool or the outer host. Review
`ui/terminal_host.mli` and `terminal/host/runtime.mli`: expose the smallest
reusable pool/runtime interface Silver needs without pulling in the editor UI.

**Ready for Silver:** a fake outer host receives exactly one toggle for terminal
2, with no local PTY spawned. Returning focus restores Insert mode and cursor;
slow literal prefixes and pasted chords still reach the buffer. In standalone
mode, toggle/reopen still reaches the same shell. Supply a pool-only example
that keeps hidden output and shuts down its children.

**Handoff (WB-089/090):** use the [`cobalt.terminal` pool](../../examples/terminal_pool/README.md)
for shells and the hosted editor's [`on_toggle_terminal` callback](../../hosted/cobalt_hosted.mli)
for input. A numbered toggle carries `Some n`; an unnumbered toggle carries
`None`, leaving the most-recent selection with the frontend that owns the pool.

## C4 — Address an opted-in standalone editor

**Owner:** a session adapter delivers C1; the tile never listens for requests.
Allow one live Cobalt instance to be explicitly selected as “main” for a
project. Begin with a session-lived local transport (a user-local socket is one
option); specify selection, project scope, teardown and an acknowledged result.
Do not expose arbitrary palette execution. No resident Cobalt daemon is needed.

**Ready for Silver:** run two Cobalt instances and a tiny sender. Only the
selected instance opens the requested location. A missing or exited destination
is reported, not silently replaced. Dirty buffers in the destination are reused;
unsaved contents from another session are never implied to have transferred.
Silver owns the destination picker/bindings and unavailable-destination UX.

**Sender handoff:** [`cobalt-open` usage, acknowledgement semantics and
endpoint lifetime](../../main_editor/README.md). A lost acknowledgement is
distinct from an editor rejection: do not retry an open automatically.

## C5 — Optional Silver module and overview tile

**Owner:** an optional Silver-integration module, selected at composition time
like the [decoration provider](../architecture.md#boundaries). It owns endpoint,
project/run binding, connection lifetime, async reads, freshness and the latest
bounded status snapshot. The tile consumes prepared rows and emits user intents.
No network work during rendering; editor core and generic tile host need no
Silver types. Start with a build-time adapter, not a runtime plugin loader.

**Ready for Silver:** drive the module with a fake peer through initial status,
disconnect, project/run change and reconnect. Show scope and stale/unavailable
state; late replies cannot overwrite the new binding. Closing the tile never
cancels a run. Demonstrate ordinary standalone editing with the adapter absent.
**Live handoff:** bind the tile and a Silver window to the same run and compare
their observed status without coupling scroll, focus or window lifetime.

**Silver protocol:** the Testing daemon serves `POST /api/v1/simulation`
with `Content-Type: application/sexp` and `X-Workbench-Protocol: 1`.
`Get` reads the project's simulation snapshot; `Observe` reads a named
attempt. Both requests carry the daemon instance ID and project ID. The
authoritative types are in Silver's `protocol/simulation.ml`.

**Handoff:** [watch an attempt](../../bin/SILVER_OVERVIEW.md), inspect the
[adapter contract](../../silver_overview/README.md), or [reproduce the two-window
acceptance check and captured exchanges](../../examples/silver_overview/README.md).

## C6 — Run a Silver test from the editor

**Closed (WB-093): test quick launch only.** The optional Silver composition
owns the verified project binding, test catalog, settings and acknowledgements.
The tile and exact `test` invoke the same launch operation. A project binding
suffices before the first attempt exists; hiding the tile does not drop it or
retarget a pending launch. Stage work moved to C8/WB-095 and is not delivered
by C6.

The [launch adapter](../../silver_overview/README.md#testing-quick-launch)
documents the verified connection, discovery digest and one-shot submission.
The [session model](../../silver_overview/silver_quick_launch.mli) defines how
the tile and `test` alias share settings and resolve a target. Run
`dune runtest silver_overview` to exercise these contracts without a daemon.
The [two-window acceptance harness](../../examples/silver_overview/README.md#c6-slice-1-quick-launch-wire-capture)
verified that applying `n=50` created no attempt, then tile `R` and palette
`test` each created a distinct passing attempt with that value in Silver.

- The tile lists suites and variants; `R` runs the selected row. `Enter` opens
  a floating field editor; Apply returns to the row **without launching**, and
  cancel leaves the previous values intact.
- Overrides are scoped per project/suite/variant for the session, including across tile
  close/reopen. Exact palette alias `test` uses the configured default target,
  otherwise the last launched target for that project (not the last browsed row).
  If neither exists, open the picker. Show the resolved target and non-default
  values in the result, e.g. `Run test · FIFO / seeded · n=50`.
- Launch uses saved project inputs and captures the selection and discovery
  digest together. A stale catalog requires reselection, not substitution.
  Results distinguish rejection from unconfirmed delivery; reconnect never
  replays a submission. The watched attempt is independent.

**Regression coverage:** `dune runtest silver_overview screen bin` covers the
model, fake peer, headless tile/palette routing and standalone PTY. The
[captured Testing exchanges](../../examples/silver_overview/wire/) are reusable
regression fixtures, not ASIC launch examples.

## C7 — Discover and connect to a shared Silver project

**WB-094-editor-project-sharing.** From ordinary standalone Cobalt, open
`Silver: Discover/Connect…`, list local project shares with their project
identity and availability, and bind only after explicit selection and
verification. Keep the existing explicit endpoint/project route, including the
CLI, as a fallback. A daemon address alone is not a project share. Do not scan
ports or directories, infer a share from the active buffer, or auto-start a
daemon. No prior run/attempt is required.

**Implemented:** the picker reads Silver's locked WB-094 live registry. See the
[publication contract and fixture](../../silver_overview/README.md#discoverconnect-wb-094)
and [standalone fake-peer terminal test](../../bin/test_silver_share_cli.py).
The Cobalt-only fixture remains a separate input, not a production index.

**Start here:** [`Silver_connection`](../../silver_overview/silver_connection.mli)
already lists one native `daemon.sexp` plus known endpoints, validates loopback
URLs, and injects a fake peer for `hello` and exact-root project open. The
[composition](../../bin/composition/silver_adapter.enabled.ml) already swaps
command bindings only after verification; the [host interface](../../ui/silver_overview_host.mli)
and [`Ui_state`](../../screen/ui_state.ml) implement a generation-fenced endpoint
picker tied to the editor's startup root. Today the host hands the picker URL
strings, not project choices. Extend that seam with display rows and opaque
candidate IDs that retain the advertised identity; don't round-trip an
advertised selection as free-form URL input. Keep file lookup, handshake and
binding outside the tile. Show empty, malformed, withdrawn, unreachable and
connecting states with a usable manual route. A failed or superseded connect
must not replace the current working binding, retarget pending work, or silently
open a different project.

**Ready for Silver:** extend
[`test_connection`](../../silver_overview/test/test_connection.ml) with a
temporary share source and injected peer; check exact root/instance, stale,
duplicate or withdrawn choices, failed verification, and no launch RPC. Extend
the [headless picker tests](../../screen/test/test_silver_overview_tile.ml)
for no-flags entry, two projects (including one not at the editor startup root),
manual fallback, late lookup/connect, and focus return. Add a `bin` fake-peer
PTY test from ordinary startup; preserve the no-adapter startup smoke check.

**Live acceptance (Silver WB-094):** Select a share from unflagged Cobalt, compare backend/project
and retained attempt identity and outcome, then launch a test from Cobalt and
find it in Silver alongside that history. Check withdrawal or project switch
with an active job and independent offers: only discoverability changes, not
the service, job or history. A withdrawn offer cannot be used as a share
even if an explicit connection still works. These gates do not block the
fixture-backed wizard or manual path.

## C8 — Stage checklist and palette aliases

**Implemented:** the [shared launch adapter](../../silver_overview/FLOW.md)
uses advertised fresh stage endpoints and Silver's `Stage_fresh` /
`Launch_fresh` operations. The [terminal test](../../bin/test_silver_stage_cli.py)
exercises the checklist and exact aliases against an offline peer.

**Owner testing — run progress.** The checklist should show the stage name
once, Silver's observed execution status, and the flow/variant context. Follow
the latest applicable ASIC run unless a run is selected. Use muted styling
when no run or stage evidence is available; don't infer completion from the
requested endpoint. A stage's observed outcome and whether a fresh launch
through it is allowed are independent.

**WB-095-companion-flow-launch.** Focused `R`
launches the active flow through the selected stage, including a supported
fresh endpoint before any prior run. Preserve applicable flow/profile settings
and explicit assignments, or use the target's declared defaults if no
settings apply; change only the endpoint. Reject stale explicit inputs rather
than falling back. Exact `synth`, `timing` and `routing`
target their named stages independently of the selected row; resolve through
Silver's declared capabilities/defaults, never by guessing endpoint IDs or
using another target's profile. The exact action is row 1 and selected, even
when unavailable. Enter on an unavailable exact query reports why and cannot
dispatch a runner-up. Additional query text restores ordinary search. `R` keeps
tile focus; accepting/dismissing the palette returns to its caller.

**Start here:** reuse the cached rows / captured intent pattern in
[`Silver_overview_host`](../../ui/silver_overview_host.mli), the `test` path in
[`Ui_state`](../../screen/ui_state.ml), and
[`priority_alias`/`exact_only`](../../palette/catalog.mli). Put ASIC catalog
mapping, resolution and submit orchestration in the optional adapter, separate
from the test model and from watched simulation state. Use the same typed
submit path for checklist and palette. Capture the binding, catalog generation
and resolved target with each intent; revalidate before submission instead of
substituting new inputs. Cobalt should not duplicate Silver's provider policy
or launch on render, discovery, or selection.

**Ready for Silver:** add headless `screen` tests for a selected row that differs
from the alias, all three exact queries, unavailable Enter/no fallback, extra
text, focus, and palette dispatch with the checklist hidden. In `silver_overview`
test the launch seam with a fake service: one submit per ready intent, none
for stale/unsupported targets, matching captured inputs for equivalent `R`
and alias actions, and no replay after an unconfirmed reply. Surface accepted
identity without replacing the watched attempt.

**Handoff:** WB-095 records the seven-run comparison against native Silver.
The [captured C8 fixture](../../silver_overview/test/wb095-c8.sexp) replays the
wire contract in Cobalt. The live comparison covers default configuration;
explicit nondefault stage settings also have adapter tests.

## C9 — Flow kickoff tile

**Owner testing workflow:** Keep the editor visible beside a small flow selector.
`j`/`k` chooses the active flow without submitting. Open the command palette
and enter `st` to focus the stage checklist; `R` should launch the chosen flow
through the highlighted stage, with no intermediate Apply or Kickoff step.
`ed` should restore the editor even if a Silver tile was previously hidden.

**Implemented:** see [kickoff controls](../../bin/SILVER_OVERVIEW.md#kick-off-a-named-flow),
the [adapter's plan/submit contract](../../silver_overview/FLOW.md), and the
[terminal regression test](../../bin/test_silver_kickoff_cli.py). The latter
checks direct flow selection into checklist `R`, plus project switching during
preparation, exact reviewed values, and acknowledgement while the separate
review tab is hidden. WB-095 verifies the nondefault selector-driven stage
reservation and separately compares a reviewed preview against Silver's native
plan, observing one accepted workflow for two quick Kickoff presses.

**WB-095-companion-flow-launch.** Keep the default selector small and use
the optional review tab for editing inputs, reviewing the resolved preview
and explicitly choosing **Kickoff**. Show the resolved chip/variant, flow, profile, endpoint
and parameter values supplied by Silver. Disable Kickoff with a reason for
missing, pending, failed or stale preparation; submit only the exact ready
preview. Opening the tile, editing/applying inputs and preparing a preview
do not start execution. Kickoff uses saved project inputs; no editor auto-save.
Show pending, accepted identity, rejection or unconfirmed delivery without
stealing focus or changing a watched run. Hiding the tile must not discard
a pending reply or cancel Silver's work.

**Start here:** model the draft separately from the test model
([`Silver_quick_launch`](../../silver_overview/silver_quick_launch.mli) is an
example of captured edits and explicit apply). Mount the new tile using the
[optional composition](../../bin/composition/dune) and the
[view registry seam](../../ui/silver_overview_host.ml). Consume the shared
C8/C9 launch interface against a fake service, not C8's checklist or a live
daemon. Snapshot binding, catalog generation and preview identity at Kickoff;
invalidate stale drafts or plans visibly, never pick a replacement silently.

**Ready for Silver:** add model tests for declared defaults, input validation
and stale generations; headless tile tests for edit/cancel/Apply and preview
versus Kickoff, focus and hide/reopen; fake-service (and `bin` PTY) tests for exactly one
submission with the reviewed values, switching project during planning, delayed
acknowledgements, and no automatic replay. Test with an explicit project
binding and keep no-Silver editing unaffected.

**Handoff:** the [captured C9 fixture](../../silver_overview/test/wb095-c9.sexp)
preserves the real preparation and submission exchanges. The WB-095 two-window
check verifies preview alone creates no run and a superseded preview cannot
start a workflow. It exercises the real service with deterministic producers,
not a physical EDA flow.
