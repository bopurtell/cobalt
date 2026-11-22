"""Drive the Silver palette, Overview paint, and Stage clock through a real PTY."""
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import select
import sys
import tempfile
import threading
import time

sys.path.insert(0, str(Path(__file__).absolute().parents[1] / "examples" / "hosted_editor"))
from test_hosted_editor import Screen, terminal


EDITOR = "SILVER_POLISH_DOCUMENT"
ATTEMPT = "polish-testing-attempt"
FLOW_TITLE = "Silver: Flow Runner"
OVERVIEW_TITLE = "Silver: Overview"
STAGE_TITLE = "Silver: Stage Checklist"
BRAILLE = "\u2800-\u28ff"
TIMEOUT = 8


def command(tty, query, title=None):
    """Assert the palette has selected row one, then accept it without Tab."""
    title = title or query
    first = re.compile(rf"│ > {re.escape(query)} +│[^\n]*\n"
                       rf"[^\n]*│ > {re.escape(title)} +")
    tty.send(b" cc" + query.encode())
    tty.wait(lambda: first.search(tty.text), f"selected first palette row: {title}", TIMEOUT)
    tty.send(b"\r")


def focused(tty, title, footer):
    return f"╭─ {title}" in tty.text and footer in tty.text and not tty.screen.cursor_visible


def asic_snapshot(final):
    selection = ("((flow fixture-flow) (profile fixture-profile) (endpoint mapped-post-cts)"
                 " (assignments ()) (chip_target (((chip fixture-chip) (variant fixture-variant)))))")
    stages = [("synthesis", "Synthesis", "Completed" if final else "Running"),
              ("timing-stage", "Timing", "Cancelled" if final else "Cancelling"),
              ("check", "Extra check", "Failed" if final else "Pending")]
    stage_rows = "".join(f"((id {id}) (name {json.dumps(name)}) (status {status})"
                         " (requested true) (reason ()) (action ()))"
                         for id, name, status in stages)
    running = "false" if final else "true"
    status = "cancelled" if final else "running"
    run = ("((run ((backend asic) (id polish-run) (build ()) (label ())))"
           " (reference ((attempt polish-run) (stream_id stream)))"
           f" (selection ({selection})) (cursor 0) (status {status})"
           f" (execution_file ()) (error ()) (stages ({stage_rows}))"
           f" (execution_timing (((started_at (2026-01-02T00:00:00Z)) (running {running})"
           " (measured_seconds ())))))")
    return f"(Ok ((configured true) (runs ({run})) (workflows ()) (operations ()) (summaries ())))"


@contextmanager
def peer(project):
    requests = []
    release_final = threading.Event()
    final_requested = threading.Event()
    hold_testing = threading.Event()
    closing = threading.Event()
    root = json.dumps(str(project))

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
            requests.append((self.path, ""))
            if self.path == "/api/hello":
                self.result("((protocol_versions (1)) (capabilities (simulation asic))"
                            " (instance_id polish-fixture))")
            else:
                self.send_error(404)

        def do_POST(self):
            body = self.rfile.read(int(self.headers["Content-Length"])).decode()
            requests.append((self.path, body))
            if self.path == "/api/v1/open-project":
                self.result(f"(Ok ((project ((id first) (root ((path {root})))))))")
            elif self.path == "/api/v1/simulation" and "(operation Get)" in body:
                self.result("(Ok ((configured false) (discovery ()) (discovery_digest ())"
                            " (discovery_job ()) (discovery_error ()) (attempts ()) (detail ())))")
            elif self.path == "/api/v1/simulation" and f"(Observe {ATTEMPT})" in body:
                # Overview has already painted. Avoid unrelated service replies
                # driving the Stage frontend through another update.
                if hold_testing.is_set():
                    closing.wait(3 * TIMEOUT)
                    return
                self.result(f"(Ok ((detail (((id {ATTEMPT}) (project_root {root})"
                            " (captured ((selection ((suite PolishSuite)))))"
                            " (lifecycle Finished) (outcome Passed))))))")
            elif self.path == "/api/v1/asic" and "(operation Get)" in body:
                self.result(asic_snapshot(final=release_final.is_set()))
            elif self.path == "/api/v1/asic" and "(Observe" in body:
                final_requested.set()
                if release_final.wait(3 * TIMEOUT):
                    self.result(asic_snapshot(final=True))
                else:
                    self.send_error(504)
            elif self.path == "/api/v1/asic" and "(Load_summary" in body:
                self.result(asic_snapshot(final=True))
            else:
                self.send_error(404)

    with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield f"http://127.0.0.1:{server.server_port}", final_requested, release_final, hold_testing
        finally:
            closing.set()
            release_final.set()
            server.shutdown()
            thread.join()
    assert any(path == "/api/v1/asic" and "(Observe" in body for path, body in requests), requests
    assert all(path in ("/api/hello", "/api/v1/open-project")
               or (path == "/api/v1/simulation"
                   and ("(operation Get)" in body or f"(Observe {ATTEMPT})" in body))
               or (path == "/api/v1/asic"
                   and any(op in body for op in ("(operation Get)", "(Observe", "(Load_summary")))
               for path, body in requests), requests
    opens = [body for path, body in requests if path == "/api/v1/open-project"]
    root_field = re.compile(r"\(root\s*(?:" + re.escape(root) + "|" + re.escape(str(project)) + r")\)")
    assert opens and all(root_field.search(body) for body in opens), requests


def verify_overview(tty, project, endpoint):
    command(tty, "ov", f"Focus {OVERVIEW_TITLE}")
    tty.wait(lambda: focused(tty, OVERVIEW_TITLE, "› Status:") and all(value in tty.text for value in
             (str(project), endpoint, "Fresh", "Finished", "Passed")),
             "focused Overview with bound fields", TIMEOUT)
    columns, value_colors = set(), {}
    # A long Dune sandbox root is legitimately clipped in a compact pane.
    # The exact bound project is checked separately in the recorded request.
    for label, value in (("Status:", "Fresh"), ("Project:", str(project)[:18]), ("Endpoint:", endpoint),
                         ("Run:", ATTEMPT), ("Lifecycle:", "Finished"), ("Outcome:", "Passed")):
        for i, row in enumerate(tty.screen.lines):
            text = "".join(row)
            match = re.search(rf"{label} +({re.escape(value)})", text)
            if match:
                colors = tty.screen.foregrounds[i]
                fields = slice(match.start(1), match.end(1))
                assert colors[fields][0] is not None and len(set(colors[fields])) == 1, (text, colors[fields])
                assert colors[fields][0] != colors[match.start()], (text, colors[match.start():match.end()])
                columns.add((match.start(), match.start(1)))
                value_colors[label] = colors[fields][0]
                break
        else:
            raise AssertionError((label, value, tty.text))
    assert len(columns) == 1, columns
    assert value_colors["Project:"] == value_colors["Endpoint:"], value_colors
    assert value_colors["Status:"] == value_colors["Lifecycle:"] == value_colors["Outcome:"], value_colors
    assert value_colors["Status:"] != value_colors["Project:"], value_colors


def stage_marker(tty, label, status, glyphs):
    match = re.search(rf"([{glyphs}]) +{label}: +{status}", tty.text)
    return match[1] if match else None


def verify_spinner(tty, final_requested, release_final):
    command(tty, "st", STAGE_TITLE)

    def active():
        return (stage_marker(tty, "Synthesis", "running", BRAILLE),
                stage_marker(tty, "Timing", r"cancelling…", BRAILLE))

    tty.wait(lambda: focused(tty, STAGE_TITLE, "j/k stage | R run") and all(active())
             and stage_marker(tty, "Extra check", "pending", "◷"),
             "Running and Cancelling stage spinners", TIMEOUT)
    # The fake peer withholds the next service response. The only way the
    # matching visible glyphs can change is a frontend turn without a keypress.
    assert final_requested.wait(TIMEOUT), "stage follow-up never reached the fake peer"
    for _ in range(2):
        previous = active()
        tty.wait(lambda: all(now and now != before for now, before in zip(active(), previous)),
                 "both stage spinners advance without input or a reply", TIMEOUT)
    release_final.set()

    def stopped():
        return (stage_marker(tty, "Synthesis", "completed", "✓"),
                stage_marker(tty, "Timing", "cancelled", "×"),
                stage_marker(tty, "Extra check", "failed", "!"))

    tty.wait(lambda: all(stopped()), "final stage markers without a keypress", TIMEOUT)
    # Pump the PTY across multiple animation ticks rather than sleeping with
    # an unread stream. Assert the current frame, not scrollback.
    end = time.monotonic() + 1.2
    while (remaining := end - time.monotonic()) > 0:
        if select.select([tty.master], [], [], remaining)[0]:
            tty.screen.feed(os.read(tty.master, 65536))
        if not tty.screen.drawing:
            assert all(stopped()), tty.text


def test(binary, root):
    project = root / "first"
    project.mkdir()
    file = project / "code.txt"
    file.write_text(EDITOR + "\n")
    journal, release = root / "submitted", root / "release"
    release.touch()
    env = dict(os.environ, HOME=str(root), TMPDIR=str(root), XDG_RUNTIME_DIR=str(root),
               XDG_CONFIG_HOME=str(root / "config"), XDG_STATE_HOME=str(root / "state"),
               XDG_CACHE_HOME=str(root / "cache"), XDG_DATA_HOME=str(root / "data"),
               TERM="xterm-256color", COLORTERM="truecolor", LC_ALL="C.UTF-8",
               COBALT_STAGE_FIXTURE_JOURNAL=str(journal), COBALT_STAGE_FIXTURE_RELEASE=str(release))
    with peer(project) as (endpoint, final_requested, release_final, hold_testing):
        args = [binary, "--no-lsp", "--workspace", "--silver-endpoint", endpoint,
                "--silver-project", str(project), "--silver-run", ATTEMPT, str(file)]
        with terminal(args, env) as (tty, before):
            tty.screen = Screen(track_foreground=True)
            tty.see(EDITOR)
            tty.resize(300, 44)
            tty.see(EDITOR, ATTEMPT)
            def open_flow():
                command(tty, "flow", FLOW_TITLE)
                tty.wait(lambda: focused(tty, FLOW_TITLE, "j/k: select flow | Esc: editor") and EDITOR in tty.text
                         and "Fixture flow · active" in tty.text and "╭─ Commands" not in tty.text,
                         "compact flow selector focused beside the editor", TIMEOUT)
                assert not any(text in tty.text for text in
                               ("Silver: Flow Review", "Flow choice:", "Kickoff disabled:")), tty.text

            assert f"╭─ {FLOW_TITLE}" not in tty.text, tty.text
            open_flow()
            command(tty, f"Toggle {FLOW_TITLE}")
            tty.wait(lambda: f"╭─ {FLOW_TITLE}" not in tty.text and tty.screen.cursor_on(EDITOR),
                     "Flow Runner explicitly hidden with editor focus", TIMEOUT)
            open_flow()
            open_flow()  # Repeating the alias focuses; it never toggles closed.
            verify_overview(tty, project, endpoint)
            hold_testing.set()
            verify_spinner(tty, final_requested, release_final)
            tty.send(b"\x1b q")
            tty.finish(before)
    assert not journal.exists(), journal.read_text()
    assert file.read_text() == EDITOR + "\n"


if __name__ == "__main__":
    binary = str(Path(sys.argv[1]).resolve(strict=True))
    with tempfile.TemporaryDirectory(prefix="cobalt-silver-polish-") as temporary:
        test(binary, Path(temporary).resolve())
    print("Silver polish PTY: pinned compact flow, aligned highlighted Overview, local running/final stage paint")
