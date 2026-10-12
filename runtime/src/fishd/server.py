import hmac
import json
import logging
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from fishd.errors import Refused

MAX_BODY_BYTES = 2 * 1024 * 1024
_MODEL_ACTION = re.compile(r"/v1/models/([A-Za-z0-9@._-]+)(/cancel)?")
log = logging.getLogger("fishd")


def make_server(host, port, service, api_key):
    expected = ("Bearer " + api_key).encode()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def reply(self, status, value):
            body = json.dumps(value).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def authorized(self):
            supplied = (self.headers.get("Authorization") or "").encode("utf-8", "surrogateescape")
            return hmac.compare_digest(supplied, expected)

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
            if not self.authorized():
                return self.reply(401, {"detail": "invalid or missing bearer token"})
            if method == "GET" and self.path == "/v1/models":
                return self.reply(200, {"data": service.models()})
            if method == "POST" and self.path == "/v1/models":
                body = self.read_json()
                if not isinstance(body, dict) or not isinstance(body.get("source"), str):
                    raise Refused(400, "request body must include a 'source' string and a 'role'")
                return self.reply(202, service.start_download(body["source"], body.get("role"), body.get("revision")))
            if method == "POST" and self.path == "/v1/systemone":
                return self.reply(200, service.decide(self.read_json()))
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
                self.reply(refused.status, {"detail": refused.detail})
            except Exception:
                log.exception("request failed: %s %s", method, self.path)
                self.reply(500, {"detail": "internal error; see the fishd log"})

        def do_GET(self):
            self.handle_method("GET")

        def do_POST(self):
            self.handle_method("POST")

        def do_DELETE(self):
            self.handle_method("DELETE")

    server = ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = True
    return server
