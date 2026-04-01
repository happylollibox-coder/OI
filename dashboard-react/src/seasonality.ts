import type { PeakRow } from './types';

export type AdsSeasonality = 'PRE_PEAK' | 'PRE_PEAK_BOOST' | 'PEAK' | 'OFF_SEASON';

export const SEASONALITY_OPTIONS: { value: AdsSeasonality; label: string }[] = [
  { value: 'PRE_PEAK', label: 'Pre Peak (2-4 wk)' },
  { value: 'PRE_PEAK_BOOST', label: 'Pre Peak Boost (1-2 wk)' },
  { value: 'PEAK', label: 'Peak' },
  { value: 'OFF_SEASON', label: 'Off Season' },
];

/**
 * Classify a date string (YYYY-MM-DD or YYYY-MM) into AdsSeasonality using PeakRow boundary fields.
 * Uses pre_peak_start, boost_start, peak_start, peak_end — no hardcoded day offsets.
 */
export function getSeasonality(dateStr: string, pk: PeakRow): AdsSeasonality {
  const ps = pk.pre_peak_start || '';
  const bs = pk.boost_start || '';
  const pstart = pk.peak_start || '';
  const pend = pk.peak_end || '';
  if (!ps || !bs || !pstart || !pend) return 'OFF_SEASON';

  // Normalize to YYYY-MM-DD for comparison (month_start may be YYYY-MM)
  const d = dateStr.length === 7 ? `${dateStr}-01` : dateStr;

  if (d >= ps && d < bs) return 'PRE_PEAK';
  if (d >= bs && d < pstart) return 'PRE_PEAK_BOOST';
  if (d >= pstart && d < pend) return 'PEAK';
  return 'OFF_SEASON';
}

/**
 * Filter rows by seasonality. When seasonality is null or pk is null, returns all rows.
 * dateKey: the property on each row that holds the date (e.g. 'week_start', 'month_start').
 */
export function filterBySeasonality<T>(
  rows: T[],
  dateKey: keyof T & string,
  seasonality: AdsSeasonality | null,
  pk: PeakRow | null
): T[] {
  if (!seasonality || !pk) return rows;
  return rows.filter(r => {
    const val = r[dateKey];
    const dateStr = typeof val === 'string' ? val : '';
    if (!dateStr) return false;
    return getSeasonality(dateStr, pk) === seasonality;
  });
}
