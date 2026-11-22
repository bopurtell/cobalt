"""A scripted, read-only loopback Silver peer for process-level adapter tests."""

from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from queue import Empty, Queue
import re
from threading import Event, Thread


HELLO = "/api/hello"
OPEN = "/api/v1/open-project"
SIMULATION = "/api/v1/simulation"
TIMEOUT = 5


def parse_request(source):
    """Decode the small request vocabulary (not a response parser)."""
    tokens = iter(re.findall(r'"(?:[^"\\]|\\.)*"|[()]|[^()\s"]+', source))

    def read(token):
        if token == "(":
            items = []
            for item in tokens:
                if item == ")":
                    return items
                items.append(read(item))
            raise AssertionError(f"unclosed list: {source!r}")
        assert token != ")", source
        return json.loads(token) if token.startswith('"') else token

    parsed = read(next(tokens))
    assert next(tokens, None) is None, source
    return parsed


@dataclass
class Request:
    method: str
    path: str
    headers: object
    body: str
    ready: Event = field(default_factory=Event)
    sent: Event = field(default_factory=Event)
    response: object = None

    def reply(self, body, *, status=200, headers=(), length=None, chunked=False):
        if isinstance(body, str):
            body = body.encode()
        assert not self.ready.is_set(), self
        self.response = (body, status, headers, length, chunked)
        self.ready.set()
        return self

    def disconnect(self):
        """End the HTTP connection before returning any status or payload."""
        assert not self.ready.is_set(), self
        self.ready.set()

    def wait_sent(self):
        assert self.sent.wait(TIMEOUT), f"peer did not finish {self.path}"


class _Server(ThreadingHTTPServer):
    daemon_threads = True


class _Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def do_GET(self):
        self._handle()

    def do_POST(self):
        self._handle()

    def _handle(self):
        self.close_connection = True
        self.connection.settimeout(TIMEOUT)
        size = int(self.headers.get("Content-Length", "0"))
        assert 0 <= size <= 16_384, size
        raw = self.rfile.read(size)
        request = Request(self.command, self.path, self.headers, raw.decode())
        self.server.requests.put(request)
        try:
            if not request.ready.wait(TIMEOUT) or request.response is None:
                return
            body, status, headers, length, chunked = request.response
            self.send_response(status)
            self.send_header("Content-Type", "application/sexp")
            self.send_header("Connection", "close")
            if chunked:
                self.send_header("Transfer-Encoding", "chunked")
            else:
                self.send_header("Content-Length", str(len(body) if length is None else length))
            for key, value in headers:
                self.send_header(key, value)
            self.end_headers()
            if chunked:
                for offset in range(0, len(body), 37):
                    chunk = body[offset:offset + 37]
                    self.wfile.write(f"{len(chunk):x}\r\n".encode() + chunk + b"\r\n")
                self.wfile.write(b"0\r\n\r\n")
            else:
                self.wfile.write(body)
        except OSError:
            # Old in-flight requests may be cancelled before a scripted late reply.
            pass
        finally:
            request.sent.set()


class Peer:
    def __enter__(self):
        self.server = _Server(("127.0.0.1", 0), _Handler)
        self.server.requests = Queue()
        self.thread = Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.01})
        self.thread.start()
        self.seen = []
        return self

    def __exit__(self, *_):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        for request in self.seen:
            if not request.ready.is_set():
                request.disconnect()

    @property
    def endpoint(self):
        return f"http://127.0.0.1:{self.server.server_port}"

    def expect(self, path, fields=None):
        try:
            request = self.server.requests.get(timeout=TIMEOUT)
        except Empty:
            raise AssertionError(f"peer did not receive {path}: {fields}") from None
        self.seen.append(request)
        assert request.path == path, (request, path)
        assert request.headers["Host"] == f"127.0.0.1:{self.server.server_port}", request
        if path == HELLO:
            assert (request.method, request.body) == ("GET", ""), request
        else:
            assert request.method == "POST", request
            assert request.headers.get("Content-Type") == "application/sexp", request
            assert request.headers.get("X-Workbench-Protocol") == "1", request
            pairs = parse_request(request.body)
            assert len(pairs) == len(fields) and dict(pairs) == fields, (request, fields)
        return request

    def hello(self):
        return self.expect(HELLO)

    def open(self, root, *, instance="daemon-1"):
        return self.expect(OPEN, {
            "instance_id": instance, "root": root, "environment": "Inherit_daemon",
        })

    def status(self, project, attempt=None, *, instance="daemon-1"):
        return self.expect(SIMULATION, {
            "instance_id": instance, "project": project,
            "operation": "Get" if attempt is None else ["Observe", attempt],
        })

    def assert_idle(self, duration=0.1):
        try:
            request = self.server.requests.get(timeout=duration)
        except Empty:
            return
        self.seen.append(request)
        raise AssertionError(f"unexpected request: {request}")


def hello_reply(instance="daemon-1", *, version=1, capabilities="simulation"):
    return (
        f"((application_version test)(protocol_versions ({version}))"
        f"(instance_id {instance})(capabilities ({capabilities})))"
    )


def open_reply(project, root):
    return f'(Ok ((project ((id {project})(root ((path {json.dumps(root)})))))))'


def summary(attempt, *, job="11", suite="test suite", lifecycle="Running", outcome="Unknown"):
    return (
        f"((id {attempt})(job {job})(suite {json.dumps(suite, ensure_ascii=False)})(seed 42)"
        f"(created_at 2026-01-01T00:00:00Z)(parent ())(lifecycle {lifecycle})(outcome {outcome}))"
    )


def detail(attempt, root, *, job="11", lifecycle="Running", outcome="Unknown", cases="",
           artifacts="", progress=""):
    return (
        f"((id {attempt})(job {job})(project_root {json.dumps(root)})"
        "(created_at 2026-01-01T00:00:00Z)(parent ())"
        "(captured ((selection ((suite suite)(seed 42)(cases ())(parameters ())(asic_inputs ())))"
        "(discovery_digest digest)(provider_executable fake)(provider_args ())"
        "(environment Inherit_daemon)))"
        f"(lifecycle {lifecycle})(outcome {outcome})(exit_code ())(diagnostic ())"
        f"(progress ({progress}))(cases ({cases}))(artifacts ({artifacts}))"
        "(next_sequence 1)(recent_events ()))"
    )


def snapshot(attempts=(), observed=None):
    return (
        "(Ok ((configured true)(discovery ())(discovery_digest ())(discovery_job ())"
        f"(discovery_error ())(attempts ({''.join(attempts)}))(next_before ())"
        f"(detail ({observed or ''}))(byte_page ())(history_error ())))"
    )
