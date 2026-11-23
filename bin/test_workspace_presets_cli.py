"""Real standalone PTY coverage for the Default and Silver workspace presets."""

from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import threading

sys.path.insert(0, str(Path(__file__).absolute().parents[1] / "examples" / "hosted_editor"))
from test_hosted_editor import terminal


EVIDENCE_PARENT = Path("/var/tmp/cobalt-stage-progress")
FIRST_LINE = "WORKSPACE_PRESET_DOCUMENT"
SECOND_LINE = "SECOND_LINE_TARGET"
DIRTY_LINE = "SEDIRTY_COND_LINE_TARGET"
ORIGINAL = f"{FIRST_LINE}\n{SECOND_LINE}\n"
SILVER = ("Silver: Overview", "Silver: Stage Checklist", "Silver: Flow Runner")
REVIEW = "Silver: Flow Review"


def tile(text, name, *, focused=None):
    star = r"\*?" if focused is None else (r"\*" if focused else "")
    return re.search(rf"╭─ {re.escape(name)}{star}(?= |:|─|╮)", text) is not None


def editor_cursor(tty, marker, offset):
    if not tty.screen.cursor_on(marker):
        return False
    row = "".join(tty.screen.lines[tty.screen.row])
    return tty.screen.col == row.index(marker) + offset


def command(tty, query, title=None):
    title = title or query
    selected_first = re.compile(rf"│ > {re.escape(query)} +│[^\n]*\n"
                                rf"[^\n]*│ > {re.escape(title)} +")
    tty.send(b" cc" + query.encode("ascii"))
    tty.wait(lambda: selected_first.search(tty.text), f"{title!r} first and selected")
    tty.send(b"\r")


def workspace(tty, description, *, silver=False, zen=False, overview=True,
              marker=SECOND_LINE, offset=2, extra=()):
    def visible():
        text = tty.text
        return ("╭─ Commands" not in text and marker in text
                and tile(text, "Status") != zen
                and tile(text, "Problems") == (not silver and not zen)
                and tile(text, SILVER[0]) == (overview and not zen)
                and all(tile(text, name) == silver for name in SILVER[1:])
                and not tile(text, "History") and not tile(text, REVIEW)
                and all(word in text for word in extra)
                and editor_cursor(tty, marker, offset))

    tty.wait(visible, description)


def open_at_second_line(tty):
    tty.see(FIRST_LINE)
    tty.resize(320, 44)
    tty.see(SECOND_LINE)
    tty.send(b"jll")
    tty.wait(lambda: editor_cursor(tty, SECOND_LINE, 2), "editor cursor on second line")


def disconnected(binary, file, env):
    with terminal([binary, "--no-lsp", "--workspace", str(file)], env) as (tty, before):
        open_at_second_line(tty)
        workspace(tty, "default non-Zen workspace has no History",
                  extra=("Silver disconnected",))
        tty.send(b"iDIRTY_\x1b")
        tty.wait(lambda: editor_cursor(tty, DIRTY_LINE, 7), "unsaved edit and cursor")

        command(tty, "Layout: Silver")
        workspace(tty, "Silver layout exposes all three disconnected tiles", silver=True,
                  marker=DIRTY_LINE, offset=7, extra=("Connect to a Silver project first",))
        assert file.read_text(encoding="utf-8") == ORIGINAL, "preset saved the buffer"

        command(tty, "st", SILVER[1])
        tty.wait(lambda: "j/k stage | R run" in tty.text and not tty.screen.cursor_visible,
                 "focused stage checklist footer and no editor cursor")
        command(tty, "Layout: Default")
        workspace(tty, "Default hides Stage and Kickoff and restores the editor cursor",
                  marker=DIRTY_LINE, offset=7)

        tty.send(b" vM")
        tty.wait(lambda: tile(tty.text, "History", focused=True), "History can be shown and focused")
        command(tty, "Layout: Default")
        workspace(tty, "Default hides explicitly shown History", marker=DIRTY_LINE, offset=7)

        tty.send(b" vz")
        workspace(tty, "Zen suppresses supporting tiles", zen=True, marker=DIRTY_LINE, offset=7)
        command(tty, "Layout: Silver")
        workspace(tty, "Silver preset from Zen enters the workspace with editor focus",
                  silver=True, marker=DIRTY_LINE, offset=7)
        command(tty, "Layout: Default")
        workspace(tty, "Default restores the workspace again", marker=DIRTY_LINE, offset=7)

        tty.send(b"u")
        tty.wait(lambda: SECOND_LINE in tty.text and DIRTY_LINE not in tty.text, "original undo step")
        tty.send(b"\x12")
        tty.wait(lambda: DIRTY_LINE in tty.text, "original redo step")
        assert file.read_text(encoding="utf-8") == ORIGINAL, "switching/undo/redo wrote to disk"
        tty.send(b" w q")
        tty.finish(before)
    assert file.read_text(encoding="utf-8") == ORIGINAL.replace(SECOND_LINE, DIRTY_LINE)


def configured_startup(binary, file, env, config):
    with terminal([binary, "--no-lsp", str(file)], env) as (tty, before):
        workspace(tty, "ordinary startup still defaults to Zen without configuration",
                  zen=True, marker=FIRST_LINE, offset=0)
        tty.send(b" q")
        tty.finish(before)
    source = ("open Cobalt_config\nlet () =\n"
              "  View.set_startup_workspace true;\n"
              "  View.set_startup_silver_overview false\n")
    config.write_text(source, encoding="utf-8")
    with terminal([binary, "--no-lsp", str(file)], env) as (tty, before):
        # Verify the initial frame before any key or resize.
        workspace(tty, "ordinary startup shows only Status and Problems",
                  overview=False, marker=FIRST_LINE, offset=0)
        open_at_second_line(tty)
        tty.send(b" vz")
        workspace(tty, "Zen is still available", zen=True)
        tty.send(b" vz")
        workspace(tty, "leaving Zen retains the startup band", overview=False)
        tty.send(b" vS")
        workspace(tty, "hidden overview can be toggled on")
        command(tty, "Reload configuration")
        workspace(tty, "reload keeps the live overview visible",
                  extra=("Configuration reloaded",))
        tty.send(b" vS")
        workspace(tty, "overview can be toggled off again", overview=False)
        command(tty, "Layout: Silver")
        workspace(tty, "Silver preset overrides the startup band", silver=True)
        command(tty, "Layout: Default")
        workspace(tty, "Default remains the built-in preset")
        tty.send(b" q")
        tty.finish(before)
    for flags in (["--workspace"], ["--workspace", "--bare"]):
        with terminal([binary, "--no-lsp", *flags, str(file)], env) as (tty, before):
            tty.see(FIRST_LINE)
            if "--bare" in flags:
                assert not any(tile(tty.text, name) for name in ("Status", "Problems", *SILVER))
                assert tty.text.startswith(FIRST_LINE), tty.text
                tty.send(b" vB")
            workspace(tty, "explicit Workspace or return from Bare respects the startup band",
                      overview=False, marker=FIRST_LINE, offset=0)
            tty.send(b" q")
            tty.finish(before)
    assert config.read_text(encoding="utf-8") == source


@contextmanager
def unavailable_peer(project):
    """A private Silver wire peer with a verified project but no providers."""
    requests = []
    root = json.dumps(str(project))
    instance, project_id = "workspace-preset-fixture", "workspace-preset-bound-project"

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def reply(self, response):
            data = response.encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/sexp")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            requests.append((self.path, ""))
            if self.path == "/api/hello":
                self.reply(f"((protocol_versions (1)) (capabilities (simulation)) (instance_id {instance}))")
            else:
                self.send_error(404)

        def do_POST(self):
            request = self.rfile.read(int(self.headers["Content-Length"])).decode()
            requests.append((self.path, request))
            if self.path == "/api/v1/open-project":
                self.reply(f"(Ok ((project ((id {project_id}) (root ((path {root})))))))")
            elif self.path == "/api/v1/simulation" and "(operation Get)" in request:
                self.reply("(Ok ((configured false) (discovery ()) (discovery_digest ())"
                           " (discovery_job ()) (discovery_error ()) (attempts ()) (detail ())))")
            else:
                self.send_error(404)

    with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield f"http://127.0.0.1:{server.server_port}"
        finally:
            server.shutdown()
            thread.join()
    assert requests, "Cobalt did not use the private peer"
    assert {path for path, _ in requests} == {"/api/hello", "/api/v1/open-project", "/api/v1/simulation"}, requests
    opens = [request for path, request in requests if path == "/api/v1/open-project"]
    assert len(opens) == 1, opens
    assert re.search(r"\(root\s*" + re.escape(root) + r"\)", opens[0]), opens
    assert f"(instance_id {instance})" in opens[0] and "(environment Inherit_daemon)" in opens[0], opens
    assert all(f"(project {project_id})" in request and "(operation Get)" in request
               for path, request in requests if path == "/api/v1/simulation"), requests


def bound_but_unavailable(binary, file, env, project):
    original = file.read_text(encoding="utf-8")
    with unavailable_peer(project) as url:
        flags = ["--silver-endpoint", url, "--silver-project", str(project)]
        with terminal([binary, "--no-lsp", *flags, str(file)], env) as (tty, before):
            open_at_second_line(tty)
            expected = (f"Project:  {project}", "Silver does not advertise ASIC operations",
                        "Silver Testing provider is not configured")
            workspace(tty, "explicit Silver launch shows Overview despite startup preference",
                      extra=expected[:1])
            command(tty, "Layout: Silver")
            workspace(tty, "Silver shows the exact explicit project even without providers",
                      silver=True, extra=expected)
            command(tty, "Layout: Default")
            workspace(tty, "Default keeps the explicit project's Overview without editing",
                      extra=(f"Project:  {project}",))
            command(tty, "Layout: Silver")
            workspace(tty, "Silver reuses the same bound project", silver=True, extra=expected)
            tty.send(b" q")
            tty.finish(before)
    assert file.read_text(encoding="utf-8") == original


def main():
    binary = str(Path(sys.argv[1]).resolve(strict=True))
    EVIDENCE_PARENT.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="wsp-", dir=EVIDENCE_PARENT) as temporary:
        root = Path(temporary)
        env = dict(os.environ, HOME=temporary, TMPDIR=temporary, XDG_RUNTIME_DIR=temporary,
                   TERM="xterm-256color", COLORTERM="truecolor", LC_ALL="C.UTF-8",
                   XDG_CONFIG_HOME=str(root / "config"), XDG_STATE_HOME=str(root / "state"),
                   XDG_CACHE_HOME=str(root / "cache"), XDG_DATA_HOME=str(root / "data"))
        project = root / "bound project"
        project.mkdir()
        file = root / "outside-project.txt"
        file.write_text(ORIGINAL, encoding="utf-8")
        disconnected(binary, file, env)
        file.write_text(ORIGINAL, encoding="utf-8")
        config = root / "config" / "cobalt" / "config.ml"
        config.parent.mkdir(parents=True)
        configured_startup(binary, file, env, config)
        bound_but_unavailable(binary, file, env, project)
    print("Workspace presets CLI: configured startup, live palette, Zen, focus, dirty editor, and read-only Silver binding")


if __name__ == "__main__":
    main()
