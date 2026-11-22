"""Real no-provider CLI: startup notice is nonfatal; read/edit/save/toggle/quit."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time


def smoke(binary):
    with tempfile.TemporaryDirectory(prefix="cobalt-no-provider-") as directory:
        root = Path(directory)
        document = root / "document.md"
        original = b"NO_PROVIDER_DOCUMENT\nsecond line\n"
        document.write_bytes(original)
        env = dict(os.environ, XDG_CONFIG_HOME=str(root), HOME=str(root),
                   TERM="xterm-256color", COLORTERM="truecolor", LC_ALL="C.UTF-8")
        help_result = subprocess.run([binary, "--help"], env=env, capture_output=True,
                                     timeout=10, check=True)
        assert b"--markdown" in help_result.stdout
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 160, 0, 0))
        process = subprocess.Popen(
            [binary, "--no-lsp", "--bare", "--markdown", str(document)],
            stdin=slave, stdout=slave, stderr=slave, env=env)
        os.close(slave)
        output = bytearray()

        def until(predicate):
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                if predicate():
                    return
                readable, _, _ = select.select([master], [], [], .05)
                if readable:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
                    if not chunk:
                        break
                    output.extend(chunk)
            assert predicate(), output.decode(errors="replace")

        try:
            until(lambda: b"NO_PROVIDER_DOCUMENT" in output
                  and b"Document decorations unavailable in this build" in output)
            os.write(master, b"iX")
            until(lambda: b"X" in output)
            os.write(master, b"\x1b")
            # Escape is terminal-protocol ambiguous: let its normal timer flush.
            time.sleep(.2)
            os.write(master, b" w")
            until(lambda: document.read_bytes() == b"X" + original)
            # Exercise the actual generic palette entry in this stub build.
            output.clear()
            os.write(master, b" cc")
            until(lambda: b"Commands" in output or b"Palette" in output)
            output.clear()
            os.write(master, b"Toggle document decorations")
            until(lambda: b"1/1" in output)
            output.clear()
            os.write(master, b"\r")
            # The palette closes by clearing its overlay; the document itself
            # need not be repainted, so wait for the cleared palette region.
            until(lambda: b" " * 80 in output)
            os.write(master, b" q")
            # The PTY can close just before the process becomes waitable.
            assert process.wait(timeout=5) == 0
            assert document.read_bytes() == b"X" + original
        finally:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)
            os.close(master)
    print("no provider: --markdown notice; same CLI/UI; read/edit/save/palette toggle/quit")


if __name__ == "__main__":
    smoke(str(Path(sys.argv[1]).resolve()))
