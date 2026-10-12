import json
import os
from pathlib import Path

DEFAULT_HOME = "~/.fishStack"


def home(override=None):
    """The FishStack home where run/daemon.json is published and CommissionAI reads it."""
    return Path(override or os.environ.get("FISH_STACK_HOME") or DEFAULT_HOME).expanduser()


def daemon_file(root):
    return root / "run" / "daemon.json"


def pid_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def publish(root, pid, port):
    """Write run/daemon.json, the record CommissionAI reads to find this server.

    A record that names another live server is left alone, so a second FishStack cannot take
    the leases from the first. Returns False in that case.
    """
    directory = root / "run"
    directory.mkdir(parents=True, exist_ok=True)
    target = daemon_file(root)
    owner = _record(target)
    if owner and owner.get("pid") != pid and isinstance(owner.get("pid"), int) and pid_alive(owner["pid"]):
        return False
    temporary = target.with_name("daemon.json.%d.tmp" % pid)
    temporary.write_text(json.dumps({"pid": pid, "port": port}) + "\n")
    os.replace(temporary, target)
    return True


def _record(target):
    try:
        record = json.loads(target.read_text())
    except (OSError, ValueError):
        return None
    return record if isinstance(record, dict) else None


def withdraw(root, pid):
    """Remove the record, but only when it still names this process."""
    target = daemon_file(root)
    try:
        record = json.loads(target.read_text())
    except (OSError, ValueError):
        return
    if isinstance(record, dict) and record.get("pid") == pid:
        target.unlink(missing_ok=True)
