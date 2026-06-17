import { describe, it, expect } from 'vitest';
import { periodDayCount } from './utils';

describe('periodDayCount', () => {
  const WM = '2026-06-15'; // orders watermark

  it('completed week → full 7 days', () => {
    expect(periodDayCount('2026-06-07', 'weeks', WM)).toBe(7); // ends Jun 13 < Jun 15
  });

  it('in-progress week → elapsed days through watermark, inclusive', () => {
    expect(periodDayCount('2026-06-14', 'weeks', WM)).toBe(2); // Jun 14–15
  });

  it('no watermark → full calendar length', () => {
    expect(periodDayCount('2026-06-14', 'weeks')).toBe(7);
  });

  it('completed month → its full day count', () => {
    expect(periodDayCount('2026-05', 'month', WM)).toBe(31); // May ends before watermark
  });

  it('in-progress month → elapsed days through watermark', () => {
    expect(periodDayCount('2026-06', 'month', WM)).toBe(15); // Jun 1–15
  });

  it('in-progress quarter → elapsed days through watermark', () => {
    // Q2 = Apr(30) + May(31) + Jun 1–15(15) = 76
    expect(periodDayCount('2026-Q2', 'quarter', WM)).toBe(76);
  });

  it('completed quarter → full length', () => {
    // Q1 2026 = 31 + 28 + 31 = 90
    expect(periodDayCount('2026-Q1', 'quarter', WM)).toBe(90);
  });

  it('in-progress year → elapsed days through watermark', () => {
    // 2026 (non-leap) Jan1–Jun15 = 31+28+31+30+31+15 = 166
    expect(periodDayCount('2026', 'year', WM)).toBe(166);
  });

  it('date mode / empty / future period → at least 1', () => {
    expect(periodDayCount('2026-06-16', 'date', WM)).toBe(1);
    expect(periodDayCount('', 'weeks', WM)).toBe(1);
    // watermark before period start (future week) clamps to 1
    expect(periodDayCount('2026-07-05', 'weeks', WM)).toBe(1);
  });
});
