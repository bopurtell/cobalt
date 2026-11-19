#!/usr/bin/env python3
"""Prove build-time absence without touching/moving/removing the source checkout.

Run only when the coordinating session grants Dune ownership:
  python3 scripts/smoke_no_markdown.py
The independent temporary copy contains no markdown/ subtree or existing _build.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=6)
    args = parser.parse_args()
    if not 1 <= args.jobs <= 6:
        parser.error("--jobs must be between 1 and 6")
    source = Path(__file__).resolve().parent.parent
    temporary_root = Path("/tmp/opencode")
    temporary_root.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="cobalt-without-markdown-",
                                     dir=temporary_root) as directory:
        destination = Path(directory) / "cobalt"

        def ignore(path, names):
            excluded = {".git", "_build", "dist", "__pycache__"}
            if Path(path) == source:
                excluded.add("markdown")
            return excluded.intersection(names)

        shutil.copytree(source, destination, ignore=ignore, symlinks=True)
        assert not (destination / "markdown").exists()
        env = dict(os.environ, DUNE_CACHE="disabled")
        subprocess.run(["dune", "build", f"-j{args.jobs}", "bin/cobalt.exe",
                        "bin/cobalt_no_provider.exe"], cwd=destination, env=env, check=True)
        selected = destination / "_build/default/bin/composition/provider_adapter.ml"
        assert "Cobalt_markdown" not in selected.read_text()
        for name in ("cobalt", "cobalt_no_provider"):
            subprocess.run(["python3", "bin/test_no_provider_cli.py",
                            f"_build/default/bin/{name}.exe"],
                           cwd=destination, env=env, check=True)
        print("PASS: markdown/ absent from build inputs; default executable selected stub")


if __name__ == "__main__":
    main()
