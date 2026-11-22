"""Exercise temporary tile visibility through the standalone command palette."""

import os
from pathlib import Path
import re
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "examples" / "hosted_editor"))
from test_hosted_editor import terminal


PALETTE = "╭─ Commands"
PROBLEMS = "╭─ Problems"
REPORT = "╭─ Demo report"
REPORT_SELECTION = "│ > DEMO REPORT 3/10:"
EDITOR_LINE = "SECOND_LINE_TARGET"
DIRTY_LINE = "SEDIRTY_COND_LINE_TARGET"


def wait_screen(tty, description, *, present=(), absent=(), cursor=None):
    def matches():
        return (all(marker in tty.text for marker in present)
                and not any(marker in tty.text for marker in absent)
                and (cursor is None or cursor()))

    tty.wait(matches, description)


def editor_cursor(tty, marker, offset=None):
    if not tty.screen.cursor_on(marker):
        return False
    line = "".join(tty.screen.lines[tty.screen.row])
    start = line.index(marker)
    end = start + len(marker)
    # Check the column as well as the row: another tile can share the same row.
    return (start <= tty.screen.col < end if offset is None
            else tty.screen.col == start + offset)


def command(tty, query, title):
    # The selected result must be the first painted row beneath the exact query.
    selected_first = re.compile(rf"│ > {re.escape(query)} +│[^\n]*\n"
                                rf"[^\n]*│ > {re.escape(title)} +")
    tty.send(b" cc" + query.encode("ascii"))
    tty.wait(lambda: PALETTE in tty.text and selected_first.search(tty.text),
             f"{title!r} first and selected for {query!r}")
    tty.send(b"\r")


def test(binary, root, env):
    path = root / "retained.txt"
    original = f"FIRST_LINE\n{EDITOR_LINE}\n"
    path.write_text(original, encoding="utf-8")

    with terminal([binary, "--no-lsp", "--workspace", "--demo-report", str(path)], env) as (
        tty, before
    ):
        tty.see(PROBLEMS + " (workspace)", REPORT + " (static)", "FIRST_LINE")
        tty.send(b"jll")
        tty.wait(lambda: editor_cursor(tty, EDITOR_LINE, 2), "editor cursor on second line")

        # Use the focused title, not the transient 'Problems focused' notice.
        tty.send(b" vo vf")
        tty.see(PROBLEMS + "* (document)")
        command(tty, "hide", "Hide focused tile")
        wait_screen(tty, "Problems is hidden and the same editor cursor is restored",
                    present=(REPORT + " (static)",),
                    absent=(PALETTE, PROBLEMS, "No active problems"),
                    cursor=lambda: editor_cursor(tty, EDITOR_LINE, 2))

        tty.send(b"iDIRTY_\x1b")
        tty.see(DIRTY_LINE, "NORMAL")
        assert path.read_text(encoding="utf-8") == original

        command(tty, "unhide", "Unhide tile")
        wait_screen(tty, "Problems returns with its document filter and dirty editor intact",
                    present=(PROBLEMS + "* (document)", DIRTY_LINE), absent=(PALETTE,))

        # The report provides a second view with an observable retained selection.
        tty.send(b"\x1b")
        tty.wait(lambda: editor_cursor(tty, DIRTY_LINE), "editor focus after leaving Problems")
        tty.send(b" vDjj")
        wait_screen(tty, "report focused on its third row",
                    present=(REPORT + "* (static)", REPORT_SELECTION, DIRTY_LINE))
        command(tty, "hide", "Hide focused tile")
        wait_screen(tty, "only the report is hidden and the editor has focus",
                    present=(PROBLEMS + " (document)",),
                    absent=(PALETTE, REPORT, "DEMO REPORT"),
                    cursor=lambda: editor_cursor(tty, DIRTY_LINE))
        command(tty, "unhide", "Unhide tile")
        wait_screen(tty, "report returns focused on the same row",
                    present=(REPORT + "* (static)", REPORT_SELECTION, DIRTY_LINE),
                    absent=(PALETTE,))

        tty.send(b"\x1b")
        tty.wait(lambda: editor_cursor(tty, DIRTY_LINE), "editor focus after leaving the report")
        command(tty, "unhide", "Unhide tile")
        wait_screen(tty, "unhide with no hidden tile reports why and leaves the editor focused",
                    present=("No hidden workspace tile", PROBLEMS + " (document)",
                             REPORT + " (static)", DIRTY_LINE), absent=(PALETTE,),
                    cursor=lambda: editor_cursor(tty, DIRTY_LINE))

        tty.send(b" w q")
        tty.finish(before)
    assert path.read_text(encoding="utf-8") == original.replace(EDITOR_LINE, DIRTY_LINE)


if __name__ == "__main__":
    binary = str(Path(sys.argv[1]).resolve())
    with tempfile.TemporaryDirectory(prefix="cobalt-tile-visibility-cli-") as temporary:
        root = Path(temporary)
        env = dict(os.environ, HOME=temporary, TMPDIR=temporary,
                   XDG_CONFIG_HOME=str(root / "config"), XDG_STATE_HOME=str(root / "state"),
                   XDG_CACHE_HOME=str(root / "cache"), XDG_DATA_HOME=str(root / "data"),
                   XDG_RUNTIME_DIR=temporary, TERM="xterm-256color", COLORTERM="truecolor",
                   LC_ALL="C.UTF-8")
        test(binary, root, env)
    print("Tile visibility CLI: palette hide/unhide and refusal, retained Problems filter,"
          " report selection, and editable dirty buffer")
