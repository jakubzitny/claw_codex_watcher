# Codex Watcher Monorepo

Read-only local webapp to watch Codex thread activity remotely, with:

- `apps/web`: React + Vite + TypeScript UI
- `apps/api`: FastAPI backend (REST + WebSocket)
- `apps/ios-watcher`: native iPhone + CarPlay companion app (Swift + SwiftUI)
- `packages/shared-types`: shared TS models/helpers

## Stack

- pnpm workspaces
- TypeScript
- React + Vite
- FastAPI + Uvicorn
- Biome (lint + format)
- Jest (unit tests)
- Playwright (e2e)
- GitHub Actions (CI)

## Quick Start

```bash
make install
make dev
```

- Web: `http://127.0.0.1:5173`
- API: `http://127.0.0.1:18000`

## API Endpoints

- `GET /api/v1/health`
- `GET /api/v1/threads`
- `GET /api/v1/threads/{thread_id}`
- `GET /api/v1/threads/{thread_id}/events`
- `WS /ws/v1/threads`

## Data Source

Backend reads local Codex state directly from `~/.codex` by default:

- `state_5.sqlite` (`threads` metadata)
- per-thread `sessions/.../*.jsonl` rollout logs

Config:

- `CODEX_HOME` (default `~/.codex`)
- `RETENTION_HOURS` (default `24`)
- `ACTIVE_WINDOW_SECONDS` (default `120`)
- `REPO_SCOPE` (default current working directory)
- `PERSISTENCE_DB_PATH` (default `./.watcher/watcher.db`)
- `WATCHER_AUTH_TOKEN` (optional; enables token auth for REST + WS)

## Tunnel + Auth

Set a token before exposing the app externally:

```bash
export WATCHER_AUTH_TOKEN='replace-with-long-random-token'
export VITE_WATCHER_TOKEN="$WATCHER_AUTH_TOKEN"
make dev
```

Then open a tunnel (example with cloudflared):

```bash
cloudflared tunnel --url http://127.0.0.1:5173
```

The frontend will include the token on API requests and WS connections.

## Commands

```bash
make dev-fe
make dev-be
make lint
make format
make format-check
make test-unit
make test-api
make test-e2e
make build
make check
```

iOS module:

```bash
cd apps/ios-watcher
pnpm gen
pnpm build
pnpm test:unit
```

## Notes

- Current mode is read-only.
- Retention defaults to 24h, matching your requirement.
- Thread list is repo-scoped by default (`REPO_SCOPE`), so sidebar shows only threads for that repo.
- Backend writes thread summaries/details to SQLite persistence and can fall back to it when live Codex files are unavailable.
- Fixture Codex data in `apps/api/tests/fixtures/codex_home` is used for CI and e2e determinism.
- `make dev` runs `dev:be` + `dev:fe` together.
- Backend venv/dependencies are auto-bootstrapped on first `make dev` via `scripts/run-api-dev.sh`.
- If backend is already running on `127.0.0.1:18000`, dev mode reuses it instead of failing.
- Frontend dev mode connects directly to backend via `apps/web/.env.development` (`VITE_API_BASE_URL`, `VITE_WS_BASE_URL`, `VITE_WATCHER_TOKEN`).
- Status includes `thinking` separately from `running`.
