export type ThreadStatus = 'running' | 'thinking' | 'completed' | 'waiting' | 'failed'

export type ThreadSummary = {
  id: string
  title: string
  shortTitle: string
  cwd: string
  source: string
  modelProvider: string
  createdAt: string
  updatedAt: string
  archived: boolean
  status: ThreadStatus
  messageCount: number
  toolCallCount: number
  errorCount: number
  artifactCount: number
  runningCommandCount: number
  approvalPendingCount: number
  planTotalSteps: number
  planCompletedSteps: number
}

export type ThreadMessage = {
  id: string
  timestamp: string
  role: 'user' | 'assistant' | 'developer'
  phase?: string
  text: string
}

export type ToolCall = {
  id: string
  timestamp: string
  name: string
  argumentsPreview: string
  outputPreview?: string
  exitCode?: number
  errored: boolean
  pending: boolean
  needsApproval: boolean
}

export type Artifact = {
  id: string
  timestamp: string
  path: string
  exists: boolean
}

export type ThreadDetail = {
  summary: ThreadSummary
  messages: ThreadMessage[]
  toolCalls: ToolCall[]
  artifacts: Artifact[]
  plan?: PlanProgress | null
}

export type PlanStep = {
  step: string
  status: string
}

export type PlanProgress = {
  updatedAt: string
  total: number
  completed: number
  inProgress: number
  pending: number
  steps: PlanStep[]
}

export type ThreadsSnapshotEvent = {
  type: 'threads_snapshot'
  at: string
  data: ThreadSummary[]
}
