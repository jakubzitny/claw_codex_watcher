import { shortTitle } from './index'

describe('shortTitle', () => {
  it('returns short titles unchanged', () => {
    expect(shortTitle('abc')).toBe('abc')
  })

  it('trims and truncates long titles', () => {
    const input = 'x'.repeat(200)
    expect(shortTitle(input)).toHaveLength(88)
    expect(shortTitle(input).endsWith('...')).toBe(true)
  })
})
