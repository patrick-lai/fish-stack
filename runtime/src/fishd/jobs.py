import json
import os
import subprocess
import sys
import threading
from dataclasses import dataclass, field

from fishd.errors import Refused
from fishd.hf import model_key

ACTIVE_STATES = ("starting", "downloading", "converting")
POLL_SECONDS = 1.0


def worker_command(role, repo, revision, model_dir):
    return [sys.executable, "-m", "fishd.worker", role, repo, revision, str(model_dir)]


def directory_bytes(path):
    total = 0
    for root, _, files in os.walk(path):
        for name in files:
            try:
                total += os.path.getsize(os.path.join(root, name))
            except FileNotFoundError:
                # Hugging Face renames a partial file to its final name when it finishes.
                continue
    return total


@dataclass
class Job:
    key: str
    repo: str
    revision: str
    role: str
    state: str = "starting"
    bytes_done: int = 0
    bytes_total: int | None = None
    error: str | None = None
    process: subprocess.Popen | None = None
    cancelled: bool = False
    finished: threading.Event = field(default_factory=threading.Event)


class Jobs:
    def __init__(self, state, command=worker_command):
        self._state = state
        self._command = command
        self._lock = threading.Lock()
        self._jobs = {}

    def get(self, key):
        with self._lock:
            return self._jobs.get(key)

    def all(self):
        with self._lock:
            return list(self._jobs.values())

    def forget(self, key):
        with self._lock:
            self._jobs.pop(key, None)

    def start(self, repo, revision, role):
        key = model_key(repo, revision)
        with self._lock:
            current = self._jobs.get(key)
            if current is not None and current.state in ACTIVE_STATES:
                raise Refused(409, "This model is already downloading.")
            job = Job(key=key, repo=repo, revision=revision, role=role)
            self._jobs[key] = job
        threading.Thread(target=self._run, args=(job,), daemon=True).start()
        return job

    def cancel(self, key):
        with self._lock:
            job = self._jobs.get(key)
            if job is None or job.state not in ACTIVE_STATES:
                raise Refused(409, "Nothing is downloading for this model.")
            job.cancelled = True
            process = job.process
        if process is not None:
            process.terminate()

    def shutdown(self):
        with self._lock:
            processes = [job.process for job in self._jobs.values() if job.process is not None]
        for process in processes:
            process.terminate()

    def _run(self, job):
        model_dir = self._state.model_dir(job.key)
        with self._state.log_path(job.key).open("ab") as log, subprocess.Popen(self._command(job.role, job.repo, job.revision, model_dir), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=log, text=True) as process:
            with self._lock:
                job.process = process
                if job.cancelled:
                    process.terminate()
            reader = threading.Thread(target=self._read_events, args=(job, process.stdout), daemon=True)
            reader.start()
            code = self._wait(job, process, model_dir)
            reader.join()
        self._finish(job, code)

    def _wait(self, job, process, model_dir):
        while True:
            try:
                return process.wait(timeout=POLL_SECONDS)
            except subprocess.TimeoutExpired:
                if job.state == "downloading" and job.bytes_total:
                    job.bytes_done = min(directory_bytes(model_dir), job.bytes_total)

    def _read_events(self, job, stdout):
        for line in stdout:
            event = json.loads(line)
            with self._lock:
                if "stage" in event:
                    job.state = event["stage"]
                if "total_bytes" in event:
                    job.bytes_total = event["total_bytes"]

    def _finish(self, job, code):
        record = self._state.ready_record(job.key)
        with self._lock:
            if job.cancelled:
                job.state = "cancelled"
            elif code == 0 and record is not None:
                job.state = "ready"
                job.bytes_done = job.bytes_total or 0
            else:
                job.state = "failed"
                job.error = "The download stopped before the model was ready. Open the log for details."
            job.process = None
        job.finished.set()
