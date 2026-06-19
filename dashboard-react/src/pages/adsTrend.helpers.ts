import { addDays } from '../utils';

/** Append a window label to a Section count string (e.g. "82 active · week of Jun 8–14"). */
export function withWindow(count: string, windowLabel: string): string {
  return windowLabel ? `${count} · ${windowLabel}` : count;
}

/** Inclusive list of calendar day ISO strings, oldest→newest. [] if start > end. */
export function daysBetween(startISO: string, endISO: string): string[] {
  const out: string[] = [];
  let d = startISO;
  let guard = 0;
  while (d <= endISO && guard++ < 2000) {
    out.push(d);
    d = addDays(d, 1);
  }
  return out;
}

/** Inclusive list of week-start ISO strings stepping by 7 days, oldest→newest. */
export function weeksBetween(startISO: string, endISO: string): string[] {
  const out: string[] = [];
  let d = startISO;
  let guard = 0;
  while (d <= endISO && guard++ < 520) {
    out.push(d);
    d = addDays(d, 7);
  }
  return out;
}

/** For each axis key, return its bucket value (0 when missing). */
export function fillSeries(
  buckets: Map<string, number> | undefined,
  axis: string[]
): number[] {
  if (!buckets) return axis.map(() => 0);
  return axis.map(k => buckets.get(k) ?? 0);
}
