import json
import os
from pathlib import Path

DEFAULT_HOME = "~/.fishStack"


def home(override=None):
    """The FishStack home where run/daemon.json is published and CommissionAI reads it."""
    return Path(override or os.environ.get("FISH_STACK_HOME") or DEFAULT_HOME).expanduser()


def daemon_file(root):
    return root / "run" / "daemon.json"


def publish(root, pid, port):
    """Write run/daemon.json, the record CommissionAI reads to find this server."""
    directory = root / "run"
    directory.mkdir(parents=True, exist_ok=True)
    target = daemon_file(root)
    temporary = target.with_name("daemon.json.%d.tmp" % pid)
    temporary.write_text(json.dumps({"pid": pid, "port": port}) + "\n")
    os.replace(temporary, target)


def withdraw(root, pid):
    """Remove the record, but only when it still names this process."""
    target = daemon_file(root)
    try:
        record = json.loads(target.read_text())
    except (OSError, ValueError):
        return
    if isinstance(record, dict) and record.get("pid") == pid:
        target.unlink(missing_ok=True)
