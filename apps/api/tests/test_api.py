import importlib
import os
from pathlib import Path

from fastapi.testclient import TestClient


def _make_client(
    *,
    codex_home: Path | None = None,
    repo_scope: str = '/repo/fixture',
    watcher_auth_token: str = '',
    persistence_db_name: str = 'watcher-test.db',
) -> TestClient:
    fixture_home = Path(__file__).parent / 'fixtures' / 'codex_home'
    os.environ['CODEX_HOME'] = str(codex_home or fixture_home)
    os.environ['REPO_SCOPE'] = repo_scope
    os.environ['WATCHER_AUTH_TOKEN'] = watcher_auth_token
    os.environ['PERSISTENCE_DB_PATH'] = str(fixture_home / persistence_db_name)

    import codex_watcher.main as main

    importlib.reload(main)
    return TestClient(main.app)


def test_health() -> None:
    client = _make_client()
    response = client.get('/api/v1/health')

    assert response.status_code == 200
    data = response.json()
    assert data['status'] == 'ok'
    assert data['authEnabled'] == 'false'


def test_threads_endpoint() -> None:
    client = _make_client()
    response = client.get('/api/v1/threads?hours=48')

    assert response.status_code == 200
    payload = response.json()
    assert len(payload) == 2
    assert payload[0]['id'] == 'thread-2'


def test_thread_detail_endpoint() -> None:
    client = _make_client()
    response = client.get('/api/v1/threads/thread-1')

    assert response.status_code == 200
    payload = response.json()
    assert payload['summary']['id'] == 'thread-1'
    assert len(payload['messages']) >= 2
    assert len(payload['toolCalls']) == 1


def test_plan_and_pending_command_are_exposed() -> None:
    client = _make_client()
    response = client.get('/api/v1/threads/thread-2')

    assert response.status_code == 200
    payload = response.json()
    assert payload['summary']['runningCommandCount'] == 1
    assert payload['summary']['approvalPendingCount'] == 1
    assert payload['plan']['total'] == 2
    pending = [call for call in payload['toolCalls'] if call['pending']]
    assert len(pending) >= 1


def test_optional_auth_token() -> None:
    client = _make_client(watcher_auth_token='secret-token', persistence_db_name='watcher-test-auth.db')

    unauthorized = client.get('/api/v1/threads?hours=48')
    assert unauthorized.status_code == 401

    authorized = client.get('/api/v1/threads?hours=48', headers={'x-watcher-token': 'secret-token'})
    assert authorized.status_code == 200


def test_persistence_fallback_when_codex_home_unavailable() -> None:
    fixture_home = Path(__file__).parent / 'fixtures' / 'codex_home'
    warm_client = _make_client(
        codex_home=fixture_home,
        watcher_auth_token='',
        persistence_db_name='watcher-test-fallback.db',
    )
    warm_response = warm_client.get('/api/v1/threads?hours=48')
    assert warm_response.status_code == 200
    assert len(warm_response.json()) == 2

    cold_client = _make_client(
        codex_home=fixture_home / 'missing-codex-home',
        watcher_auth_token='',
        persistence_db_name='watcher-test-fallback.db',
    )
    cold_response = cold_client.get('/api/v1/threads?hours=48')
    assert cold_response.status_code == 200
    assert len(cold_response.json()) == 2
