import { useEffect, useMemo, useState } from 'react'

import { connectThreadsSocket, fetchThreadDetail, fetchThreads } from './api'
import type { PlanProgress, ThreadDetail, ThreadSummary, ToolCall } from './types'

const formatTime = (iso: string): string => {
  const value = new Date(iso)
  if (Number.isNaN(value.getTime())) {
    return 'unknown'
  }
  return value.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })
}

const formatAge = (iso: string): string => {
  const value = new Date(iso)
  if (Number.isNaN(value.getTime())) {
    return ''
  }
  const deltaMs = Date.now() - value.getTime()
  const minutes = Math.max(0, Math.floor(deltaMs / 60_000))
  if (minutes < 1) return 'now'
  if (minutes < 60) return `${minutes}m`
  const hours = Math.floor(minutes / 60)
  return `${hours}h`
}

const statusClass = (status: ThreadSummary['status']): string => {
  if (status === 'running') return 'is-running'
  if (status === 'thinking') return 'is-thinking'
  if (status === 'completed') return 'is-completed'
  if (status === 'failed') return 'is-failed'
  return 'is-waiting'
}

type TimelineItem =
  | {
      id: string
      timestamp: string
      kind: 'message'
      message: ThreadDetail['messages'][number]
    }
  | {
      id: string
      timestamp: string
      kind: 'command'
      call: ToolCall
    }

const commandStateLabel = (call: ToolCall): string => {
  if (call.pending && call.needsApproval) return 'needs approval'
  if (call.pending) return 'running'
  if (call.errored) return 'failed'
  return 'done'
}

const planPercent = (plan: PlanProgress): number => {
  if (plan.total === 0) return 0
  return Math.round((plan.completed / plan.total) * 100)
}

export const App = () => {
  const [threads, setThreads] = useState<ThreadSummary[]>([])
  const [selectedThreadId, setSelectedThreadId] = useState<string | null>(null)
  const [detail, setDetail] = useState<ThreadDetail | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    let socket: WebSocket | null = null
    let reconnectTimer: number | null = null
    let closedByApp = false
    let reconnectAttempt = 0

    const load = async () => {
      try {
        const data = await fetchThreads()
        setThreads(data)
      } catch (err) {
        setError(String(err))
      }
    }

    const clearReconnectTimer = () => {
      if (reconnectTimer === null) return
      window.clearTimeout(reconnectTimer)
      reconnectTimer = null
    }

    const connectSocket = () => {
      socket = connectThreadsSocket(
        (event) => {
          setThreads(event.data)
        },
        (message) => {
          setError(message)
        },
      )

      socket.onopen = () => {
        reconnectAttempt = 0
        setError((prev) => {
          if (prev === 'Live updates disconnected. Reconnecting...') return null
          return prev
        })
      }

      socket.onclose = () => {
        if (closedByApp) return

        setError('Live updates disconnected. Reconnecting...')
        clearReconnectTimer()
        const delay = Math.min(4_000, 400 * 2 ** reconnectAttempt)
        reconnectAttempt += 1
        reconnectTimer = window.setTimeout(() => {
          connectSocket()
        }, delay)
      }
    }

    load().catch((err) => setError(String(err)))
    connectSocket()

    return () => {
      closedByApp = true
      clearReconnectTimer()
      socket?.close()
    }
  }, [])

  useEffect(() => {
    if (!selectedThreadId && threads.length > 0) {
      setSelectedThreadId(threads[0].id)
      return
    }
    if (
      selectedThreadId &&
      !threads.some((thread) => thread.id === selectedThreadId) &&
      threads.length > 0
    ) {
      setSelectedThreadId(threads[0].id)
    }
  }, [threads, selectedThreadId])

  const selectedSummary = useMemo(() => {
    if (!selectedThreadId) return null
    return threads.find((thread) => thread.id === selectedThreadId) ?? null
  }, [threads, selectedThreadId])

  useEffect(() => {
    if (!selectedThreadId) {
      setDetail(null)
      return
    }

    if (
      detail &&
      selectedSummary &&
      detail.summary.id === selectedSummary.id &&
      detail.summary.updatedAt === selectedSummary.updatedAt
    ) {
      return
    }

    let isMounted = true
    setLoading(true)

    fetchThreadDetail(selectedThreadId)
      .then((payload) => {
        if (!isMounted) return
        setDetail(payload)
      })
      .catch((err) => {
        if (!isMounted) return
        setError(String(err))
      })
      .finally(() => {
        if (!isMounted) return
        setLoading(false)
      })

    return () => {
      isMounted = false
    }
  }, [detail, selectedSummary, selectedThreadId])

  const timeline = useMemo(() => {
    if (!detail) return []

    const items: TimelineItem[] = [
      ...detail.messages.map((message) => ({
        id: message.id,
        timestamp: message.timestamp,
        kind: 'message' as const,
        message,
      })),
      ...detail.toolCalls.map((call) => ({
        id: call.id,
        timestamp: call.timestamp,
        kind: 'command' as const,
        call,
      })),
    ]

    items.sort((left, right) => right.timestamp.localeCompare(left.timestamp))
    return items
  }, [detail])

  const pendingCalls = useMemo(() => {
    if (!detail) return []
    return detail.toolCalls.filter((call) => call.pending && call.name !== 'update_plan')
  }, [detail])

  const repoScopeLabel = useMemo(() => {
    const cwd = threads[0]?.cwd
    if (!cwd) return 'current repo'
    const parts = cwd.split('/').filter(Boolean)
    return parts[parts.length - 1] ?? cwd
  }, [threads])

  return (
    <div className="app-shell">
      <aside className="left-rail">
        <div className="rail-actions">
          <button type="button" disabled>
            New thread
          </button>
          <button type="button" disabled>
            Automations
          </button>
          <button type="button" disabled>
            Skills
          </button>
        </div>

        <section className="thread-nav">
          <div className="thread-nav-header">
            <h2>Threads</h2>
            <span>repo: {repoScopeLabel}</span>
          </div>

          <ul className="thread-list" data-testid="thread-list">
            {threads.map((thread) => (
              <li key={thread.id}>
                <button
                  type="button"
                  className={`thread-row ${thread.id === selectedThreadId ? 'active' : ''}`}
                  onClick={() => setSelectedThreadId(thread.id)}
                >
                  <div className="thread-row-top">
                    <span className={`status-dot ${statusClass(thread.status)}`} />
                    <strong>{thread.shortTitle}</strong>
                  </div>
                  <div className="thread-row-meta">
                    <span>{formatAge(thread.updatedAt)}</span>
                    {thread.planTotalSteps > 0 ? (
                      <span>{`plan ${thread.planCompletedSteps}/${thread.planTotalSteps}`}</span>
                    ) : null}
                    {thread.runningCommandCount > 0 ? (
                      <span>{`cmd ${thread.runningCommandCount}`}</span>
                    ) : null}
                    {thread.approvalPendingCount > 0 ? (
                      <span className="warn">approval</span>
                    ) : null}
                  </div>
                </button>
              </li>
            ))}
          </ul>
        </section>

        <div className="rail-footer">Settings</div>
      </aside>

      <main className="center-pane">
        <header className="topbar">
          <div>
            <h1>{selectedSummary?.shortTitle ?? 'No thread selected'}</h1>
            <p>{selectedSummary?.cwd ?? 'Select a thread from the sidebar.'}</p>
          </div>
          {selectedSummary ? (
            <div className="topbar-flags">
              <span className={`chip ${statusClass(selectedSummary.status)}`}>
                {selectedSummary.status}
              </span>
              {selectedSummary.approvalPendingCount > 0 ? (
                <span className="chip chip-plain warn">approval required</span>
              ) : null}
            </div>
          ) : null}
        </header>

        <section className="stream">
          {error ? <p className="error-banner">{error}</p> : null}
          {!selectedSummary ? <p className="empty">No threads in this repo scope.</p> : null}

          {selectedSummary ? (
            <>
              {detail?.plan ? (
                <article className="system-box">
                  <h3>Plan Progress</h3>
                  <p>{`${detail.plan.completed}/${detail.plan.total} completed (${planPercent(detail.plan)}%)`}</p>
                  <div className="plan-bar" aria-hidden="true">
                    <span style={{ width: `${planPercent(detail.plan)}%` }} />
                  </div>
                  <ul>
                    {detail.plan.steps.map((step, index) => (
                      <li key={`${step.step}-${index}`}>
                        <span className="step-status">{step.status}</span>
                        <span>{step.step}</span>
                      </li>
                    ))}
                  </ul>
                </article>
              ) : null}

              {pendingCalls.length > 0 ? (
                <article className="system-box">
                  <h3>Command Activity</h3>
                  <p>{`${pendingCalls.length} running command(s)`}</p>
                  <ul>
                    {pendingCalls.map((call) => (
                      <li key={call.id}>
                        <span className="step-status">{commandStateLabel(call)}</span>
                        <span>{call.name}</span>
                      </li>
                    ))}
                  </ul>
                </article>
              ) : null}

              <section className="conversation">
                <h3>Conversation</h3>
                {loading && !detail ? <p>Loading...</p> : null}
                {timeline.map((item) => {
                  if (item.kind === 'message') {
                    return (
                      <article key={item.id} className={`entry message role-${item.message.role}`}>
                        <header>
                          <strong>{item.message.role}</strong>
                          <span>{formatTime(item.message.timestamp)}</span>
                          {item.message.phase ? <em>{item.message.phase}</em> : null}
                        </header>
                        <pre>{item.message.text}</pre>
                      </article>
                    )
                  }

                  return (
                    <article key={item.id} className="entry command">
                      <header>
                        <strong>{item.call.name}</strong>
                        <span>{formatTime(item.call.timestamp)}</span>
                        <em className={item.call.needsApproval ? 'warn' : ''}>
                          {commandStateLabel(item.call)}
                        </em>
                      </header>
                      <pre>{item.call.argumentsPreview || '(no arguments)'}</pre>
                      {item.call.outputPreview ? <pre>{item.call.outputPreview}</pre> : null}
                    </article>
                  )
                })}
              </section>
            </>
          ) : null}
        </section>

        <footer className="composer-shell">
          <div className="composer-box">
            <textarea readOnly value="Read-only watcher. Open Codex desktop to send messages." />
            <div className="composer-meta">
              <span>GPT-5.3-Codex</span>
              <span>Read-only monitor</span>
            </div>
          </div>
        </footer>
      </main>
    </div>
  )
}

export { formatTime, statusClass }
