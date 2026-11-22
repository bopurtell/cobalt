# Silver integration: Cobalt-side tickets

**Status:** C1–C5 are implemented. C5 has also passed its live two-window
handoff; C6 is proposed. Use these as implementation slices, not duplicate feature
trackers. Silver's `docs/cobalt_editor_roadmap.md` owns the user workflows and
end-to-end acceptance. “Ready for Silver” here means a Cobalt interface is usable
and demonstrated against a local harness. It does not mean the two apps have
been integrated. Keep example requests, replies and harness instructions with
the module that implements them so Silver can consume the same examples.

## Delivery order

| Ticket | Start after | Handoff |
| --- | --- | --- |
| [C1: Session open](#c1--open-a-location-in-a-live-session) | Now | Silver WB-087/088: generic location, including test declarations |
| [C2: Hosted view](#c2--host-the-real-editor-view) | C1 for the demo | WB-087: persistent embedded editing |
| [C3: Terminal handoff](#c3--expose-toggleterm-as-a-host-action) | Runtime packaging now; C2 for hosted input | WB-089/090: numbered shells and focus |
| [C4: Main editor destination](#c4--address-an-opted-in-standalone-editor) | C1; independent of C2/C3 | Silver navigation: second destination for the same location |
| [C5: Companion overview](#c5--optional-silver-module-and-overview-tile) | Now, with a fake peer | Cobalt-first monitoring against a real Silver endpoint |
| [C6: Companion commands](#c6--run-a-silver-command-from-the-editor) | C5 connection/model contract | Cobalt-first launch and acknowledgement |

**Suggested first batch:** C1 → C2, then C3. Silver can start the test jump as
soon as C2 lands; it need not wait for C4–C6. If opening in the main editor
matters more than shared shells, do C4 immediately after C1. For C5/C6, agree
one example status response and one launch/result exchange against Silver's
actual public protocol early. A fixture can unblock Cobalt UI work; it cannot
establish wire compatibility.

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

## C6 — Run a Silver command from the editor

**Owner:** the Silver module owns requests/results. Extend palette/command
routing only enough to invoke an adapter action from a focused code buffer as
well as from a tile. Start with “run this named catalog test”; capture the
project and test identity at invocation. Route the typed action to Silver's
execution service rather than forwarding keys to a Silver window.

**Ready for Silver:** with code focused, dispatch one request to a fake peer
and surface accepted/rejected/unavailable results without stealing focus.
After disconnect, report an unconfirmed launch rather than replaying it on
reconnect. An acknowledgement is a command result, not a coalescible overview
snapshot. **Live handoff:** launch once from standalone Cobalt and observe the
same attempt in Silver; closing Cobalt leaves the attempt running.
