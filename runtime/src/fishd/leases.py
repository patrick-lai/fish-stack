import hmac
import secrets
import threading
import time
import uuid

MIN_TTL_S = 10
MAX_TTL_S = 600
DEFAULT_TTL_S = 120


class Leases:
    """Short-lived decision keys handed to CommissionAI for CommissionAI's lease calls.

    A lease key only opens the decision route, and it stops working when the
    lease expires or is released. The master key never leaves the state folder.
    """

    def __init__(self, clock=time.time):
        self._clock = clock
        self._lock = threading.Lock()
        self._leases = {}

    def issue(self, ttl_s):
        ttl = clamp_ttl(ttl_s)
        with self._lock:
            self._prune()
            lease_id = str(uuid.uuid4())
            key = secrets.token_urlsafe(32)
            self._leases[lease_id] = {"key": key, "ttl": ttl, "expires": self._clock() + ttl}
            return lease_id, key, self._leases[lease_id]["expires"]

    def renew(self, lease_id):
        with self._lock:
            self._prune()
            lease = self._leases.get(lease_id)
            if lease is None:
                return None
            lease["expires"] = self._clock() + lease["ttl"]
            return lease["key"], lease["expires"]

    def release(self, lease_id):
        with self._lock:
            return self._leases.pop(lease_id, None) is not None

    def accepts(self, key):
        with self._lock:
            self._prune()
            return any(hmac.compare_digest(key.encode(), lease["key"].encode()) for lease in self._leases.values())

    def active(self):
        with self._lock:
            self._prune()
            return len(self._leases)

    def _prune(self):
        now = self._clock()
        for lease_id in [lease_id for lease_id, lease in self._leases.items() if lease["expires"] <= now]:
            del self._leases[lease_id]


def clamp_ttl(value):
    if value is None:
        return DEFAULT_TTL_S
    if isinstance(value, bool) or not isinstance(value, int):
        return DEFAULT_TTL_S
    return max(MIN_TTL_S, min(MAX_TTL_S, value))
