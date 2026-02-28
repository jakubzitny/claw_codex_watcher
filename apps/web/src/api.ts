import type { ThreadDetail, ThreadSummary, ThreadsSnapshotEvent } from './types'

declare const __WATCHER_API_BASE__: string | undefined
declare const __WATCHER_WS_BASE__: string | undefined
declare const __WATCHER_TOKEN__: string | undefined

const API_BASE =
  typeof __WATCHER_API_BASE__ !== 'undefined' && __WATCHER_API_BASE__
    ? __WATCHER_API_BASE__
    : '/api/v1'
const WS_BASE =
  typeof __WATCHER_WS_BASE__ !== 'undefined' && __WATCHER_WS_BASE__ ? __WATCHER_WS_BASE__ : ''
const WATCHER_TOKEN =
  typeof __WATCHER_TOKEN__ !== 'undefined' && __WATCHER_TOKEN__ ? __WATCHER_TOKEN__ : ''

const authHeaders = (): HeadersInit => {
  if (!WATCHER_TOKEN) return {}
  return { 'x-watcher-token': WATCHER_TOKEN }
}

export const fetchThreads = async (): Promise<ThreadSummary[]> => {
  const response = await fetch(`${API_BASE}/threads`, {
    headers: authHeaders(),
  })
  if (!response.ok) {
    throw new Error(`Failed to load threads: ${response.status}`)
  }
  return (await response.json()) as ThreadSummary[]
}

export const fetchThreadDetail = async (threadId: string): Promise<ThreadDetail> => {
  const response = await fetch(`${API_BASE}/threads/${threadId}`, {
    headers: authHeaders(),
  })
  if (!response.ok) {
    throw new Error(`Failed to load thread ${threadId}: ${response.status}`)
  }
  return (await response.json()) as ThreadDetail
}

const socketUrl = (): string => {
  const query = WATCHER_TOKEN ? `?token=${encodeURIComponent(WATCHER_TOKEN)}` : ''
  if (WS_BASE) {
    return `${WS_BASE}/ws/v1/threads${query}`
  }
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
  return `${protocol}//${window.location.host}/ws/v1/threads${query}`
}

export const connectThreadsSocket = (
  onData: (event: ThreadsSnapshotEvent) => void,
  onMalformedPayload: (error: string) => void,
): WebSocket => {
  const socket = new WebSocket(socketUrl())

  socket.onmessage = (message) => {
    try {
      const payload = JSON.parse(message.data as string) as ThreadsSnapshotEvent
      if (payload.type === 'threads_snapshot') {
        onData(payload)
      }
    } catch (error) {
      onMalformedPayload(`Malformed socket payload: ${String(error)}`)
    }
  }

  return socket
}
