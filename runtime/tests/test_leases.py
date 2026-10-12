import json
import os
import tempfile
import unittest
from pathlib import Path

from fishd import discovery
from fishd.leases import DEFAULT_TTL_S, MAX_TTL_S, MIN_TTL_S, Leases


class FakeClock:
    def __init__(self):
        self.now = 1_000_000.0

    def __call__(self):
        return self.now


class LeaseStoreTests(unittest.TestCase):
    def setUp(self):
        self.clock = FakeClock()
        self.leases = Leases(clock=self.clock)

    def test_ttl_is_clamped_and_defaults_when_missing(self):
        self.assertEqual(self.leases.issue(None)[2] - self.clock.now, DEFAULT_TTL_S)
        self.assertEqual(self.leases.issue(1)[2] - self.clock.now, MIN_TTL_S)
        self.assertEqual(self.leases.issue(10**6)[2] - self.clock.now, MAX_TTL_S)
        self.assertEqual(self.leases.issue("soon")[2] - self.clock.now, DEFAULT_TTL_S)

    def test_a_key_stops_working_when_its_lease_expires(self):
        _, key, expires = self.leases.issue(30)
        self.assertTrue(self.leases.accepts(key))
        self.clock.now = expires
        self.assertFalse(self.leases.accepts(key))

    def test_renew_extends_the_lease_without_changing_its_key(self):
        lease_id, key, expires = self.leases.issue(30)
        self.clock.now += 20
        renewed_key, renewed_expires = self.leases.renew(lease_id)
        self.assertEqual(renewed_key, key)
        self.assertEqual(renewed_expires, self.clock.now + 30)
        self.clock.now = expires + 5
        self.assertTrue(self.leases.accepts(key))

    def test_release_revokes_once(self):
        lease_id, key, _ = self.leases.issue(30)
        self.assertTrue(self.leases.release(lease_id))
        self.assertFalse(self.leases.accepts(key))
        self.assertFalse(self.leases.release(lease_id))
        self.assertIsNone(self.leases.renew(lease_id))

    def test_unknown_keys_are_refused(self):
        self.leases.issue(30)
        self.assertFalse(self.leases.accepts("not-a-lease-key"))
        self.assertFalse(self.leases.accepts(""))


class DiscoveryTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name) / "fishStack"

    def test_publish_writes_the_record_commission_reads(self):
        discovery.publish(self.root, 4242, 8089)
        record = json.loads((self.root / "run" / "daemon.json").read_text())
        self.assertEqual(record, {"pid": 4242, "port": 8089})

    def test_withdraw_removes_only_this_process_record(self):
        discovery.publish(self.root, 4242, 8089)
        discovery.withdraw(self.root, 9999)
        self.assertTrue((self.root / "run" / "daemon.json").exists())
        discovery.withdraw(self.root, 4242)
        self.assertFalse((self.root / "run" / "daemon.json").exists())

    def test_withdraw_tolerates_a_missing_or_broken_record(self):
        discovery.withdraw(self.root, 1)
        (self.root / "run").mkdir(parents=True)
        (self.root / "run" / "daemon.json").write_text("{not json")
        discovery.withdraw(self.root, 1)
        self.assertTrue((self.root / "run" / "daemon.json").exists())

    def test_home_prefers_the_argument_then_the_environment(self):
        previous = os.environ.get("FISH_STACK_HOME")
        self.addCleanup(lambda: os.environ.pop("FISH_STACK_HOME", None) if previous is None else os.environ.__setitem__("FISH_STACK_HOME", previous))
        os.environ["FISH_STACK_HOME"] = "/tmp/from-env"
        self.assertEqual(discovery.home(), Path("/tmp/from-env"))
        self.assertEqual(discovery.home("/tmp/from-arg"), Path("/tmp/from-arg"))
        os.environ.pop("FISH_STACK_HOME")
        self.assertEqual(discovery.home(), Path.home() / ".fishStack")


if __name__ == "__main__":
    unittest.main()
