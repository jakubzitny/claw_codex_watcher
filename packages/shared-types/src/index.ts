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
}

export type ThreadsSnapshotEvent = {
  type: 'threads_snapshot'
  at: string
  data: ThreadSummary[]
}

export const shortTitle = (title: string): string => {
  const clean = title.replace(/\s+/g, ' ').trim()
  if (clean.length <= 88) return clean
  return `${clean.slice(0, 85)}...`
}
