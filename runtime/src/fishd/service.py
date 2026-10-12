import copy
import logging
import shutil
import threading
from datetime import datetime, timezone

from fishd import PROTOCOL, VERSION
from fishd.catalog import DEFAULT_CONFIG, ROLES
from fishd.decision import load_decision_engine, parse_request
from fishd.embedding import load_embedding_engine
from fishd.errors import Refused
from fishd.hf import model_key, parse_source
from fishd.jobs import ACTIVE_STATES, Jobs, worker_command
from fishd.leases import Leases
from fishd.state import config_key

LOADERS = {"decision": load_decision_engine, "embedding": load_embedding_engine}
LEASE_PROTOCOL = "jev-systemone"
MAX_INPUTS = 64
MAX_INPUT_CHARS = 8000
# The models the defaults name. The app marks them as recommended and offers to restore them.
RECOMMENDED = {config_key(DEFAULT_CONFIG[role]) for role in ROLES}
log = logging.getLogger("fishd")


def _stamp(epoch_seconds):
    return datetime.fromtimestamp(epoch_seconds, timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _texts(value):
    if isinstance(value, str):
        value = [value]
    if not isinstance(value, list) or not value or len(value) > MAX_INPUTS or not all(isinstance(text, str) for text in value):
        raise Refused(400, "input must be a string or a non-empty list of at most %d strings" % MAX_INPUTS)
    if any(len(text) > MAX_INPUT_CHARS for text in value):
        raise Refused(413, "each input must be at most %d characters" % MAX_INPUT_CHARS)
    return value


class Service:
    def __init__(self, state, loaders=LOADERS, command=worker_command, origin="", leases=None):
        self.state = state
        self.jobs = Jobs(state, command)
        self.origin = origin
        self.leases = leases or Leases()
        self._loaders = loaders
        self._engines = {}
        self._warming = set()
        self._warm_lock = threading.Lock()
        self._load_lock = threading.Lock()
        self._gates = {role: threading.Lock() for role in ROLES}
        self._served = {"decision": 0, "embedding": 0}
        self._served_lock = threading.Lock()

    def start(self):
        config = self.state.config()
        if config["download_on_start"]:
            for role in ROLES:
                entry = config[role]
                if self.state.ready_record(config_key(entry)) is None:
                    self.jobs.start(entry["repo"], entry["revision"], role)
        for role in ROLES:
            if self.state.ready_record(config_key(config[role])) is not None:
                self._warm(role)

    def shutdown(self):
        self.jobs.shutdown()

    def health(self):
        config = self.state.config()
        roles = {}
        for role in ROLES:
            entry = config[role]
            roles[role] = {"model": entry["repo"], "revision": entry["revision"], "state": self._state_of(config_key(entry)), "loaded": role in self._engines}
        with self._served_lock:
            served = dict(self._served)
        activity = {"decisions": served["decision"], "embeddings": served["embedding"], "leases": self.leases.active()}
        return {"status": "ok", "protocol": PROTOCOL, "version": VERSION, "roles": roles, "activity": activity}

    def models(self):
        config = self.state.config()
        active = self._active_keys()
        known = {config_key(config[role]): {"repo": config[role]["repo"], "revision": config[role]["revision"], "role": role} for role in ROLES}
        for key in self._ready_keys():
            record = self.state.ready_record(key)
            known[key] = {"repo": record["repo"], "revision": record["revision"], "role": record["role"]}
        for job in self.jobs.all():
            known[job.key] = {"repo": job.repo, "revision": job.revision, "role": job.role}
        return [self._describe(key, info, key in active) for key, info in sorted(known.items())]

    def start_download(self, source, role, revision=None):
        if role not in ROLES:
            raise Refused(422, "role must be one of: %s" % ", ".join(ROLES))
        repo, chosen = parse_source(source, revision)
        key = model_key(repo, chosen)
        if self.state.ready_record(key) is not None:
            raise Refused(409, "This model is already downloaded.")
        job = self.jobs.start(repo, chosen, role)
        return self._describe(key, {"repo": job.repo, "revision": job.revision, "role": job.role}, False)

    def reset_config(self):
        """Puts the recommended models back in config.json. Nothing is deleted; missing recommended models download."""
        with self._load_lock:
            current = self.state.config()
            for role in ROLES:
                if config_key(current[role]) != config_key(DEFAULT_CONFIG[role]):
                    self._engines.pop(role, None)
            self.state.write_config(copy.deepcopy(DEFAULT_CONFIG))
        self.start()

    def cancel_download(self, key):
        self._require_known(key)
        self.jobs.cancel(key)

    def delete(self, key):
        self._require_known(key)
        job = self.jobs.get(key)
        if job is not None and job.state in ACTIVE_STATES:
            raise Refused(409, "Cancel the download before deleting this model.")
        if key in self._active_keys():
            raise Refused(409, "This model is the active one in config.json. Point its role at another model first.")
        path = self.state.model_dir(key)
        if path.exists():
            shutil.rmtree(path)
        self.jobs.forget(key)

    def decide(self, body):
        state, questions = parse_request(body)
        engine = self._engine("decision")
        with self._gates["decision"]:
            answers = engine.decide(state, questions)
        self._count("decision")
        return answers

    def lease(self, body):
        """Issue a decision lease. Answers fast; never waits for a model load."""
        if not isinstance(body, dict) or body.get("protocol") != LEASE_PROTOCOL:
            raise Refused(422, "protocol must be %s" % LEASE_PROTOCOL, code="fishstack.invalid")
        self._ready_engine("decision")
        lease_id, key, expires = self.leases.issue(body.get("ttl_s"))
        return self._lease_record(lease_id, key, expires)

    def renew_lease(self, lease_id):
        renewed = self.leases.renew(lease_id)
        if renewed is None:
            raise Refused(404, "No live lease with that id.", code="fishstack.not_found")
        key, expires = renewed
        return self._lease_record(lease_id, key, expires)

    def _lease_record(self, lease_id, key, expires):
        return {
            "schema": "fishstack.lease/1",
            "lease_id": lease_id,
            "base_url": self.origin,
            "model": self.state.config()["decision"]["repo"],
            "protocol": LEASE_PROTOCOL,
            "api_key": key,
            "expires_at": _stamp(expires),
        }

    def release_lease(self, lease_id):
        if not self.leases.release(lease_id):
            raise Refused(404, "No live lease with that id.", code="fishstack.not_found")

    def accepts_lease(self, key):
        return self.leases.accepts(key)

    def _ready_engine(self, role):
        # Never takes _load_lock: a model load holds it, and a lease must answer in well under a second.
        engine = self._engines.get(role)
        if engine is not None:
            return engine
        entry = self.state.config()[role]
        if self.state.ready_record(config_key(entry)) is None:
            raise Refused(503, "The %s model is not ready yet. Check GET /v1/models for progress." % role, code="decision.not_ready", retry_after=60)
        self._warm(role)
        raise Refused(503, "The %s model is loading. Try again in a few seconds." % role, code="decision.warming", retry_after=5)

    def _warm(self, role):
        with self._warm_lock:
            if role in self._engines or role in self._warming:
                return
            self._warming.add(role)
        threading.Thread(target=self._warm_now, args=(role,), name="warm-" + role, daemon=True).start()

    def _warm_now(self, role):
        try:
            self._engine(role)
        except Refused as refused:
            log.warning("could not load the %s model: %s", role, refused.detail)
        except Exception:
            log.exception("could not load the %s model", role)
        finally:
            with self._warm_lock:
                self._warming.discard(role)

    def embed(self, body):
        texts = _texts(body.get("input"))
        engine = self._engine("embedding")
        requested = body.get("model")
        if requested is not None and requested != engine.name:
            raise Refused(400, "model must be %s or omitted" % engine.name)
        with self._gates["embedding"]:
            vectors, tokens = engine.embed(texts)
        self._count("embedding")
        return {
            "object": "list",
            "model": engine.name,
            "data": [{"object": "embedding", "index": index, "embedding": vector} for index, vector in enumerate(vectors)],
            "usage": {"prompt_tokens": tokens, "total_tokens": tokens},
        }

    def _count(self, role):
        with self._served_lock:
            self._served[role] += 1

    def _engine(self, role):
        with self._load_lock:
            engine = self._engines.get(role)
            if engine is None:
                entry = self.state.config()[role]
                key = config_key(entry)
                record = self.state.ready_record(key)
                if record is None:
                    raise Refused(503, "The %s model is not ready yet. Check GET /v1/models for progress." % role)
                engine = self._loaders[role](self.state.model_dir(key) / record["path"], entry["repo"])
                self._engines[role] = engine
            return engine

    def _active_keys(self):
        config = self.state.config()
        return {config_key(config[role]) for role in ROLES}

    def _ready_keys(self):
        return [path.name for path in self.state.models_dir.iterdir() if path.is_dir() and self.state.ready_record(path.name) is not None]

    def _require_known(self, key):
        known = self._active_keys() | set(self._ready_keys()) | {job.key for job in self.jobs.all()}
        if key not in known:
            raise Refused(404, "No model with that id.")

    def _state_of(self, key):
        job = self.jobs.get(key)
        if job is not None and job.state in ACTIVE_STATES:
            return job.state
        if self.state.ready_record(key) is not None:
            return "ready"
        if job is not None:
            return job.state
        return "not_downloaded"

    def _describe(self, key, info, active):
        job = self.jobs.get(key)
        record = self.state.ready_record(key)
        if record is not None and not (job is not None and job.state in ACTIVE_STATES):
            done = total = record["bytes"]
        elif job is not None:
            done, total = job.bytes_done, job.bytes_total
        else:
            done, total = 0, None
        return {
            "id": key,
            "repo": info["repo"],
            "revision": info["revision"],
            "role": info["role"],
            "state": self._state_of(key),
            "bytes_done": done,
            "bytes_total": total,
            "active": active,
            "recommended": key in RECOMMENDED,
            "error": job.error if job is not None else None,
        }
