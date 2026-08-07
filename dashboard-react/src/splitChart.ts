// Pure reduction from the FBA/AWD split engine's daily series
// (`fbaAwdSplit.ts` -> `SplitPlan.series`) down to the weekly rows the
// simulation chart renders, plus the display window that bounds them.
//
// This module does no stock or DOC arithmetic of its own — every number in
// a row comes straight off a `SeriesDay` the engine already computed.
// Recomputing any of it here would let the chart and the transfer table
// disagree about the same day, which is exactly what sharing `series` is
// meant to prevent.
import {
  addDays, getMonday, localDateKey, fmtWeekLabel,
} from './stockProjection';
import type { SeriesDay } from './fbaAwdSplit';

export interface SplitChartWindow {
  start: Date;
  end: Date;
}

/**
 * The display window for the split simulation chart.
 *
 * Starts four days before `today` so the operator can see where they are
 * coming from, not just where the plan goes next. Ends at whichever is
 * later — the calendar year end, or `today + docTarget` days — because a
 * `docTarget`-day-of-cover decision is meaningless if the chart cannot show
 * `docTarget` days of runway: near year end, a window that stopped at
 * Dec 31 would cut the DOC line off long before it said anything.
 *
 * The engine (`fbaAwdSplit.ts`) deliberately computes further out than this
 * window — its horizon is `365 + targetDoc` days — so that the DOC reading
 * near the window's right edge is a genuine forward-looking calculation,
 * not an artifact of the forecast running out exactly where the chart
 * happens to stop.
 *
 * When `today + docTarget` lands exactly on year end, the two candidates
 * are the same date, so there is nothing to actually pick between; ties
 * resolve to year end.
 */
export function splitChartWindow(today: Date, docTarget = 100): SplitChartWindow {
  const day = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const start = addDays(day, -4);
  const yearEnd = new Date(day.getFullYear(), 11, 31);
  const horizonEnd = addDays(day, docTarget);
  const end = horizonEnd > yearEnd ? horizonEnd : yearEnd;
  return { start, end };
}

export interface SplitWeekRow {
  weekLabel: string;
  weekStart: string; // YYYY-MM-DD (Monday)
  fbaStock: number;
  awdStock: number;
  fbaDoc: number;
  docCapped: boolean;
  arrivals: number;
  arrivalNote?: string;
}

/** Parse a `YYYY-MM-DD` key as a local date — the inverse of `localDateKey`. */
function parseDateKey(key: string): Date {
  const [y, m, d] = key.split('-').map(Number);
  return new Date(y, m - 1, d);
}

/**
 * Reduces the engine's daily series to Monday-anchored weekly rows.
 *
 * Days outside `window` are dropped first, so a partial week at either edge
 * of the window produces a row from only the days it actually has. Stock
 * balances (`fbaStock`, `awdStock`, `fbaDoc`/`docCapped`) take the last
 * in-window day of the week, because a stock line should show where the
 * pool ended up, not an average across the week. `arrivals` sums across the
 * week, since arrivals are events, not a balance. A week with no series
 * data inside the window produces no row — this reduces what the engine
 * gave it, it does not invent weeks the engine never modelled.
 */
export function reduceSeriesToWeeks(series: SeriesDay[], window: SplitChartWindow): SplitWeekRow[] {
  const inWindow = series
    .filter(d => {
      const date = parseDateKey(d.date);
      return date >= window.start && date <= window.end;
    })
    .sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));

  const buckets = new Map<string, SeriesDay[]>();
  for (const entry of inWindow) {
    const weekStart = localDateKey(getMonday(parseDateKey(entry.date)));
    const bucket = buckets.get(weekStart);
    if (bucket) bucket.push(entry);
    else buckets.set(weekStart, [entry]);
  }

  const rows: SplitWeekRow[] = [];
  for (const [weekStart, days] of buckets) {
    const last = days[days.length - 1];
    const arrivals = days.reduce((sum, d) => sum + d.arrivals, 0);
    const notes: string[] = [];
    for (const d of days) {
      if (d.arrivalNote && !notes.includes(d.arrivalNote)) notes.push(d.arrivalNote);
    }
    rows.push({
      weekLabel: fmtWeekLabel(parseDateKey(weekStart)),
      weekStart,
      fbaStock: last.fbaUnits,
      awdStock: last.awdUnits,
      fbaDoc: last.doc,
      docCapped: last.docCapped,
      arrivals,
      ...(notes.length ? { arrivalNote: notes.join(', ') } : {}),
    });
  }

  return rows;
}
