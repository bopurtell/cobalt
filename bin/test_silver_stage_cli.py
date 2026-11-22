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
                    ui.see(b"Silver: Stage Checklist")
                    ui.see(b"Silver does not advertise ASIC operations")
                    send(ui, [b" cc", b"timing"])
                    send(ui, [b"\r", b"\x1b", b" q"])
                    assert ui.process.wait(timeout=4) == 0
                assert not lines()

                with editor(fixture, file, env, flags, width=300) as ui:
                    ui.see(b"XUNRELATED_EDITOR_FILE")
                    send(ui, [b" cc", b"ov", b"\t", b"\r",
                              b" cc", b"st", b"\t", b"\r"])
                    ui.see(b"fixture-chip/fixture-variant")
                    ui.see(b"fixture-flow/fixture-profile")
                    ui.see(b"CTS:")
                    ui.see(b"Signoff:")
                    ui.see(b"not reported")
                    assert b"Clock tree synthesis" not in ui.output
                    assert b"Available" not in ui.output
                    assert b"mapped-post-cts" not in ui.output
                    assert b"endpoint cts" not in ui.output
                    assert b"endpoint mapped-final-report" not in ui.output
                    send(ui, [b"G", b"R"])
                    ui.see(b"Routing endpoint not published; nothing ran")
                    send(ui, [b" cc", b"routing", b"\t", b"\r"])
                    assert not lines(), lines()
                    send(ui, [b"gg", b"j", b"R"])
                    wait(lambda: len(lines()) == 1)
                    # The fixture acknowledgement arrives after the checklist
                    # has been hidden; PTY history still receives the run ID.
                    send(ui, [b" cc", b"Toggle Silver: Stage Checklist", b"\r", b"iY\x1b", b" w"])
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


def test_observation(fixture):
    """Exercise actual ASIC reads with an independent synthetic launch service."""
    with tempfile.TemporaryDirectory(prefix="cobalt-silver-stage-watch-") as temporary:
        root = Path(temporary).resolve()
        bound = root / "explicit-project"
        bound.mkdir()
        file = root / "code.txt"
        file.write_text("STAGE_WATCH_EDITOR\n")
        journal = root / "submitted"
        release = root / "release"
        release.touch()
        env = dict(os.environ, HOME=temporary, XDG_CONFIG_HOME=temporary, XDG_RUNTIME_DIR=temporary,
                   TERM="xterm-256color", COLORTERM="truecolor", LC_ALL="C.UTF-8",
                   COBALT_STAGE_FIXTURE_JOURNAL=str(journal), COBALT_STAGE_FIXTURE_RELEASE=str(release))
        requests, attempts = [], []
        report_completed = threading.Event()
        next_read, release_next_read = threading.Event(), threading.Event()
        delay_old, delayed, release_old, old_responded = (threading.Event() for _ in range(4))
        spinner_frames = tuple(glyph.encode() for glyph in "⣷⣯⣟⡿⢿⣻⣽⣾")

        def spinner_glyphs(output):
            return {glyph for glyph in spinner_frames if glyph in output}

        def selection(variant, assignments=""):
            return ("((flow fixture-flow) (profile fixture-profile) (endpoint mapped-post-cts)"
                    f" (assignments ({assignments}))"
                    f" (chip_target (((chip fixture-chip) (variant {variant})))))")

        def stage(id, name, status, action=""):
            return (f"((id {id}) (name {json.dumps(name)}) (status {status})"
                    f" (requested true) (reason ()) (action ({action})))")

        def run(id, variant, date, stages):
            return (f"((run ((backend asic) (id {id}) (build ()) (label ())))"
                    f" (reference ((attempt {id}) (stream_id stream))) (selection ({selection(variant)}))"
                    f" (cursor 0) (status running) (execution_file ()) (error ()) (stages ({stages}))"
                    f" (execution_timing (((started_at ({date})) (running true) (measured_seconds ())))))")

        def snapshot(*, project_switched=False, stale=False):
            if project_switched or stale:
                run_id = "second-project-asic" if project_switched else "retired-project-asic"
                name = "Second project step" if project_switched else "RETIRED_REPLY_STAGE"
                rows = run(run_id, "fixture-variant", "2026-01-04T00:00:00Z",
                           stage("project-stage", name, "Pending"))
                return f"(Ok ((configured true) (runs ({rows})) (workflows ()) (operations ()) (summaries ())))"
            observed_status = "Completed" if report_completed.is_set() else "Running"
            matching = run("matching-asic", "fixture-variant", "2026-01-02T00:00:00Z",
                           stage("intermediate", "Custom placement pass", observed_status,
                                 action=selection("other-variant"))
                           + stage("cts", "Clock tree synthesis", "Pending")
                           + stage("native-post-cts", "Post CTS timing", "Pending",
                                   action=selection("fixture-variant", "historical=true")))
            old = run("older-matching-asic", "fixture-variant", "2026-01-01T00:00:00Z",
                      stage("older-checkpoint", "Older placement pass", "Skipped"))
            other_variant = run("other-variant-asic", "other-variant", "2026-01-03T00:00:00Z",
                                stage("different", "WRONG_STAGE_FOR_VARIANT", "Completed"))
            return f"(Ok ((configured true) (runs ({other_variant}{matching}{old})) (workflows ()) (operations ()) (summaries ())))"

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def result(self, text):
                payload = text.encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/sexp")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                try:
                    self.wfile.write(payload)
                except (BrokenPipeError, ConnectionResetError):
                    pass

            def do_GET(self):
                assert self.path == "/api/hello", self.path
                self.result("((protocol_versions (1)) (capabilities (simulation asic)) (instance_id watch-fixture))")

            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"])).decode()
                if self.path == "/api/v1/open-project":
                    assert str(root) in body and "(instance_id watch-fixture)" in body, body
                    project, path = ("watch-project", bound) if str(bound) in body else ("new-project", root)
                    self.result(f"(Ok ((project ((id {project}) (root ((path {json.dumps(str(path))})))))))")
                elif self.path == "/api/v1/asic":
                    requests.append(body)
                    assert "(instance_id watch-fixture)" in body
                    assert "(operation Get)" in body or "(Observe" in body, body
                    if "(project new-project)" in body:
                        assert "(Observe" not in body or "(id second-project-asic)" in body, body
                        self.result(snapshot(project_switched=True))
                    else:
                        assert "(project watch-project)" in body
                        assert ("(Observe" not in body or "(id matching-asic)" in body
                                or "(id older-matching-asic)" in body), body
                        if delay_old.is_set():
                            delayed.set()
                            release_old.wait(10)
                            self.result(snapshot(stale=True))
                            old_responded.set()
                        else:
                            if len(requests) >= 2 and not release_next_read.is_set():
                                next_read.set()
                                release_next_read.wait(8)
                            self.result(snapshot())
                else:
                    assert self.path == "/api/v1/simulation", self.path
                    if "(Observe " in body:
                        attempts.append(body)
                        assert "(Observe testing-attempt)" in body, body
                        self.result(
                            f"(Ok ((detail (((id testing-attempt) (project_root {json.dumps(str(bound))})"
                            " (captured ((selection ((suite WatchSuite)))))"
                            " (lifecycle Running) (outcome Unknown))))))"
                        )
                        return
                    self.result("(Ok ((configured false) (discovery ()) (discovery_digest ())"
                                " (discovery_job ()) (discovery_error ()) (attempts ()) (detail ())))")

        with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            threading.Thread(target=server.serve_forever, daemon=True).start()
            endpoint = f"http://127.0.0.1:{server.server_port}"
            flags = ["--silver-endpoint", endpoint,
                     "--silver-project", str(bound), "--silver-run", "testing-attempt"]
            try:
                with editor(fixture, file, env, flags, width=360) as ui:
                    ui.see(b"STAGE_WATCH_EDITOR")
                    ui.see(b"Attempt:")
                    ui.see(b"testing-attempt")
                    assert not requests, requests
                    send(ui, [b" cc", b"silver stage checklist", b"\r"])
                    wait(lambda: requests)
                    ui.see(b"Latest ASIC run matching-asic")
                    ui.see(b"Custom placement pass")
                    ui.see(b"running")
                    ui.see(b"CTS:")
                    ui.see(b"Post CTS timing")
                    evidence = ui.output[ui.output.index(b"Latest ASIC run matching-asic"):]
                    assert evidence.index(b"Custom placement pass") < evidence.index(b"Post CTS timing")
                    assert b"WRONG_STAGE_FOR_VARIANT" not in ui.output
                    assert b"Clock tree synthesis" not in ui.output
                    # Hold the next normal read in flight. With no keypresses, no
                    # submissions and no new snapshot, the visible marker still cycles.
                    assert next_read.wait(5)
                    spinner_start, count = len(ui.output), len(requests)
                    wait(lambda: len(spinner_glyphs(ui.output[spinner_start:])) >= 3, seconds=3)
                    assert len(requests) == count, requests[count:]
                    assert not journal.exists()
                    # The next frame must be injected by the observation host,
                    # not by terminal input, focus or a manual refresh.
                    old_output = len(ui.output)
                    report_completed.set()
                    release_next_read.set()
                    wait(lambda: b"completed" in ui.output[old_output:])
                    spinner_stop = len(ui.output)
                    time.sleep(.45)
                    assert not spinner_glyphs(ui.output[spinner_stop:])
                    send(ui, [b"gg", b"j", b"R"])
                    ui.see(b"This stage is not a fresh launch destination; nothing ran")
                    assert not journal.exists()
                    send(ui, [b"["])
                    ui.see(b"Pinned ASIC run older-matching-asic")
                    ui.see(b"Older placement pass")
                    send(ui, [b"]"])
                    ui.see(b"Pinned ASIC run matching-asic")
                    old_output = len(ui.output)
                    send(ui, [b"L"])
                    wait(lambda: b"Latest ASIC run matching-asic" in ui.output[old_output:])
                    # The observed native row uses the receipt's explicit
                    # mapped endpoint, not its display name or provider ID.
                    send(ui, [b"gg", b"j", b"j", b"j", b"R"])
                    wait(lambda: journal.exists() and journal.read_text().endswith("mapped-post-cts\n"))
                    assert not b"WRONG_STAGE_FOR_VARIANT" in ui.output
                    send(ui, [b" cc", b"timing", b"\r"])
                    wait(lambda: len(journal.read_text().splitlines()) == 2)
                    assert journal.read_text().splitlines() == [
                        "fixture-chip/fixture-variant fixture-flow fixture-profile mapped-post-cts"
                    ] * 2
                    assert all("(Observe testing-attempt)" in request for request in attempts)
                    start = len(ui.output)
                    send(ui, [b"["])
                    wait(lambda: b"Pinned ASIC run older-matching-asic" in ui.output[start:])
                    send(ui, [b" cc", b"Toggle Silver: Stage Checklist", b"\r"])
                    time.sleep(.25)
                    count = len(requests)
                    time.sleep(1.25)
                    assert len(requests) == count, requests[count:]
                    delay_old.set()
                    send(ui, [b" cc", b"silver stage checklist", b"\r"])
                    assert delayed.wait(8)
                    send(ui, [b" cc", b"silver connect", b"\r", endpoint.encode(), b"\r"])
                    ui.see(b"Latest ASIC run second-project-asic")
                    ui.see(b"Second project step")
                    release_old.set()
                    assert old_responded.wait(4)
                    wait(lambda: sum("(project new-project)" in request for request in requests) >= 2)
                    assert b"RETIRED_REPLY_STAGE" not in ui.output
                    send(ui, [b"\x1b", b" q"])
                    assert ui.process.wait(timeout=4) == 0
            finally:
                release_next_read.set()
                release_old.set()
                server.shutdown()
    print("Silver stage observation PTY: live evidence, exact receipt mapping, scoped pinning and reconnect")


if __name__ == "__main__":
    fixture, binary, stub = (str(Path(arg).resolve()) for arg in sys.argv[1:])
    test(fixture, binary, stub)
    test_observation(fixture)
