from pathlib import Path

from codex_watcher.reader import CodexReader
from codex_watcher.settings import Settings


def _fixture_settings() -> Settings:
    codex_home = Path(__file__).parent / 'fixtures' / 'codex_home'
    return Settings(
        codex_home=codex_home,
        retention_hours=48,
        active_window_seconds=120,
        repo_scope='/repo/fixture',
        persistence_db_path=codex_home / 'watcher-test.db',
        watcher_auth_token=None,
    )


def test_list_threads() -> None:
    reader = CodexReader(_fixture_settings())
    rows = reader.list_threads(limit=10, hours=48)

    assert len(rows) == 2
    assert rows[0].id == 'thread-2'
    assert rows[0].status == 'running'
    assert rows[0].runningCommandCount == 1
    assert rows[0].approvalPendingCount == 1
    assert rows[0].planTotalSteps == 2
    assert rows[0].planCompletedSteps == 0
    assert rows[1].id == 'thread-1'
    assert rows[1].status == 'completed'


def test_get_thread_detail_extracts_artifacts_and_tools() -> None:
    reader = CodexReader(_fixture_settings())
    detail = reader.get_thread_detail('thread-1')

    assert detail.summary.errorCount == 0
    assert len(detail.toolCalls) == 1
    assert detail.toolCalls[0].name == 'exec_command'
    assert len(detail.artifacts) >= 1
    assert detail.artifacts[0].path.startswith('/')


def test_thread_events() -> None:
    reader = CodexReader(_fixture_settings())
    events = reader.get_thread_events('thread-1', limit=20)

    assert len(events) >= 3
    assert any(event.type == 'message' for event in events)
    assert any(event.type == 'tool' for event in events)


def test_pending_command_and_plan() -> None:
    reader = CodexReader(_fixture_settings())
    detail = reader.get_thread_detail('thread-2')

    assert detail.plan is not None
    assert detail.plan.total == 2
    assert detail.summary.runningCommandCount == 1
    assert detail.summary.approvalPendingCount == 1
    pending_calls = [call for call in detail.toolCalls if call.pending]
    assert len(pending_calls) == 2
    assert any(call.name == 'exec_command' and call.needsApproval for call in pending_calls)
