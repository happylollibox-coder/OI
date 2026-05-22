import { describe, it, expect } from 'vitest'
import { fmt, fM, fK, fP, fR, fShort, fCpc, getWeekStart, weekRangeLabel, formatDateRange } from './utils'

describe('fmt', () => {
  it('formats numbers with locale separators', () => {
    expect(fmt(1234567)).toBe('1,234,567')
    expect(fmt(1234.5, 2)).toBe('1,234.50')
  })
  it('returns -- for null/undefined', () => {
    expect(fmt(null)).toBe('--')
    expect(fmt(undefined)).toBe('--')
  })
})

describe('fM (money)', () => {
  it('formats as dollar amount', () => {
    expect(fM(1234.5)).toBe('$1,234.50')
    expect(fM(0)).toBe('$0.00')
  })
  it('returns -- for null', () => {
    expect(fM(null)).toBe('--')
  })
})

describe('fK (compact money)', () => {
  it('formats thousands as K', () => {
    expect(fK(5000)).toBe('$5.0K')
    expect(fK(12345)).toBe('$12.3K')
  })
  it('keeps small values as-is', () => {
    expect(fK(500)).toBe('$500')
  })
  it('returns -- for null', () => {
    expect(fK(null)).toBe('--')
  })
})

describe('fP (percent)', () => {
  it('formats with one decimal', () => {
    expect(fP(75.5)).toBe('75.5%')
    expect(fP(0)).toBe('0.0%')
  })
})

describe('fR (ROAS)', () => {
  it('formats as multiplier', () => {
    expect(fR(2.5)).toBe('2.50x')
  })
})

describe('fShort', () => {
  it('formats millions', () => {
    expect(fShort(1500000)).toBe('1.5M')
  })
  it('formats thousands', () => {
    expect(fShort(2500)).toBe('2.5K')
  })
  it('formats small numbers', () => {
    expect(fShort(42)).toBe('42')
    expect(fShort(3.14)).toBe('3.1')
  })
  it('returns empty for null', () => {
    expect(fShort(null)).toBe('')
  })
})

describe('fCpc', () => {
  it('formats cost per click', () => {
    expect(fCpc(1.23)).toBe('$1.23/click')
  })
})

describe('getWeekStart', () => {
  it('returns Sunday for a Wednesday', () => {
    // 2026-04-08 is Wednesday → Sunday is 2026-04-05
    expect(getWeekStart('2026-04-08')).toBe('2026-04-05')
  })
  it('returns same day for a Sunday', () => {
    expect(getWeekStart('2026-04-05')).toBe('2026-04-05')
  })
  it('handles Saturday', () => {
    // 2026-04-11 is Saturday → Sunday is 2026-04-05
    expect(getWeekStart('2026-04-11')).toBe('2026-04-05')
  })
})

describe('weekRangeLabel', () => {
  it('formats a week range', () => {
    expect(weekRangeLabel('2026-04-05')).toBe('Apr 5 – Apr 11')
  })
  it('returns empty for empty input', () => {
    expect(weekRangeLabel('')).toBe('')
  })
})

describe('formatDateRange', () => {
  it('formats start-end range', () => {
    expect(formatDateRange('2026-03-29', '2026-04-04')).toBe('Mar 29 – Apr 4')
  })
  it('returns empty for missing dates', () => {
    expect(formatDateRange()).toBe('')
  })
})
