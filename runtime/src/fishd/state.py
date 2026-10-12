import json
import os
import secrets
from pathlib import Path

from fishd.catalog import DEFAULT_CONFIG, ROLES
from fishd.errors import Refused
from fishd.hf import model_key


class State:
    def __init__(self, root: Path):
        self.root = root
        self.models_dir = root / "models"
        self.logs_dir = root / "logs"
        self.root.mkdir(parents=True, exist_ok=True)
        self.models_dir.mkdir(exist_ok=True)
        self.logs_dir.mkdir(exist_ok=True)

    def api_key(self) -> str:
        path = self.root / "api-key"
        try:
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            return path.read_text().strip()
        with os.fdopen(descriptor, "w") as handle:
            handle.write(secrets.token_urlsafe(32))
        return path.read_text().strip()

    def config(self) -> dict:
        path = self.root / "config.json"
        if not path.exists():
            path.write_text(json.dumps(DEFAULT_CONFIG, indent=2) + "\n")
        config = json.loads(path.read_text())
        missing = [role for role in ROLES if role not in config]
        if missing:
            raise Refused(500, "config.json is missing roles: %s" % ", ".join(missing))
        return config

    def write_config(self, config: dict):
        path = self.root / "config.json"
        temporary = path.with_name("config.json.tmp")
        temporary.write_text(json.dumps(config, indent=2) + "\n")
        os.replace(temporary, path)

    def model_dir(self, key: str) -> Path:
        return self.models_dir / key

    def log_path(self, key: str) -> Path:
        return self.logs_dir / (key + ".log")

    def ready_record(self, key: str):
        path = self.model_dir(key) / "READY"
        if not path.exists():
            return None
        return json.loads(path.read_text())


def config_key(entry: dict) -> str:
    return model_key(entry["repo"], entry["revision"])
