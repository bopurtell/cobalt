"""Drive standalone mouse input through the real Notty decoder and PTY."""
from contextlib import contextmanager
import errno
import os
from pathlib import Path
import pty
import re
import select
import subprocess
import sys
import tempfile
import termios
import time

# Share the ANSI parser with the other standalone/hosted PTY acceptance test.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "examples" / "hosted_editor"))
from test_hosted_editor import Screen, set_size


MOUSE_MODES = {1000, 1002, 1003, 1005, 1006, 1015}
DEC_MODES = re.compile(rb"\x1b\[\?([\d;]+)([hl])")


def sgr_mouse(button, x, y, *, suffix="M"):
    # Terminal cells in the report are one-based.
    return f"\x1b[<{button};{x + 1};{y + 1}{suffix}".encode()


class Editor:
    def __init__(self, master, slave, process):
        self.master, self.slave, self.process = master, slave, process
        self.output = bytearray()
        self.screen = Screen()

    def read(self):
        if not select.select([self.master], [], [], 0.02)[0]:
            return
        try:
            chunk = os.read(self.master, 65536)
        except OSError as exc:
            if exc.errno == errno.EIO:
                return
            raise
        self.output.extend(chunk)
        self.screen.feed(chunk)

    def wait(self, predicate, what):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if not self.screen.drawing and predicate():
                return
            if self.process.poll() is not None:
                break
            self.read()
        raise AssertionError(f"waiting for {what} (exit {self.process.poll()}):\n"
                             f"{self.screen.text}\n{bytes(self.output[-1500:])!r}")

    def see(self, marker):
        self.wait(lambda: marker in self.screen.text, marker)

    def keys(self, keys):
        os.write(self.master, keys)

    def report(self, button, text, offset=0, *, suffix="M", on_row_with=""):
        matches = [(line.index(text) + offset, y)
                   for y, cells in enumerate(self.screen.lines)
                   if text in (line := "".join(cells)) and on_row_with in line]
        assert len(matches) == 1, (text, on_row_with, matches, self.screen.text)
        [(x, y)] = matches
        # Wire coordinates are one-based. Picking an exact column and row in
        # the resulting edit checks that UI input doesn't subtract again.
        return sgr_mouse(button, x, y, suffix=suffix)

    def finish(self, before, status=0):
        # Keep draining so shutdown writes cannot block on a full PTY.
        deadline = time.monotonic() + 10
        while self.process.poll() is None and time.monotonic() < deadline:
            self.read()
        assert self.process.poll() == status, (self.process.poll(), self.screen.text)
        while select.select([self.master], [], [], 0)[0]:
            self.read()
        assert termios.tcgetattr(self.slave) == before, "outer TTY left modified"
        assert not self.modes() & MOUSE_MODES, "terminal left reporting mouse events"
        assert 2004 not in self.modes(), "terminal left in bracketed paste mode"
        assert 1049 not in self.modes(), "terminal left on alternate screen"

    def modes(self, *, ever_enabled=False):
        enabled = set()
        for match in DEC_MODES.finditer(self.output):
            modes = {int(mode) for mode in match[1].split(b";")}
            if match[2] == b"h":
                enabled.update(modes)
            elif not ever_enabled:
                enabled.difference_update(modes)
        return enabled

    def mouse_mode_writes(self):
        return [match[0] for match in DEC_MODES.finditer(self.output)
                if {int(mode) for mode in match[1].split(b";")} & MOUSE_MODES]

    def assert_button_motion(self):
        # xterm's tracking modes are mutually exclusive: the last selected
        # mode must be 1002, not merely present somewhere in the output.
        tracking = None
        for match in DEC_MODES.finditer(self.output):
            for mode in map(int, match[1].split(b";")):
                if mode in (9, 1000, 1001, 1002, 1003):
                    if match[2] == b"h":
                        tracking = mode
                    elif mode == tracking:
                        tracking = None
        assert tracking == 1002, (tracking, self.mouse_mode_writes())
        assert 1006 in self.modes(), "SGR mouse coordinates are not enabled"

    def toggle_mouse(self, *, enabled):
        self.keys(b" ccToggle mouse\r")
        if enabled:
            self.wait(lambda: {1002, 1006} <= self.modes(), "button-motion reporting on")
            self.assert_button_motion()
        else:
            self.wait(lambda: not self.modes() & MOUSE_MODES, "mouse reporting off")
        assert {1049, 2004} <= self.modes(), "toggle disturbed screen or paste mode"

    def palette_command(self, query, title):
        # Enter only after the exact query has selected the intended first result.
        selected_first = re.compile(rf"│ > {re.escape(query)} +│[^\n]*\n"
                                    rf"[^\n]*│ > {re.escape(title)} +")
        self.keys(b" cc" + query.encode("ascii"))
        self.wait(lambda: "╭─ Commands" in self.screen.text
                  and selected_first.search(self.screen.text),
                  f"{title!r} first and selected for {query!r}")
        self.keys(b"\r")


@contextmanager
def editor(binary, file, env, *flags):
    master, slave = pty.openpty()
    process = None
    try:
        before = termios.tcgetattr(slave)
        set_size(slave, 132, 34)  # Matches Screen's initial dimensions.
        process = subprocess.Popen([binary, "--no-lsp", *flags, str(file)],
                                   stdin=slave, stdout=slave, stderr=slave, env=env)
        yield Editor(master, slave, process), before
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait(timeout=5)
        os.close(master)
        os.close(slave)


def test(binary, root, env):
    file = root / "mouse.txt"
    original = "first line\nclick:abcd\npaste:abcd\n" + "".join(
        f"row-{n:03}\n" for n in range(80))
    file.write_text(original)

    with editor(binary, file, env, "--no-mouse", "--bare") as (tty, before):
        tty.see("paste:abcd")
        assert not tty.modes(ever_enabled=True) & MOUSE_MODES
        # A report from a parent that was already tracking mouse still can't
        # move the cursor in an editor that starts with reporting off.
        tty.keys(tty.report(0, "click:abcd", 7) + b"iN\x1b w q")
        tty.finish(before)
        assert not tty.modes(ever_enabled=True) & MOUSE_MODES
        assert file.read_text() == "N" + original

    file.write_text(original)
    with editor(binary, file, env, "--bare") as (tty, before):
        tty.see("paste:abcd")
        tty.assert_button_motion()
        assert 2004 in tty.modes(), "bracketed paste not enabled"
        # Press on b; release and drag on a different row must not move again.
        tty.keys(tty.report(0, "click:abcd", 7) + tty.report(32, "first line")
                 + tty.report(0, "first line", suffix="m")
                 + tty.report(16, "first line") + b"iN\x1b")
        tty.see("click:aNbcd")
        tty.keys(tty.report(65, "click:aNbcd") * 80)
        tty.wait(lambda: "row-060" in tty.screen.text and "click:aNbcd" not in tty.screen.text,
                 "wheel-down moves viewport away from cursor")
        assert not tty.screen.cursor_visible, "offscreen cursor is still drawn"
        tty.keys(tty.report(64, "row-060") * 80)
        tty.see("first line")
        tty.keys(tty.report(65, "click:aNbcd") * 80)
        tty.wait(lambda: "row-060" in tty.screen.text and "click:aNbcd" not in tty.screen.text,
                 "wheel-down moves viewport away again")
        tty.keys(b"iR")
        tty.see("click:aRNbcd")  # Editing recovers the original cursor, not the wheel target.

        # Click while in Insert and paste text containing the normal escape
        # chord. A report inside paste must not route the paste to another row.
        tty.keys(tty.report(0, "paste:abcd", 7) + b"\x1b[200~P"
                 + tty.report(0, "click:aRNbcd") + b"jk\x1b[201~\x1b w q")
        tty.finish(before)
        expected = original.replace("click:abcd", "click:aRNbcd").replace(
            "paste:abcd", "paste:aPjkbcd")
        assert file.read_text() == expected, file.read_text()

    with editor(binary, file, env, "--mouse") as (tty, before):
        tty.see("paste:aPjkbcd")
        tty.assert_button_motion()
        tty.process.terminate()
        tty.finish(before, status=1)
        assert file.read_text() == expected


def test_toggle(binary, root, env):
    file = root / "toggle.txt"
    file.write_text("first:abcd\nsecond:abcd\nthird:abcd\n")
    with editor(binary, file, env, "--bare") as (tty, before):
        tty.see("third:abcd")
        tty.assert_button_motion()
        writes = tty.mouse_mode_writes()
        assert len(set(writes)) == len(writes), "startup rewrote mouse modes"
        tty.keys(tty.report(0, "second:abcd", 8) + b"iA\x1b")
        tty.see("second:aAbcd")
        assert tty.mouse_mode_writes() == writes, "redraw rewrote mouse modes"

        tty.toggle_mouse(enabled=False)
        # Inject a late report despite the terminal being in selection mode:
        # it must neither move the cursor nor leak escape bytes as keys.
        tty.keys(tty.report(0, "first:abcd", 7) + b"iB\x1b")
        tty.see("second:aBAbcd")
        assert not tty.modes() & MOUSE_MODES, "redraw re-enabled mouse modes"

        tty.toggle_mouse(enabled=True)
        tty.keys(tty.report(0, "third:abcd", 7) + b"iC\x1b w q")
        tty.finish(before)
        assert file.read_text() == "first:abcd\nsecond:aBAbcd\nthird:aCbcd\n"

    with editor(binary, file, env, "--mouse", "--no-mouse", "--bare") as (tty, before):
        tty.see("third:aCbcd")
        assert not tty.modes(ever_enabled=True) & MOUSE_MODES
        tty.toggle_mouse(enabled=True)
        tty.toggle_mouse(enabled=False)
        tty.keys(b" q")
        tty.finish(before)


def test_directory(binary, root, env):
    directory = root / "project"
    directory.mkdir()
    first, second = directory / "a.txt", directory / "b.txt"
    first.write_text("FIRST_DOCUMENT\n")
    second.write_text("SECOND_DOCUMENT\n")
    for n in range(48):
        (directory / f"row-{n:03}.txt").touch()
    original_entries = sorted(p.name for p in directory.iterdir())
    with editor(binary, directory, env, "--mouse", "--workspace") as (tty, before):
        tty.see("a.txt")
        tty.keys(b" ds\r")
        tty.see("FIRST_DOCUMENT")
        tty.see("b.txt")
        tty.wait(lambda: tty.screen.cursor_on("FIRST_DOCUMENT"), "editor focus")
        tty.keys(tty.report(65, "b.txt", 1) * 48)
        tty.wait(lambda: "row-047.txt" in tty.screen.text and "b.txt" not in tty.screen.text,
                 "wheel over unfocused directory scrolls its listing")
        assert tty.screen.cursor_on("FIRST_DOCUMENT"), "directory wheel stole editor focus"
        tty.keys(tty.report(64, "row-047.txt", 1) * 48)
        tty.see("b.txt")
        tty.keys(tty.report(0, "b.txt", 1))
        tty.wait(lambda: tty.screen.cursor_on("b.txt"), "directory row gains focus")
        assert "FIRST_DOCUMENT" in tty.screen.text and "SECOND_DOCUMENT" not in tty.screen.text
        assert sorted(p.name for p in directory.iterdir()) == original_entries
        assert first.read_text() == "FIRST_DOCUMENT\n"
        assert second.read_text() == "SECOND_DOCUMENT\n"

        tty.keys(b"\r")
        tty.see("SECOND_DOCUMENT")
        # The top tab strip contains both names; the browser has one per row.
        tty.keys(tty.report(0, "a.txt", 1, on_row_with="b.txt"))
        tty.see("FIRST_DOCUMENT")
        tty.keys(b" q")
        tty.finish(before)


def test_two_editors(binary, root, env):
    directory = root / "split"
    directory.mkdir()
    first, second = directory / "a.txt", directory / "b.txt"
    left = "left:abcd\n" + "".join(f"left-{n:03}\n" for n in range(48))
    right = "right:abcd\n" + "".join(f"right-{n:03}\n" for n in range(48))
    first.write_text(left)
    second.write_text(right)
    with editor(binary, directory, env, "--mouse", "--workspace") as (tty, before):
        tty.see("a.txt")
        tty.keys(b" ds\r")
        tty.see("left:abcd")
        tty.keys(b" dfj\r")
        tty.see("right:abcd")
        tty.keys(b" dh bp sn")
        tty.wait(lambda: "left:abcd" in tty.screen.text and "right:abcd" in tty.screen.text,
                  "both editor panes")
        tty.assert_button_motion()

        def pane_borders():
            # The file frames' top borders share a line and have one gap
            # between them. Use cell indices, not offsets in the UTF-8 stream.
            for y, cells in enumerate(tty.screen.lines):
                if "╭" not in cells:
                    continue
                l0 = cells.index("╭")
                if "╮" not in cells[l0 + 1:]:
                    continue
                l1 = cells.index("╮", l0 + 1)
                r0 = l1 + 2
                if r0 < len(cells) and cells[r0] == "╭" and "╮" in cells[r0 + 1:]:
                    return y, l0, l1, r0, cells.index("╮", r0 + 1)
            return None

        tty.wait(lambda: pane_borders() is not None, "two adjacent file frames")
        y, l0, l1, r0, r1 = pane_borders()
        divider = l1 + 1

        def moved_by(delta):
            return pane_borders() == (y, l0, l1 + delta, r0 + delta, r1)

        tty.keys(sgr_mouse(0, divider, y + 1) + sgr_mouse(32, divider + 9, y + 2))
        tty.wait(lambda: moved_by(9), "SGR motion widens the left pane by nine cells")
        tty.keys(sgr_mouse(0, divider + 12, y + 2, suffix="m"))
        tty.wait(lambda: moved_by(12), "SGR release finishes at its reported column")

        # A terminal doesn't normally send a motion report after release in
        # mode 1002. Inject a late one, followed by a click/edit, to prove the
        # capture is gone without using a timing-based negative assertion.
        tty.keys(sgr_mouse(32, divider - 8, y + 2)
                 + tty.report(0, "left:abcd", 6) + b"iL\x1b")
        tty.see("left:aLbcd")
        assert moved_by(12), "motion after release still changed the split"

        tty.keys(tty.report(65, "right:abcd") * 48)
        tty.wait(lambda: "right-047" in tty.screen.text and "right:abcd" not in tty.screen.text,
                 "wheel over the other editor scrolls only that editor")
        assert "left:aLbcd" in tty.screen.text
        tty.keys(b"iF\x1b w")
        tty.see("left:aFLbcd")

        tty.keys(tty.report(64, "right-047") * 48)
        tty.see("right:abcd")
        tty.keys(tty.report(0, "right:abcd", 7) + b"iR\x1b w")
        tty.see("right:aRbcd")
        assert "left:aFLbcd" in tty.screen.text

        # Selecting a file tab changes the content of the focused pane in
        # place. Both panes now render the same file; the cursor must still
        # follow the clicked physical slot, including on the same row.
        tty.keys(tty.report(0, "1:a.txt", 3, on_row_with="b.txt"))

        def copies():
            marker = "left:aFLbcd"
            return [(x, row) for row, cells in enumerate(tty.screen.lines)
                    for x in range(len(cells) - len(marker) + 1)
                    if "".join(cells[x:x + len(marker)]) == marker]

        tty.wait(lambda: len(copies()) == 2, "the same file in both panes")
        for x, row in sorted(copies()):
            col = x + 2
            tty.keys(sgr_mouse(0, col, row) + sgr_mouse(0, col, row, suffix="m"))
            tty.wait(lambda: tty.screen.cursor_visible
                     and (tty.screen.col, tty.screen.row) == (col, row),
                     f"same-file pane cursor at {col},{row}")
            assert moved_by(12)

        tty.keys(b" q")
        tty.finish(before)
    assert first.read_text() == left.replace("left:abcd", "left:aFLbcd")
    assert second.read_text() == right.replace("right:abcd", "right:aRbcd")


def test_workspace_focus(binary, root, env):
    file = root / "history.txt"
    original = "first history line\nclick:abcd\n"
    file.write_text(original)
    history = "╭─ History"
    problems = "╭─ Problems"
    # Snippet initialization records a History entry even with a fresh HOME.
    entry = "info [snippets]"
    with editor(binary, file, env, "--workspace") as (tty, before):
        tty.wait(lambda: tty.screen.cursor_on("first history line")
                 and problems + " (workspace)" in tty.screen.text,
                 "editor focused with Problems visible")
        assert history not in tty.screen.text, "History unexpectedly visible at startup"
        tty.keys(b" vm")
        tty.wait(lambda: tty.screen.cursor_on("first history line")
                 and history + ":" in tty.screen.text and entry in tty.screen.text,
                 "History opened without taking focus and shows the startup event")
        tty.assert_button_motion()

        tty.keys(tty.report(0, entry))
        tty.wait(lambda: history + "*:" in tty.screen.text and not tty.screen.cursor_visible,
                 "History gains focus and the editor cursor disappears")
        tty.palette_command("hide", "Hide focused tile")
        tty.wait(lambda: history not in tty.screen.text and "╭─ Commands" not in tty.screen.text
                 and problems + " (workspace)" in tty.screen.text
                 and tty.screen.cursor_on("first history line"),
                 "only History is hidden and editor focus is restored")

        tty.palette_command("unhide", "Unhide tile")
        tty.see(history + "*:")
        tty.keys(tty.report(0, "No active problems"))
        tty.wait(lambda: problems + "*" in tty.screen.text and history + ":" in tty.screen.text,
                 "click switches from History to Problems")
        tty.keys(tty.report(0, "click:abcd", 7))
        tty.wait(lambda: tty.screen.cursor_on("click:abcd")
                 and problems + " (workspace)" in tty.screen.text,
                 "click switches from Problems back to the editor")

        tty.toggle_mouse(enabled=False)
        # A late report over History must not redirect the queued edit.
        tty.keys(tty.report(0, entry) + b"iN\x1b")
        tty.wait(lambda: tty.screen.cursor_on("click:aNbcd") and history + ":" in tty.screen.text,
                 "late History click is ignored while mouse reporting is off")
        assert not tty.modes() & MOUSE_MODES
        tty.keys(b" w q")
        tty.finish(before)
    assert file.read_text() == original.replace("click:abcd", "click:aNbcd")


if __name__ == "__main__":
    binary = str(Path(sys.argv[1]).resolve())
    with tempfile.TemporaryDirectory(prefix="cobalt-mouse-cli-") as temporary:
        root = Path(temporary)
        env = dict(os.environ, HOME=temporary, XDG_CONFIG_HOME=str(root / "config"),
                   TERM="xterm-256color", COLORTERM="truecolor", LC_ALL="C.UTF-8")
        test(binary, root, env)
        test_toggle(binary, root, env)
        test_directory(binary, root, env)
        test_two_editors(binary, root, env)
        test_workspace_focus(binary, root, env)
    print("Mouse CLI: default, startup override, runtime toggle, click/keyboard edit,"
           " wheel, directories, tabs, editor divider drag, same-file panes, workspace focus, bracketed paste,"
          " quit and signal cleanup")
