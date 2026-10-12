import shutil
import threading

from fishd import PROTOCOL, VERSION
from fishd.catalog import ROLES
from fishd.decision import load_decision_engine, parse_request
from fishd.embedding import load_embedding_engine
from fishd.errors import Refused
from fishd.hf import model_key, parse_source
from fishd.jobs import ACTIVE_STATES, Jobs, worker_command
from fishd.state import config_key

LOADERS = {"decision": load_decision_engine, "embedding": load_embedding_engine}
MAX_INPUTS = 64
MAX_INPUT_CHARS = 8000


def _texts(value):
    if isinstance(value, str):
        value = [value]
    if not isinstance(value, list) or not value or len(value) > MAX_INPUTS or not all(isinstance(text, str) for text in value):
        raise Refused(400, "input must be a string or a non-empty list of at most %d strings" % MAX_INPUTS)
    if any(len(text) > MAX_INPUT_CHARS for text in value):
        raise Refused(413, "each input must be at most %d characters" % MAX_INPUT_CHARS)
    return value


class Service:
    def __init__(self, state, loaders=LOADERS, command=worker_command):
        self.state = state
        self.jobs = Jobs(state, command)
        self._loaders = loaders
        self._engines = {}
        self._load_lock = threading.Lock()
        self._gates = {role: threading.Lock() for role in ROLES}

    def start(self):
        config = self.state.config()
        if not config["download_on_start"]:
            return
        for role in ROLES:
            entry = config[role]
            if self.state.ready_record(config_key(entry)) is None:
                self.jobs.start(entry["repo"], entry["revision"], role)

    def shutdown(self):
        self.jobs.shutdown()

    def health(self):
        config = self.state.config()
        roles = {}
        for role in ROLES:
            entry = config[role]
            roles[role] = {"model": entry["repo"], "revision": entry["revision"], "state": self._state_of(config_key(entry)), "loaded": role in self._engines}
        return {"status": "ok", "protocol": PROTOCOL, "version": VERSION, "roles": roles}

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
            return engine.decide(state, questions)

    def embed(self, body):
        texts = _texts(body.get("input"))
        engine = self._engine("embedding")
        requested = body.get("model")
        if requested is not None and requested != engine.name:
            raise Refused(400, "model must be %s or omitted" % engine.name)
        with self._gates["embedding"]:
            vectors, tokens = engine.embed(texts)
        return {
            "object": "list",
            "model": engine.name,
            "data": [{"object": "embedding", "index": index, "embedding": vector} for index, vector in enumerate(vectors)],
            "usage": {"prompt_tokens": tokens, "total_tokens": tokens},
        }

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
            "error": job.error if job is not None else None,
        }
