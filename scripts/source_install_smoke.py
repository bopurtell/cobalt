#!/usr/bin/env python3
"""Opt-in, real install/upgrade/removal smoke with a read-only opam switch."""

import argparse
from contextlib import chdir
import hashlib
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import time


SOURCE = Path(__file__).resolve().parents[1]
SYSTEM_PATH = "/usr/bin:/bin"


def run(argv, cwd, env, *, status=0, contains=(), timeout=120):
    argv = [str(arg) for arg in argv]
    result = subprocess.run(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, timeout=timeout)
    if (result.returncode != status or
            any(fragment not in result.stdout for fragment in contains)):
        raise AssertionError(f"{shlex.join(argv)}: expected {status}, got {result.returncode}"
                             f"\nExpected output fragments: {contains!r}\n{result.stdout}")
    return result.stdout


def isolated_env(scratch, opam_root):
    env = dict(os.environ)
    for key in tuple(env):
        if key.startswith(("OPAM", "DUNE_", "OCAML", "CAML_", "COBALT_", "XDG_")) or key in (
                "DESTDIR", "PREFIX", "TMPDIR", "TMP", "TEMP", "LD_LIBRARY_PATH", "LD_PRELOAD"):
            del env[key]
    env.update(PATH=SYSTEM_PATH, HOME=str(scratch / "home"), OPAMROOT=opam_root,
               TMPDIR=str(scratch / "tmp"), DUNE_CACHE="disabled",
               TERM="xterm-256color", COLORTERM="truecolor", LC_ALL="C.UTF-8")
    for key in ("CONFIG", "DATA", "CACHE", "STATE", "RUNTIME"):
        directory = scratch / key.lower()
        directory.mkdir(mode=0o700)
        env[f"XDG_{key}_HOME"] = str(directory)
    Path(env["HOME"]).mkdir()
    Path(env["TMPDIR"]).mkdir()
    return env


def digest(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def commands(prefix):
    paths = [prefix / "bin" / name for name in ("cobalt", "cobalt-open")]
    for path in paths:
        assert path.is_file() and not path.is_symlink() and os.access(path, os.X_OK), path
        with path.open("rb") as binary:
            assert binary.read(4) == b"\x7fELF", path
    assert not (prefix / "bin/co").exists()
    return paths


def launched(prefix, cwd, env):
    # Do not run opam exec here. Locate the installation solely via PATH.
    clean = {key: value for key, value in env.items() if not key.startswith("OPAM")}
    clean["PATH"] = f"{prefix / 'bin'}:{SYSTEM_PATH}"
    for binary, flags, marker in (
        ("cobalt", "--list-themes", "cobalt-midnight"),
        ("cobalt-open", "--help", "Usage:"),
    ):
        assert shutil.which(binary, path=clean["PATH"]) == str(prefix / "bin" / binary)
        run([binary, flags], cwd, clean, contains=(marker,))
    return clean


def edit_from_directory(prefix, project, env):
    # Use the same real PTY driver as the CLI smoke tests.
    sys.path.insert(0, str(SOURCE / "bin"))
    from test_silver_cli import editor

    directory = project / "outside-workspace"
    directory.mkdir()
    file = directory / "target.txt"
    original = b"SOURCE_INSTALL_EDIT_SENTINEL\n"
    file.write_bytes(original)
    with chdir(project), editor(prefix / "bin/cobalt", directory, env, []) as ui:
        ui.see(b"target.txt")
        ui.keys(b"\r")
        ui.see(original.rstrip())
        ui.keys(b"iX\x1b")
        # Allow the terminal parser's standalone-Escape timer to flush.
        time.sleep(.2)
        ui.keys(b" w")
        deadline = time.monotonic() + 10
        while file.read_bytes() != b"X" + original and time.monotonic() < deadline:
            time.sleep(.02)
        assert file.read_bytes() == b"X" + original, bytes(ui.output[-5000:])
        ui.keys(b" q")
        assert ui.process.wait(timeout=5) == 0, bytes(ui.output[-5000:])


def exercise(scratch, opam, opam_root, switch, jobs):
    clone = scratch / "fresh checkout"
    shutil.copytree(SOURCE, clone, symlinks=True,
                    ignore=shutil.ignore_patterns(".git", "_build", "dist", "__pycache__"))
    assert not (clone / "_build").exists()
    caller = scratch / "caller"
    caller.mkdir()
    env = isolated_env(scratch, opam_root)
    opam_bin = scratch / "opam-bin"
    opam_bin.mkdir()
    (opam_bin / "opam").symlink_to(opam)
    env["PATH"] = f"{opam_bin}:{SYSTEM_PATH}"
    script = clone / "install.sh"
    job_flag = ["--jobs", jobs]
    switch_flag = ["--switch", switch]
    selected = [opam, "exec", "--readonly", f"--switch={switch}", "--"]
    switch_prefix = Path(run([*selected, "printenv", "OPAM_SWITCH_PREFIX"], caller, env).strip())
    root = Path(opam_root)
    selections = [root / "config", switch_prefix / ".opam-switch/switch-state",
                  switch_prefix / ".opam-switch/switch-config"]
    switch_before = {file: digest(file) for file in selections if file.is_file()}

    shell_files = [Path(env["HOME"]) / name for name in (".profile", ".bashrc", ".zshrc")]
    for file in shell_files:
        file.write_text("# untouched by installer\n")
    no_tools = dict(env, PATH=str(opam_bin / "nonexistent"))
    # Help only needs cat (the fake PATH below exposes it but no opam).
    help_bin = scratch / "help-bin"
    help_bin.mkdir()
    (help_bin / "cat").symlink_to(shutil.which("cat", path=SYSTEM_PATH))
    run([script, "--help"], caller, dict(env, PATH=str(help_bin)),
        contains=("--prefix DIR", "--switch NAME", "--jobs N"))
    for invalid in ("0", "-1", "1.5", "two"):
        run([script, "--jobs", invalid], caller, no_tools, status=1, contains=("positive integer",))
    run([script, "--prefix"], caller, no_tools, status=1, contains=("requires a value",))
    run([script, "--unknown"], caller, no_tools, status=1, contains=("Unknown argument",))
    run([script], caller, no_tools, status=1, contains=("opam is required",))
    run([script, "--switch", "cobalt-smoke-no-such-switch"], caller, env, status=1,
        contains=("Cannot use opam switch", "opam switch list"))
    run([script], caller, dict(env, OPAMROOT=str(scratch / "empty-opam-root")), status=1,
        contains=("No usable opam switch selected", "--switch NAME"))
    unwritable = caller / "unwritable"
    unwritable.mkdir(mode=0o500)
    if not os.access(unwritable, os.W_OK):
        run([script, *switch_flag, "--prefix", unwritable], caller, env, status=1,
            contains=("Install destination is not writable",))
    blocked = caller / "blocked"
    blocked.write_text("not a directory")
    run([script, *switch_flag, "--prefix", "blocked/subdir"], caller, env, status=1,
        contains=("Install destination is not writable",))

    # A minimal opam-shaped fixture can omit tools without changing the real switch.
    fake_bin = scratch / "missing-tools"
    fake_bin.mkdir()
    fake_opam = fake_bin / "opam"
    fake_opam.write_text(f"""#!/bin/sh
shift 4
PATH={shlex.quote(str(fake_bin))}
export PATH
exec "$@"
""")
    fake_opam.chmod(0o755)
    for tool in ("true", "sh", "dirname"):
        (fake_bin / tool).symlink_to(shutil.which(tool, path=SYSTEM_PATH))
    run([script, *switch_flag], caller, dict(env, PATH=str(fake_bin)), status=1,
        contains=("Required build tool not found: dune", "--deps-only ."))
    (fake_bin / "dune").symlink_to(fake_bin / "true")
    compiler = fake_bin / "ocamlopt"
    compiler.write_text("#!/bin/sh\nprintf '%s' nonexistent-c12-cc\n")
    compiler.chmod(0o755)
    run([script, *switch_flag], caller, dict(env, PATH=str(fake_bin)), status=1,
        contains=("Required build tool not found: gzip",))
    (fake_bin / "gzip").symlink_to(fake_bin / "true")
    run([script, *switch_flag], caller, dict(env, PATH=str(fake_bin)), status=1,
        contains=("Install the C compiler configured in the switch: nonexistent-c12-cc",))

    default_prefix = Path(env["HOME"]) / ".local"
    # Only use opam's selected switch when it actually matches the requested
    # toolchain; otherwise exercise OPAM_SWITCH without changing the selection.
    current = subprocess.run([opam, "switch", "show", "--readonly"], cwd=caller, env=env,
                             capture_output=True, text=True)
    default_env = dict(env, COBALT_BUILD_JOBS=str(jobs))
    if current.returncode != 0 or current.stdout.strip() != switch:
        default_env["OPAM_SWITCH"] = switch
    print("Building and installing into isolated HOME…", flush=True)
    run([script], caller, default_env, contains=(str(default_prefix / "bin/cobalt"),),
        timeout=1200)
    assert not (clone / "cobalt.install").exists()
    commands(default_prefix)
    launched(default_prefix, caller, env)

    custom = caller / "custom prefix's files"
    custom_env = dict(env, COBALT_PREFIX="not this prefix", PREFIX="not this either",
                      OPAM_SWITCH="not-this-switch", OPAMSWITCH="wrong-opam-switch",
                      COBALT_BUILD_JOBS="invalid",
                      DUNE_BUILD_DIR=str(scratch / "unusable-absolute-build"),
                      DESTDIR=str(scratch / "unwanted-staging"))
    custom_args = [script, "--prefix", custom.name, *switch_flag, *job_flag]
    print("Installing and upgrading a relative custom prefix from outside the checkout…", flush=True)
    output = run(custom_args, caller, custom_env, contains=(str(custom / "bin/cobalt"),), timeout=1200)
    path_line = next(line.strip() for line in output.splitlines() if line.strip().startswith("export PATH="))
    assert run(["sh", "-c", f'{path_line}\ncommand -v cobalt'], caller, env).strip() == str(custom / "bin/cobalt")
    for unwanted in ("not this prefix", "not this either"):
        assert not (caller / unwanted).exists()
    for unwanted in ("unusable-absolute-build", "unwanted-staging"):
        assert not (scratch / unwanted).exists()
    paths = commands(custom)
    # Delete one installed artifact and confirm that a rerun reinstalls it.
    paths[1].unlink()
    run([script, *switch_flag, *job_flag], caller,
        dict(env, COBALT_PREFIX=custom.name, PREFIX="not this either"), timeout=1200,
        contains=(str(custom / "bin/cobalt"),))
    paths[1].unlink()
    run([script, *job_flag], caller, dict(env, PREFIX=custom.name, OPAM_SWITCH=switch),
        timeout=1200, contains=(str(custom / "bin/cobalt"),))
    commands(custom)
    assert not (caller / "not this either").exists()
    launched(custom, caller, env)

    installed_files = [path for path in custom.rglob("*") if path.is_file()]
    good = {path: (digest(path), path.stat().st_mtime_ns) for path in installed_files}
    # Force a real compile failure in the private copy only.
    entry = clone / "bin/cobalt.ml"
    original = entry.read_bytes()
    entry.write_bytes(original + b"\nlet = intentional_c12_build_failure\n")
    try:
        run(custom_args, caller, custom_env, status=1, timeout=1200,
            contains=("Syntax error", "--deps-only .", "previous installation has not been changed"))
    finally:
        entry.write_bytes(original)
    assert {path: (digest(path), path.stat().st_mtime_ns) for path in installed_files} == good

    consumer = scratch / "consumer"
    shutil.copytree(clone / "examples/hosted_consumer", consumer,
                    ignore=shutil.ignore_patterns("_build"))
    consumer_dune = consumer / "dune"
    consumer_dune.write_text(consumer_dune.read_text().replace("cobalt.hosted", "cobalt.hosted cobalt.terminal"))

    # Hide the checkout and deny traversal of its build directory before
    # running the binaries or building the independent consumer.
    parked = clone.rename(scratch / "hidden-checkout")
    build_dir = parked / "_build"
    build_mode = build_dir.stat().st_mode & 0o777
    try:
        build_dir.chmod(0)
        clean_env = launched(custom, caller, env)
        edit_from_directory(custom, caller, clean_env)
        print("Linking a separate consumer against installed public libraries…", flush=True)
        project = scratch / "consumer-project"
        (project / "src").mkdir(parents=True)
        (project / "src/first.txt").write_text("first file\n")
        (project / "second.txt").write_text("second file\né界x\n")
        run([*selected, "dune", "exec", "--root", ".", "-j", jobs, "./smoke.exe", "--", project],
            consumer, dict(env, OCAMLPATH=str(custom / "lib")), timeout=300,
            contains=("external C1/C2 smoke passed",))
    finally:
        build_dir.chmod(build_mode)
        parked.rename(clone)

    unrelated = custom / "bin/unrelated"
    unrelated.write_text("leave this in the shared prefix\n")
    config = Path(env["XDG_CONFIG_HOME"]) / "cobalt/config.ml"
    config.parent.mkdir(exist_ok=True)
    config.write_text("(* keep editor config *)\n")
    run([*selected, "dune", "uninstall", "--root", ".", "--build-dir", "_build", "--profile",
         "release", "--pkg=disabled", "-j", jobs, "--prefix", custom, "cobalt"],
        clone, env, timeout=300)
    for path in paths:
        assert not path.exists(), path
    # Dune can leave empty directories when removing nested private interfaces.
    leftovers = [path for path in (custom / "lib/cobalt").rglob("*")
                 if path.is_symlink() or not path.is_dir()]
    assert not leftovers, leftovers
    assert unrelated.read_text() == "leave this in the shared prefix\n"
    assert config.read_text() == "(* keep editor config *)\n"
    assert all(file.read_text() == "# untouched by installer\n" for file in shell_files)
    assert {file: digest(file) for file in switch_before} == switch_before


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--switch", default=os.environ.get("OPAM_SWITCH") or "5.2.0+ox")
    parser.add_argument("--jobs", type=int, default=4, choices=range(1, 5))
    parser.add_argument("--scratch-dir", type=Path, default=Path("/tmp/opencode"))
    args = parser.parse_args()
    scratch_dir = args.scratch_dir.expanduser().resolve()
    if scratch_dir == SOURCE or SOURCE in scratch_dir.parents:
        parser.error("--scratch-dir must be outside the checkout")
    opam = shutil.which("opam")
    if not opam:
        parser.error("opam is required")
    switch = args.switch
    if switch in (".", "..") or "/" in switch:
        switch = str(Path(switch).resolve())
    opam_root = str(Path(os.environ.get("OPAMROOT") or "~/.opam").expanduser().resolve())
    scratch_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="cobalt-source-install-", dir=scratch_dir) as directory:
        exercise(Path(directory), Path(opam).resolve(), opam_root, switch, args.jobs)
    print("PASS: isolated native source install, upgrade, PTY edit, external consumer, failure paths and uninstall")


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    main()
