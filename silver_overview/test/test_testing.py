"""Exercise the Testing API and HTTP client across fake and recorded Silver peers."""
import json
from pathlib import Path
import re
import select
import subprocess
import sys

from fake_peer import Peer, SIMULATION, TIMEOUT, hello_reply, open_reply, parse_request, snapshot


ROOT = "/test/project with spaces"
INSTANCE = "daemon-c6"
PROJECT = "project-c6"


class Driver:
    def __init__(self, executable, endpoint, timeout=700):
        self.args = [executable, endpoint, str(timeout)]

    def __enter__(self):
        self.process = subprocess.Popen(
            self.args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
        )
        return self

    def __exit__(self, exc_type, *_):
        self.process.stdin.close()
        try:
            status = self.process.wait(timeout=TIMEOUT)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=TIMEOUT)
            raise
        finally:
            self.process.stdout.close()
        if exc_type is None:
            assert status == 0, status

    def send(self, *command):
        self.process.stdin.write(json.dumps(command) + "\n")
        self.process.stdin.flush()

    def receive(self, kind):
        assert select.select([self.process.stdout], [], [], TIMEOUT)[0], kind
        response = json.loads(self.process.stdout.readline())
        assert response["kind"] == kind, response
        return response

    def command(self, kind, *command):
        self.send(*command)
        return self.receive(kind)


def handshake(peer, driver, *, root=ROOT, opened_root=None):
    driver.send("connect", root)
    peer.hello().reply(hello_reply(INSTANCE))
    peer.open(root, instance=INSTANCE).reply(open_reply(PROJECT, opened_root or root))
    if opened_root is None:
        assert driver.receive("connected")["root"] == root
    else:
        assert "different project root" in driver.receive("error")["reason"]


def simulation(peer, operation):
    return peer.expect(SIMULATION, {
        "instance_id": INSTANCE, "project": PROJECT, "operation": operation,
    })


def get_launch(peer, expected_digest, expected_selection, keys):
    request = peer.expect(SIMULATION)
    fields = dict(parse_request(request.body))
    assert fields["instance_id"] == INSTANCE and fields["project"] == PROJECT, fields
    name, *payload = fields["operation"]
    assert name == "Launch", payload
    key = dict(payload).pop("submission_key")
    assert len(key) <= 128 and re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9._-]*", key), key
    assert key not in keys, (key, keys)
    keys.add(key)
    assert dict(payload) == {
        "submission_key": key, "discovery_digest": expected_digest, "selection": expected_selection,
    }, payload
    return request


def test_testing(executable, fixture_dir):
    def fixture(name):
        return json.loads((fixture_dir / f"c6-{name}.json").read_text())

    launch_fixture = fixture("launch")
    catalog_body = fixture("catalog")["response"]["body"]
    launch_body = launch_fixture["response"]["body"]
    captured = dict(parse_request(launch_fixture["request"]["body"]))["operation"]
    digest = dict(captured[1:])["discovery_digest"]
    selection = dict(captured[1:])["selection"]
    detail = dict(dict(parse_request(launch_body)[1])["detail"][0])
    root = detail["project_root"]
    command = ("launch", "FIFO", "seeded", "42", "50")
    keys = set()
    with Peer() as peer, Driver(executable, peer.endpoint) as driver:
        driver.send("connect", ROOT)
        peer.hello().reply(hello_reply(INSTANCE, version=2))
        assert "protocol v1" in driver.receive("error")["reason"]
        peer.assert_idle()
        handshake(peer, driver, opened_root="/somewhere/else")
        peer.assert_idle()

        # Empty project: schedule one discovery and poll it, without launching.
        handshake(peer, driver, root=root)
        driver.send("discover")
        simulation(peer, "Get").reply(snapshot().replace("(configured true)", "(configured false)"))
        assert "not configured" in driver.receive("error")["reason"]
        peer.assert_idle()
        driver.send("discover")
        simulation(peer, "Get").reply(snapshot())
        simulation(peer, "Discover").reply(snapshot().replace("(discovery_error ())",
                                                              '(discovery_error ("provider failed"))'))
        assert driver.receive("error")["reason"] == "provider failed"
        peer.assert_idle()
        driver.send("discover")
        simulation(peer, "Get").reply(snapshot())
        simulation(peer, "Discover").reply(snapshot().replace("(discovery_job ())",
                                                              "(discovery_job (job-1))"))
        simulation(peer, "Get").reply(catalog_body, chunked=True)
        catalog = driver.receive("catalog")
        assert catalog == {"kind": "catalog", "digest": digest, "suites": [{
            "id": "FIFO", "label": "FIFO", "default_seed": "42",
            "cases": [{"id": "seeded", "label": "seeded"}, {"id": "smoke", "label": "smoke"}],
            "parameters": [{"key": "n", "label": "n", "default": "10", "choices": ["10", "50"]}],
        }]}, catalog
        driver.command("rejected", "launch", "FIFO", "", "42", "50")
        driver.command("rejected", "launch", "FIFO", "seeded", "42", "99")
        peer.assert_idle()

        driver.send(*command)
        get_launch(peer, digest, selection, keys).reply(launch_body)
        assert driver.receive("accepted") == {
            "kind": "accepted", "attempt": detail["id"], "job": detail["job"],
        }

        replies = [
            ("rejected", '(Error ((kind Invalid_request)(message "not allowed")))', 200),
            ("rejected", '(Error ((kind Instance_changed)(message "daemon instance has changed")))', 200),
            ("rejected", '(Error ((kind Conflict)(message "Daemon is shutting down")))', 200),
            ("rejected", '((kind Invalid_request)(message "malformed simulation request"))', 400),
            ("uncertain", '(Error ((kind Internal_failure)(message "lost after reservation")))', 200),
            ("uncertain", '(Error ((kind Invalid_request)(message "unknown gateway reply")))', 502),
            ("uncertain", launch_body.replace(root, ROOT), 200),
            ("uncertain", launch_body.replace("(n 50)", "(n 10)"), 200),
            ("uncertain", "(Ok ((detail ())))", 200),
        ]
        for result, body, status in replies:
            driver.send(*command)
            get_launch(peer, digest, selection, keys).reply(body, status=status)
            driver.receive(result)
            peer.assert_idle(duration=0.02)

        driver.send(*command)
        get_launch(peer, digest, selection, keys).disconnect()
        driver.receive("uncertain")
        peer.assert_idle()

        # A deadline is ambiguous, even if a valid acknowledgement eventually appears.
        driver.send(*command)
        late = get_launch(peer, digest, selection, keys)
        driver.receive("uncertain")
        late.reply(launch_body)
        late.wait_sent()
        peer.assert_idle()

        handshake(peer, driver, root=root)
        driver.command("rejected", *command)  # Catalog still belongs to the closed connection.
        peer.assert_idle()
        driver.send("discover")
        simulation(peer, "Get").reply(catalog_body)
        driver.receive("catalog")
        driver.send(*command)
        get_launch(peer, digest, selection, keys).reply(
            '(Error ((kind Conflict)(message "Stale simulation discovery digest")))')
        driver.receive("stale")
        driver.command("stale", *command)
        peer.assert_idle()

        driver.send("discover")
        simulation(peer, "Get").reply(catalog_body.replace(digest, "fresh-digest"))
        driver.receive("catalog")
        driver.send(*command)
        get_launch(peer, "fresh-digest", selection, keys).reply(
            launch_body.replace(digest, "fresh-digest"))
        driver.receive("accepted")
        peer.assert_idle()


if __name__ == "__main__":
    test_testing(Path(sys.argv[1]).resolve(), Path(sys.argv[2]))
