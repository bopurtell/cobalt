# Silver integration: Cobalt-side tickets

**Status:** C1–C5 are **closed** for their Cobalt-side scope; their handoff
evidence is linked below. C5 also passed its live two-window check. C6 is
**in progress**, starting with test quick launch. Use these as implementation slices, not duplicate feature
trackers. Silver's `docs/cobalt_editor_roadmap.md` owns the user workflows and
end-to-end acceptance. “Ready for Silver” here means a Cobalt interface is usable
and demonstrated against a local harness. It does not mean the two apps have
been integrated. Keep example requests, replies and harness instructions with
the module that implements them so Silver can consume the same examples.

## Ticket status and handoffs

| Ticket | Status | Handoff |
| --- | --- | --- |
| [C1: Session open](#c1--open-a-location-in-a-live-session) | Closed | Silver WB-087/088: generic location, including test declarations |
| [C2: Hosted view](#c2--host-the-real-editor-view) | Closed | WB-087: persistent embedded editing |
| [C3: Terminal handoff](#c3--expose-toggleterm-as-a-host-action) | Closed | WB-089/090: numbered shells and focus |
| [C4: Main editor destination](#c4--address-an-opted-in-standalone-editor) | Closed | Silver navigation: second destination for the same location |
| [C5: Companion overview](#c5--optional-silver-module-and-overview-tile) | Closed | Cobalt-first monitoring against a real Silver endpoint |
| [C6: Companion commands](#c6--run-a-silver-command-from-the-editor) | In progress | WB-093: test quick launch first, then stage quick launch |

**Next:** C6 builds on C5's connection model. Use the two delivery slices below;
Silver WB-093 is the single end-to-end acceptance record.

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

**Status: slice 1 implemented and live-tested; slice 2 proposed.** One optional Silver module owns the connection,
selected targets, settings, launch requests and acknowledgements. It may split those
responsibilities into internal modules. Tiles render module state and emit intents;
tile `R` and palette commands invoke the same launch operation.

**Connect once.** `Silver: Connect…` lists known or advertised local Silver
connections and accepts an explicit endpoint. Verify Silver's handshake before
binding. A project binding suffices before the first attempt exists. Changing
buffers or hiding a tile neither retargets commands nor drops pending results.

**Slice 1 — test quick launch**

The [launch adapter](../../silver_overview/README.md#testing-quick-launch)
documents the verified connection, discovery digest and one-shot submission.
The [session model](../../silver_overview/silver_quick_launch.mli) defines how
the tile and `test` alias share settings and resolve a target. Run
`dune runtest silver_overview` to exercise these contracts without a daemon.
The [two-window acceptance harness](../../examples/silver_overview/README.md#c6-slice-1-quick-launch-wire-capture)
verified that applying `n=50` created no attempt, then tile `R` and palette
`test` each created a distinct passing attempt with that value in Silver.

- Render suites and their variants in a compact tile. `R` on a suite launches with
  configured/catalog defaults; `R` on a variant launches that variant. `Enter`
  opens a floating field editor. Apply returns to the row **without launching**;
  cancel leaves its previous values intact.
- Keep overrides per project/suite/variant for the session, including across tile
  close/reopen. Exact palette alias `test` uses the configured default target,
  otherwise the last launched target for that project (not the last browsed row).
  If neither exists, open the picker. Show the resolved target and non-default
  values in the result, e.g. `Run test · FIFO / seeded · n=50`.
- Launch saved project inputs. Capture the selection and discovery digest together;
  a stale catalog requires a fresh selection rather than a silent substitution.

**Slice 2 — stage quick launch.** `R` on a checklist row runs the active flow
through that stage using Silver's quick-launch rules and defaults. Exact palette
aliases `synth`, `timing` and `routing` target their named stages regardless of
the selected row. For these fundamental aliases and `test`, put the action in
**row 1, selected** on an exact query. More text resumes normal search. An
unavailable exact action shows its reason; Enter must not launch another match.

**Focus and results.** Keep focus in the invoking tile after `R`; dismissing the
palette restores its caller. Show acceptance and the run/attempt identity without
replacing a watched run. Separate rejection from a lost acknowledgement; never
resubmit automatically on reconnect. Closing Cobalt leaves Silver's work running.

**Handoff to WB-093:** capture one real catalog/launch/reply exchange and use
it as a fake-peer fixture. Verify one submission per invocation, focus, and
unconfirmed delivery. Then run two live checks: (1) change `n=10` to `50`,
launch via `R`, hide the tile and launch via palette `test` from code; Silver
must show two distinct attempts for the same target with `n=50`; (2) compare
a checklist `R` launch with an exact alias launch through the same stage.
