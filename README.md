# Fish Stack

A native macOS menu-bar app that serves local models to your other apps. It runs the decision model (`/v1/systemone`, the same request shape as `jev-local`) and an embedding model (`/v1/embeddings`), both on MLX for Apple silicon. It also downloads models from Hugging Face and shows their progress. See [docs/spec.md](docs/spec.md) for the design.

## Requirements

- Apple silicon Mac with 16 GB or more of memory
- Xcode (the app builds with its toolchain, not the Command Line Tools)
- [uv](https://docs.astral.sh/uv/) (`brew install uv`). It installs Python 3.12 and the pinned packages.
- About 12 GB free disk for the decision model (8.4 GB download, plus the converted copy)

## Run the tests

```sh
make test
```

The runtime tests use fake engines and a fake download worker, so they need no GPU and download nothing.

## Build the app

```sh
make app
open build/FishStack.app
```

The app bundles the runtime. On first launch it runs `uv sync` into `~/Library/Application Support/FishStack/venv`, then starts `fishd` on `127.0.0.1:8089`. `fishd` exits when the app quits.

For development, `FISH_STACK_PORT`, `FISH_STACK_STATE` and `FISH_STACK_RUNTIME` override the port, state folder and runtime folder. If a server already answers on the port, the app attaches to it instead of starting one.

`make test` also runs `MenuSnapshotTests`, which renders the menu against a running server and writes a PNG. It is skipped unless `FISH_STACK_SNAPSHOT`, `FISH_STACK_PORT` and `FISH_STACK_STATE` are set.

## Run the server by hand

```sh
cd runtime && uv sync --python 3.12
make run-dev   # serves on $COMMISSION_DEV_PORT (default 20880) with state in ./state-dev
```

Get the bearer key from `<state>/api-key` and call it:

```sh
KEY=$(cat state-dev/api-key)
curl -s -H "Authorization: Bearer $KEY" http://127.0.0.1:20880/v1/models
curl -s -X POST -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"input":["a duplicate charge"],"model":"mlx-community/bge-small-en-v1.5-4bit"}' \
  http://127.0.0.1:20880/v1/embeddings
```

Downloads can also start from the API. A repo id and a Hugging Face URL both work:

```sh
curl -s -X POST -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"source":"https://huggingface.co/BAAI/bge-small-en-v1.5","role":"embedding"}' \
  http://127.0.0.1:20880/v1/models
```

## Models and state

- The defaults are the decision model `internlm/Intern-Decision-4B` (converted to MLX 4-bit, group size 64, the same as `jev-local`) and the embedding model `mlx-community/bge-small-en-v1.5-4bit`. Both use pinned revisions.
- `<state>/config.json` names the active model per role. Set `download_on_start` to `false` to stop automatic downloads at startup.
- `<state>/models/<owner--name@revision>/` holds each model. A `READY` file marks a model as complete. Partial downloads are kept and resume.
- `<state>/logs/` holds one log per download and the app's logs.

## Not in this version

- Changing the active model from the app or the API (edit `config.json` and restart).
- Hugging Face search.
- A chat LLM endpoint.
- Registering with pAtelier leases, so CommissionAI would still start its own `jev-local` server.
- Reranking and ColBERT embeddings used by CommissionAI memory.

## Layout

- `runtime/` is the `fishd` Python package: `decision.py`, `embedding.py`, `jobs.py` (download manager), `worker.py` (runs one download), `service.py`, `server.py`.
- `app/` is the SwiftUI menu-bar app.
- `scripts/build-app.sh` builds and bundles the app.
- `docs/spec.md` is the spec.
