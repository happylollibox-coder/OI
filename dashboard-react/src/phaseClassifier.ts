/**
 * Phase classifier — assigns any date to one of 3 seasonal phases
 * using holiday boundaries from DIM_US_HOLIDAYS (via DashboardData.holidays).
 *
 * Tier model (aligned with V_FORECAST_ROAS):
 *   offseason: dates not in any holiday boost/peak window
 *   boost:     boost_start → peak_start - 1  (per holiday)
 *   peak:      peak_start  → holiday_date - 1 (per holiday)
 */
import type { HolidayRow } from './types';

export type SeasonPhase = 'offseason' | 'boost' | 'peak';

export const PHASE_META: Record<SeasonPhase, { label: string; color: string; bgClass: string }> = {
  offseason: { label: 'Off Season', color: '#71717a', bgClass: 'bg-zinc-500/15' },
  boost:     { label: 'Boost',      color: '#f59e0b', bgClass: 'bg-amber-500/15' },
  peak:      { label: 'Peak',       color: '#ef4444', bgClass: 'bg-red-500/15' },
};

export const ALL_PHASES: SeasonPhase[] = ['offseason', 'boost', 'peak'];

/**
 * Subtract 1 day from a YYYY-MM-DD string.
 */
function dayBefore(dateStr: string): string {
  const d = new Date(dateStr + 'T00:00:00');
  d.setDate(d.getDate() - 1);
  return d.toISOString().slice(0, 10);
}

/**
 * Classify a date string (YYYY-MM-DD) into a SeasonPhase.
 * Checks all gift_season holidays. Peak takes priority over boost.
 */
export function classifyPhase(dateStr: string, holidays: HolidayRow[]): SeasonPhase {
  if (!dateStr) return 'offseason';
  // Normalize to YYYY-MM-DD
  const d = dateStr.length === 7 ? `${dateStr}-01` : dateStr.slice(0, 10);

  let isBoosting = false;

  for (const h of holidays) {
    if (h.category !== 'gift_season') continue;
    const peakStart = h.peak_start;
    const peakEnd = h.holiday_date ? dayBefore(h.holiday_date) : '';
    const boostStart = h.boost_start;
    const boostEnd = peakStart ? dayBefore(peakStart) : '';

    // Peak takes priority
    if (peakStart && peakEnd && d >= peakStart && d <= peakEnd) {
      return 'peak';
    }
    // Track boost (but keep checking other holidays for possible peak)
    if (boostStart && boostEnd && d >= boostStart && d <= boostEnd) {
      isBoosting = true;
    }
  }

  return isBoosting ? 'boost' : 'offseason';
}

/**
 * Group rows by phase. Each row is classified by its date field.
 */
export function groupByPhase<T>(
  rows: T[],
  dateKey: keyof T & string,
  holidays: HolidayRow[],
): Record<SeasonPhase, T[]> {
  const groups: Record<SeasonPhase, T[]> = { offseason: [], boost: [], peak: [] };
  for (const row of rows) {
    const val = row[dateKey];
    const dateStr = typeof val === 'string' ? val : '';
    const phase = classifyPhase(dateStr, holidays);
    groups[phase].push(row);
  }
  return groups;
}

/**
 * Filter rows to only those matching the given phase.
 * If phase is null, returns all rows.
 */
export function filterByPhase<T>(
  rows: T[],
  dateKey: keyof T & string,
  phase: SeasonPhase | null,
  holidays: HolidayRow[],
): T[] {
  if (!phase) return rows;
  return rows.filter(row => {
    const val = row[dateKey];
    const dateStr = typeof val === 'string' ? val : '';
    return classifyPhase(dateStr, holidays) === phase;
  });
}
