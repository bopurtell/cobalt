"""Replay Silver's recorded catalog and launch reply through the real Cobalt PTY."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import socket
import sys
import tempfile
import threading
import time

from test_silver_cli import editor, wait


def send(ui, keys):
    for key in keys:
        ui.keys(key)
        time.sleep(.08)


def new_output(ui, start, marker):
    wait(lambda: marker in ui.output[start:])


def test(binary, wire):
    catalog = json.loads((wire / "c6-catalog.json").read_text())["response"]["body"]
    ack = json.loads((wire / "c6-launch.json").read_text())["response"]["body"]
    recorded_root = re.search(r'\(project_root"([^"]+)"\)', ack)[1]
    digest = re.search(r"\(discovery_digest\(([^)]+)\)\)", catalog)[1]
    attempt = re.search(r"\(id (sim-[a-z0-9]+)\)", ack)[1]
    parent = os.getenv("COBALT_TEST_SHARE_TMPDIR", "/tmp")
    with tempfile.TemporaryDirectory(prefix="cobalt-silver-quick-launch-", dir=parent) as temp:
        root = Path(temp).resolve() / "project with spaces"
        root.mkdir()
        file = root / "main.txt"
        file.write_text("UNRELATED_EDITOR_FILE\n")
        env = dict(os.environ, HOME=temp, XDG_CONFIG_HOME=temp, XDG_RUNTIME_DIR=temp,
                   TERM="xterm-256color", COLORTERM="truecolor", LC_ALL="C.UTF-8")
        launches, requests = [], []
        release = threading.Event()

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def result(self, text):
                body = text.encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/sexp")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                requests.append(self.path)
                assert self.path == "/api/hello"
                self.result("((protocol_versions (1)) (capabilities (simulation)) "
                            "(instance_id fixture))")

            def do_POST(self):
                requests.append(self.path)
                body = self.rfile.read(int(self.headers["Content-Length"])).decode()
                assert "(instance_id fixture)" in body, body
                if self.path == "/api/v1/open-project":
                    assert str(root) in body, body
                    self.result(f"(Ok ((project ((id project) (root ((path {json.dumps(str(root))})))))))")
                    return
                assert self.path == "/api/v1/simulation" and "(project project)" in body, body
                if "(operation Get)" in body:
                    self.result(catalog)
                else:
                    assert "(operation(Launch" in body.replace(" ", ""), body
                    launches.append(body)
                    number = len(launches)
                    assert f"(discovery_digest{digest})" in body.replace(" ", ""), body
                    assert "(selection((suiteFIFO)(cases(seeded))(seed42)(parameters((n50)))(asic_inputs())))" in body.replace(" ", ""), body
                    if number == 1:
                        assert release.wait(8), "Cobalt did not hide the tile before acceptance"
                        self.result(ack.replace(recorded_root, str(root)))
                    else:
                        # The daemon could still execute the launch after the connection closes.
                        self.connection.shutdown(socket.SHUT_RDWR)
                        self.close_connection = True

        with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            threading.Thread(target=server.serve_forever, daemon=True).start()
            endpoint = f"http://127.0.0.1:{server.server_port}"
            flags = ["--silver-endpoint", endpoint, "--silver-project", str(root)]
            try:
                with editor(binary, file, env, flags, width=420) as ui:
                    ui.see(b"seeded")
                    send(ui, [b" cc", b"test", b"\r"])
                    ui.see(b"Choose a Silver test")
                    assert not launches, "Opening the first-use picker launched a test"
                    send(ui, [b"\x1b"])
                    send(ui, [b" vU", b"j", b"\r"])
                    ui.see(b"Test settings")
                    send(ui, [b"\t", b"\x15", b"50", b"\r"])
                    assert not launches, "Apply unexpectedly launched a test"
                    send(ui, [b"\r", b"\t", b"\x15", b"10", b"\x1b"])
                    assert not launches, "Cancel unexpectedly launched a test"
                    ui.keys(b"R")
                    wait(lambda: len(launches) == 1)
                    # R must have left this exact tile row focused.
                    start = len(ui.output)
                    ui.keys(b"\r")
                    new_output(ui, start, b"Test settings")
                    send(ui, [b"\x1b", b"\x1b", b" vS"])
                    ui.see(b"Silver: Overview hidden")
                    release.set()
                    send(ui, [b" vM", b" st"])
                    ui.see(attempt.encode())
                    send(ui, [b"\x1b"])
                    start = len(ui.output)
                    send(ui, [b" cc", b"test"])
                    new_output(ui, start, b"Run test")
                    ui.keys(b"\r")
                    wait(lambda: len(launches) == 2)
                    send(ui, [b" vM"])
                    ui.see(b"Delivery unconfirmed")
                    send(ui, [b"\x1b"])
                    keys = [re.search(r"\(submission_key\s*([^() ]+)\)", body)[1]
                            for body in launches]
                    assert len(set(keys)) == 2, keys
                    # Palette returned to code. A verified reconnect to the same
                    # project may refresh reads, never the unconfirmed submission.
                    send(ui, [b"iX\x1b", b" w"])
                    wait(lambda: file.read_text() == "XUNRELATED_EDITOR_FILE\n")
                    count = len(requests)
                    send(ui, [b" cc", b"silver connect", b"\r", endpoint.encode(), b"\r"])
                    wait(lambda: len(requests) >= count + 3)
                    send(ui, [b" vS", b" vUr"])
                    wait(lambda: len(requests) >= count + 4)
                    time.sleep(.4)
                    assert len(launches) == 2, launches
                    send(ui, [b"\x1b", b" q"])
                    assert ui.process.wait(timeout=4) == 0
                with editor(binary, file, env, [*flags, "--silver-test-default", "FIFO/smoke"]) as ui:
                    ui.see(b"seeded")
                    send(ui, [b" cc", b"test"])
                    ui.see(b"FIFO / smoke")
                    assert b"Choose a Silver test" not in ui.output
                # No CLI binding: a native daemon advertisement is not a project
                # share. The picker still accepts a typed loopback URL.
                env.pop("COBALT_SILVER_SHARE_FIXTURE", None)
                metadata = Path(temp) / "hardcaml-workbench/daemon.sexp"
                metadata.parent.mkdir(mode=0o700)
                metadata.write_text(f"((endpoint {endpoint})(instance_id fixture)(pid {os.getpid()}))")
                metadata.chmod(0o600)
                local_file = root / "code.txt"
                local_file.write_text("CONNECT_FROM_CODE\n")
                count = len(requests)
                with editor(binary, local_file, env, []) as ui:
                    ui.see(b"CONNECT_FROM_CODE")
                    send(ui, [b" cc", b"silver connect", b"\r"])
                    ui.see(b"No Silver project shares")
                    assert len(requests) == count, requests
                    send(ui, [endpoint.encode(), b"\r"])
                    wait(lambda: len(requests) >= count + 3)
                    send(ui, [b" vz", b" vU"])
                    ui.see(b"seeded")
                    assert len(launches) == 2, launches
            finally:
                release.set()
                server.shutdown()
    print("Silver quick launch CLI: real replay, focus, hidden acknowledgement, and no replay")


if __name__ == "__main__":
    test(str(Path(sys.argv[1]).resolve()), Path(sys.argv[2]))
