# Fish Stack

A native macOS menu-bar app that serves local models to your other apps. It runs the decision model (`/v1/systemone`, the same request shape as `jev-local`) and an embedding model (`/v1/embeddings`), both on MLX for Apple silicon. It also downloads models from Hugging Face and shows their progress. See [docs/spec.md](docs/spec.md) for the design.

## Requirements

For people using the app:

- Apple silicon Mac with macOS 14 or later and 16 GB or more of memory
- About 12 GB free disk for the models (8.4 GB download, plus the converted copy)
- Internet for the one-time setup and the model downloads

Nothing else is needed. The app bundles `uv`, which installs Python 3.12 and the pinned packages on first launch. It checks these requirements first and shows what to fix. If setup fails, it retries every 30 seconds.

For building the app:

- Xcode (the app builds with its toolchain, not the Command Line Tools)
- [uv](https://docs.astral.sh/uv/) (`brew install uv`). `scripts/build-app.sh` copies it into the app. Set `UV_BIN` to use another copy.

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

## CommissionAI

fish-stack serves CommissionAI directly, and CommissionAI reaches it in two ways:

- **Endpoint setting (preferred):** start CommissionAI with `COMMISSION_JEV_LOCAL_ENDPOINT=http://127.0.0.1:8089` and `COMMISSION_JEV_LOCAL_KEY_FILE="$HOME/Library/Application Support/FishStack/api-key"`. CommissionAI checks the endpoint with its own decision smoke test (billing at 0.85 or higher) and uses it instead of starting its own `jev-local` runtime. The endpoint must be a loopback http origin. A failing or misconfigured endpoint falls back to the paths below.
- **Lease:** fish-stack writes `~/.fishStack/run/daemon.json`, and CommissionAI leases the decision endpoint from it when no endpoint setting is present.

Either way CommissionAI reads its settings when it starts, so restart it to switch. If neither path works, it falls back to its own runtime. fish-stack logs every served request, for example `served POST /v1/systemone -> 200 (master key)`, in `<state>/logs/fishd.log`. The record is removed when fish-stack quits.

The end-to-end check lives in the commission-ai repo. It is the ignored test `fish_stack_lease`, which runs CommissionAI's real `LocalJev` against a running fish-stack. From `service/` in that repo: `cargo test -p commission-service --test suite commissionai_takes_the_decision_lease_from_fish_stack -- --ignored --nocapture`.

## Not in this version

- Changing the active model from the app or the API (edit `config.json` and restart).
- Hugging Face search.
- A chat LLM endpoint.
- Reranking and ColBERT embeddings used by CommissionAI memory.

## Layout

- `runtime/` is the `fishd` Python package: `decision.py`, `embedding.py`, `jobs.py` (download manager), `worker.py` (runs one download), `service.py`, `server.py`.
- `app/` is the SwiftUI menu-bar app.
- `scripts/build-app.sh` builds and bundles the app.
- `docs/spec.md` is the spec.
