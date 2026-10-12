import http.client
import json
import logging
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

from fishd.server import make_server
from fishd.service import Service
from fishd.state import State

CONFIG = {
    "download_on_start": True,
    "decision": {"repo": "owner/decision", "revision": "r1"},
    "embedding": {"repo": "owner/embed", "revision": "r2"},
}

FINISH = """
import json, pathlib, sys
role, repo, revision, model_dir = sys.argv[1:5]
target = pathlib.Path(model_dir)
target.mkdir(parents=True, exist_ok=True)
print(json.dumps({"stage": "downloading", "total_bytes": 10}), flush=True)
(target / "READY").write_text(json.dumps({"repo": repo, "revision": revision, "role": role, "path": "source", "bytes": 10, "sha": "fake"}))
print(json.dumps({"stage": "ready"}), flush=True)
"""

BLOCK = """
import json, sys, time
print(json.dumps({"stage": "downloading", "total_bytes": 10}), flush=True)
time.sleep(3600)
"""


def fake_command(role, repo, revision, model_dir):
    script = BLOCK if repo.endswith("/slow") else FINISH
    return [sys.executable, "-c", script, role, repo, revision, str(model_dir)]


class FakeDecision:
    name = "decision"

    def decide(self, state, questions):
        return {"model": self.name, "answers": {field: {"type": "noul", "noul": 0.9} for field in questions}}


class FakeEmbedding:
    name = "embed"

    def embed(self, texts):
        return [[float(index + 1)] * 3 for index in range(len(texts))], len(texts)


FAKE_LOADERS = {"decision": lambda path, name: FakeDecision(), "embedding": lambda path, name: FakeEmbedding()}


def wait_until(condition, timeout=10.0):
    deadline = time.monotonic() + timeout
    while not condition():
        if time.monotonic() > deadline:
            raise AssertionError("condition did not hold within %.0fs" % timeout)
        time.sleep(0.02)


class ServerTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        (root / "config.json").write_text(json.dumps(CONFIG))
        state = State(root)
        self.key = state.api_key()
        self.service = Service(state, loaders=FAKE_LOADERS, command=fake_command)
        self.server = make_server("127.0.0.1", 0, self.service, self.key)
        self.port = self.server.server_address[1]
        self.service.origin = "http://127.0.0.1:%d" % self.port
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.stop)
        self.service.start()
        wait_until(lambda: self.health()["roles"]["embedding"]["state"] == "ready")

    def stop(self):
        self.service.shutdown()
        self.server.shutdown()
        self.server.server_close()

    def call(self, method, path, body=None, auth=True, token=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        headers = {"Content-Type": "application/json"}
        if auth:
            headers["Authorization"] = "Bearer " + (token or self.key)
        payload = None if body is None else json.dumps(body).encode()
        connection.request(method, path, body=payload, headers=headers)
        response = connection.getresponse()
        data = json.loads(response.read())
        connection.close()
        return response.status, data

    def health(self):
        return self.call("GET", "/health", auth=False)[1]

    def test_decision_requests_need_the_bearer_key(self):
        status, _ = self.call("POST", "/v1/systemone", {"state": "x", "questions": {"t": {"type": "noul"}}}, auth=False)
        self.assertEqual(status, 401)

    def test_decision_returns_answers_for_each_question(self):
        status, data = self.call("POST", "/v1/systemone", {"state": "x", "questions": {"t": {"type": "noul"}}})
        self.assertEqual(status, 200)
        self.assertEqual(data["answers"], {"t": {"type": "noul", "noul": 0.9}})

    def test_embeddings_accept_one_text_or_a_list(self):
        status, data = self.call("POST", "/v1/embeddings", {"input": ["one", "two"], "model": "embed"})
        self.assertEqual(status, 200)
        self.assertEqual([item["index"] for item in data["data"]], [0, 1])
        self.assertEqual(len(data["data"][0]["embedding"]), 3)

    def test_a_download_can_be_cancelled_and_deleted(self):
        status, started = self.call("POST", "/v1/models", {"source": "https://huggingface.co/other/slow", "role": "embedding"})
        self.assertEqual((status, started["id"]), (202, "other--slow@main"))
        wait_until(lambda: self.model("other--slow@main").get("state") == "downloading")
        status, _ = self.call("POST", "/v1/models/other--slow@main/cancel")
        self.assertEqual(status, 200)
        wait_until(lambda: self.model("other--slow@main").get("state") == "cancelled")
        status, _ = self.call("DELETE", "/v1/models/other--slow@main")
        self.assertEqual(status, 200)
        self.assertEqual(self.model("other--slow@main"), {})

    def test_the_active_model_cannot_be_deleted(self):
        status, data = self.call("DELETE", "/v1/models/owner--decision@r1")
        self.assertEqual(status, 409)
        self.assertIn("active", data["detail"])

    def test_a_lease_waits_for_the_decision_model_then_opens_the_decision_route(self):
        wait_until(lambda: self.model("owner--decision@r1").get("state") == "ready")
        request = {"schema": "patelier.lease-request/1", "product": "commission", "purpose": "classify", "ttl_s": 120, "protocol": "jev-systemone"}
        status, data = self.call("POST", "/v1/leases", request, auth=False)
        self.assertEqual((status, data["schema"], data["code"]), (503, "patelier.error/1", "decision.warming"))
        self.assertGreater(data["retry_after_s"], 0)
        wait_until(lambda: self.health()["roles"]["decision"]["loaded"])
        status, lease = self.call("POST", "/v1/leases", request, auth=False)
        self.assertEqual(status, 200)
        self.assertEqual(lease["schema"], "patelier.lease/1")
        self.assertEqual(lease["base_url"], "http://127.0.0.1:%d" % self.port)
        self.assertEqual(lease["protocol"], "jev-systemone")
        self.assertRegex(lease["lease_id"], r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
        self.assertGreaterEqual(len(lease["api_key"]), 16)
        self.assertNotEqual(lease["api_key"], self.key)
        self.assertTrue(lease["expires_at"].endswith("Z"))
        status, data = self.call("POST", "/v1/systemone", {"state": "x", "questions": {"t": {"type": "noul"}}}, token=lease["api_key"])
        self.assertEqual(status, 200)
        self.assertEqual(data["answers"], {"t": {"type": "noul", "noul": 0.9}})
        status, _ = self.call("GET", "/v1/models", token=lease["api_key"])
        self.assertEqual(status, 401)
        activity = self.health()["activity"]
        self.assertGreaterEqual(activity["decisions"], 1)
        self.assertGreaterEqual(activity["leases"], 1)

    def test_renew_keeps_the_key_and_release_revokes_it(self):
        wait_until(lambda: self.model("owner--decision@r1").get("state") == "ready")
        wait_until(lambda: self.call("POST", "/v1/leases", {"protocol": "jev-systemone"}, auth=False)[0] == 200)
        _, lease = self.call("POST", "/v1/leases", {"protocol": "jev-systemone"}, auth=False)
        status, renewed = self.call("PUT", "/v1/leases/" + lease["lease_id"], auth=False)
        self.assertEqual((status, renewed["api_key"]), (200, lease["api_key"]))
        status, _ = self.call("DELETE", "/v1/leases/" + lease["lease_id"], auth=False)
        self.assertEqual(status, 200)
        status, _ = self.call("POST", "/v1/systemone", {"state": "x", "questions": {"t": {"type": "noul"}}}, token=lease["api_key"])
        self.assertEqual(status, 401)
        status, data = self.call("PUT", "/v1/leases/" + lease["lease_id"], auth=False)
        self.assertEqual((status, data["code"]), (404, "patelier.not_found"))

    def test_each_served_decision_is_logged_with_the_key_that_opened_it(self):
        lines = []

        class Collect(logging.Handler):
            def emit(self, record):
                lines.append(record.getMessage())

        collector = Collect(level=logging.INFO)
        logger = logging.getLogger("fishd")
        previous = logger.level
        logger.setLevel(logging.INFO)
        logger.addHandler(collector)
        self.addCleanup(logger.setLevel, previous)
        self.addCleanup(logger.removeHandler, collector)
        wait_until(lambda: self.model("owner--decision@r1").get("state") == "ready")
        self.call("POST", "/v1/systemone", {"state": "x", "questions": {"t": {"type": "noul"}}})
        wait_until(lambda: "served POST /v1/systemone -> 200 (master key)" in lines)
        wait_until(lambda: self.call("POST", "/v1/leases", {"protocol": "jev-systemone"}, auth=False)[0] == 200)
        _, lease = self.call("POST", "/v1/leases", {"protocol": "jev-systemone"}, auth=False)
        self.call("POST", "/v1/systemone", {"state": "x", "questions": {"t": {"type": "noul"}}}, token=lease["api_key"])
        wait_until(lambda: "served POST /v1/systemone -> 200 (lease)" in lines)

    def test_a_lease_for_another_protocol_is_refused(self):
        status, data = self.call("POST", "/v1/leases", {"protocol": "other"}, auth=False)
        self.assertEqual((status, data["code"]), (422, "patelier.invalid"))

    def model(self, key):
        return next((item for item in self.call("GET", "/v1/models")[1]["data"] if item["id"] == key), {})


if __name__ == "__main__":
    unittest.main()
