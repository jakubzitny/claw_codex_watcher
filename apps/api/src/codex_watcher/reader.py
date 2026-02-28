from __future__ import annotations

import json
import re
import sqlite3
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from .models import (
    Artifact,
    PlanProgress,
    PlanStep,
    ThreadDetail,
    ThreadEvent,
    ThreadMessage,
    ThreadSummary,
    ToolCall,
)
from .settings import Settings

EXIT_CODE_RE = re.compile(r'Process exited with code\s+(\d+)')
ABS_PATH_RE = re.compile(r'(/[^\s"\'`]+)')
PLAN_STATUSES = {'pending', 'in_progress', 'thinking', 'completed'}


@dataclass
class ParsedThread:
    summary: ThreadSummary
    messages: list[ThreadMessage]
    tool_calls: list[ToolCall]
    artifacts: list[Artifact]
    events: list[ThreadEvent]
    plan: PlanProgress | None


def _ts_to_iso(ts: int | float | None) -> str:
    if not ts:
        return datetime.now(UTC).isoformat()
    return datetime.fromtimestamp(float(ts), tz=UTC).isoformat()


def _short_title(text: str) -> str:
    clean = ' '.join(text.split())
    if len(clean) <= 88:
        return clean
    return f'{clean[:85]}...'


def _flatten_message_content(payload: dict[str, Any]) -> str:
    content = payload.get('content')
    if not isinstance(content, list):
        return ''
    chunks: list[str] = []
    for entry in content:
        if not isinstance(entry, dict):
            continue
        text = entry.get('text')
        if isinstance(text, str) and text.strip():
            chunks.append(text.strip())
    return '\n\n'.join(chunks)


def _extract_exit_code(output: str | None) -> int | None:
    if not output:
        return None
    match = EXIT_CODE_RE.search(output)
    if not match:
        return None
    return int(match.group(1))


def _extract_artifacts(text: str, timestamp: str, seed: str) -> list[Artifact]:
    seen: set[str] = set()
    results: list[Artifact] = []

    for match in ABS_PATH_RE.findall(text):
        if len(match) < 3 or not match.startswith('/'):
            continue
        path = match.rstrip('.,:;)]}')
        if path in seen:
            continue
        seen.add(path)
        results.append(
            Artifact(
                id=f'{seed}:{len(results)}',
                timestamp=timestamp,
                path=path,
                exists=Path(path).exists(),
            )
        )

    return results


def _parse_json(text: str | None) -> dict[str, Any] | None:
    if not isinstance(text, str) or not text.strip():
        return None
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    return payload


def _needs_approval(arguments: str | None) -> bool:
    payload = _parse_json(arguments)
    if payload is None:
        return False
    return payload.get('sandbox_permissions') == 'require_escalated'


def _extract_plan(arguments: str | None) -> list[PlanStep] | None:
    payload = _parse_json(arguments)
    if payload is None:
        return None

    raw_plan = payload.get('plan')
    if not isinstance(raw_plan, list):
        return None

    steps: list[PlanStep] = []
    for item in raw_plan:
        if not isinstance(item, dict):
            continue
        step = str(item.get('step') or '').strip()
        if not step:
            continue
        raw_status = str(item.get('status') or 'pending').strip().lower()
        status = raw_status if raw_status in PLAN_STATUSES else 'pending'
        steps.append(PlanStep(step=step, status=status))

    if not steps:
        return None
    return steps


class CodexReader:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.state_db = self.settings.codex_home / 'state_5.sqlite'

    def _connect(self) -> sqlite3.Connection:
        if not self.state_db.exists():
            raise FileNotFoundError(f'Codex state db was not found at {self.state_db}')
        conn = sqlite3.connect(self.state_db)
        conn.row_factory = sqlite3.Row
        return conn

    def list_threads(
        self,
        limit: int = 100,
        hours: int | None = None,
        repo_scope: str | None = None,
    ) -> list[ThreadSummary]:
        retention_hours = hours if hours is not None else self.settings.retention_hours
        cutoff = int(datetime.now(UTC).timestamp()) - retention_hours * 3600
        effective_scope = self.settings.repo_scope if repo_scope is None else repo_scope

        with self._connect() as conn:
            if effective_scope:
                rows = conn.execute(
                    """
                    SELECT id, title, cwd, source, model_provider, created_at, updated_at, archived, rollout_path
                    FROM threads
                    WHERE updated_at >= ?
                      AND (cwd = ? OR cwd LIKE ?)
                    ORDER BY updated_at DESC
                    LIMIT ?
                    """,
                    (cutoff, effective_scope, f'{effective_scope}/%', limit),
                ).fetchall()
            else:
                rows = conn.execute(
                    """
                    SELECT id, title, cwd, source, model_provider, created_at, updated_at, archived, rollout_path
                    FROM threads
                    WHERE updated_at >= ?
                    ORDER BY updated_at DESC
                    LIMIT ?
                    """,
                    (cutoff, limit),
                ).fetchall()

        summaries: list[ThreadSummary] = []
        for row in rows:
            parsed = self._parse_thread_row(row, include_details=False)
            summaries.append(parsed.summary)

        return summaries

    def get_thread_detail(self, thread_id: str) -> ThreadDetail:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT id, title, cwd, source, model_provider, created_at, updated_at, archived, rollout_path
                FROM threads
                WHERE id = ?
                """,
                (thread_id,),
            ).fetchone()

        if row is None:
            raise KeyError(f'Thread {thread_id} does not exist')

        parsed = self._parse_thread_row(row, include_details=True)
        return ThreadDetail(
            summary=parsed.summary,
            messages=parsed.messages,
            toolCalls=parsed.tool_calls,
            artifacts=parsed.artifacts,
            plan=parsed.plan,
        )

    def get_thread_events(self, thread_id: str, limit: int = 400) -> list[ThreadEvent]:
        detail = self.get_thread_detail(thread_id)

        timeline: list[ThreadEvent] = []
        for msg in detail.messages:
            timeline.append(
                ThreadEvent(
                    timestamp=msg.timestamp,
                    type='message',
                    subtype=msg.role,
                    summary=_short_title(msg.text),
                )
            )

        for call in detail.toolCalls:
            suffix = f' (exit {call.exitCode})' if call.exitCode is not None else ''
            timeline.append(
                ThreadEvent(
                    timestamp=call.timestamp,
                    type='tool',
                    subtype=call.name,
                    summary=f'{call.name}{suffix}',
                )
            )

        for artifact in detail.artifacts:
            timeline.append(
                ThreadEvent(
                    timestamp=artifact.timestamp,
                    type='artifact',
                    subtype='file',
                    summary=artifact.path,
                )
            )

        timeline.sort(key=lambda item: item.timestamp)
        return timeline[-limit:]

    def _parse_thread_row(self, row: sqlite3.Row, include_details: bool) -> ParsedThread:
        rollout_path = Path(row['rollout_path'])
        if not rollout_path.is_absolute():
            rollout_path = self.settings.codex_home / rollout_path

        messages: list[ThreadMessage] = []
        calls_by_id: dict[str, ToolCall] = {}
        pending_call_ids: set[str] = set()
        artifacts: list[Artifact] = []
        latest_plan_steps: list[PlanStep] | None = None
        latest_plan_updated_at: str | None = None

        if rollout_path.exists():
            with rollout_path.open('r', encoding='utf-8') as handle:
                for index, line in enumerate(handle):
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        event = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    if event.get('type') != 'response_item':
                        continue

                    payload = event.get('payload')
                    if not isinstance(payload, dict):
                        continue

                    timestamp = event.get('timestamp') or _ts_to_iso(row['updated_at'])
                    payload_type = payload.get('type')

                    if payload_type == 'message':
                        role = payload.get('role')
                        if role not in {'assistant', 'user', 'developer'}:
                            continue
                        text = _flatten_message_content(payload)
                        if not text:
                            continue
                        message = ThreadMessage(
                            id=f'msg-{index}',
                            timestamp=timestamp,
                            role=role,
                            phase=payload.get('phase'),
                            text=text,
                        )
                        messages.append(message)

                    elif payload_type == 'function_call':
                        call_id = payload.get('call_id') or f'call-{index}'
                        arguments = payload.get('arguments')
                        arguments_str = arguments if isinstance(arguments, str) else str(arguments or '')
                        name = str(payload.get('name') or 'tool')
                        needs_approval = _needs_approval(arguments_str)
                        call = ToolCall(
                            id=call_id,
                            timestamp=timestamp,
                            name=name,
                            argumentsPreview=arguments_str[:500],
                            outputPreview=None,
                            exitCode=None,
                            errored=False,
                            pending=True,
                            needsApproval=needs_approval,
                        )
                        calls_by_id[call_id] = call
                        pending_call_ids.add(call_id)
                        if name == 'update_plan':
                            plan_steps = _extract_plan(arguments_str)
                            if plan_steps:
                                latest_plan_steps = plan_steps
                                latest_plan_updated_at = timestamp

                    elif payload_type == 'function_call_output':
                        call_id = payload.get('call_id')
                        if not isinstance(call_id, str):
                            continue
                        output_text = payload.get('output')
                        output_str = output_text if isinstance(output_text, str) else ''
                        exit_code = _extract_exit_code(output_str)
                        existing = calls_by_id.get(call_id)
                        if existing is None:
                            existing = ToolCall(
                                id=call_id,
                                timestamp=timestamp,
                                name='tool',
                                argumentsPreview='',
                                outputPreview=output_str[:500],
                                exitCode=exit_code,
                                errored=bool(exit_code and exit_code != 0),
                                pending=False,
                                needsApproval=False,
                            )
                            calls_by_id[call_id] = existing
                        else:
                            existing.outputPreview = output_str[:500]
                            existing.exitCode = exit_code
                            existing.errored = bool(exit_code and exit_code != 0)
                            existing.pending = False
                        pending_call_ids.discard(call_id)
                        artifacts.extend(_extract_artifacts(output_str, timestamp, f'artifact-{call_id}'))

        tool_calls = sorted(calls_by_id.values(), key=lambda item: item.timestamp)
        running_command_count = sum(
            1 for call in tool_calls if call.pending and call.name not in {'update_plan'}
        )
        approval_pending_count = sum(1 for call in tool_calls if call.pending and call.needsApproval)
        plan = self._to_plan_progress(latest_plan_steps, latest_plan_updated_at)
        status = self._derive_status(
            updated_at=row['updated_at'],
            messages=messages,
            tool_calls=tool_calls,
            has_pending_calls=bool(pending_call_ids),
        )

        summary = ThreadSummary(
            id=row['id'],
            title=row['title'],
            shortTitle=_short_title(row['title']),
            cwd=row['cwd'],
            source=row['source'],
            modelProvider=row['model_provider'],
            createdAt=_ts_to_iso(row['created_at']),
            updatedAt=_ts_to_iso(row['updated_at']),
            archived=bool(row['archived']),
            status=status,
            messageCount=len(messages),
            toolCallCount=len(tool_calls),
            errorCount=sum(1 for call in tool_calls if call.errored),
            artifactCount=len(artifacts),
            runningCommandCount=running_command_count,
            approvalPendingCount=approval_pending_count,
            planTotalSteps=plan.total if plan else 0,
            planCompletedSteps=plan.completed if plan else 0,
        )

        if include_details:
            events = self._build_events(messages, tool_calls, artifacts)
            return ParsedThread(
                summary=summary,
                messages=messages,
                tool_calls=tool_calls,
                artifacts=artifacts,
                events=events,
                plan=plan,
            )

        return ParsedThread(summary=summary, messages=[], tool_calls=[], artifacts=[], events=[], plan=None)

    def _derive_status(
        self,
        *,
        updated_at: int,
        messages: list[ThreadMessage],
        tool_calls: list[ToolCall],
        has_pending_calls: bool,
    ) -> str:
        now = int(datetime.now(UTC).timestamp())

        last_user = max((msg.timestamp for msg in messages if msg.role == 'user'), default='')
        last_assistant = max((msg.timestamp for msg in messages if msg.role == 'assistant'), default='')
        last_final = max(
            (msg.timestamp for msg in messages if msg.role == 'assistant' and msg.phase == 'final_answer'),
            default='',
        )

        has_error = any(call.errored for call in tool_calls)
        recent = now - int(updated_at) <= self.settings.active_window_seconds

        if has_error and not last_final:
            return 'failed'

        if has_pending_calls:
            return 'running'

        if recent and last_user and (not last_assistant or last_user >= last_assistant):
            return 'thinking'

        if recent:
            return 'running'

        if last_final and (not last_user or last_final >= last_user):
            return 'completed'

        if last_assistant and last_user and last_assistant >= last_user:
            return 'completed'

        return 'waiting'

    @staticmethod
    def _to_plan_progress(
        steps: list[PlanStep] | None, updated_at: str | None
    ) -> PlanProgress | None:
        if not steps:
            return None

        completed = sum(1 for step in steps if step.status == 'completed')
        in_progress = sum(1 for step in steps if step.status == 'in_progress')
        pending = sum(1 for step in steps if step.status == 'pending')
        return PlanProgress(
            updatedAt=updated_at or datetime.now(UTC).isoformat(),
            total=len(steps),
            completed=completed,
            inProgress=in_progress,
            pending=pending,
            steps=steps,
        )

    @staticmethod
    def _build_events(
        messages: list[ThreadMessage], tool_calls: list[ToolCall], artifacts: list[Artifact]
    ) -> list[ThreadEvent]:
        events: list[ThreadEvent] = []

        for msg in messages:
            events.append(
                ThreadEvent(
                    timestamp=msg.timestamp,
                    type='message',
                    subtype=msg.role,
                    summary=_short_title(msg.text),
                )
            )

        for call in tool_calls:
            result = f'exit={call.exitCode}' if call.exitCode is not None else 'pending'
            events.append(
                ThreadEvent(
                    timestamp=call.timestamp,
                    type='tool',
                    subtype=call.name,
                    summary=f'{call.name} {result}',
                )
            )

        for item in artifacts:
            events.append(
                ThreadEvent(
                    timestamp=item.timestamp,
                    type='artifact',
                    subtype='file',
                    summary=item.path,
                )
            )

        events.sort(key=lambda event: event.timestamp)
        return events
