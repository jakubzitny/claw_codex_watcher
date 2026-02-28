from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path

from .models import ThreadDetail, ThreadSummary


class PersistenceStore:
    def __init__(self, db_path: Path):
        self.db_path = db_path.expanduser().resolve()
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_schema()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_schema(self) -> None:
        with self._connect() as conn:
            conn.execute(
                '''
                CREATE TABLE IF NOT EXISTS thread_summaries (
                    thread_id TEXT PRIMARY KEY,
                    updated_at TEXT NOT NULL,
                    cwd TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    saved_at INTEGER NOT NULL
                )
                '''
            )
            conn.execute(
                '''
                CREATE TABLE IF NOT EXISTS thread_details (
                    thread_id TEXT PRIMARY KEY,
                    updated_at TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    saved_at INTEGER NOT NULL
                )
                '''
            )

    def save_threads(self, rows: list[ThreadSummary]) -> None:
        saved_at = int(time.time())
        with self._connect() as conn:
            for row in rows:
                conn.execute(
                    '''
                    INSERT INTO thread_summaries(thread_id, updated_at, cwd, payload_json, saved_at)
                    VALUES(?, ?, ?, ?, ?)
                    ON CONFLICT(thread_id) DO UPDATE SET
                      updated_at=excluded.updated_at,
                      cwd=excluded.cwd,
                      payload_json=excluded.payload_json,
                      saved_at=excluded.saved_at
                    ''',
                    (
                        row.id,
                        row.updatedAt,
                        row.cwd,
                        json.dumps(row.model_dump()),
                        saved_at,
                    ),
                )

    def load_threads(self, limit: int = 100, repo_scope: str | None = None) -> list[ThreadSummary]:
        with self._connect() as conn:
            if repo_scope:
                rows = conn.execute(
                    '''
                    SELECT payload_json
                    FROM thread_summaries
                    WHERE cwd = ? OR cwd LIKE ?
                    ORDER BY updated_at DESC
                    LIMIT ?
                    ''',
                    (repo_scope, f'{repo_scope}/%', limit),
                ).fetchall()
            else:
                rows = conn.execute(
                    '''
                    SELECT payload_json
                    FROM thread_summaries
                    ORDER BY updated_at DESC
                    LIMIT ?
                    ''',
                    (limit,),
                ).fetchall()

        result: list[ThreadSummary] = []
        for row in rows:
            try:
                payload = json.loads(row['payload_json'])
                result.append(ThreadSummary.model_validate(payload))
            except Exception:
                continue
        return result

    def save_thread_detail(self, detail: ThreadDetail) -> None:
        saved_at = int(time.time())
        with self._connect() as conn:
            conn.execute(
                '''
                INSERT INTO thread_details(thread_id, updated_at, payload_json, saved_at)
                VALUES(?, ?, ?, ?)
                ON CONFLICT(thread_id) DO UPDATE SET
                  updated_at=excluded.updated_at,
                  payload_json=excluded.payload_json,
                  saved_at=excluded.saved_at
                ''',
                (
                    detail.summary.id,
                    detail.summary.updatedAt,
                    json.dumps(detail.model_dump()),
                    saved_at,
                ),
            )

    def load_thread_detail(self, thread_id: str) -> ThreadDetail | None:
        with self._connect() as conn:
            row = conn.execute(
                '''
                SELECT payload_json
                FROM thread_details
                WHERE thread_id = ?
                ''',
                (thread_id,),
            ).fetchone()

        if row is None:
            return None

        try:
            payload = json.loads(row['payload_json'])
            return ThreadDetail.model_validate(payload)
        except Exception:
            return None
