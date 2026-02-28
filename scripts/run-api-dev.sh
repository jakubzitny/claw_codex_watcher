#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_DIR="$ROOT_DIR/apps/api"
VENV_DIR="$API_DIR/.venv"
REQUIREMENTS_FILE="$API_DIR/requirements-dev.txt"
STAMP_FILE="$VENV_DIR/.deps-installed.stamp"

PYTHON_BIN="${PYTHON_BIN:-python3}"
API_HOST="${API_HOST:-127.0.0.1}"
API_PORT="${API_PORT:-18000}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-http://${API_HOST}:${API_PORT}/api/v1/health}"

if [ ! -x "$VENV_DIR/bin/python" ]; then
  echo "[dev:be] Creating Python virtualenv at $VENV_DIR"
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

if [ ! -f "$STAMP_FILE" ] || [ "$REQUIREMENTS_FILE" -nt "$STAMP_FILE" ]; then
  echo "[dev:be] Installing backend dependencies"
  "$VENV_DIR/bin/python" -m pip install --upgrade pip >/dev/null
  "$VENV_DIR/bin/pip" install -r "$REQUIREMENTS_FILE" >/dev/null
  touch "$STAMP_FILE"
fi

if lsof -nP -iTCP:"$API_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  if curl -fsS "$HEALTHCHECK_URL" >/dev/null 2>&1; then
    echo "[dev:be] Reusing existing API on ${API_HOST}:${API_PORT}"
    trap 'exit 0' INT TERM
    while true; do
      sleep 3600
    done
  fi

  echo "[dev:be] Port ${API_PORT} is busy and healthcheck failed. Stop conflicting process first."
  exit 1
fi

exec "$VENV_DIR/bin/python" -m uvicorn \
  --app-dir "$API_DIR/src" \
  codex_watcher.main:app \
  --reload \
  --host "$API_HOST" \
  --port "$API_PORT"
