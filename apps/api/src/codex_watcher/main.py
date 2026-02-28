from __future__ import annotations

import asyncio
import json
from datetime import UTC, datetime

from fastapi import Depends, FastAPI, Header, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from .models import ThreadDetail, ThreadEvent, ThreadSummary, ThreadsSnapshotEvent
from .persistence import PersistenceStore
from .reader import CodexReader
from .settings import load_settings

settings = load_settings()
reader = CodexReader(settings)
store = PersistenceStore(settings.persistence_db_path)

app = FastAPI(title='Codex Watcher API', version='0.1.0')
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r'^https?://(localhost|127\.0\.0\.1)(:\d+)?$',
    allow_methods=['*'],
    allow_headers=['*'],
)


def _extract_auth_token(
    authorization: str | None,
    x_watcher_token: str | None,
) -> str | None:
    if x_watcher_token:
        return x_watcher_token.strip()
    if not authorization:
        return None
    value = authorization.strip()
    if not value.lower().startswith('bearer '):
        return None
    return value[7:].strip()


def require_auth(
    authorization: str | None = Header(default=None),
    x_watcher_token: str | None = Header(default=None),
) -> None:
    if not settings.watcher_auth_token:
        return

    token = _extract_auth_token(authorization, x_watcher_token)
    if token != settings.watcher_auth_token:
        raise HTTPException(status_code=401, detail='Invalid watcher token')


@app.get('/api/v1/health')
def health() -> dict[str, str]:
    return {
        'status': 'ok',
        'at': datetime.now(UTC).isoformat(),
        'codexHome': str(settings.codex_home),
        'repoScope': settings.repo_scope or '',
        'persistenceDbPath': str(settings.persistence_db_path),
        'authEnabled': 'true' if settings.watcher_auth_token else 'false',
    }


@app.get('/api/v1/threads', response_model=list[ThreadSummary])
def list_threads(
    limit: int = Query(default=100, ge=1, le=500),
    hours: int = Query(default=settings.retention_hours, ge=1, le=24 * 30),
    repo_scope: str | None = Query(default=None),
    _auth: None = Depends(require_auth),
) -> list[ThreadSummary]:
    effective_scope = settings.repo_scope if repo_scope is None else repo_scope
    try:
        rows = reader.list_threads(limit=limit, hours=hours, repo_scope=effective_scope)
        store.save_threads(rows)
        return rows
    except FileNotFoundError as exc:
        fallback = store.load_threads(limit=limit, repo_scope=effective_scope)
        if fallback:
            return fallback
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.get('/api/v1/threads/{thread_id}', response_model=ThreadDetail)
def thread_detail(thread_id: str, _auth: None = Depends(require_auth)) -> ThreadDetail:
    try:
        detail = reader.get_thread_detail(thread_id)
        store.save_thread_detail(detail)
        return detail
    except KeyError as exc:
        fallback = store.load_thread_detail(thread_id)
        if fallback is not None:
            return fallback
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except FileNotFoundError as exc:
        fallback = store.load_thread_detail(thread_id)
        if fallback is not None:
            return fallback
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.get('/api/v1/threads/{thread_id}/events', response_model=list[ThreadEvent])
def thread_events(
    thread_id: str,
    limit: int = Query(default=400, ge=1, le=5000),
    _auth: None = Depends(require_auth),
) -> list[ThreadEvent]:
    try:
        return reader.get_thread_events(thread_id, limit=limit)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except FileNotFoundError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.websocket('/ws/v1/threads')
async def threads_ws(ws: WebSocket) -> None:
    if settings.watcher_auth_token:
        ws_token = ws.query_params.get('token')
        if ws_token != settings.watcher_auth_token:
            await ws.close(code=1008, reason='Invalid watcher token')
            return

    await ws.accept()
    last_signature = ''

    try:
        while True:
            try:
                rows = reader.list_threads(
                    limit=200,
                    hours=settings.retention_hours,
                    repo_scope=settings.repo_scope,
                )
                store.save_threads(rows)
            except FileNotFoundError:
                rows = store.load_threads(limit=200, repo_scope=settings.repo_scope)

            signature = '|'.join(
                f'{row.id}:{row.updatedAt}:{row.status}:{row.errorCount}:{row.messageCount}'
                for row in rows
            )
            if signature != last_signature:
                event = ThreadsSnapshotEvent(at=datetime.now(UTC).isoformat(), data=rows)
                await ws.send_text(event.model_dump_json())
                last_signature = signature
            await asyncio.sleep(1.5)
    except WebSocketDisconnect:
        return
    except Exception as exc:  # pragma: no cover
        await ws.send_text(json.dumps({'type': 'error', 'message': str(exc)}))
        await ws.close()
