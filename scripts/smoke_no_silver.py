#!/usr/bin/env python3
"""Build and exercise the production Cobalt CLI with silver_overview/ absent.

Run: python3 -B scripts/smoke_no_silver.py --jobs 4
Use --scratch-dir on a larger filesystem if /tmp/opencode is space-constrained.
Like smoke_no_markdown.py, this checks a fresh source copy, not an alternate
executable that bypasses production composition.
"""
import argparse
import os
from pathlib import Path
import select
import shutil
import socket
import subprocess
import sys
import tempfile
import time


def exercise(binary, scratch):
    from test_silver_cli import editor, wait

    home = scratch / "home"
    home.mkdir()
    document = scratch / "standalone.txt"
    original = b"STANDALONE_WITHOUT_SILVER\n"
    document.write_bytes(original)
    env = dict(os.environ, HOME=str(home), TERM="xterm-256color",
               COLORTERM="truecolor", LC_ALL="C.UTF-8")
    for key in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"):
        env[key] = str(home)

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        endpoint = f"http://127.0.0.1:{listener.getsockname()[1]}"
        scope = ["--silver-endpoint", endpoint, "--silver-project", str(scratch)]
        for flags in (scope, [*scope, "--silver-test-default", "FIFO/seeded"],
                      [*scope, "--silver-run", "unavailable-attempt"]):
            result = subprocess.run([binary, *flags, document], cwd=scratch, env=env,
                                    capture_output=True, timeout=10)
            if (result.returncode != 1
                    or b"Silver overview adapter unavailable in this build" not in result.stderr):
                raise AssertionError(result)

        with editor(binary, document, env, []) as ui:
            ui.see(original.rstrip())
            ui.keys(b" vS")
            ui.see(b"Silver: Overview unavailable")
            ui.keys(b"iX\x1b")
            # Escape is terminal-protocol ambiguous; let its timer flush.
            time.sleep(.2)
            ui.keys(b" w")
            wait(lambda: document.read_bytes() == b"X" + original)
            ui.keys(b" q")
            if ui.process.wait(timeout=5) != 0:
                raise AssertionError(bytes(ui.output[-5000:]))

        if select.select([listener], [], [], 0)[0]:
            raise AssertionError("the disabled composition contacted Silver")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, choices=range(1, 5), default=4)
    parser.add_argument("--scratch-dir", type=Path, default=Path("/tmp/opencode"))
    args = parser.parse_args()
    source = Path(__file__).resolve().parent.parent
    scratch_dir = args.scratch_dir.expanduser().resolve()
    if scratch_dir == source or source in scratch_dir.parents:
        parser.error("--scratch-dir must be outside the checkout")
    scratch_dir.mkdir(parents=True, exist_ok=True)

    def ignore(path, names):
        excluded = {".git", "_build", "dist", "__pycache__"}
        if Path(path) == source:
            excluded.add("silver_overview")
        return excluded.intersection(names)

    with tempfile.TemporaryDirectory(prefix="cobalt-without-silver-", dir=scratch_dir) as directory:
        scratch = Path(directory)
        destination = scratch / "cobalt"
        shutil.copytree(source, destination, ignore=ignore, symlinks=True)
        env = dict(os.environ, DUNE_BUILD_DIR="_build", DUNE_CACHE="disabled")
        subprocess.run(["dune", "build", "--root", ".", f"-j{args.jobs}", "bin/cobalt.exe"],
                       cwd=destination, env=env, check=True)
        composition = destination / "_build/default/bin/composition/silver_adapter.ml"
        stub = destination / "bin/composition/silver_adapter.disabled.ml"
        selected_lines = [line for line in composition.read_bytes().splitlines()
                          if not line.startswith(b"#")]
        if selected_lines != stub.read_bytes().splitlines():
            raise AssertionError("the default executable did not select the Silver stub")

        sys.path.insert(0, str(destination / "bin"))
        exercise(destination / "_build/default/bin/cobalt.exe", scratch)
    print("PASS: production Cobalt built without silver_overview/; rejects Silver flags, edits and saves normally")


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    main()
