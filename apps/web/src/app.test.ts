import { formatTime, statusClass } from './app'

describe('statusClass', () => {
  it('maps statuses to css classes', () => {
    expect(statusClass('running')).toBe('is-running')
    expect(statusClass('thinking')).toBe('is-thinking')
    expect(statusClass('completed')).toBe('is-completed')
    expect(statusClass('waiting')).toBe('is-waiting')
    expect(statusClass('failed')).toBe('is-failed')
  })
})

describe('formatTime', () => {
  it('returns unknown for invalid dates', () => {
    expect(formatTime('bad-value')).toBe('unknown')
  })

  it('formats valid timestamps', () => {
    const rendered = formatTime('2026-02-28T12:00:00Z')
    expect(rendered).toMatch(/\d{2}:\d{2}:\d{2}/)
  })
})
