"""Exercise the real adapter (including its HTTP transport) against a fake daemon."""
import json
from pathlib import Path
import select
import subprocess
import sys
import time

from fake_peer import (
    Peer, TIMEOUT, detail, hello_reply, open_reply, parse_request, snapshot, summary,
)


DRIVER = Path(sys.argv[1]).resolve()
ROOT = "/test/project space"
OTHER_ROOT = "/test/other project"


class Adapter:
    def __init__(self, endpoint):
        self.endpoint = endpoint

    def __enter__(self):
        self.process = subprocess.Popen(
            [DRIVER, self.endpoint], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return self

    def __exit__(self, exc_type, *_):
        self.process.stdin.close()
        try:
            status = self.process.wait(timeout=TIMEOUT)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=TIMEOUT)
            if exc_type is None:
                raise
        else:
            if exc_type is None:
                assert status == 0, self.process.stderr.read().decode()
        finally:
            self.process.stdout.close()
            self.process.stderr.close()

    def command(self, *parts):
        self.process.stdin.write(("\t".join(parts) + "\n").encode())
        self.process.stdin.flush()
        assert select.select([self.process.stdout], [], [], TIMEOUT)[0], parts
        line = self.process.stdout.readline()
        assert line, (parts, self.process.poll())
        return json.loads(line)

    def bind(self, root=ROOT, attempt=""):
        state = self.command("bind", root, attempt)
        assert state["state"] == "unavailable" and "attempts" not in state, state

    def wait(self, wanted, **fields):
        until = time.monotonic() + TIMEOUT
        while True:
            state = self.command("read")
            if state["state"] == wanted and all(state.get(k) == v for k, v in fields.items()):
                return state
            assert time.monotonic() < until, (state, wanted, fields)
            time.sleep(0.01)


def handshake(peer, *, root=ROOT, project="project-1", instance="daemon-1", attempt=None,
              hello=None):
    (hello or peer.hello()).reply(hello_reply(instance))
    peer.open(root, instance=instance).reply(open_reply(project, root))
    return peer.status(project, attempt, instance=instance)


def assert_attempts(state, *attempts):
    assert [attempt["id"] for attempt in state["attempts"]] == list(attempts), state


def refresh_and_reconnect():
    with Peer() as peer, Adapter(peer.endpoint) as adapter:
        initial = adapter.command("read")
        assert initial["state"] == "unavailable" and "attempts" not in initial, initial
        peer.assert_idle()

        adapter.bind()
        first = handshake(peer)
        assert adapter.command("read")["state"] == "unavailable"
        first.reply(snapshot([summary("first"), summary("second", lifecycle="Finished", outcome="Passed")]))
        fresh = adapter.wait("fresh", root=ROOT, project="project-1", instance="daemon-1")
        assert_attempts(fresh, "first", "second")
        assert fresh["run"] is None and not fresh["truncated"], fresh
        assert fresh["attempts"][1] == {
            "id": "second", "suite": "test suite", "lifecycle": "Finished", "outcome": "Passed",
        }, fresh

        poll = peer.status("project-1")
        poll.reply(snapshot([summary("third")]), chunked=True)
        refreshed = adapter.wait("fresh", attempts=[
            {**fresh["attempts"][0], "id": "third"},
        ])
        assert_attempts(refreshed, "third")

        peer.status("project-1").disconnect()
        stale = adapter.wait("stale")
        assert_attempts(stale, "third")
        assert stale["project"] == "project-1" and stale["instance"] == "daemon-1", stale
        assert stale["reason"], stale
        recovered = handshake(peer, project="project-after-restart", instance="daemon-2")
        state = adapter.command("read")
        assert state["state"] == "unavailable" and "attempts" not in state, state
        recovered.reply(snapshot())
        fresh = adapter.wait("fresh", project="project-after-restart", instance="daemon-2")
        assert_attempts(fresh)


def reject_wrong_scope():
    with Peer() as peer, Adapter(peer.endpoint) as adapter:
        adapter.bind()
        peer.hello().reply(hello_reply(version=2))
        # Retry negotiation, not open-project against an incompatible daemon.
        peer.hello().reply(hello_reply(capabilities="snapshot"))
        peer.hello().reply(hello_reply())
        peer.open(ROOT).reply(open_reply("alien", OTHER_ROOT))
        # Retry the explicit project; never publish or query the returned wrong root.
        valid = handshake(peer, project="correct")
        assert adapter.command("read")["state"] == "unavailable"
        valid.reply(snapshot([summary("project-only")]))
        assert_attempts(adapter.wait("fresh", project="correct"), "project-only")

        adapter.bind(OTHER_ROOT, "desired")
        wrong_root = handshake(peer, root=OTHER_ROOT, project="project-2", attempt="desired")
        wrong_root.reply(snapshot(observed=detail("desired", ROOT)))
        wrong_id = handshake(peer, root=OTHER_ROOT, project="project-2", attempt="desired")
        assert adapter.command("read")["state"] == "unavailable"
        wrong_id.reply(snapshot(observed=detail("some-other-attempt", OTHER_ROOT)))
        unknown = handshake(peer, root=OTHER_ROOT, project="project-2", attempt="desired")
        assert adapter.command("read")["state"] == "unavailable"
        unknown.reply(snapshot([summary("desired")]))  # Summary alone is not Observe evidence.
        exact = handshake(peer, root=OTHER_ROOT, project="project-2", attempt="desired")
        assert adapter.command("read")["state"] == "unavailable"
        exact.reply(snapshot([summary("irrelevant")], detail("desired", OTHER_ROOT)))
        fresh = adapter.wait("fresh", root=OTHER_ROOT, run="desired", project="project-2")
        assert_attempts(fresh, "desired")

        # Teardown during a real HTTP Observe. The peer remains up and accepts
        # any sent requests, so even accidental run mutation would be visible.
        pending = peer.status("project-2", "desired")
        assert adapter.command("close")["state"] == "unavailable"
        pending.reply(snapshot(observed=detail("desired", OTHER_ROOT))).wait_sent()
        peer.assert_idle(0.35)
        adapter.bind(OTHER_ROOT, "desired")
        pending = handshake(peer, root=OTHER_ROOT, project="project-2", attempt="desired")
        assert adapter.command("shutdown")["state"] == "unavailable"
        pending.reply(snapshot(observed=detail("desired", OTHER_ROOT))).wait_sent()
        adapter.bind(OTHER_ROOT, "desired")
        peer.assert_idle(0.35)
        assert adapter.command("read")["state"] == "unavailable"
    peer.assert_idle()


def bounded_and_malformed():
    with Peer() as peer, Adapter(peer.endpoint) as adapter:
        adapter.bind()
        rows = [summary(f"row-{n}") for n in range(100)]
        rows[0] = summary("row-0", suite="unsafe\nline\t" + "界" * 2000)
        handshake(peer).reply(snapshot(rows))
        fresh = adapter.wait("fresh")
        assert len(fresh["attempts"]) == 25 and fresh["truncated"], fresh
        assert fresh["attempts"][0]["id"] == "row-0", fresh
        suite = fresh["attempts"][0]["suite"]
        assert 0 < len(suite.encode()) <= 256 and "\n" not in suite and "\t" not in suite, suite

        request = peer.status("project-1")
        bad_bodies = [
            ("this is not one valid S-expression", {}),
            ("(Ok ((attempts ((not-a-record)))(detail ())))", {}),
            ("(Ok ((attempts ())(attempts ())(detail ())))", {}),
            (snapshot([summary("bad-lifecycle", lifecycle="Unknown")]), {}),
            (snapshot([summary("x" * 5000)]), {}),
            ("(" * 15000 + ")" * 15000, {}),
            (snapshot(), {"length": 128 * 1024 * 1024}),
            (snapshot(), {"length": len(snapshot()) + 20}),
            (snapshot(), {"chunked": True, "headers": [("Content-Length", "1")]}),
            (snapshot(), {"headers": [("X-Long", "a" * 20_000)]}),
            ("", {"status": 302, "headers": [("Location", "/not-the-explicit-endpoint")]}),
            ('(Error ((kind Internal_failure)(message "' + 'x' * 8192 + '")))', {}),
            ('((kind Instance_changed)(message "daemon restarted"))', {"status": 409}),
        ]
        for body, options in bad_bodies:
            request.reply(body, **options)
            # A re-handshake means this particular response has been processed.
            hello = peer.hello()
            stale = adapter.command("read")
            assert stale["state"] == "stale", stale
            assert stale["attempts"] == fresh["attempts"] and stale["truncated"], stale
            # RPC kind and message are independently bounded display fields.
            assert 0 < len(stale["reason"].encode()) <= 550, stale["reason"]
            request = handshake(peer, hello=hello)
        request.reply(snapshot([summary("after-bad-responses")]).replace(
            "(next_before ())", "(next_before (older))",
        ))
        fresh = adapter.wait("fresh")
        assert_attempts(fresh, "after-bad-responses")
        assert fresh["truncated"], fresh

        timed_out = peer.status("project-1")
        stale = adapter.wait("stale")
        assert "timed out" in stale["reason"].lower(), stale
        timed_out.disconnect()


def editor_exit_does_not_cancel():
    with Peer() as peer:
        with Adapter(peer.endpoint) as adapter:
            adapter.bind(ROOT, "still-running")
            handshake(peer, attempt="still-running").reply(
                snapshot(observed=detail("still-running", ROOT)),
            )
            fresh = adapter.wait("fresh")
            assert fresh["attempts"][0]["lifecycle"] == "Running", fresh
            outstanding = peer.status("project-1", "still-running")
            # Close stdin to drive normal process exit while an Observe is in flight.
        outstanding.reply(snapshot(observed=detail("still-running", ROOT))).wait_sent()
        peer.assert_idle(0.35)


def replay_silver_capture(directory):
    def capture(name):
        return json.loads((directory / f"{name}.json").read_text())

    hello = capture("hello")
    opened = capture("open-project")
    observed = capture("observe")
    open_fields = dict(parse_request(opened["request"]["body"]))
    root = open_fields["root"]
    instance = open_fields["instance_id"]
    _, attempt_id = dict(parse_request(observed["request"]["body"]))["operation"]

    def replay(peer, example):
        request = example["request"]
        fields = dict(parse_request(request["body"])) if request["body"] else None
        response = example["response"]
        peer.expect(request["target"], fields).reply(response["body"], status=response["status"])
        return fields

    expected = {
        "id": attempt_id,
        "suite": "fixture",
        "lifecycle": "Finished",
        "outcome": "Passed",
    }
    with Peer() as peer, Adapter(peer.endpoint) as adapter:
        adapter.bind(root)
        replay(peer, hello)
        replay(peer, opened)
        get_fields = replay(peer, capture("get"))
        project = get_fields["project"]
        state = adapter.wait("fresh", root=root, instance=instance, project=project, run=None)
        assert state["attempts"] == [expected], state

        adapter.bind(root, expected["id"])
        replay(peer, hello)
        replay(peer, opened)
        replay(peer, observed)
        state = adapter.wait("fresh", root=root, instance=instance, project=project, run=expected["id"])
        assert state["attempts"] == [expected], state

        missing = capture("observe-not-found")
        _, unknown_id = dict(parse_request(missing["request"]["body"]))["operation"]
        adapter.bind(root, unknown_id)
        replay(peer, hello)
        replay(peer, opened)
        replay(peer, missing)
        # Observe really was handled before the next handshake; no Get / fallback.
        peer.hello()
        state = adapter.command("read")
        assert state["state"] == "unavailable" and "attempts" not in state, state
        assert "not found" in state["reason"].lower(), state


if __name__ == "__main__":
    refresh_and_reconnect()
    reject_wrong_scope()
    bounded_and_malformed()
    editor_exit_does_not_cancel()
    replay_silver_capture(Path(sys.argv[2]))
