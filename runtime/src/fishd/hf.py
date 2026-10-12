import re
from urllib.parse import urlsplit

from fishd.errors import Refused

_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,95}")
_REVISION = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
_REPO_HOSTS = ("huggingface.co", "hf.co")
_NOT_MODELS = ("datasets", "spaces")
_BAD_SOURCE = "Enter a Hugging Face model as owner/name or a huggingface.co model URL."


def parse_source(text, revision=None):
    """Return (repo, revision) for a repo id or a Hugging Face model URL."""
    text = text.strip()
    url_revision = None
    if "://" in text:
        url = urlsplit(text)
        if url.scheme != "https" or url.hostname not in _REPO_HOSTS or url.username or url.password:
            raise Refused(422, _BAD_SOURCE)
        parts = [part for part in url.path.split("/") if part]
        if len(parts) < 2 or parts[0] in _NOT_MODELS:
            raise Refused(422, _BAD_SOURCE)
        if len(parts) >= 4 and parts[2] in ("tree", "blob", "resolve"):
            url_revision = parts[3]
        elif len(parts) != 2:
            raise Refused(422, _BAD_SOURCE)
        owner, name = parts[0], parts[1]
    else:
        owner, _, name = text.partition("/")
    if not (_NAME.fullmatch(owner) and _NAME.fullmatch(name)):
        raise Refused(422, _BAD_SOURCE)
    chosen = revision or url_revision or "main"
    if not isinstance(chosen, str) or not _REVISION.fullmatch(chosen):
        raise Refused(422, "The revision must be a branch, tag or commit hash without slashes.")
    return f"{owner}/{name}", chosen


def model_key(repo, revision):
    return f"{repo.replace('/', '--')}@{revision}"
