"""Exercise cobalt-open against real standalone Cobalt sessions in separate PTYs."""
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
from contextlib import ExitStack, contextmanager


EDITOR, SENDER = (str(Path(arg).resolve()) for arg in sys.argv[1:])


class Editor:
    def __init__(self, master, process):
        self.master = master
        self.process = process
        self.output = bytearray()

    def read(self, seconds):
        if select.select([self.master], [], [], seconds)[0]:
            try:
                data = os.read(self.master, 65536)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                return False
            self.output.extend(data)
            return bool(data)
        return True

    def wait_for(self, marker, after=0):
        deadline = time.monotonic() + 10
        while marker not in self.output[after:] and time.monotonic() < deadline:
            if not self.read(.05):
                break
        assert marker in self.output[after:], (marker, bytes(self.output[-4000:]))

    def keys(self, keys):
        os.write(self.master, keys)


@contextmanager
def launch(env, file, *, opt_in=False):
    master, slave = pty.openpty()
    try:
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
        options = ["--main-editor"] if opt_in else []
        process = subprocess.Popen([EDITOR, "--no-lsp", "--bare", *options, str(file)],
                                   stdin=slave, stdout=slave, stderr=slave, env=env)
    except BaseException:
        os.close(master)
        raise
    finally:
        os.close(slave)
    try:
        yield Editor(master, process)
    finally:
        if process.poll() is None:
            process.kill()
        process.wait(timeout=5)
        os.close(master)


with tempfile.TemporaryDirectory(prefix="cobalt-main-cli-") as temporary, ExitStack() as stack:
    temp = Path(temporary)
    root = temp / "project"
    root.mkdir()
    subdirectory = root / "src"
    subdirectory.mkdir()
    env = dict(os.environ, HOME=temporary, XDG_CONFIG_HOME=temporary,
               TERM="xterm-256color", LC_ALL="C.UTF-8")
    seed = root / "seed.txt"
    seed.write_bytes(b"SELECTED_EDITOR_SEED\n")
    other = root / "other.txt"
    other.write_bytes(b"OTHER_EDITOR_SEED\n")
    target = subdirectory / "target.txt"
    original = b"REMOTE_FILE_MARKER\n"
    target.write_bytes(original)

    def send(*arguments, project=root):
        return subprocess.run([SENDER, "--project", str(project), *arguments],
                              capture_output=True, timeout=7, env=env)

    def unavailable(result):
        assert result.returncode == 2 and result.stderr, result

    def send_when_ready(*arguments):
        deadline = time.monotonic() + 10
        while True:
            result = send(*arguments)
            if result.returncode != 2 or time.monotonic() >= deadline:
                return result
            time.sleep(.05)

    observer = stack.enter_context(launch(env, other))
    observer.wait_for(b"OTHER_EDITOR_SEED")
    unavailable(send("src/target.txt"))

    owner = stack.enter_context(launch(env, seed, opt_in=True))
    owner.wait_for(b"SELECTED_EDITOR_SEED")
    result = send_when_ready("src/target.txt", "1", "2")
    assert result.returncode == 0, result
    owner.wait_for(b"REMOTE_FILE_MARKER")
    unavailable(send("target.txt", project=subdirectory))

    # A duplicate opt-in must fail without taking over the existing destination.
    contender = stack.enter_context(launch(env, other, opt_in=True))
    contender.wait_for(b"A main editor already owns this project")
    assert contender.process.wait(timeout=5) != 0

    # Append a line that exists only in the selected instance, then leave its tab.
    offset = len(owner.output)
    owner.keys(b"oUNSAVED_SELECTED_TEXT\x1b")
    owner.wait_for(b"UNSAVED_SELECTED_TEXT", after=offset)
    offset = len(owner.output)
    owner.keys(b" bp")
    owner.wait_for(b"SELECTED_EDITOR_SEED", after=offset)
    assert target.read_bytes() == original

    # A missing target is a C1 rejection; it must not create a file.
    rejected = send("src/absent.txt", "1", "1")
    assert rejected.returncode == 1 and rejected.stderr, rejected
    assert not (subdirectory / "absent.txt").exists()

    # Line 2 is valid only in the dirty buffer. Acknowledgement plus a redraw
    # proves we reused that buffer rather than opening a copy of the disk file.
    offset = len(owner.output)
    result = send("src/target.txt", "2", "1")
    assert result.returncode == 0, result
    owner.wait_for(b"UNSAVED_SELECTED_TEXT", after=offset)
    owner.keys(b"iPRESENT_\x1b")
    owner.wait_for(b"PRESENT_UNSAVED_SELECTED_TEXT", after=offset)
    assert target.read_bytes() == original

    owner.keys(b" Q")
    assert owner.process.wait(timeout=5) == 0
    unavailable(send("src/target.txt", "1", "1"))
    assert observer.process.poll() is None

    # Exercise signal teardown as well as normal quit. Only a fresh explicit
    # opt-in is allowed to provide a new destination after the previous exit.
    successor = stack.enter_context(launch(env, root, opt_in=True))
    result = send_when_ready("src/target.txt")
    assert result.returncode == 0, result
    successor.wait_for(b"REMOTE_FILE_MARKER")
    successor.process.terminate()
    assert successor.process.wait(timeout=5) == 1
    unavailable(send("src/target.txt"))

    # A new observer keystroke/render acts as a barrier after all sends. Neither
    # opening the target nor transferring unsaved owner text was allowed here.
    observer.keys(b"iSTILL_\x1b")
    observer.wait_for(b"STILL_OTHER_EDITOR_SEED")
    assert b"REMOTE_FILE_MARKER" not in observer.output
    assert b"UNSAVED_SELECTED_TEXT" not in observer.output
    assert target.read_bytes() == original
    print("Main editor CLI: opt-in, exclusive routing, C1 rejection, dirty reuse, quit/SIGTERM")
