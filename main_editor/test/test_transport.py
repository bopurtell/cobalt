"""Process-level C4 contract tests, independent of the editor UI."""
import hashlib
import json
import os
from pathlib import Path
import select
import socket
import stat
import struct
import subprocess
import sys
import tempfile
import time


RECEIVER, SENDER = (Path(arg).resolve() for arg in sys.argv[1:])
BASE = Path(f"/tmp/cobalt-main-v1-{os.geteuid()}")


def endpoint(root, suffix):
    return BASE / (hashlib.md5(os.fsencode(root), usedforsecurity=False).hexdigest() + suffix)


def line(process, expected):
    assert select.select([process.stdout], [], [], 5)[0], expected
    actual = process.stdout.readline().decode().rstrip("\n")
    assert actual == expected, (actual, expected)


def send(root, *args, code=0, contains=None):
    start = time.monotonic()
    p = subprocess.run(
        [SENDER, "--project", root, *args], capture_output=True, text=True, timeout=7
    )
    assert p.returncode == code, p
    if contains is not None:
        assert contains in p.stderr, p
    assert time.monotonic() - start < 7
    if code == 0:
        assert p.stdout == "Opened\n", p


def exact(sock, n):
    result = bytearray()
    while len(result) < n:
        chunk = sock.recv(n - len(result))
        assert chunk, (result, n)
        result += chunk
    return result


def raw(root):
    sock = socket.socket(socket.AF_UNIX)
    sock.settimeout(4)
    sock.connect(str(endpoint(root, ".sock")))
    return sock


def frame(message):
    body = json.dumps(message).encode()
    return struct.pack("!I", len(body)) + body


def reply(sock):
    sock.shutdown(socket.SHUT_WR)
    size, = struct.unpack("!I", exact(sock, 4))
    return json.loads(exact(sock, size))


def quick_failure(root, contains):
    p = subprocess.run([RECEIVER, root], input=b"", capture_output=True, timeout=5)
    assert p.returncode == 3 and contains.encode() in p.stderr, p


def test(dir, processes):
    def launch(root):
        p = subprocess.Popen(
            [RECEIVER, root], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, bufsize=0,
        )
        processes.append(p)
        return p

    def start(root):
        p = launch(root)
        line(p, "ready")
        return p

    def stop(p):
        p.stdin.close()
        assert p.wait(timeout=5) == 0, p.stderr.read()

    root = str(dir / "p")
    other = str(dir / "q")
    lock = endpoint(root, ".lock")
    sock = endpoint(root, ".sock")
    assert not lock.exists()
    p = subprocess.run([SENDER, "--help"], capture_output=True, timeout=5)
    assert p.returncode == 0 and b"cobalt-open --project" in p.stdout, p
    send(root, "file", code=2)
    assert not lock.exists(), "sender must not create an endpoint"

    editor = start(root)
    proof = BASE / json.loads(lock.read_text())[1] / "s"
    assert proof.stat().st_ino == sock.stat().st_ino
    assert stat.S_IMODE(BASE.stat().st_mode) == 0o700
    assert stat.S_IMODE(lock.stat().st_mode) == 0o600
    assert stat.S_IMODE(sock.stat().st_mode) == 0o600
    quick_failure(root + "/.", "already owns")
    unrelated = start(other)
    send(root + "/.", "file with space")
    line(editor, "file:file with space")
    send(root, "file", "2")
    line(editor, "location:file:2:1")
    send(root, "é界", "2", "4")
    line(editor, "location:é界:2:4")
    send(other, "separate")
    line(unrelated, "file:separate")
    send(root, "file", "0", code=2, contains="positive decimal coordinate")
    for args in [
        ("../outside", "below the project root"),
        ("missing", "test missing"),
        ("bad-position", "test bad position"),
        ("exited", "Session has exited"),
    ]:
        send(root, args[0], code=1, contains=args[1])
    send(root, "throw", code=2, contains="adapter threw")
    send(root, "x" * 33000, code=2, contains="too large")

    request = {
        "version": 1, "action": "open_location", "project_root": root,
        "relative_file": "must-not-run", "position": None,
    }
    for payload in [
        struct.pack("!I", 0x7FFF_FFFF),
        struct.pack("!I", 2) + b"??",
        struct.pack("!I", 12) + b"{}",
        frame({**request, "action": "execute_command"}),
        frame({**request, "version": 2}),
        frame(request) + frame(request),
    ]:
        with raw(root) as peer:
            peer.sendall(payload)
            assert reply(peer)[0] == "transport_error"
    with raw(root) as peer:
        peer.sendall(frame({**request, "project_root": other}))
        assert reply(peer) == ["wrong_project", root, other]
    with raw(root) as idle:
        idle.sendall(b"\x00")
        send(root, "after-malformed")
        line(editor, "file:after-malformed")
        # No half-close: the receiver still times out and writes a bounded error.
        size, = struct.unpack("!I", exact(idle, 4))
        assert json.loads(exact(idle, size))[0] == "transport_error"

    send(root, "never", code=2, contains="Timed out")
    send(root, "must-not-run", code=2, contains="busy")
    stop(editor)
    assert not sock.exists() and not proof.exists()
    send(root, "missing-destination", code=2)
    editor = start(root)
    editor.kill()
    editor.wait(timeout=5)
    assert sock.exists(), "SIGKILL must leave a stale socket for this test"
    stale_proof = BASE / json.loads(lock.read_text())[1] / "s"
    send(root, "no-auto-start", code=2)
    editor = start(root)
    assert not stale_proof.exists()
    send(root, "after-restart")
    line(editor, "file:after-restart")

    # Replacing a name by an unrelated socket must not allow stop or stale
    # recovery to unlink it, even when it has the same owner and permissions.
    sock.unlink()
    with socket.socket(socket.AF_UNIX) as foreign:
        foreign.bind(str(sock))
        foreign.listen(1)
        sock.chmod(0o600)
        identity = sock.stat().st_ino
        stop(editor)
        quick_failure(root, "cannot be verified")
        assert sock.stat().st_ino == identity
    sock.unlink()

    sock.symlink_to(lock)
    quick_failure(root, "cannot be verified")
    assert sock.is_symlink()
    sock.unlink()

    # Simultaneous startup has exactly one winner, even without a lock file.
    race = str(dir / "race")
    contenders = [launch(race), launch(race)]
    outputs = []
    for p in contenders:
        assert select.select([p.stdout], [], [], 5)[0], "simultaneous startup did not resolve"
        outputs.append(p.stdout.readline())
    assert sorted(outputs) == [b"", b"ready\n"], outputs
    stop(contenders[outputs.index(b"ready\n")])
    loser = contenders[outputs.index(b"")]
    assert loser.wait(timeout=5) == 3, loser.stderr.read()
    stop(unrelated)


with tempfile.TemporaryDirectory(prefix="cobalt-c4-") as temp:
    directory = Path(temp)
    children = []
    try:
        test(directory, children)
    finally:
        for child in children:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=5)
        for project in ("p", "q", "race"):
            root = str(directory / project)
            lock = endpoint(root, ".lock")
            # These test projects are unique to this process and all their
            # children are gone. Do not remove the shared runtime directory.
            if lock.exists():
                try:
                    proof = BASE / json.loads(lock.read_text())[1] / "s"
                except (json.JSONDecodeError, IndexError):
                    pass
                else:
                    proof.unlink(missing_ok=True)
                    if proof.parent.exists():
                        proof.parent.rmdir()
            endpoint(root, ".sock").unlink(missing_ok=True)
            lock.unlink(missing_ok=True)
