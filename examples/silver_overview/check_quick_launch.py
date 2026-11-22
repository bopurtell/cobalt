#!/usr/bin/env python3
"""Capture the C6 slice-1 test catalog and quick-launch exchange from real Silver."""
import argparse
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace

from check_live import discover_project, one, open_project, palette, private_fixture, require, until


def assert_launch(selection):
    require(dict(selection) == {
        "suite": "FIFO", "cases": ["seeded"], "seed": "42",
        "parameters": [["n", "50"]], "asic_inputs": [],
    }, f"Unexpected quick-launch selection: {selection!r}")


def wire_only(fixture):
    silver = fixture.silver
    open_project(silver, fixture.project)
    require(silver.instance == fixture.daemon_info["instance_id"], "Daemon identity changed")
    catalog = discover_project(silver, automatic=True, catalog_label="catalog")
    require(catalog["attempts"] == [], "Project must begin without an attempt")
    discovery = dict(one(catalog["discovery"], "catalog"))
    suite = dict(one(discovery["suites"], "suite"))
    require(suite["id"] == "FIFO" and [dict(case)["id"] for case in suite["cases"]]
            == ["seeded", "smoke"], f"Unexpected catalog: {suite!r}")
    launch = silver.simulation([
        "Launch", ("submission_key", "c6-live"),
        ("discovery_digest", one(catalog["discovery_digest"], "discovery digest")),
        ("selection", [("suite", "FIFO"), ("cases", ["seeded"]), ("seed", "42"),
                       ("parameters", [("n", "50")]), ("asic_inputs", [])]),
    ], label="launch")
    detail = dict(one(launch["detail"], "launch acknowledgement"))
    assert_launch(dict(detail["captured"])["selection"])
    attempt = detail["id"]
    observed = until("quick launch completion", lambda: silver.simulation(["Observe", attempt]),
                     lambda snap: dict(one(snap["detail"], "observed attempt"))["lifecycle"]
                     not in ("Queued", "Running"))
    require(dict(one(observed["detail"], "finished attempt"))["outcome"] == "Passed",
            f"Quick launch failed: {observed!r}")
    calls = [json.loads(line) for line in fixture.calls.read_text().splitlines()]
    require([call["operation"] for call in calls] == ["discover", "run"],
            f"Expected one discovery and one launch: {calls!r}")
    assert_launch(dict(calls[1]["request"])["selection"])
    return {"acceptance": "wire-only", "attempts": [attempt]}


def cobalt_launch(args, fixture, evidence):
    from support.terminal import Terminal

    silver, project = fixture.silver, fixture.project
    open_project(silver, project)
    require(silver.simulation("Get")["attempts"] == [], "Expected no prior attempts")

    def open_pty(name, argv):
        directory = evidence / name
        directory.mkdir()
        terminal = Terminal(SimpleNamespace(evidence=directory, env=fixture.env),
                            argv=argv, cwd=project, width=420, height=52)
        fixture.stack.callback(terminal.close)
        return terminal

    cobalt = open_pty("cobalt-quick-launch", [
        str(args.cobalt), "--no-lsp", "--silver-endpoint", silver.endpoint,
        "--silver-project", str(project), str(project / "fixture.txt"),
    ])

    def send(*keys, allow_exit=False):
        for key in keys:
            os.write(cobalt.master, key)
            cobalt.drain(.12, allow_exit=allow_exit)

    cobalt.capture("catalog", ["Silver: Overview", "FIFO", "seeded", "smoke"])
    testing = None
    if args.silver_client is not None:
        testing = open_pty("silver-testing", [str(args.silver_client), "--connect",
                           silver.endpoint, "--project-root", str(project)])
        testing.capture("overview", ["Overview", "Testing"])
        palette(testing, "Strings (global): Show full identifiers")
        palette(testing, "Switch to Testing")
        testing.capture("catalog", ["[2 Testing]", "simulation-attempts", "FIFO"])
    send(b" vU", b"j", b"\r")
    cobalt.capture("edit-settings", ["Test settings", "FIFO / seeded", "Seed"])
    send(b"\t")
    cobalt.capture("parameter-before", ["n (2/2)", "10"])
    send(b"\x15", b"50", b"\r")
    cobalt.capture("applied", ["Silver: Overview", "seeded", "Saved test settings"],
                   absent=["╭─ Test settings"])
    require(silver.simulation("Get")["attempts"] == [], "Apply started a simulation")
    send(b"R")
    cobalt.capture("first-result", ["Accepted", "FIFO", "n=50"])
    first = dict(one(silver.simulation("Get")["attempts"], "tile-launched attempt"))["id"]
    send(b"\r")
    cobalt.capture("focus-after-launch", ["Test settings", "FIFO / seeded"])
    send(b"\x1b", b"\x1b", b" vS")
    cobalt.capture("tile-hidden", ["c6 fixture editor"], absent=["╭─ Silver: Overview"])
    send(b" cc", b"test")
    cobalt.capture("exact-test", ["Run test", "FIFO / seeded", "n=50"])
    send(b"\r")
    attempts = until("hidden palette launch", lambda: silver.simulation("Get")["attempts"],
                     lambda attempts: len(attempts) == 2)
    ids = [dict(item)["id"] for item in attempts]
    require(len(set(ids)) == 2 and first in ids, f"Expected two distinct attempts: {ids!r}")
    second = one([id_ for id_ in ids if id_ != first], "palette-launched attempt")
    send(b" vM", b" st")
    cobalt.capture("second-result", ["Accepted", second], absent=["╭─ Silver: Overview"])
    send(b" sb", b"\x1b", b" q", allow_exit=True)
    require(cobalt.process.wait(timeout=10) == 0, "Cobalt did not exit cleanly")

    for name, attempt in (("tile", first), ("palette", second)):
        observed = until(f"{name} launch completion", lambda: silver.simulation(["Observe", attempt],
                         label=f"observe-{name}"), lambda snap: dict(one(snap["detail"], "attempt"))
                         ["lifecycle"] not in ("Queued", "Running"))
        detail = dict(one(observed["detail"], "finished attempt"))
        assert_launch(dict(detail["captured"])["selection"])
        require(detail["outcome"] == "Passed", f"{name} launch failed: {detail!r}")
    calls = [json.loads(line) for line in fixture.calls.read_text().splitlines()]
    require([call["operation"] for call in calls] == ["discover", "run", "run"],
            f"Expected one discovery and two launches: {calls!r}")
    for call in calls[1:]:
        assert_launch(dict(call["request"])["selection"])
    if testing is not None:
        testing.capture("attempts", ["[2 Testing]", "simulation-attempts", first, second])
    return {"acceptance": "two-windows" if args.silver_client else "cobalt-and-daemon",
            "attempts": [first, second]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--silver-checkout", type=Path, required=True)
    parser.add_argument("--daemon", type=Path, required=True)
    parser.add_argument("--cobalt", type=Path, help="exercise real Cobalt keys instead of wire-only")
    parser.add_argument("--silver-client", type=Path, help="also verify Silver Testing shows both attempts")
    args = parser.parse_args()
    if args.silver_client and not args.cobalt:
        parser.error("--silver-client requires --cobalt")
    for name in ("silver_checkout", "daemon", "cobalt", "silver_client"):
        if (path := getattr(args, name)) is not None:
            setattr(args, name, path.resolve(strict=True))
    base = Path("/tmp/opencode")
    base.mkdir(exist_ok=True)
    evidence = Path(tempfile.mkdtemp(prefix="c6-live-", dir=base))
    print(f"Private C6 evidence: {evidence}", flush=True)
    with private_fixture(args, evidence, quick_launch=True) as fixture:
        result = cobalt_launch(args, fixture, evidence) if args.cobalt else wire_only(fixture)
    output = json.dumps(result, indent=2) + "\n"
    (evidence / "result.json").write_text(output)
    print(output, end="")


if __name__ == "__main__":
    main()
