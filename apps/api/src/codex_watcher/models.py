from __future__ import annotations

from typing import Literal

from pydantic import BaseModel

ThreadStatus = Literal['running', 'thinking', 'completed', 'waiting', 'failed']
MessageRole = Literal['user', 'assistant', 'developer']


class ThreadSummary(BaseModel):
    id: str
    title: str
    shortTitle: str
    cwd: str
    source: str
    modelProvider: str
    createdAt: str
    updatedAt: str
    archived: bool
    status: ThreadStatus
    messageCount: int
    toolCallCount: int
    errorCount: int
    artifactCount: int
    runningCommandCount: int
    approvalPendingCount: int
    planTotalSteps: int
    planCompletedSteps: int


class ThreadMessage(BaseModel):
    id: str
    timestamp: str
    role: MessageRole
    phase: str | None = None
    text: str


class ToolCall(BaseModel):
    id: str
    timestamp: str
    name: str
    argumentsPreview: str
    outputPreview: str | None = None
    exitCode: int | None = None
    errored: bool
    pending: bool
    needsApproval: bool


class Artifact(BaseModel):
    id: str
    timestamp: str
    path: str
    exists: bool


class PlanStep(BaseModel):
    step: str
    status: str


class PlanProgress(BaseModel):
    updatedAt: str
    total: int
    completed: int
    inProgress: int
    pending: int
    steps: list[PlanStep]


class ThreadDetail(BaseModel):
    summary: ThreadSummary
    messages: list[ThreadMessage]
    toolCalls: list[ToolCall]
    artifacts: list[Artifact]
    plan: PlanProgress | None = None


class ThreadEvent(BaseModel):
    timestamp: str
    type: str
    subtype: str | None = None
    summary: str


class ThreadsSnapshotEvent(BaseModel):
    type: Literal['threads_snapshot'] = 'threads_snapshot'
    at: str
    data: list[ThreadSummary]
