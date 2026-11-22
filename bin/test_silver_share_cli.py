"""C7 project sharing through ordinary standalone startup and a fake peer."""
import fcntl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import sys
import tempfile
import threading

from test_silver_cli import editor, wait
from test_silver_quick_launch_cli import send


def test(binary, *, live=False):
    # Dune may set TMPDIR to a group-writable sandbox parent that a live reader rejects.
    parent = os.getenv("COBALT_TEST_SHARE_TMPDIR", "/tmp") if live else None
    with tempfile.TemporaryDirectory(prefix="cobalt-silver-share-", dir=parent) as temp:
        directory = Path(temp).resolve()
        roots = {name: directory / name for name in ("alpha", "beta")}
        for root in roots.values():
            root.mkdir()
        file = roots["alpha"] / "code.txt"
        file.write_text("EDITOR_STARTS_IN_ALPHA\n")
        fixture = directory / "shares.sexp"
        env = dict(os.environ, HOME=temp, XDG_CONFIG_HOME=temp, XDG_RUNTIME_DIR=temp,
                   COBALT_SILVER_SHARE_FIXTURE=str(fixture), TERM="xterm-256color",
                   COLORTERM="truecolor", LC_ALL="C.UTF-8")
        registry = directory / "hardcaml-workbench/editor-shares/v1"
        ids = {name: (ch + "0" * 31) for name, ch in (("alpha", "a"), ("beta", "b"))}
        publishers = {}
        if live:
            env.pop("COBALT_SILVER_SHARE_FIXTURE")
            for path in [registry.parent.parent, registry.parent, registry]:
                path.mkdir(mode=0o700)
        requests = []
        snapshots = []
        release = threading.Event()
        delayed = threading.Event()
        returned = threading.Event()

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
                assert self.path == "/api/hello"
                self.result("((protocol_versions (1))(capabilities (simulation))(instance_id peer))")

            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"])).decode()
                requests.append((self.path, body))
                assert "(instance_id peer)" in body, body
                if self.path == "/api/v1/snapshot":
                    snapshots.append(body)
                    blocked = len(snapshots) == 2
                    if blocked:
                        delayed.set()
                        assert release.wait(6)
                    projects = " ".join(
                        f"((id {name})(root ((path {json.dumps(str(root))}))))"
                        for name, root in roots.items()
                    )
                    self.result(f"(Ok ((projects ({projects}))(jobs ())(artifacts ())"
                                "(cursor ((instance_id peer)(sequence 0)))))")
                    if blocked:
                        returned.set()
                else:
                    assert self.path == "/api/v1/simulation" and "(operation Get)" in body, body
                    # A missing catalog must not trigger a provider discovery job.
                    self.result("(Ok ((configured true)(discovery ())(discovery_digest ())"
                                "(discovery_job ())(discovery_error ())(attempts ())(detail ())))")

        with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            threading.Thread(target=server.serve_forever, daemon=True).start()
            endpoint = f"http://127.0.0.1:{server.server_port}"

            def publish(*names):
                if live:
                    for name in set(publishers) - set(names):
                        (registry / f"{ids[name]}.sexp").unlink()
                        publishers.pop(name).close()
                    for name in set(names) - set(publishers):
                        temporary = registry / ".tmp"
                        fd = os.fdopen(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w")
                        mode = "embedded" if name == "alpha" else "attached"
                        fd.write(f"(silver-editor-share-v1 ((offer_id {ids[name]})"
                                 f"(endpoint {endpoint})(instance_id peer)(project_id {name})"
                                 f"(project_root {json.dumps(str(roots[name]))})(mode {mode})))")
                        fd.flush()
                        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        temporary.rename(registry / f"{ids[name]}.sexp")
                        publishers[name] = fd
                    return
                data = " ".join(
                    f"((offer_id share-{name})(endpoint {endpoint})(instance_id peer)"
                    f"(project_id {name})(project_root {json.dumps(str(roots[name]))}))"
                    for name in names
                )
                temporary = directory / "new.sexp"
                temporary.write_text(f"(cobalt-share-fixture-v1 {data})")
                temporary.chmod(0o600)
                temporary.replace(fixture)

            def open_picker(ui):
                start = len(ui.output)
                send(ui, [b" cc", b"silver connect", b"\r"])
                labels = ([f"{name} [{mode} · {ids[name][:12]}]".encode()
                           for name, mode in [("alpha", "embedded"), ("beta", "attached")]]
                          if live else [b"share-alpha/alpha", b"share-beta/beta"])
                wait(lambda: all(label in ui.output[start:] for label in labels))

            def beta_reads():
                return sum(path == "/api/v1/simulation" and "(project beta)" in body
                           for path, body in requests)

            def wait_for_beta(ui, count):
                try:
                    wait(lambda: beta_reads() == count)
                except AssertionError as error:
                    raise AssertionError((requests, bytes(ui.output[-4000:]))) from error

            try:
                publish("alpha", "beta")
                with editor(binary, file, env, [], width=260) as ui:
                    ui.see(b"EDITOR_STARTS_IN_ALPHA")
                    assert requests == []
                    open_picker(ui)
                    assert requests == []
                    send(ui, [b"\t", b"\r"])
                    wait_for_beta(ui, 1)
                    send(ui, [b"iX\x1b", b" w"])
                    wait(lambda: file.read_text() == "XEDITOR_STARTS_IN_ALPHA\n")

                    # A superseded successful handshake must not win later.
                    open_picker(ui)
                    send(ui, [b"\r"])
                    assert delayed.wait(4)
                    open_picker(ui)
                    send(ui, [b"\t", b"\r"])
                    wait_for_beta(ui, 2)
                    release.set()
                    assert returned.wait(4)

                    # A withdrawn row does no network I/O and leaves beta bound.
                    open_picker(ui)
                    publish("beta")
                    count = len(requests)
                    send(ui, [b"\r"])
                    ui.see(b"Silver share was withdrawn")
                    assert len(requests) == count, requests
                    send(ui, [b" vz", b" vUr"])
                    wait_for_beta(ui, 3)
                    send(ui, [b"\x1b", b" q"])
                    assert ui.process.wait(timeout=4) == 0
                assert [path for path, _ in requests] == [
                    "/api/hello", "/api/v1/snapshot", "/api/v1/simulation",
                    "/api/hello", "/api/v1/snapshot",
                    "/api/hello", "/api/v1/snapshot", "/api/v1/simulation",
                    "/api/v1/simulation",
                ], requests
            finally:
                release.set()
                server.shutdown()
                for fd in publishers.values():
                    fd.close()
    source = "locked registry" if live else "fixture"
    print(f"Silver share {source}: exact project, no launch/open, withdrawal and superseded connect")


if __name__ == "__main__":
    test(str(Path(sys.argv[1]).resolve()))
    test(str(Path(sys.argv[1]).resolve()), live=True)
