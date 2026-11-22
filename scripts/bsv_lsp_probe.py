#!/usr/bin/env python3
"""Compare BSC and a real BSV LSP server on the upstream BSC AmbaAdapters example."""

import argparse
import json
import os
from pathlib import Path
from queue import Queue
import shutil
import subprocess
import tempfile
from threading import Thread


class Wire:
    def __init__(self, process, trace):
        self.process = process
        self.trace = trace
        self.responses = Queue()
        self.serial = 0
        Thread(target=self.read, daemon=True).start()

    def read(self):
        try:
            while True:
                headers = {}
                while (line := self.process.stdout.readline().strip()):
                    key, value = line.split(b":", 1)
                    headers[key.lower()] = value.strip()
                if not headers:
                    raise EOFError("server closed stdout")
                packet = json.loads(self.process.stdout.read(int(headers[b"content-length"])))
                self.log("received", packet)
                self.responses.put(packet)
        except (EOFError, ValueError, KeyError, OSError) as exc:
            self.responses.put(exc)

    def log(self, direction, packet):
        with self.trace.open("a") as out:
            print(json.dumps({direction: packet}), file=out)

    def send(self, packet):
        packet = {"jsonrpc": "2.0", **packet}
        self.log("sent", packet)
        data = json.dumps(packet).encode()
        self.process.stdin.write(f"Content-Length: {len(data)}\r\n\r\n".encode() + data)
        self.process.stdin.flush()

    def notify(self, method, params=None):
        self.send({"method": method, **({"params": params} if params is not None else {})})

    def receive(self, match):
        while True:
            packet = self.responses.get(timeout=15)
            if isinstance(packet, Exception):
                raise packet
            if match(packet):
                return packet
            if "method" in packet and "id" in packet:
                self.send({"id": packet["id"], "error": {
                    "code": -32601, "message": "Unimplemented by probe"}})

    def request(self, method, params=None):
        self.serial += 1
        self.send({"id": self.serial, "method": method,
                   **({"params": params} if params is not None else {})})
        return self.receive(lambda p: "method" not in p and p.get("id") == self.serial)


def location(text, token, *, line_contains):
    for line, contents in enumerate(text.splitlines()):
        if line_contains in contents:
            return {"line": line, "character": contents.index(token) + 1}
    raise AssertionError((token, line_contains))


def prepare_project(root, example):
    (root / "lib").mkdir()
    (root / "build").mkdir()
    path = root / "TBbaseline.bsv"
    for source in example.glob("*.bsv"):
        shutil.copyfile(source, path if source.name == path.name else root / "lib" / source.name)
    flags = ["-u", "-verilog", "-g", "sysM1_25", "-p", "+:lib",
             "-bdir", "build", "-vdir", "build", "-info-dir", "build", path.name]
    (root / "blues.toml").write_text("")
    (root / "blues_compdb.json").write_text(json.dumps([{
        "directory": ".", "arguments": ["bsc", *flags],
    }]))
    return path, flags


def probe(wire, root, main, dependency, original, variants):
    doc = {"uri": main.as_uri()}
    dep = {"uri": dependency.as_uri()}
    result = wire.request("initialize", {
        "processId": os.getpid(),
        "rootUri": root.as_uri(),
        "workspaceFolders": [{"uri": root.as_uri(), "name": root.name}],
        "capabilities": {"general": {"positionEncodings": ["utf-16", "utf-8"]}},
    })
    caps = result["result"]["capabilities"]
    wire.notify("initialized", {})
    push = "diagnosticProvider" not in caps
    observe = {}

    def open_document(document, text):
        wire.notify("textDocument/didOpen", {"textDocument": {
            **document, "languageId": "bsv", "version": 1, "text": text}})

    def diagnostics(document):
        if push:
            return wire.receive(lambda p: p.get("method") == "textDocument/publishDiagnostics"
                                and p["params"]["uri"] == document["uri"])["params"]
        return wire.request("textDocument/diagnostic", {"textDocument": document})

    def queries(text):
        def query(method, token, anchor):
            return wire.request("textDocument/" + method, {"textDocument": doc,
                "position": location(text, token, line_contains=anchor)})

        partial = "B1m2s bus <- bus_2m_2\n" in text
        completion = (wire.request("textDocument/completion", {
            "textDocument": doc, "position": {"line": 10, "character": 24},
        }) if partial else query("completion", "bus_1m_2s", "B1m2s bus <-"))
        items = completion.get("result")
        if isinstance(items, dict):
            items = items["items"]
        return {
            "local_hover": query("hover", "bus", "B1m2s bus <-"),
            "import_hover": None if partial else query("hover", "slaveSel3", "B1m2s bus <-"),
            "import_definition": None if partial else query("definition", "slaveSel3", "B1m2s bus <-"),
            "completion_labels": sorted({i["label"] for i in items}) if items is not None else completion,
        }

    open_document(doc, original)
    observe["clean_closed_dependency"] = {"diagnostics": diagnostics(doc), **queries(original)}
    open_document(dep, dependency.read_text())
    observe["clean_open_dependency"] = {
        "diagnostics": diagnostics(dep) if push else diagnostics(doc), **queries(original)}
    wire.notify("textDocument/didClose", {"textDocument": dep})
    for version, (stage, text) in enumerate([*variants.items(), ("restored", original)], 2):
        wire.notify("textDocument/didChange", {"textDocument": {**doc, "version": version},
                    "contentChanges": [{"text": text}]})
        observe[stage] = {"diagnostics": diagnostics(doc), **queries(text)}
    assert main.read_text() == original, "language server modified the saved source"
    shutdown = wire.request("shutdown")
    assert "error" not in shutdown, shutdown
    wire.notify("exit")
    return {"capabilities": caps, "observations": observe}


def check_blues(result, root):
    assert "hoverProvider" not in result["capabilities"]
    for stage, obs in result["observations"].items():
        assert {"bus_1m_2s", "bus_2m_2s", "slaveSel3", "mkADPSlave"} <= set(obs["completion_labels"]), stage
        if stage != "partial_instantiation":
            assert "bus" in obs["completion_labels"], stage
            [link] = obs["import_definition"]["result"]
            assert link["targetUri"] == (root / "lib" / "Buses.bsv").as_uri(), link
            assert link["targetSelectionRange"]["start"] == {"line": 24, "character": 17}, link
        assert obs["local_hover"]["error"]["code"] == -32601, stage
        diagnostics = obs["diagnostics"]["result"]["items"]
        assert bool(diagnostics) == (stage in {"incomplete", "partial_instantiation"}), (stage, diagnostics)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--example", required=True, type=Path,
                        help="BSC testsuite/bsc.bsv_examples/AmbaAdapters directory")
    parser.add_argument("--bsc", default="bsc")
    parser.add_argument("--expect-blues", action="store_true",
                        help="assert observations for blues-lsp 0.1.4")
    parser.add_argument("server", nargs=argparse.REMAINDER,
                        help="server command and arguments (after --)")
    args = parser.parse_args()
    server = args.server[1:] if args.server[:1] == ["--"] else args.server
    if not server or not (bsc := shutil.which(args.bsc)) or not shutil.which(server[0]):
        parser.error("provide an executable BSC and server")
    bsc = str(Path(bsc).absolute())
    server[0] = str(Path(shutil.which(server[0])).absolute())

    root = Path(tempfile.mkdtemp(prefix="cobalt-bsv-lsp-"))
    print(root, flush=True)
    path, flags = prepare_project(root, args.example)
    original = path.read_text()
    variants = {
        "incomplete": original.replace("Slave slave0 <- mkADPSlave(1) ;", "Slave slave0 <- mkADPSlave("),
        "wrong_type": original.replace("mkADPSlave(1)", 'mkADPSlave("oops")'),
        "partial_instantiation": original.replace("bus_1m_2s ( slaveSel3 ) ;", "bus_2m_2", 1),
    }
    assert all(text != original for text in variants.values())
    # BSC uses the saved text; restore it before testing unsaved overlays over LSP.
    try:
        for stage, text in {"clean": original, **variants}.items():
            if stage != "clean":
                # The compiler's recompilation timestamp can be coarser than the edits.
                (root / "build" / path.with_suffix(".bo").name).unlink(missing_ok=True)
            path.write_text(text)
            result = subprocess.run([bsc, *flags], cwd=root, timeout=30, text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
            (root / f"bsc-{stage}.txt").write_text(result.stdout)
            assert (result.returncode == 0) == (stage == "clean"), (stage, result.stdout)
    finally:
        path.write_text(original)

    env = {**os.environ, "PATH": str(Path(bsc).parent) + os.pathsep + os.environ["PATH"]}
    with (root / "server.stderr").open("w") as stderr, subprocess.Popen(
            server, cwd=root, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=stderr) as process:
        try:
            result = probe(Wire(process, root / "wire.jsonl"), root, path,
                           root / "lib" / "Buses.bsv", original, variants)
            (root / "report.json").write_text(json.dumps(result, indent=2) + "\n")
            if args.expect_blues:
                check_blues(result, root)
            process.stdin.close()
            try:
                assert process.wait(timeout=2) == 0
            except subprocess.TimeoutExpired:
                print("Server acknowledged shutdown but did not exit; killing it.", flush=True)
        finally:
            if process.poll() is None:
                process.kill()


if __name__ == "__main__":
    main()
