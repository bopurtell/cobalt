# Shared Silver flow composition

The selected, adapter-enabled `Silver_adapter` owns one `Silver_flow.t` per
editor session. Both Stage and Kickoff consume `session.flow`; neither owns
binding, refresh, or shutdown. The composition binds/loads the flow model only
after the normal project verification succeeds. A failed or superseded
verification leaves the previous flow service intact. Flow change notifications
advance the same host revision used by the optional Silver views. The same
notification path redraws the checklist from cached ASIC evidence. Checklist
visibility starts or pauses its own observer without changing the flow catalog
or the independent Testing-attempt observer.

The checklist follows the latest ASIC evidence in the verified project and
active chip/variant, flow, and profile, or pins a retained run in that same
scope. On a scope change or project replacement it cannot project earlier
evidence. Reported physical stages determine order and labels; a unique stage
receipt mapping identifies an advertised launch destination. Evidence-only
rows are blocked, and catalog launch intents still resolve from current local
inputs, never from historical assignments.

Project replacement fences catalog/preview/intent state. A submission already
sent keeps the verified project transport alive until its acknowledgement
is resolved; shutdown closes that transport without sending a cancellation
or retry. All replies stay scoped to the original request. Accepted identities
are reported without changing a watched attempt.

`factory_with_flow_service` is an in-process test seam: it replaces the
companion service *after* ordinary verification. `cobalt_stage_fixture` uses
it to drive a deterministic catalog, prepare/submit and delayed acknowledgement
through a PTY while using the real ASIC observation transport. The same test
runs the production executable against a
simulation-only peer and checks that it sends no ASIC RPC. Use
`dune runtest -j4 screen bin` for the UI/harness checks, and
`dune runtest -j4 silver_overview` for the native protocol-shaped fixtures.
Neither is a live-parity check. The default factory uses
`Silver_flow.production`. A build without `silver_overview/` selects stubs
and imports no Silver model or transport.
