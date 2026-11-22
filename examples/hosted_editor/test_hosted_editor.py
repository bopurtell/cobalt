"""PTY acceptance for the sample host and the unmodified standalone entry point."""

import codecs
from contextlib import contextmanager
import errno
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unicodedata


F2 = b"\x1bOQ"
F3 = b"\x1bOR"
F4 = b"\x1bOS"
F5 = b"\x1b[15~"
F6 = b"\x1b[17~"
F10 = b"\x1b[21~"
ANSI = re.compile(r"\x1b(?:\[([0-?]*)([ -/]*)([@-~])|\][^\x07]*\x07)")
NATIVE = b" vn"
FIRST = "HOST_START_DOCUMENT\n"
SECOND = "other line\n界SECOND_DOCUMENT\n"


class Screen:
    """The small subset of ANSI used by Notty's line-diff renderer."""

    def __init__(self):
        self.resize(132, 34)
        self.row = self.col = 0
        self.cursor_visible = False
        self.drawing = False
        self.decode = codecs.getincrementaldecoder("utf-8")(errors="replace")
        self.pending = ""

    def resize(self, width, height):
        self.width, self.height = width, height
        self.lines = [[" "] * width for _ in range(height)]

    def feed(self, chunk):
        data = self.pending + self.decode.decode(chunk)
        i = 0
        while i < len(data):
            c = data[i]
            if c == "\x1b":
                match = ANSI.match(data, i)
                if not match:
                    break
                params, _, command = match.groups()
                if command == "H":
                    self.row, self.col = (int(value) - 1 for value in params.split(";"))
                elif command == "E":
                    self.row, self.col = self.row + 1, 0
                elif command == "K" and 0 <= self.row < self.height:
                    self.lines[self.row][self.col:] = [" "] * max(0, self.width - self.col)
                elif params == "?25" and command in ("h", "l"):
                    self.cursor_visible = command == "h"
                elif params == "?2026" and command in ("h", "l"):
                    self.drawing = command == "h"
                elif command == "G" and params == "1":
                    self.col = 0
                i = match.end()
                continue
            if c == "\r":
                self.col = 0
            elif c == "\n":
                self.row, self.col = self.row + 1, 0
            elif c >= " " and 0 <= self.row < self.height and self.col < self.width:
                self.lines[self.row][self.col] = c
                self.col += 1
                if unicodedata.east_asian_width(c) in ("F", "W") and self.col < self.width:
                    self.lines[self.row][self.col] = ""
                    self.col += 1
            i += 1
        self.pending = data[i:]

    @property
    def text(self):
        return "\n".join("".join(line) for line in self.lines)

    def cursor_on(self, text):
        return (self.cursor_visible and 0 <= self.row < self.height
                and text in "".join(self.lines[self.row]))


class Terminal:
    def __init__(self, master, slave, process):
        self.master = master
        self.slave = slave
        self.process = process
        self.screen = Screen()

    @property
    def text(self):
        return self.screen.text

    def wait(self, predicate, description, timeout=10):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if not self.screen.drawing and predicate():
                return
            readable, _, _ = select.select([self.master], [], [], 0.02)
            if readable:
                self.screen.feed(os.read(self.master, 65536))
            elif self.process.poll() is not None:
                break
        assert not self.screen.drawing and predicate(), (
            f"waiting for {description} (exit {self.process.poll()}):\n{self.text[-10000:]}"
        )

    def see(self, *needles):
        self.wait(lambda: all(needle in self.text for needle in needles), repr(needles))

    def send(self, keys):
        os.write(self.master, keys)

    def resize(self, width, height):
        self.screen.resize(width, height)
        set_size(self.slave, width, height)
        # An openpty pair alone does not make the slave the controlling terminal.
        self.process.send_signal(signal.SIGWINCH)

    def finish(self, termios_before):
        assert self.process.wait(timeout=10) == 0, self.text
        assert termios.tcgetattr(self.slave) == termios_before, "outer TTY left modified"


def set_size(slave, width, height):
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", height, width, 0, 0))


@contextmanager
def terminal(args, env):
    master, slave = pty.openpty()
    before = termios.tcgetattr(slave)
    set_size(slave, 132, 34)
    try:
        process = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave, env=env)
        try:
            yield Terminal(master, slave, process), before
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
    finally:
        os.close(master)
        os.close(slave)


def hosted(binary, root, env):
    first, second = root / "first.txt", root / "second.txt"
    first.write_text(FIRST, encoding="utf-8")
    second.write_text(SECOND, encoding="utf-8")
    with terminal([binary, str(root), first.name, second.name], env) as (tty, before):
        tty.see("HOST SIBLING", "HOST_START_DOCUMENT", "Editor focus", "Editor: 102x33")

        tty.send(NATIVE)
        tty.see("Line numbers: absolute")

        tty.send(F5)
        tty.see("Opened second.txt", "界SECOND_DOCUMENT")
        tty.wait(lambda: tty.screen.cursor_on("界SECOND_DOCUMENT"), "translated editor cursor")
        # C1 uses one-based display columns: column 3 is after this two-cell glyph.
        tty.send(b"iDIRTY_\x1b")
        tty.see("界DIRTY_SECOND_DOCUMENT")

        tty.send(F4)
        tty.see("Opened first.txt", "HOST_START_DOCUMENT")
        tty.send(F5)
        tty.see("Opened second.txt", "界DIRTY_SECOND_DOCUMENT")
        tty.send(F6)
        tty.see("Open failed:", "界DIRTY_SECOND_DOCUMENT")

        # Send focus and text together to exercise routing before the next draw.
        tty.send(F2 + b"ix")
        tty.see("Sibling focus", "Sibling keys: 2", "界DIRTY_SECOND_DOCUMENT")
        tty.wait(lambda: not tty.screen.cursor_visible, "hidden editor cursor")
        tty.send(F2)
        tty.see("Editor focus", "界DIRTY_SECOND_DOCUMENT")
        tty.wait(lambda: tty.screen.cursor_visible, "restored editor cursor")

        tty.resize(90, 24)
        tty.see("Editor: 60x23", "界DIRTY_SECOND_DOCUMENT")
        tty.send(F3)
        tty.see("Editor hidden", "Sibling focus", "Sibling keys: 2")
        assert "DIRTY_SECOND_DOCUMENT" not in tty.text
        tty.send(F4)
        tty.see("Opened first.txt", "Editor hidden")
        tty.send(F5)
        tty.see("Opened second.txt", "Editor hidden")
        tty.resize(120, 30)
        tty.see("Editor hidden", "Terminal: 120x30")
        tty.send(F3)
        tty.see("Editor focus", "Editor: 90x29", "界DIRTY_SECOND_DOCUMENT")

        tty.send(b"u")
        tty.see("界SECOND_DOCUMENT")
        tty.send(b"\x12")
        tty.see("界DIRTY_SECOND_DOCUMENT")
        assert second.read_text(encoding="utf-8") == SECOND

        # Cobalt's own quit still checks unsaved buffers; the demo does not intercept it.
        tty.send(b" q")
        tty.see("Unsaved", "界DIRTY_SECOND_DOCUMENT")
        tty.send(b" Q")
        tty.see("Editor closed", "HOST SIBLING")
        tty.send(b"x")
        tty.see("Sibling keys: 3")
        tty.send(F5)
        tty.see("Open failed: editor closed")
        tty.send(F10)
        tty.finish(before)


def standalone(binary, root, env):
    with terminal([binary, "--no-lsp", "--workspace", str(root / "first.txt")], env) as (
        tty, before
    ):
        tty.see("HOST_START_DOCUMENT")
        tty.send(NATIVE)
        tty.see("Line numbers: absolute")
        tty.send(b" q")
        tty.finish(before)


def alive(pid):
    try:
        os.kill(pid, 0)
    except OSError as exc:
        if exc.errno != errno.ESRCH:
            raise
        return False
    return True


def shutdown(binary, root, env):
    # An inert terminal child with a verifiable PID, independent of interactive
    # startup configuration or shell prompt behavior.
    shell = root / "demo-shell"
    pid_file = root / "demo-shell.pid"
    shell.write_text('#!/bin/sh\nprintf "%s\\n" "$$" > "$DEMO_SHELL_PID"\nexec sleep 300\n')
    shell.chmod(0o700)
    with terminal([binary, str(root), "first.txt", "second.txt"],
                  dict(env, SHELL=str(shell), DEMO_SHELL_PID=str(pid_file))) as (tty, before):
        try:
            tty.see("HOST_START_DOCUMENT")
            tty.send(b" /")
            tty.wait(lambda: pid_file.exists() and pid_file.read_text().strip(), "PTY child")
            pid = int(pid_file.read_text())
            tty.send(F3)
            tty.see("Editor hidden")
            assert alive(pid), "hiding Cobalt shut down the session's PTY"
            tty.send(F10)
            tty.finish(before)
            assert not alive(pid), "host shutdown leaked Cobalt's PTY child"
        finally:
            if pid_file.exists() and (text := pid_file.read_text().strip()) and alive(int(text)):
                os.kill(int(text), signal.SIGKILL)


def main():
    demo, cobalt = (str(Path(arg).resolve()) for arg in sys.argv[1:])
    with tempfile.TemporaryDirectory(prefix="cobalt-hosted-editor-") as tmp:
        root = Path(tmp)
        env = dict(os.environ, HOME=tmp, XDG_CONFIG_HOME=str(root / "config"),
                   TERM="xterm-256color", COLORTERM="truecolor", LC_ALL="C.UTF-8")
        hosted(demo, root, env)
        standalone(cobalt, root, env)
        shutdown(demo, root, env)
    print("Hosted editor: open and reopen, resize, focus, hide/show, undo/redo, native parity, shutdown")


if __name__ == "__main__":
    main()
