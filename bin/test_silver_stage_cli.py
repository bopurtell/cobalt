"""C8 through the real CLI/PTY with a synthetic companion service, not Silver wire."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import time

from test_silver_cli import editor, wait
from test_silver_quick_launch_cli import send


def test(fixture, binary, stub):
    with tempfile.TemporaryDirectory(prefix="cobalt-silver-stage-") as temporary:
        root = Path(temporary).resolve()
        file = root / "code.txt"
        file.write_text("UNRELATED_EDITOR_FILE\n")
        journal = root / "submitted"
        release = root / "release"
        env = dict(os.environ, HOME=temporary, XDG_CONFIG_HOME=temporary, XDG_RUNTIME_DIR=temporary,
                   TERM="xterm-256color", COLORTERM="truecolor", LC_ALL="C.UTF-8",
                   COBALT_STAGE_FIXTURE_JOURNAL=str(journal), COBALT_STAGE_FIXTURE_RELEASE=str(release))
        requests = []

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def result(self, text):
                payload = text.encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/sexp")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def do_GET(self):
                requests.append(self.path)
                assert self.path == "/api/hello", self.path
                self.result("((protocol_versions (1)) (capabilities (simulation)) (instance_id fixture))")

            def do_POST(self):
                requests.append(self.path)
                body = self.rfile.read(int(self.headers["Content-Length"])).decode()
                if self.path == "/api/v1/open-project":
                    assert str(root) in body and "(instance_id fixture)" in body, body
                    self.result(f"(Ok ((project ((id project) (root ((path {json.dumps(str(root))})))))))")
                else:
                    assert self.path == "/api/v1/simulation", self.path
                    assert "(operation Get)" in body and "(project project)" in body, body
                    self.result("(Ok ((configured false) (discovery ()) (discovery_digest ())"
                                " (discovery_job ()) (discovery_error ()) (attempts ()) (detail ())))")

        def lines():
            return journal.read_text().splitlines() if journal.exists() else []

        with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            threading.Thread(target=server.serve_forever, daemon=True).start()
            endpoint = f"http://127.0.0.1:{server.server_port}"
            flags = ["--silver-endpoint", endpoint, "--silver-project", str(root)]
            try:
                with editor(stub, file, env, []) as ui:
                    ui.see(b"UNRELATED_EDITOR_FILE")
                    send(ui, [b" cc", b"synth"])
                    ui.see(b"Silver adapter not built")
                    send(ui, [b"\r", b"iX\x1b", b" w", b" q"])
                    assert ui.process.wait(timeout=4) == 0
                    assert file.read_text() == "XUNRELATED_EDITOR_FILE\n"
                assert not requests
                with editor(binary, file, env, flags, width=300) as ui:
                    ui.see(b"Silver Testing provider is not configured")
                    send(ui, [b" cc", b"silver stage checklist", b"\r"])
                    ui.see(b"Silver: Stage checklist")
                    ui.see(b"Silver does not advertise ASIC operations")
                    send(ui, [b" cc", b"timing"])
                    send(ui, [b"\r", b"\x1b", b" q"])
                    assert ui.process.wait(timeout=4) == 0
                assert not lines()

                with editor(fixture, file, env, flags, width=300) as ui:
                    ui.see(b"XUNRELATED_EDITOR_FILE")
                    send(ui, [b" cc", b"ov", b"\t", b"\r",
                              b" cc", b"st", b"\t", b"\r"])
                    ui.see(b"mapped-post-cts")
                    ui.see(b"CTS")
                    ui.see(b"Signoff")
                    ui.see(b"endpoint cts")
                    ui.see(b"endpoint mapped-final-report")
                    assert b"Clock tree synthesis" not in ui.output
                    ui.see(b"Routing endpoint not published")
                    send(ui, [b"G", b"R", b" cc", b"routing", b"\t", b"\r"])
                    assert not lines(), lines()
                    send(ui, [b"gg", b"j", b"R"])
                    wait(lambda: len(lines()) == 1)
                    # The fixture acknowledgement arrives after the checklist
                    # has been hidden; PTY history still receives the run ID.
                    send(ui, [b" cc", b"Toggle Silver: Stage checklist", b"\r", b"iY\x1b", b" w"])
                    wait(lambda: file.read_text() == "YXUNRELATED_EDITOR_FILE\n")
                    release.touch()
                    send(ui, [b" vM", b" st"])
                    ui.see(b"stage-fixture-run")
                    send(ui, [b"\x1b"])
                    send(ui, [b" cc", b"timing", b"\r"])
                    wait(lambda: len(lines()) == 2)
                    send(ui, [b" vM"])
                    ui.see(b"Delivery unconfirmed")
                    send(ui, [b"\x1b"])
                    assert lines() == [
                        "fixture-chip/fixture-variant fixture-flow fixture-profile mapped-post-cts"
                    ] * 2
                    send(ui, [b" cc", b"silver stage checklist", b"\r", b"gg", b"j", b"j", b"R"])
                    wait(lambda: len(lines()) == 3)
                    send(ui, [b"j", b"R"])
                    wait(lambda: len(lines()) == 4)
                    assert lines()[2:] == [
                        "fixture-chip/fixture-variant fixture-flow fixture-profile cts",
                        "fixture-chip/fixture-variant fixture-flow fixture-profile mapped-final-report",
                    ]
                    send(ui, [b"\x1b"])
                    # Refresh reads only, and does not replay the unconfirmed
                    # launch. One explicit action corresponds to one submit.
                    count = len(requests)
                    send(ui, [b" vU", b"r"])
                    wait(lambda: len(requests) > count)
                    time.sleep(.25)
                    assert len(lines()) == 4, lines()
                    send(ui, [b"\x1b", b" q"])
                    assert ui.process.wait(timeout=4) == 0
            finally:
                release.touch()
                server.shutdown()
        assert set(requests) == {"/api/hello", "/api/v1/open-project", "/api/v1/simulation"}, requests
    print("Silver stage CLI: absent and unsupported reasons, explicit fixture launches, no replay")


if __name__ == "__main__":
    test(*(str(Path(arg).resolve()) for arg in sys.argv[1:]))
