import { describe, it, expect } from 'vitest';
import { splitChartWindow, reduceSeriesToWeeks } from './splitChart';
import type { SeriesDay } from './fbaAwdSplit';

/** Build a SeriesDay with sane zero defaults, overriding just what a test cares about. */
const day = (date: string, overrides: Partial<SeriesDay> = {}): SeriesDay => ({
  date, fbaUnits: 0, awdUnits: 0, doc: 0, docCapped: false, arrivals: 0, ...overrides,
});

describe('splitChartWindow', () => {
  it('starts four days before today', () => {
    expect(splitChartWindow(new Date(2026, 7, 7)).start).toEqual(new Date(2026, 7, 3));
  });

  it('ends at year end when that is further out than docTarget days', () => {
    // 2026-08-07 + 100d = 2026-11-15; year end 2026-12-31 is later.
    expect(splitChartWindow(new Date(2026, 7, 7)).end).toEqual(new Date(2026, 11, 31));
  });

  it('ends at today+docTarget days when that runs past year end', () => {
    // 2026-11-20 + 100d = 2027-02-28; year end 2026-12-31 is earlier.
    expect(splitChartWindow(new Date(2026, 10, 20)).end).toEqual(new Date(2027, 1, 28));
  });

  it('resolves the boundary where today+docTarget lands exactly on year end to one deterministic answer', () => {
    // day-of-year(2026-09-22) = 265; 365 - 265 = 100, so +100d lands exactly on Dec 31 2026 —
    // the two candidates coincide, so the pinned answer is unambiguous.
    expect(splitChartWindow(new Date(2026, 8, 22)).end).toEqual(new Date(2026, 11, 31));
  });

  it('honors a custom docTarget', () => {
    // 2026-08-07 + 50d = 2026-09-26; year end is still later, so the window still ends Dec 31.
    expect(splitChartWindow(new Date(2026, 7, 7), 50).end).toEqual(new Date(2026, 11, 31));
  });
});

describe('reduceSeriesToWeeks', () => {
  // Mon 2026-08-03 .. Sun 2026-08-09 — one full calendar week.
  const week1 = { start: new Date(2026, 7, 3), end: new Date(2026, 7, 9) };

  it('reduces one full week to one row: last-day stock/DOC, summed arrivals, distinct joined notes', () => {
    const series: SeriesDay[] = [
      day('2026-08-03', { fbaUnits: 500, awdUnits: 200, doc: 50 }),
      day('2026-08-04', { fbaUnits: 480, awdUnits: 200, doc: 48 }),
      day('2026-08-05', { fbaUnits: 460, awdUnits: 200, doc: 46, arrivals: 100, arrivalNote: 'Inbound shipment' }),
      day('2026-08-06', { fbaUnits: 540, awdUnits: 180, doc: 54, arrivals: 20, arrivalNote: 'AWD→FBA transfer' }),
      day('2026-08-07', { fbaUnits: 520, awdUnits: 180, doc: 52 }),
      day('2026-08-08', { fbaUnits: 500, awdUnits: 180, doc: 50 }),
      day('2026-08-09', { fbaUnits: 480, awdUnits: 180, doc: 48 }),
    ];

    const rows = reduceSeriesToWeeks(series, week1);

    expect(rows).toEqual([{
      weekLabel: 'Aug 3',
      weekStart: '2026-08-03',
      fbaStock: 480,  // last day (8/9) — not the first day's 500, not an average
      awdStock: 180,  // last day (8/9)
      fbaDoc: 48,     // last day (8/9)
      docCapped: false,
      arrivals: 120,  // 100 + 20 summed across the week
      arrivalNote: 'Inbound shipment, AWD→FBA transfer',
    }]);
  });

  it('carries the docCapped flag from the last day of the week, for a "400+" style render', () => {
    const series: SeriesDay[] = [day('2026-08-03', { fbaUnits: 5000, doc: 400, docCapped: true })];

    const rows = reduceSeriesToWeeks(series, { start: new Date(2026, 7, 3), end: new Date(2026, 7, 3) });

    expect(rows).toEqual([{
      weekLabel: 'Aug 3', weekStart: '2026-08-03',
      fbaStock: 5000, awdStock: 0, fbaDoc: 400, docCapped: true, arrivals: 0,
    }]);
  });

  it('excludes days outside the window from both the bucket and the arrivals sum', () => {
    const series: SeriesDay[] = [
      day('2026-08-03', { fbaUnits: 500 }),
      day('2026-08-09', { fbaUnits: 480 }),
      // Both outside week1 (which ends 8/9) — must not appear or contribute anything.
      day('2026-08-10', { fbaUnits: 999, arrivals: 50 }),
      day('2026-08-11', { fbaUnits: 1, arrivals: 50 }),
    ];

    const rows = reduceSeriesToWeeks(series, week1);

    expect(rows).toHaveLength(1);
    expect(rows[0].weekStart).toBe('2026-08-03');
    expect(rows[0].fbaStock).toBe(480); // last in-window day, not the out-of-window 8/11 entry
    expect(rows[0].arrivals).toBe(0);
  });

  it('the first bucket is the Monday on or before window.start, even with no data for the earlier days', () => {
    const window = { start: new Date(2026, 7, 5), end: new Date(2026, 7, 6) }; // Wed-Thu, week starts Mon 8/3
    const series: SeriesDay[] = [
      day('2026-08-05', { fbaUnits: 300 }),
      day('2026-08-06', { fbaUnits: 290 }),
    ];

    const rows = reduceSeriesToWeeks(series, window);

    expect(rows).toHaveLength(1);
    expect(rows[0].weekStart).toBe('2026-08-03'); // Monday of that week, not 8/5 itself
    expect(rows[0].weekLabel).toBe('Aug 3');
    expect(rows[0].fbaStock).toBe(290); // last day present, 8/6
  });

  it('a partial week at either edge still produces a row using only the days it has', () => {
    const window = { start: new Date(2026, 7, 5), end: new Date(2026, 7, 14) }; // Wed 8/5 .. Fri 8/14
    const series: SeriesDay[] = [
      day('2026-08-05', { fbaUnits: 460 }),
      day('2026-08-09', { fbaUnits: 480 }), // last day of the partial first week (Wed-Sun)
      day('2026-08-10', { fbaUnits: 470 }),
      day('2026-08-14', { fbaUnits: 400 }), // last day of the partial second week (Mon-Fri)
    ];

    const rows = reduceSeriesToWeeks(series, window);

    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({ weekStart: '2026-08-03', fbaStock: 480 });
    expect(rows[1]).toMatchObject({ weekStart: '2026-08-10', fbaStock: 400 });
  });

  it('returns an empty array for an empty series rather than throwing', () => {
    expect(reduceSeriesToWeeks([], week1)).toEqual([]);
  });

  it('does not invent a row for a week the series has no data for inside the window', () => {
    const window = { start: new Date(2026, 7, 3), end: new Date(2026, 7, 23) }; // 3 weeks: 8/3 .. 8/23
    const series: SeriesDay[] = [
      day('2026-08-03', { fbaUnits: 500 }),
      day('2026-08-09', { fbaUnits: 480 }),
      // No data at all for the week of 8/10-8/16 — must not produce a synthesized zero row.
      day('2026-08-17', { fbaUnits: 300 }),
      day('2026-08-23', { fbaUnits: 250 }),
    ];

    const rows = reduceSeriesToWeeks(series, window);

    expect(rows.map(r => r.weekStart)).toEqual(['2026-08-03', '2026-08-17']);
  });
});
