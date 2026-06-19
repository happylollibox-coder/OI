import { describe, it, expect } from 'vitest';
import { withWindow, daysBetween, weeksBetween, fillSeries } from './adsTrend.helpers';

describe('withWindow', () => {
  it('appends the window label to a count string', () => {
    expect(withWindow('82 active', 'week of Jun 8–14')).toBe('82 active · week of Jun 8–14');
  });
  it('returns the count unchanged when window is empty', () => {
    expect(withWindow('30 terms', '')).toBe('30 terms');
  });
});

describe('daysBetween', () => {
  it('returns inclusive calendar days oldest→newest', () => {
    expect(daysBetween('2026-06-08', '2026-06-11')).toEqual(
      ['2026-06-08', '2026-06-09', '2026-06-10', '2026-06-11']
    );
  });
  it('returns a single day when start === end', () => {
    expect(daysBetween('2026-06-08', '2026-06-08')).toEqual(['2026-06-08']);
  });
  it('returns [] when start is after end', () => {
    expect(daysBetween('2026-06-10', '2026-06-08')).toEqual([]);
  });
});

describe('weeksBetween', () => {
  it('steps by 7 days inclusive', () => {
    expect(weeksBetween('2026-05-24', '2026-06-14')).toEqual(
      ['2026-05-24', '2026-05-31', '2026-06-07', '2026-06-14']
    );
  });
  it('returns a single week when start === end', () => {
    expect(weeksBetween('2026-06-14', '2026-06-14')).toEqual(['2026-06-14']);
  });
});

describe('fillSeries', () => {
  it('maps each axis key to its bucket value, 0 for gaps', () => {
    const buckets = new Map<string, number>([
      ['2026-06-08', 5],
      ['2026-06-10', 2],
    ]);
    expect(fillSeries(buckets, ['2026-06-08', '2026-06-09', '2026-06-10'])).toEqual([5, 0, 2]);
  });
  it('returns all zeros when buckets is undefined', () => {
    expect(fillSeries(undefined, ['2026-06-08', '2026-06-09'])).toEqual([0, 0]);
  });
});
