#!/usr/bin/env python3
"""Exercise Cobalt with real Blues on BSC's multi-package AmbaAdapters example."""

import argparse
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import time

from bsv_lsp_probe import prepare_project


def main():
    checkout = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", nargs="?", type=Path, default=checkout / "_build/default/bin/cobalt.exe")
    parser.add_argument("--example", required=True, type=Path,
                        help="BSC testsuite/bsc.bsv_examples/AmbaAdapters directory")
    parser.add_argument("--bsc", default="bsc")
    parser.add_argument("--blues", default=os.environ.get("BLUES_LSP", "blues"))
    args = parser.parse_args()
    if not (bsc := shutil.which(args.bsc)) or not (blues := shutil.which(args.blues)):
        parser.error("requires BSC and Blues (blues-lsp 0.1.4)")
    binary = args.binary.resolve()
    if not binary.is_file() or not shutil.which("tmux"):
        parser.error("requires a built Cobalt binary and tmux")

    root = Path(tempfile.mkdtemp(prefix="cobalt-bsv-smoke-"))
    print(root, flush=True)
    path, flags = prepare_project(root, args.example)
    original = path.read_text()
    dependency = root / "lib" / "Buses.bsv"
    dependency_original = dependency.read_text()
    subprocess.run([str(Path(bsc).absolute()), *flags], cwd=root, check=True,
                   capture_output=True, timeout=30)
    tmux = ["tmux", "-S", str(root / "tmux.sock"), "-f", "/dev/null"]

    def t(*arguments):
        return subprocess.check_output([*tmux, *arguments], text=True)

    def screen():
        return t("capture-pane", "-p", "-t", "bsv")

    def wait(label, predicate):
        until = time.monotonic() + 15
        while time.monotonic() < until:
            output = screen()
            if predicate(output):
                (root / f"{label}.txt").write_text(output)
                print("ok:", label, flush=True)
                return
            time.sleep(.05)
        (root / f"{label}-failure.txt").write_text(output)
        raise AssertionError(f"{label}:\n{output}")

    def key(*keys):
        t("send-keys", "-t", "bsv", *keys)

    def send(text):
        t("send-keys", "-t", "bsv", "-l", "--", text)

    try:
        env = ["env", "LC_ALL=C.UTF-8", "TERM=tmux-256color",
               f"XDG_CONFIG_HOME={root / 'config'}",
               f"BLUES_LSP={Path(blues).absolute()}",
               f"PATH={Path(bsc).absolute().parent}{os.pathsep}{os.environ['PATH']}"]
        command = shlex.join([*env, "bash", "--norc", "--noprofile"])
        t("new-session", "-d", "-s", "bsv", "-x", "190", "-y", "48", "-c", str(root), command)
        t("set-option", "-t", "bsv", "status", "off")
        send("stty -g > before; " + shlex.join([str(binary), "--workspace", path.name])
             + "; printf '%s' $? > exit-code; stty -g > after\n")
        wait("workspace", lambda s: "B1m2s bus <-" in s)
        send(" li")
        wait("attached", lambda s: 'Server: "blues#' in s and "Status: Running" in s
             and f'Root: "{root}"' in s and "Attached documents: 1" in s)
        send(" bc")
        wait("back-to-source", lambda s: "B1m2s bus <-" in s and "Language servers (live)" not in s)

        # Complete an imported name not present in any opened document, while
        # the rest of the instantiation is incomplete and unsaved.
        send("11G016lDAbus_2m_2")
        wait("incomplete-overlay", lambda s: "B1m2s bus <- bus_2m_2 " in s and "INSERT" in s)
        key("C-n")
        wait("unsaved-completion", lambda s: any(
            "bus_2m_2s" in row and "[LSP]" in row for row in s.splitlines()))
        key("Enter", "Escape")
        wait("accepted-completion", lambda s: "B1m2s bus <- bus_2m_2s" in s)
        assert path.read_text() == original
        send("uu")
        wait("undo-completion-and-edit", lambda s: "B1m2s bus <- bus_1m_2s ( slaveSel3 ) ;" in s)

        # Exact editor cursor target, inside slaveSel3 at TBbaseline.bsv:11.
        send("11G029lgD")
        wait("closed-package-definition", lambda s: "Buses.bsv" in s and
             "function Bit#(2) slaveSel3( BusAddr addr );" in s and "25:18" in s)
        key("C-o")
        wait("jump-back", lambda s: "B1m2s bus <-" in s and "11:30" in s)

        send(" q")
        wait("quit", lambda _: (root / "after").exists())
        assert (root / "exit-code").read_text() == "0"
        assert (root / "before").read_bytes() == (root / "after").read_bytes()
        assert path.read_text() == original
        assert dependency.read_text() == dependency_original
        print("PASS: Blues attachment, unopened package jump, unsaved cross-package completion, clean quit")
    finally:
        subprocess.run([*tmux, "kill-server"], capture_output=True, check=False)


if __name__ == "__main__":
    main()
