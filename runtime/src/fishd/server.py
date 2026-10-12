import hmac
import json
import logging
import re
import secrets
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from fishd.errors import Refused

MAX_BODY_BYTES = 2 * 1024 * 1024
BEARER = "Bearer "
_MODEL_ACTION = re.compile(r"/v1/models/([A-Za-z0-9@._-]+)(/cancel)?")
_LEASE_ACTION = re.compile(r"/v1/leases/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})")
log = logging.getLogger("fishd")


def error_envelope(refused):
    return {
        "schema": "fishstack.error/1",
        "code": refused.code,
        "class": "recoverable" if refused.status >= 500 else "permanent",
        "message": refused.detail,
        "retry_after_s": refused.retry_after,
        "correlation_id": secrets.token_hex(8),
    }


def make_server(host, port, service, api_key):
    expected = ("Bearer " + api_key).encode()

    class Handler(BaseHTTPRequestHandler):
        sent = None
        via = None

        def log_message(self, *args):
            pass

        def reply(self, status, value):
            self.sent = status
            body = json.dumps(value).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def authorized(self, leases_ok=False):
            supplied = (self.headers.get("Authorization") or "")
            if hmac.compare_digest(supplied.encode("utf-8", "surrogateescape"), expected):
                self.via = "master key"
                return True
            if leases_ok and supplied.startswith(BEARER) and service.accepts_lease(supplied[len(BEARER):]):
                self.via = "lease"
                return True
            return False

        def read_json(self):
            length = self.headers.get("Content-Length")
            if length is None:
                raise Refused(411, "request body needs a Content-Length")
            try:
                size = int(length)
            except ValueError:
                raise Refused(400, "invalid Content-Length")
            if size < 0 or size > MAX_BODY_BYTES:
                raise Refused(413, "request body too large")
            try:
                return json.loads(self.rfile.read(size))
            except ValueError:
                raise Refused(400, "request body must be valid JSON")

        def dispatch(self, method):
            if method == "GET" and self.path == "/health":
                return self.reply(200, service.health())
            # Leases are the handout CommissionAI calls. They are reached over loopback
            # only (the server binds 127.0.0.1), and the lease id is the only credential for renew and release.
            if method == "POST" and self.path == "/v1/leases":
                return self.reply(200, service.lease(self.read_json()))
            lease = _LEASE_ACTION.fullmatch(self.path)
            if lease and method == "PUT":
                return self.reply(200, service.renew_lease(lease.group(1)))
            if lease and method == "DELETE":
                service.release_lease(lease.group(1))
                return self.reply(200, {"detail": "released"})
            if method == "POST" and self.path == "/v1/systemone":
                if not self.authorized(leases_ok=True):
                    return self.reply(401, {"detail": "invalid or missing bearer token"})
                return self.reply(200, service.decide(self.read_json()))
            if not self.authorized():
                return self.reply(401, {"detail": "invalid or missing bearer token"})
            if method == "GET" and self.path == "/v1/models":
                return self.reply(200, {"data": service.models()})
            if method == "POST" and self.path == "/v1/models":
                body = self.read_json()
                if not isinstance(body, dict) or not isinstance(body.get("source"), str):
                    raise Refused(400, "request body must include a 'source' string and a 'role'")
                return self.reply(202, service.start_download(body["source"], body.get("role"), body.get("revision")))
            if method == "POST" and self.path == "/v1/embeddings":
                body = self.read_json()
                if not isinstance(body, dict):
                    raise Refused(400, "request body must be an object")
                return self.reply(200, service.embed(body))
            match = _MODEL_ACTION.fullmatch(self.path)
            if match and method == "POST" and match.group(2):
                service.cancel_download(match.group(1))
                return self.reply(200, {"detail": "cancelled"})
            if match and method == "DELETE" and not match.group(2):
                service.delete(match.group(1))
                return self.reply(200, {"detail": "deleted"})
            self.reply(404, {"detail": "not found"})

        def handle_method(self, method):
            try:
                self.dispatch(method)
            except Refused as refused:
                if refused.code:
                    self.reply(refused.status, error_envelope(refused))
                else:
                    self.reply(refused.status, {"detail": refused.detail})
            except Exception:
                log.exception("request failed: %s %s", method, self.path)
                self.reply(500, {"detail": "internal error; see the fishd log"})
            finally:
                if self.path != "/health":
                    log.info("served %s %s -> %s (%s)", method, self.path, self.sent, self.via or "no key")

        def do_GET(self):
            self.handle_method("GET")

        def do_POST(self):
            self.handle_method("POST")

        def do_PUT(self):
            self.handle_method("PUT")

        def do_DELETE(self):
            self.handle_method("DELETE")

    server = ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = True
    return server
