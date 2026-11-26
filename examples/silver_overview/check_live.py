#!/usr/bin/env python3
"""C5 acceptance with a private Silver daemon and independent Silver/Cobalt PTYs."""

import argparse
from contextlib import ExitStack, contextmanager
import http.client
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
from urllib.parse import urlsplit


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def until(description, action, predicate, timeout=20):
    deadline = time.monotonic() + timeout
    while True:
        value = action()
        if predicate(value):
            return value
        require(time.monotonic() < deadline, f"Timed out: {description}: {value!r}")
        time.sleep(0.05)


def reap(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


class Silver:
    def __init__(self, endpoint, codec, evidence):
        uri = urlsplit(endpoint)
        require(uri.scheme == "http" and uri.hostname == "127.0.0.1" and uri.port
                and endpoint == f"http://127.0.0.1:{uri.port}",
                f"Expected the private loopback endpoint, got {endpoint!r}")
        self.endpoint, self.port = endpoint, uri.port
        self.codec, self.evidence = codec, evidence

    def request(self, path, value=None, *, label=None):
        method = "GET" if value is None else "POST"
        headers = {"Host": f"127.0.0.1:{self.port}", "Connection": "close"}
        body = b""
        if value is not None:
            body = self.codec.sexp(value).encode("ascii")
            headers.update({
                "Content-Type": "application/sexp",
                "X-Workbench-Protocol": "1",
                "Content-Length": str(len(body)),
            })
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            connection.putrequest(method, path, skip_host=True, skip_accept_encoding=True)
            for key, val in headers.items():
                connection.putheader(key, val)
            connection.endheaders(body)
            response = connection.getresponse()
            raw = response.read()
            status = response.status
            response_headers = response.getheaders()
            if label is not None:
                (self.evidence / f"{label}.json").write_text(json.dumps({
                    "request": {"method": method, "target": path, "headers": headers,
                                "body": body.decode("utf-8")},
                    "response": {"status": status, "reason": response.reason,
                                 "headers": response_headers, "body": raw.decode("utf-8")},
                }, indent=2) + "\n")
        finally:
            connection.close()
        require(status == 200, f"{method} {path}: HTTP {status}: {raw!r}")
        require(response.getheader("Content-Type") == "application/sexp",
                f"{method} {path}: unexpected Content-Type")
        return self.codec.parse(raw.decode("utf-8"))

    def simulation(self, operation, *, label=None, error=None):
        result = self.request("/api/v1/simulation", [
            ("instance_id", self.instance), ("project", self.project), ("operation", operation),
        ], label=label)
        if error:
            require(len(result) == 2 and result[0] == "Error" and dict(result[1])["kind"] == error,
                    f"Expected {error} for {operation!r}: {result!r}")
        else:
            require(len(result) == 2 and result[0] == "Ok", f"{operation!r}: {result!r}")
        return dict(result[1])


def one(values, description):
    require(len(values) == 1, f"Expected one {description}, got: {values!r}")
    return values[0]


def open_project(silver, project):
    hello = dict(silver.request("/api/hello", label="hello"))
    require("1" in hello["protocol_versions"] and "simulation" in hello["capabilities"],
            f"Silver v1 simulation capability missing: {hello!r}")
    silver.instance = hello["instance_id"]
    opened = silver.request("/api/v1/open-project", [
        ("instance_id", silver.instance), ("root", project), ("environment", "Inherit_daemon"),
    ], label="open-project")
    require(len(opened) == 2 and opened[0] == "Ok", f"Open project: {opened!r}")
    resolved_project = dict(dict(opened[1])["project"])
    require(dict(resolved_project["root"])["path"] == str(project.resolve()),
            "Silver opened a different project")
    silver.project = resolved_project["id"]


def discover_project(silver, *, automatic=False, catalog_label=None):
    silver.simulation("Ensure_discovered" if automatic else "Discover")
    discovery = until("fixture discovery", lambda: silver.simulation("Get"),
                      lambda snap: snap["discovery_digest"] or snap["discovery_error"])
    require(not discovery["discovery_error"], f"Discovery failed: {discovery!r}")
    return silver.simulation("Get", label=catalog_label) if catalog_label else discovery


def setup_fixture(silver, project):
    open_project(silver, project)
    # Bootstrap only. Neither window gets a launch command.
    discovery = discover_project(silver)
    launched = silver.simulation([
        "Launch", ("submission_key", "c5-live"), ("discovery_digest", one(
            discovery["discovery_digest"], "discovery digest")),
        ("selection", [("suite", "fixture"), ("cases", ["first"]), ("seed", "42"),
                       ("parameters", []), ("asic_inputs", [])]),
    ])
    attempt = dict(one(launched["detail"], "launched attempt"))["id"]
    until("fixture completion", lambda: silver.simulation(["Observe", attempt]),
          lambda snap: dict(one(snap["detail"], "observed attempt"))["lifecycle"]
          not in ("Queued", "Running"))
    return attempt


def compare_wire(silver, attempt, project):
    get = silver.simulation("Get", label="get")
    observed = silver.simulation(["Observe", attempt], label="observe")
    require(get["detail"] == [], f"Get unexpectedly selected an attempt: {get!r}")
    summary = dict(one(get["attempts"], "summary"))
    detail = dict(one(observed["detail"], "observed attempt"))
    selection = dict(dict(detail["captured"])["selection"])
    expected = {"id": attempt, "lifecycle": "Finished", "outcome": "Passed"}
    for key, expected_value in expected.items():
        require(summary[key] == expected_value and detail[key] == expected_value,
                f"Get vs Observe {key}: {summary[key]!r} vs {detail[key]!r}")
    require(summary["job"] == detail["job"] and detail["project_root"] == str(project.resolve()),
            "Silver disagrees on job or fixture root")
    for key in ("suite", "seed"):
        require(summary[key] == selection[key], f"Get vs Observe selection {key}")
    require(selection["suite"] == "fixture" and selection["seed"] == "42"
            and [(dict(case)["case_id"], dict(case)["status"]) for case in detail["cases"]]
            == [("first", "Passed")], "Unexpected fixture selection or case result")
    silver.simulation(["Observe", "unallocated-c5-attempt"], label="observe-not-found",
                      error="Not_found")
    return expected | {"suite": summary["suite"], "seed": summary["seed"]}


def palette(terminal, title):
    for key in (b" ", b"c", b"c"):
        os.write(terminal.master, key)
        terminal.drain(0.12)
    os.write(terminal.master, title.encode())
    terminal.capture(f"palette-{time.time_ns()}", ["COMMAND PALETTE", title])
    os.write(terminal.master, b"\r")


def compare_windows(args, terminal_class, evidence, env, silver, project, status, stack):
    def open_pty(name, argv, *, width=180):
        out = evidence / name
        out.mkdir()
        terminal = terminal_class(SimpleNamespace(evidence=out, env=env), argv=argv,
                                  cwd=project, width=width, height=52)
        stack.callback(terminal.close)
        return terminal

    testing = open_pty("silver-testing", [str(args.silver_client), "--connect", silver.endpoint,
                                        "--project-root", str(project)], width=300)
    testing.capture("overview", ["Overview", "Testing"])
    palette(testing, "Strings (global): Show full identifiers")
    palette(testing, "Switch to Testing")
    testing_status = ["[2 Testing]", "simulation-attempts", "simulation-detail",
                      "Suite: " + status["suite"],
                      f"{status['outcome']} / {status['lifecycle']}",
                      re.compile(r"│\s*Attempt: " + re.escape(status["id"]) + r"\s*│")]
    testing.capture("attempt", testing_status)

    cobalt = open_pty("cobalt-overview", [
        str(args.cobalt), "--no-lsp", "--silver-endpoint", silver.endpoint,
        "--silver-project", str(project), "--silver-run", status["id"],
        str(project / "fixture.txt"),
    ], width=300)
    def field(key, value):
        return re.compile(re.escape(key) + r": +" + re.escape(value))

    cobalt_status = ["Silver: Overview", field("Status", "Fresh"), field("Attempt", status["id"]),
                     field("Lifecycle", status["lifecycle"]), field("Outcome", status["outcome"]),
                     field("Suite", status["suite"])]
    cobalt.capture("attempt", cobalt_status)
    testing.capture("while-cobalt-open", testing_status)

    for _ in range(12):
        footer = testing.drain(0.12).splitlines()[-1]
        if "Testing › execution" in footer:
            break
        os.write(testing.master, b"\t")
    else:
        raise RuntimeError("Could not focus the Silver Testing execution pane")
    # Silver's zoom must not change the bound attempt shown in Cobalt.
    palette(testing, "Zoom focused tile")
    testing.capture("zoomed", ["Testing |", "Testing › execution"],
                    absent=["simulation-catalog"])
    cobalt.capture("while-silver-zoomed", cobalt_status)
    palette(testing, "Unzoom workspace")
    testing.capture("unzoomed", testing_status)

    for key in (b" ", b"v", b"S"):
        os.write(cobalt.master, key)
        cobalt.drain(0.12)
    cobalt.capture("tile-closed", ["c5 fixture editor", "Silver: Overview hidden"],
                   absent=["╭─ Silver: Overview", field("Status", "Fresh")])
    testing.capture("while-cobalt-tile-closed", testing_status)

    for key in (b" ", b"v", b"S"):
        os.write(cobalt.master, key)
        cobalt.drain(0.12)
    cobalt.capture("tile-reopened", cobalt_status)
    for key in (b" ", b"q"):
        os.write(cobalt.master, key)
        cobalt.drain(0.12, allow_exit=True)
    require(cobalt.process.wait(timeout=10) == 0, "Cobalt quit did not exit cleanly")
    testing.capture("after-cobalt-quit", testing_status)


@contextmanager
def private_fixture(args, evidence, *, quick_launch=False):
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(args.silver_checkout / "scripts" / "fixtures"))
    sys.path.insert(0, str(args.silver_checkout / "test"))
    import simulation_fixture_wire as codec
    project = evidence / "project with spaces"
    project.mkdir()
    label = "c6" if quick_launch else "c5"
    (project / "dune-project").write_text(f"(lang dune 3.22)\n(name {label}_live_fixture)\n")
    (project / "fixture.txt").write_text(f"{label} fixture editor\n")
    control, calls = evidence / "control.json", evidence / "provider-calls.jsonl"
    control.write_text('{"mode":"pass"}\n')
    fixture_dir = args.silver_checkout / "scripts" / "fixtures"
    provider = evidence / "simulation_fault_provider.py"
    shutil.copyfile(fixture_dir / provider.name, provider)
    shutil.copyfile(fixture_dir / "simulation_fixture_wire.py",
                    evidence / "simulation_fixture_wire.py")
    if quick_launch:
        provider = evidence / "quick_launch_provider.py"
        shutil.copyfile(Path(__file__).with_name(provider.name), provider)
    (project / "silver-simulation.sexp").write_text(codec.sexp([
        ("schema_version", 1), ("provider_executable", sys.executable),
        ("provider_args", [provider, "--control", control, "--calls", calls]),
        ("discovery_timeout_seconds", 10), ("run_timeout_seconds", 20),
    ]) + "\n")
    env = dict(os.environ)
    for key in ("HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME",
                "XDG_RUNTIME_DIR", "TMPDIR"):
        directory = evidence / key.lower()
        directory.mkdir(mode=0o700)
        env[key] = str(directory)
    env.update(TERM="xterm-256color", PYTHONDONTWRITEBYTECODE="1")
    discovery, state = evidence / "discovery", evidence / "daemon-state"
    discovery.mkdir()
    state.mkdir()
    metadata = discovery / "daemon.sexp"
    with ExitStack() as stack:
        log = stack.enter_context((evidence / "daemon.log").open("wb"))
        daemon = subprocess.Popen([
            str(args.daemon), "--port", "0", "--discovery-dir", str(discovery),
            "--state-dir", str(state),
        ], cwd=project, env=env, stdout=log, stderr=subprocess.STDOUT)
        stack.callback(reap, daemon)

        def daemon_metadata():
            require(daemon.poll() is None, f"Silver daemon exited; see {log.name}")
            return metadata.read_text() if metadata.exists() else None

        daemon_info = dict(codec.parse(until("private daemon metadata", daemon_metadata, bool)))
        silver = Silver(daemon_info["endpoint"], codec, evidence)
        yield SimpleNamespace(silver=silver, project=project, env=env, calls=calls,
                              daemon_info=daemon_info, stack=stack)


def run(args, evidence):
    with private_fixture(args, evidence) as fixture:
        from support.terminal import Terminal

        silver, project, calls = fixture.silver, fixture.project, fixture.calls
        attempt = setup_fixture(silver, project)
        require(silver.instance == fixture.daemon_info["instance_id"], "Daemon identity changed")
        status = compare_wire(silver, attempt, project)
        before = calls.read_bytes()
        require([json.loads(line)["operation"] for line in before.splitlines()]
                == ["discover", "run"], "Exactly one fixture discovery and one launch expected")
        if not args.wire_only:
            compare_windows(args, Terminal, evidence, fixture.env, silver, project, status,
                            fixture.stack)
        final = silver.simulation(["Observe", attempt], label="after")
        detail = dict(one(final["detail"], "attempt after observation"))
        require([dict(item)["id"] for item in final["attempts"]] == [attempt]
                and all(detail[key] == status[key] for key in ("id", "lifecycle", "outcome"))
                and calls.read_bytes() == before, "Observation changed the private fixture")
        (evidence / "result.json").write_text(json.dumps(
            {"acceptance": "wire-only" if args.wire_only else "two-windows", **status},
            indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--silver-checkout", type=Path, required=True)
    parser.add_argument("--daemon", type=Path, required=True)
    parser.add_argument("--silver-client", type=Path)
    parser.add_argument("--cobalt", type=Path)
    parser.add_argument("--wire-only", action="store_true",
                        help="record real HTTP traffic only; does not pass two-window acceptance")
    args = parser.parse_args()
    if not args.wire_only and (args.silver_client is None or args.cobalt is None):
        parser.error("--silver-client and --cobalt are required unless --wire-only is explicit")
    for name in ("silver_checkout", "daemon", "silver_client", "cobalt"):
        value = getattr(args, name)
        if value is not None:
            setattr(args, name, value.resolve(strict=True))
    base = Path("/tmp/opencode")
    base.mkdir(exist_ok=True)
    evidence = Path(tempfile.mkdtemp(prefix="c5-live-", dir=base))
    print(f"Private C5 evidence: {evidence}", flush=True)
    run(args, evidence)
    print((evidence / "result.json").read_text(), end="")


if __name__ == "__main__":
    main()
