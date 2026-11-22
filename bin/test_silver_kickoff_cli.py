"""Drive the real named-flow selector, checklist and optional review against a fake."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import threading
import time

from test_silver_cli import editor, wait
from test_silver_quick_launch_cli import new_output, send


def test(binary):
    with tempfile.TemporaryDirectory(prefix="cobalt-silver-kickoff-") as tmp:
        root = Path(tmp).resolve()
        first, second = root / "first", root / "second"
        first.mkdir()
        second.mkdir()
        file = second / "main.txt"
        file.write_text("SAVED_PROJECT_TEXT\n")
        env = dict(os.environ, HOME=tmp, XDG_CONFIG_HOME=tmp, XDG_RUNTIME_DIR=tmp,
                   TERM="xterm-256color", COLORTERM="truecolor", LC_ALL="C.UTF-8",
                   COBALT_KICKOFF_FIXTURE=tmp)
        opened = []
        watched = []
        complete_watch = threading.Event()

        def lines(name):
            path = root / name
            return path.read_text().splitlines() if path.exists() else []

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
                assert self.path == "/api/hello"
                self.result("((protocol_versions (1)) (capabilities (simulation)) "
                            "(instance_id kickoff-fixture))")

            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"])).decode()
                if self.path == "/api/v1/open-project":
                    project = next(path for path in (first, second) if str(path) in body)
                    opened.append(project)
                    self.result(f"(Ok ((project ((id {project.name}) "
                                f"(root ((path {json.dumps(str(project))})))))))")
                else:
                    assert self.path == "/api/v1/simulation", body
                    if "(operation Get)" in body:
                        self.result("(Ok ((configured false) (discovery ()) (discovery_digest ())"
                                    " (discovery_job ()) (discovery_error ()) (attempts ()) (detail ())))")
                    else:
                        assert "(Observe fixture-watched)" in body and "(project second)" in body, body
                        watched.append("fixture-watched")
                        lifecycle, outcome = ("Finished", "Passed") if complete_watch.is_set() else (
                            "Running", "Unknown")
                        self.result(f"(Ok ((detail (((id fixture-watched) (project_root {json.dumps(str(second))})"
                                    " (captured ((selection ((suite FixtureSuite)))))"
                                    f" (lifecycle {lifecycle}) (outcome {outcome}))))))")

        with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            threading.Thread(target=server.serve_forever, daemon=True).start()
            endpoint = f"http://127.0.0.1:{server.server_port}"

            def command(ui, text):
                send(ui, [b" cc", text.encode(), b"\r"])

            def open_tile(ui):
                command(ui, "Focus Silver flow kickoff")

            def hide_tile(ui):
                command(ui, "Toggle Silver flow kickoff")

            def open_review(ui):
                command(ui, "Review Silver flow kickoff")

            def hide_review(ui):
                command(ui, "Toggle Silver flow kickoff review")

            def observe(ui, action, marker):
                start = len(ui.output)
                action()
                try:
                    new_output(ui, start, marker)
                except AssertionError as error:
                    text = re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"\n", bytes(ui.output[start:]))
                    raise AssertionError((marker, [s.strip() for s in text.splitlines() if s.strip()][-30:])) from error

            flags = ["--silver-endpoint", endpoint, "--silver-project", str(first)]
            try:
                with editor(binary, file, env, flags, width=300) as ui:
                    ui.see(b"SAVED_PROJECT_TEXT")
                    command(ui, "st")
                    ui.see(b"endpoint default-delay")
                    send(ui, [b"j"])
                    open_tile(ui)
                    ui.see(b"Implement first")
                    assert b"Flow choice:" not in ui.output
                    send(ui, [b"j", b"k", b"j"])
                    ui.see("Explore first · active".encode())
                    assert not lines("stage-prepared") and not lines("prepared") and not lines("submitted")
                    hide_tile(ui)
                    send(ui, [b"iZ\x1b"])
                    ui.see(b"ZSAVED_PROJECT_TEXT")
                    command(ui, "st")
                    ui.see(b"explore/review")
                    send(ui, [b"R"])
                    wait(lambda: len(lines("stage-submitted")) == 1)
                    expected = ["first-chip/variant-1 explore review explore-delay"]
                    assert lines("stage-prepared") == lines("stage-submitted") == expected
                    open_tile(ui)
                    send(ui, [b"j"])
                    ui.see(b"Silver profile is unavailable: missing-profile")
                    command(ui, "st")
                    send(ui, [b"R"])
                    assert lines("stage-prepared") == lines("stage-submitted") == expected
                    assert file.read_text() == "SAVED_PROJECT_TEXT\n"
                opened.clear()

                with editor(binary, file, env, flags, width=300) as ui:
                    ui.see(b"SAVED_PROJECT_TEXT")
                    send(ui, [b"iX\x1b"])
                    open_review(ui)
                    ui.see(b"Flow choice: Implement first")
                    # Navigate from a major tab into another tile, then back to
                    # the retained editor without closing the kickoff tab.
                    command(ui, "ov")
                    observe(ui, lambda: command(ui, "ed"), b"XSAVED_PROJECT_TEXT")
                    open_review(ui)
                    # A generic hide leaves the major slot selected but blank.
                    # ed must select the file, not merely assign editor focus.
                    command(ui, "hide")
                    observe(ui, lambda: command(ui, "ed"), b"XSAVED_PROJECT_TEXT")
                    observe(ui, lambda: send(ui, [b"iY\x1b"]), b"YXSAVED_PROJECT_TEXT")
                    send(ui, [b"u"])
                    open_review(ui)
                    assert not lines("prepared") and not lines("submitted")
                    send(ui, [b"\r"])
                    ui.see(b"Flow inputs")
                    send(ui, [b"\x15", b"bad-profile", b"\r"])
                    ui.see(b"Silver profile is unavailable: bad-profile")
                    assert not lines("prepared") and not lines("submitted")

                    send(ui, [b"\r", b"\t", b"\t", b"\x15", b"250", b"\x1b"])
                    assert not lines("prepared") and not lines("submitted")
                    send(ui, [b"\r", b"\r"])
                    ui.see(b"Parameter frequency = 100")
                    send(ui, [b"p"])
                    wait(lambda: len(lines("prepared")) == 1)
                    assert lines("prepared") == ["first-plan-1 first-chip/variant-1 implement debug place"]
                    ui.see(b"Preview preparation pending")
                    send(ui, [b"K"])
                    assert not lines("submitted")

                    # The manual reconnect uses the document's project, which
                    # deliberately differs from the initial explicit binding.
                    command(ui, "silver connect")
                    send(ui, [endpoint.encode(), b"\r"])
                    wait(lambda: opened == [first, second])
                    ui.see(b"Flow choice: Implement second")
                    (root / "release-plan").touch()
                    send(ui, [b"K"])
                    assert b"Reviewed preview: first-plan-1" not in ui.output
                    assert not lines("submitted"), lines("submitted")

                    send(ui, [b"\r", b"\x15", b"release", b"\t", b"\x15", b"signoff",
                              b"\t", b"\x15", b"200", b"\r"])
                    assert len(lines("prepared")) == 1 and not lines("submitted")
                    send(ui, [b"p"])
                    ui.see(b"Reviewed preview: second-plan-1")
                    for text in [b"second-chip / variant-1", b"Flow: implement",
                                 b"Profile: release", b"Endpoint: signoff", b"frequency = 200",
                                 b"corner = slow"]:
                        ui.see(text)
                    assert not lines("submitted")
                    assert file.read_text() == "SAVED_PROJECT_TEXT\n", "Kickoff auto-saved the editor"

                    send(ui, [b"K", b"K"])
                    wait(lambda: len(lines("submitted")) == 1)
                    first_submit = (
                        "second-plan-1 second-chip/variant-1 implement release signoff frequency=200 corner=slow"
                    )
                    assert lines("submitted") == [first_submit]
                    ui.see(b"Submission pending")
                    observe(ui, lambda: hide_review(ui), b"XSAVED_PROJECT_TEXT")
                    (root / "release-ack").touch()
                    wait(lambda: lines("acknowledged") == ["second-plan-1"])
                    send(ui, [b"iY\x1b"])
                    ui.see(b"YXSAVED_PROJECT_TEXT")
                    open_review(ui)
                    ui.see(b"Accepted")
                    ui.see(b"fixture-workflow")
                    ui.see(b"fixture-run")
                    assert file.read_text() == "SAVED_PROJECT_TEXT\n"

                    send(ui, [b"K", b"p"])
                    ui.see(b"Reviewed preview: second-plan-2")
                    assert len(lines("submitted")) == 1
                    send(ui, [b"K"])
                    ui.see(b"Delivery unconfirmed")
                    assert lines("submitted") == [first_submit, first_submit.replace("plan-1", "plan-2")]
                    hide_review(ui)
                    open_review(ui)
                    send(ui, [b"K"])
                    time.sleep(.3)
                    assert len(lines("submitted")) == 2
                    assert file.read_text() == "SAVED_PROJECT_TEXT\n"

                flags = ["--silver-endpoint", endpoint, "--silver-project", str(second),
                         "--silver-run", "fixture-watched"]
                with editor(binary, file, env, flags, width=300) as ui:
                    ui.see(b"Attempt: fixture-watched")
                    before = len(watched)
                    open_review(ui)
                    ui.see(b"Flow choice: Implement second")
                    send(ui, [b"\r", b"\r", b"p"])
                    ui.see(b"Reviewed preview: second-plan-1")
                    send(ui, [b"K"])
                    ui.see(b"fixture-workflow")
                    assert len(lines("submitted")) == 3
                    hide_review(ui)
                    complete_watch.set()
                    ui.see(b"Passed")
                    wait(lambda: len(watched) > before)
            finally:
                (root / "release-plan").touch()
                (root / "release-ack").touch()
                server.shutdown()
    print("Silver flow kickoff PTY: exact stage selection, stale plan isolation, hidden acknowledgement, no replay")


if __name__ == "__main__":
    test(str(Path(sys.argv[1]).resolve()))
