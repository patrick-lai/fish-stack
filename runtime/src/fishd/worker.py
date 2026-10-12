import fnmatch
import json
import shutil
import subprocess
import sys
from pathlib import Path

from huggingface_hub import HfApi, snapshot_download

from fishd.catalog import CONVERT_SUPPORT_FILES, ROLE_PATTERNS

# Four-bit group-size-64 is what jev-local ships, so the decision answers stay the same.
CONVERT_ARGS = ["-q", "--q-bits", "4", "--q-group-size", "64"]


def emit(**event):
    print(json.dumps(event), flush=True)


def convert(source: Path, target: Path):
    staging = target / "mlx.partial"
    if staging.exists():
        shutil.rmtree(staging)
    # mlx_lm prints progress to stdout, which carries this worker's JSON events, so route it to stderr.
    done = subprocess.run([sys.executable, "-m", "mlx_lm", "convert", "--hf-path", str(source), "--mlx-path", str(staging), *CONVERT_ARGS], stdin=subprocess.DEVNULL, stdout=sys.stderr, stderr=sys.stderr)
    if done.returncode != 0:
        raise SystemExit("mlx_lm convert failed with exit code %d" % done.returncode)
    for name in CONVERT_SUPPORT_FILES:
        if (source / name).exists() and not (staging / name).exists():
            shutil.copy(source / name, staging / name)
    final = target / "mlx"
    if final.exists():
        shutil.rmtree(final)
    staging.rename(final)
    return "mlx"


def main(argv):
    role, repo, revision, model_dir = argv
    target = Path(model_dir)
    target.mkdir(parents=True, exist_ok=True)
    patterns = ROLE_PATTERNS[role]
    info = HfApi().model_info(repo, revision=revision, files_metadata=True)
    wanted = [sibling for sibling in info.siblings if any(fnmatch.fnmatch(sibling.rfilename, pattern) for pattern in patterns)]
    total = sum(sibling.size or 0 for sibling in wanted)
    emit(stage="downloading", total_bytes=total)
    source = target / "source"
    snapshot_download(repo_id=repo, revision=revision, allow_patterns=patterns, local_dir=source)
    if role == "decision":
        emit(stage="converting")
        path = convert(source, target)
        shutil.rmtree(source)
    else:
        path = "source"
        cache = source / ".cache"
        if cache.exists():
            shutil.rmtree(cache)
    record = {"repo": repo, "revision": revision, "role": role, "path": path, "bytes": total, "sha": info.sha}
    (target / "READY").write_text(json.dumps(record, indent=2) + "\n")
    emit(stage="ready")


if __name__ == "__main__":
    main(sys.argv[1:])
