"""BSC compiler-feedback PTY test, with a fake compiler or a real BSC executable.

    python3 -B bin/test_bsc_cli.py _build/default/bin/cobalt.exe bsc
"""

import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

from test_tile_visibility_cli import command, editor_cursor

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "examples" / "hosted_editor"))
from test_hosted_editor import terminal


FAKE = r"""#!/usr/bin/env python3
import pathlib
import sys
import time

assert sys.argv[-5:] == ['-bdir', 'out', '-p', '+:libs packages', 'src/Demo.bsv'], sys.argv
assert pathlib.Path('.cobalt-bsc').is_file()
root = pathlib.Path('out')
(root / 'launched').touch()
if (root / 'delay').is_file():
    deadline = time.monotonic() + 9
    while (root / 'delay').is_file() and time.monotonic() < deadline:
        time.sleep(0.01)
    print('Error: "src/Demo.bsv", line 3, column 19: (T0004)\n  Late finding.', file=sys.stderr)
    sys.exit(1)
for file, token, column in [('libs packages/Imported.bs', 'missingThere', 13),
                             ('src/Demo.bsv', 'missingHere', 19)]:
    for i, text in enumerate(pathlib.Path(file).read_text().splitlines(), 1):
        if token in text:
            stream = sys.stdout if file.endswith('.bs') else sys.stderr
            print(f'Error: "{file}", line {i}, column {column}: (T0004)', file=stream)
            print(f"  Unbound variable `{token}'", file=stream)
            sys.exit(1)
if '-sim' in sys.argv:
    (root / 'mkDemo.ba').touch()
"""

TOP = """package Demo;
import Imported::*;
Bit#(8) topBits = missingHere;
(* synthesize *)
module mkDemo (Reg#(Bit#(8)));
  Reg#(Bit#(8)) value <- mkReg(topBits);
  method Bit#(8) _read = value;
  method Action _write(Bit#(8) next);
    value <= next;
  endmethod
endmodule
endpackage
"""
IMPORTED = """package Imported where
helperBits :: Bit 8
helperBits = missingThere
"""


def test(binary, compiler, root, env, real):
    src, libs, out = root / "src", root / "libs packages", root / "out"
    for folder in (src, libs, out):
        folder.mkdir()
    top, imported = src / "Demo.bsv", libs / "Imported.bs"
    top.write_text(TOP)
    imported.write_text(IMPORTED)
    config = root / ".cobalt-bsc"
    prog = json.dumps(compiler)
    flags = '-bdir out -p "+:libs packages" src/Demo.bsv'
    config.write_text(f'((check ({prog} -u {flags}))\n'
                      f' (build ({prog} -u -sim -g mkDemo -simdir out {flags})))\n')
    check = lambda tty: command(tty, "bsc check", "Bluespec: Check project")
    build = lambda tty: command(tty, "bsc build", "Bluespec: Build project")
    with terminal([binary, "--no-lsp", "--workspace", str(top)], env) as (tty, before):
        tty.resize(165, 34)
        tty.see("package Demo;", "No active problems")
        tty.send(b" vpj vS")
        assert not list(out.iterdir()), "opening did not need a compiler"
        tty.send(b"iDIRTY_TEST\x1b")
        tty.see("DIRTY_TESTpackage Demo;")
        check(tty)
        tty.see("BSC run #1", "Save modified buffer")
        assert not list(out.iterdir())
        assert top.read_text() == TOP, "running must never implicitly save a buffer"
        tty.send(b"u")
        check(tty)
        tty.see("BSC run #2", "Imported.bs:3:13", "T0004")
        tty.send(b" vo\r")
        tty.wait(lambda: editor_cursor(tty, "helperBits = missingThere", 13),
                 "problems Enter opens the Classic package at its zero-based column 13")
        tty.send(b"DA42\x1b")
        tty.see("helperBits = 42", "No active problems")
        assert imported.read_text() == IMPORTED
        tty.send(b" w")
        check(tty)
        tty.see("BSC run #3", "Demo.bsv:3:19", "T0004")
        tty.send(b" vo\r")
        tty.wait(lambda: editor_cursor(tty, "Bit#(8) topBits = missingHere;", 18),
                 "problems Enter opens the SystemVerilog package at column 19")
        tty.send(b"DAhelperBits;\x1b")
        tty.see("topBits = helperBits;", "No active problems")
        tty.send(b" w")
        build(tty)
        tty.see("BSC run #4", "Succeeded: 0 findings", "No active problems")
        assert (out / "mkDemo.ba").is_file()
        if not real:
            # Hold the child active while changing source. Result locations must
            # never be published, even if the edit was undone during the run.
            (out / "delay").touch()
            (out / "launched").unlink()
            check(tty)
            tty.wait((out / "launched").exists, "compiler launched in background")
            tty.send(b"iLATE_EDIT\x1b")
            tty.see("LATE_EDIT")
            tty.send(b"u")
            (out / "delay").unlink()
            tty.see("findings discarded after editor changes", "No active problems")
        config.write_text('((check (cobalt-test-missing-bsc-tool)))\n')
        check(tty)
        tty.see("Could not launch cobalt-test-missing-bsc-tool", "check PATH", "No active problems")
        config.unlink()
        check(tty)
        tty.see("No .cobalt-bsc above", "No active problems")
        tty.send(b" q")
        tty.finish(before)


if __name__ == "__main__":
    binary = str(Path(sys.argv[1]).resolve())
    real = len(sys.argv) > 2
    with tempfile.TemporaryDirectory(prefix="cobalt-bsc-") as tmp:
        root = Path(tmp)
        env = dict(os.environ, XDG_CONFIG_HOME=str(root / "config"), TERM="xterm-256color",
                   COLORTERM="truecolor", LC_ALL="C.UTF-8")
        if real:
            compiler = sys.argv[2]
            if "/" in compiler:
                compiler = str(Path(compiler).resolve())
            elif shutil.which(compiler) is None:
                raise SystemExit(f"Compiler not on PATH: {compiler}")
        else:
            fake = root / "fake compiler"
            fake.write_text(FAKE)
            fake.chmod(0o700)
            compiler = "./fake compiler"
        test(binary, compiler, root, env, real)
        print(f"PTY ({'real BSC' if real else 'fixture'}): saved-file checks, Classic and BSV jumps, successful build, missing tool")
