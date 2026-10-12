# Fish Stack: model server spec

Fish Stack is a native macOS menu-bar app. It runs a local model server (`fishd`) that serves the decision model and the embedding model to other apps on this Mac, and manages how those models are downloaded. It runs on Apple silicon with MLX.

## Goals (this iteration)

- Serve the decision model with the existing JEV request shape, so CommissionAI and other JEV clients work without code changes.
- Serve the embedding model over an OpenAI-style embeddings API.
- Download models from Hugging Face by repo id or URL, show progress, cancel, resume, and delete.
- Run from a menu-bar app that starts and supervises `fishd`.

## Non-goals (later)

- Swapping the active model from the app or the API. The active model comes from `config.json`.
- Hugging Face search.
- A chat LLM endpoint. The `mlx-lm` package is in place for it, but no route exists yet.
- Registering the endpoint with pAtelier leases. CommissionAI currently starts its own decision server through `jev_local.rs`.
- Reranking and late-interaction (ColBERT) embeddings used by CommissionAI memory.

## Models

| Role | Default model | Format | Notes |
| --- | --- | --- | --- |
| decision | `internlm/Intern-Decision-4B` at the revision pinned in `share/jev-local/runtime.json` | Converted to MLX 4-bit, group size 64 | Same model and quantisation as `jev-local`. |
| embedding | `mlx-community/bge-small-en-v1.5-4bit` at a pinned revision | MLX, already quantised | CLS pooling, normalised output, 384 dimensions. This matches `BAAI/bge-small-en-v1.5`, which CommissionAI memory uses. |

## Runtime API

Listens on `127.0.0.1` only. Every route except `GET /health` needs `Authorization: Bearer <key>`. The key is generated on first run and stored in `<state>/api-key` with mode `0600`.

| Method and path | Purpose |
| --- | --- |
| `GET /health` | Protocol version, role states and whether each engine is loaded. |
| `POST /v1/systemone` | Decision requests. Same request and response shape as `jev-local` (protocol 1). |
| `POST /v1/embeddings` | `{"input": string or [string], "model"?: string}` returns `{"object":"list","data":[{"index","embedding"}],"model","usage"}`. |
| `GET /v1/models` | Known models with role, state, progress and whether each is active. |
| `POST /v1/models` | `{"source": "owner/name or Hugging Face URL", "role": "decision" or "embedding", "revision"?: "main"}` starts a download (202). |
| `POST /v1/models/{key}/cancel` | Stops a running download. Partial files are kept so the next attempt resumes. |
| `DELETE /v1/models/{key}` | Removes a downloaded model. Refused with 409 for the active model or while a download runs. |

A model key is `owner--name@revision` with the full revision, for example `internlm--Intern-Decision-4B@0e5e6aa7d6d750e2b1504ba11a8136cb58aeb3cd`. The key of a model that uses `main` ends in `@main`.

Refusals follow `jev-local`: 400 for a malformed body, 401 for a bad key, 411 without `Content-Length`, 413 for oversize input, 422 for invalid questions, 503 while a model is not ready, and 500 with the detail only in the log.

## Download manager

- Each download runs in a worker subprocess (`python -m fishd.worker`), so cancel is a terminate and a crash cannot take down the server.
- Files go to `<state>/models/<key>/source`. The worker reports `downloading` with the expected byte total, then `converting` for the decision model, then `ready`.
- Progress is the size of the files on disk, including Hugging Face's `.incomplete` partial files, compared with the expected total.
- A finished model has a `READY` file that names the serving path (`mlx` or `source`). The server only loads models with a `READY` file.
- At startup, the server starts a download for each configured model that is not ready.

## Configuration

`<state>/config.json` maps each role to a repo and revision, and sets `download_on_start`. The defaults are written on first run. Editing it changes the active model after a restart. Swapping will get its own API later. With `download_on_start` set to `false`, the server only downloads what you request through the API.

## Menu-bar app

- `MenuBarExtra` with status, one row per role, downloads with progress, cancel and delete, and an add-model field that accepts a repo id or Hugging Face URL.
- Starts `fishd` from the bundled `runtime/` with `uv sync` into `~/Library/Application Support/FishStack/venv`, then polls `/health`.
- `fishd` exits when its parent exits, so a crashed app does not leave a server running.

## Acceptance checks

1. `runtime` unit tests pass (`make test`).
2. The Swift package builds (`make app`).
3. Against a real server: `/health` shows both roles ready, `/v1/systemone` returns the same answer shape as `jev-local`, and `/v1/embeddings` returns unit 384-dimension vectors where a paraphrase scores higher than an unrelated sentence.
4. A download can be started by URL, reports progress, is cancelled, resumes, and is deleted.
