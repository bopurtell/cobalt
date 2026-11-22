"""Exercise C5 through the real PTY, including abandoning an in-flight read."""
from contextlib import contextmanager
import fcntl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import errno
import json
import os
from pathlib import Path
import pty
import select
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time


def wait(predicate, seconds=10):
    deadline = time.monotonic() + seconds
    while not predicate():
        assert time.monotonic() < deadline, "timed out waiting for Silver request"
        time.sleep(.02)


class Terminal:
    def __init__(self, master, process):
        self.master, self.process = master, process
        self.output = bytearray()
        self.reader = threading.Thread(target=self.drain, daemon=True)
        self.reader.start()

    def drain(self):
        while True:
            if select.select([self.master], [], [], .05)[0]:
                try:
                    data = os.read(self.master, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    return
                if not data:
                    return
                self.output.extend(data)
            elif self.process.poll() is not None:
                return

    def see(self, marker):
        deadline = time.monotonic() + 10
        while marker not in self.output and time.monotonic() < deadline:
            time.sleep(.02)
        assert marker in self.output, (marker, bytes(self.output[-5000:]))

    def keys(self, keys):
        os.write(self.master, keys)


@contextmanager
def editor(binary, file, env, flags, *, width=160):
    master, slave = pty.openpty()
    process = None
    terminal = None
    try:
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 36, width, 0, 0))
        process = subprocess.Popen([binary, "--no-lsp", *flags, str(file)], env=env,
                                   stdin=slave, stdout=slave, stderr=slave)
        terminal = Terminal(master, process)
        yield terminal
    finally:
        if process is not None and process.poll() is None:
            process.kill()
        if process is not None:
            process.wait(timeout=5)
        os.close(slave)
        if terminal is not None:
            terminal.reader.join(timeout=1)
        os.close(master)


def test(binary, stub):
    with tempfile.TemporaryDirectory(prefix="cobalt-silver-cli-") as temporary:
        directory = Path(temporary).resolve()
        root = directory / "bound-project"
        root.mkdir()
        root_atom = json.dumps(str(root), ensure_ascii=False)
        file = directory / "outside-project.txt"
        file.write_bytes(b"UNRELATED_EDITOR_FILE\n")
        env = dict(os.environ, HOME=temporary, XDG_CONFIG_HOME=temporary,
                   TERM="xterm-256color", COLORTERM="truecolor", LC_ALL="C.UTF-8")
        requests, abandoned = [], []
        attempt = "attempt-explicit"
        finished = threading.Event()
        # Use a distinct project-session ID per handshake. Normal status polling
        # cannot be mistaken for a new observation started by the refresh key.
        opens = []
        observed_projects = {}

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def result(self, text):
                data = text.encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_GET(self):
                requests.append((self.path, ""))
                if self.path == "/api/hello":
                    self.result("((protocol_versions (1)) (capabilities (simulation))"
                                " (instance_id fixture))")
                else:
                    self.send_error(404)

            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"])).decode()
                requests.append((self.path, body))
                if self.path == "/api/v1/open-project":
                    assert str(root) in body and "fixture" in body, body
                    opens.append(body)
                    self.result(f"(Ok ((project ((id sid-{len(opens)}) (root ((path {root_atom})))))))")
                elif self.path == "/api/v1/simulation":
                    if "(operation Get)" in body:
                        self.result("(Ok ((configured false) (discovery ()) (discovery_digest ())"
                                    " (discovery_job ()) (discovery_error ()) (attempts ()) (detail ())))")
                        return
                    assert f"(Observe {attempt})" in body and "(project sid-" in body, body
                    project = body.split("(project sid-", 1)[1].split(")")[0]
                    generation = observed_projects.setdefault(project, len(observed_projects) + 1)
                    if generation > 1:
                        # Block the response; a local close must close this socket
                        # promptly, without waiting on transport timeout or a reply.
                        self.connection.settimeout(7)
                        try:
                            if not self.connection.recv(1):
                                abandoned.append(generation)
                        except ConnectionResetError:
                            abandoned.append(generation)
                        except socket.timeout:
                            pass
                    else:
                        lifecycle, outcome = ("Finished", "Passed") if finished.is_set() else (
                            "Running", "Unknown")
                        self.result(f"(Ok ((detail (((id {attempt}) (project_root {root_atom})"
                                    " (captured ((selection ((suite FixtureSuite)))))"
                                    f" (lifecycle {lifecycle}) (outcome {outcome}))))))")
                else:
                    self.send_error(404)

        def observed(generation):
            return generation in observed_projects.values()

        with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            threading.Thread(target=server.serve_forever, daemon=True).start()
            endpoint = f"http://127.0.0.1:{server.server_port}"
            flags = ["--silver-endpoint", endpoint, "--silver-project", str(root),
                     "--silver-run", attempt]

            def fails(program, options, diagnostic):
                result = subprocess.run([program, *options], capture_output=True,
                                        env=env, timeout=5)
                assert result.returncode == 1 and diagnostic in result.stderr, result

            try:
                fails(binary, flags[:2], b"must be supplied together")
                fails(binary, ["--silver-run", attempt], b"--silver-run requires both")
                fails(binary, [*flags, "--list-themes"], b"requires an interactive session")
                fails(binary, [*flags[:3], "relative-project", *flags[4:]], b"an absolute project root")
                fails(stub, [*flags, str(file)], b"adapter unavailable in this build")
                fails(stub, [*flags[:4], str(file)], b"adapter unavailable in this build")
                with editor(stub, file, env, []) as ui:
                    ui.see(b"UNRELATED_EDITOR_FILE")
                    ui.keys(b" vS")
                    ui.see(b"Silver: Overview unavailable")
                    ui.keys(b"iX\x1b")
                    time.sleep(.2)
                    ui.keys(b" w")
                    wait(lambda: file.read_bytes() == b"XUNRELATED_EDITOR_FILE\n")
                    ui.keys(b" q")
                    assert ui.process.wait(timeout=5) == 0
                assert requests == []

                with editor(binary, file, env, flags) as ui:
                    ui.see(b"Silver: Overview")
                    # Labels and semantic values render in different ANSI styles.
                    for marker in (b"Status:", b"Fresh", b"Run:", b"attempt-explicit",
                                   b"Lifecycle:", b"Running", b"Outcome:", b"Unknown"):
                        ui.see(marker)
                    finished.set()
                    # The absolute redraw may diff away the unchanged label.
                    ui.see(b"Finished")
                    ui.see(b"Passed")
                    ui.keys(b" vUr")
                    wait(lambda: observed(2))
                    ui.keys(b" vS")
                    wait(lambda: 2 in abandoned, seconds=3)
                    count = len(requests)
                    time.sleep(1.2)
                    assert len(requests) == count, requests
                    ui.keys(b" vS")
                    wait(lambda: observed(3))
                    ui.keys(b" q")
                    assert ui.process.wait(timeout=4) == 0
                    wait(lambda: 3 in abandoned, seconds=3)

                with editor(binary, file, env, flags) as ui:
                    wait(lambda: observed(4))
                    ui.process.send_signal(signal.SIGTERM)
                    assert ui.process.wait(timeout=4) == 1
                    wait(lambda: 4 in abandoned, seconds=3)
            finally:
                server.shutdown()
        assert {path for path, _ in requests} == {
            "/api/hello", "/api/v1/open-project", "/api/v1/simulation"
        }
    print("Silver CLI: explicit scope, refresh/hide/reopen, local cleanup, and stub editing")


if __name__ == "__main__":
    test(*(str(Path(arg).resolve()) for arg in sys.argv[1:]))
