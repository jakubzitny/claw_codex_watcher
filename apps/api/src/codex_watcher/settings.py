from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    codex_home: Path
    retention_hours: int
    active_window_seconds: int
    repo_scope: str | None
    persistence_db_path: Path
    watcher_auth_token: str | None


def load_settings() -> Settings:
    codex_home = Path(os.getenv('CODEX_HOME', str(Path.home() / '.codex'))).expanduser().resolve()
    retention_hours = int(os.getenv('RETENTION_HOURS', '24'))
    active_window_seconds = int(os.getenv('ACTIVE_WINDOW_SECONDS', '120'))
    repo_scope_raw = os.getenv('REPO_SCOPE', str(Path.cwd().resolve())).strip()
    repo_scope = repo_scope_raw if repo_scope_raw else None
    persistence_db_path = Path(
        os.getenv('PERSISTENCE_DB_PATH', str(Path.cwd().resolve() / '.watcher' / 'watcher.db'))
    ).expanduser()
    auth_token_raw = os.getenv('WATCHER_AUTH_TOKEN', '').strip()
    watcher_auth_token = auth_token_raw if auth_token_raw else None
    return Settings(
        codex_home=codex_home,
        retention_hours=retention_hours,
        active_window_seconds=active_window_seconds,
        repo_scope=repo_scope,
        persistence_db_path=persistence_db_path,
        watcher_auth_token=watcher_auth_token,
    )
