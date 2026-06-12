import type { FamilyName } from './types';

export const fmt = (n: number | null | undefined, d = 0): string =>
  n == null ? '--' : Number(n).toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d });

export const fM = (n: number | null | undefined): string =>
  n == null ? '--' : '$' + fmt(n, 2);

export const fK = (n: number | null | undefined): string => {
  if (n == null) return '--';
  return Math.abs(n) >= 1e3 ? '$' + fmt(n / 1e3, 1) + 'K' : '$' + fmt(n, 0);
};

export const fP = (n: number | null | undefined): string =>
  n == null ? '--' : fmt(n, 1) + '%';

export const fD = (n: number | null | undefined, d = 2): string =>
  n == null ? '--' : fmt(n, d);

export const fR = (n: number | null | undefined): string =>
  n == null ? '--' : fmt(n, 2) + 'x';

export const fOrd = (n: number | null | undefined): string =>
  n == null ? '--' : fmt(n) + ' ord';

export const fClk = (n: number | null | undefined): string =>
  n == null ? '--' : fmt(n) + ' clicks';

export const fShort = (n: number | null | undefined): string => {
  if (n == null) return '';
  const abs = Math.abs(n);
  if (abs >= 1e6) return (n / 1e6).toFixed(1) + 'M';
  if (abs >= 1e3) return (n / 1e3).toFixed(1) + 'K';
  return n % 1 === 0 ? n.toFixed(0) : n.toFixed(1);
};

export const fCpc = (n: number | null | undefined): string =>
  n == null ? '--' : '$' + fmt(n, 2) + '/click';

export const fMktV = (n: number | null | undefined): string =>
  n == null ? '--' : fmt(n, 0) + ' ord/wk';

export function formatDateRange(start?: string, end?: string): string {
  if (!start || !end) return '';
  const f = (d: string) => new Date(d + 'T12:00:00Z').toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
  return f(start) + ' – ' + f(end);
}

export function weekRangeLabel(weekStart: string): string {
  if (!weekStart) return '';
  const d = new Date(weekStart + 'T12:00:00Z');
  const end = new Date(d);
  end.setUTCDate(end.getUTCDate() + 6);
  const f = (dt: Date) => dt.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
  return f(d) + ' – ' + f(end);
}

/** Week range label capped at dataMaxDate (e.g. latest Orders date).
 *  For a current/in-progress week, shows "May 10 – May 11" instead of "May 10 – May 16". */
export function weekRangeLabelCapped(weekStart: string, dataMaxDate?: string): string {
  if (!weekStart) return '';
  const d = new Date(weekStart + 'T12:00:00Z');
  const calEnd = new Date(d);
  calEnd.setUTCDate(calEnd.getUTCDate() + 6);
  const calEndIso = `${calEnd.getUTCFullYear()}-${String(calEnd.getUTCMonth() + 1).padStart(2, '0')}-${String(calEnd.getUTCDate()).padStart(2, '0')}`;
  const effectiveEnd = dataMaxDate && dataMaxDate < calEndIso
    ? new Date(dataMaxDate + 'T12:00:00Z')
    : calEnd;
  const f = (dt: Date) => dt.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
  return f(d) + ' – ' + f(effectiveEnd);
}

/** Returns the Sunday of the current week as YYYY-MM-DD (Sunday-start week, matching DIM_TIME). */
export function getCurrentWeekStart(): string {
  const now = new Date();
  const day = now.getDay(); // 0=Sun,1=Mon,...6=Sat
  const sun = new Date(now);
  sun.setDate(sun.getDate() - day); // go back to Sunday
  const y = sun.getFullYear();
  const m = String(sun.getMonth() + 1).padStart(2, '0');
  const d = String(sun.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

/** Returns the Sunday week-start (YYYY-MM-DD) containing the given ISO date. */
export function getWeekStart(iso: string): string {
  const raw = iso.length === 10 ? iso + 'T12:00:00Z' : iso;
  const dt = new Date(raw);
  const day = dt.getUTCDay(); // 0=Sun
  dt.setUTCDate(dt.getUTCDate() - day);
  return `${dt.getUTCFullYear()}-${String(dt.getUTCMonth() + 1).padStart(2, '0')}-${String(dt.getUTCDate()).padStart(2, '0')}`;
}

/** Returns ISO date range for a week: "2026-02-15 – 2026-02-21". Optionally append suffix like " (latest)". */
export function weekRangeLabelIso(weekStart: string, suffix = ''): string {
  if (!weekStart) return '';
  // Use addDays (string-based) to avoid timezone shifts from Date objects
  const endStr = addDays(weekStart, 6);
  return `${weekStart} – ${endStr}${suffix ? ' ' + suffix : ''}`;
}

export type PeriodMode = 'date' | 'weeks' | 'month' | 'quarter' | 'year';

/** Convert a date/week_start to the appropriate period key. Quarter format: '2025-Q1'. */
export function periodKey(weekStart: string, mode: PeriodMode): string {
  if (mode === 'date') return weekStart; // full date YYYY-MM-DD
  if (mode === 'weeks') return weekStart;
  if (mode === 'month') return weekStart.slice(0, 7);
  if (mode === 'quarter') {
    const m = parseInt(weekStart.slice(5, 7), 10);
    const q = Math.ceil(m / 3);
    return `${weekStart.slice(0, 4)}-Q${q}`;
  }
  return weekStart.slice(0, 4);
}

export function periodLabel(key: string, mode: PeriodMode): string {
  if (mode === 'weeks') return weekRangeLabel(key);
  return key;
}

export function periodModeLabel(mode: PeriodMode, style: 'title' | 'lower' | 'latest' = 'title'): string {
  const map: Record<PeriodMode, { title: string; lower: string; latest: string }> = {
    date:    { title: 'Daily',     lower: 'daily',     latest: 'latest date' },
    weeks:   { title: 'Weekly',    lower: 'weekly',    latest: 'latest week' },
    month:   { title: 'Monthly',   lower: 'monthly',   latest: 'latest month' },
    quarter: { title: 'Quarterly', lower: 'quarterly', latest: 'latest quarter' },
    year:    { title: 'Yearly',    lower: 'yearly',    latest: 'latest year' },
  };
  return map[mode][style];
}

const MONTH_NAMES = ['', 'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

/** Format actual period value with "latest X" suffix. E.g. "2026-02-15" + weeks → "2026-02-15 – 2026-02-21 (latest week)" */
export function latestPeriodLabel(periodValue: string, mode: PeriodMode): string {
  if (!periodValue) return '--';
  if (mode === 'weeks') return weekRangeLabelIso(periodValue, `(${periodModeLabel(mode, 'latest')})`);
  if (mode === 'month') {
    const [y, m] = periodValue.split('-');
    const monthStr = MONTH_NAMES[parseInt(m || '0', 10)] || m;
    return `${y}-${monthStr} (${periodModeLabel(mode, 'latest')})`;
  }
  if (mode === 'quarter') {
    return `${periodValue} (${periodModeLabel(mode, 'latest')})`;
  }
  const year = periodValue.slice(0, 4);
  return `${year} (${periodModeLabel(mode, 'latest')})`;
}

export function periodDateKey(mode: PeriodMode): 'week_start' | 'month_start' {
  return mode === 'weeks' ? 'week_start' : 'month_start';
}

/** Date range [start, end] for a period key. Used to filter ads_7d by period. */
export function periodDateRange(periodKey: string, mode: PeriodMode): { start: string; end: string } | null {
  if (!periodKey) return null;
  if (mode === 'date') {
    return { start: periodKey, end: periodKey };
  }
  if (mode === 'weeks') {
    return { start: periodKey, end: addDays(periodKey, 6) };
  }
  if (mode === 'month') {
    const start = periodKey + '-01';
    const y = parseInt(periodKey.slice(0, 4), 10);
    const m = parseInt(periodKey.slice(5, 7), 10);
    const lastDay = new Date(y, m, 0);
    return { start, end: lastDay.toISOString().slice(0, 10) };
  }
  if (mode === 'quarter') {
    const y = parseInt(periodKey.slice(0, 4), 10);
    const q = parseInt(periodKey.slice(6, 7), 10);
    const startMonth = (q - 1) * 3 + 1;
    const endMonth = q * 3;
    const startStr = `${y}-${String(startMonth).padStart(2, '0')}-01`;
    const lastDay = new Date(y, endMonth, 0);
    return { start: startStr, end: lastDay.toISOString().slice(0, 10) };
  }
  return { start: periodKey + '-01-01', end: periodKey + '-12-31' };
}

/** Sum ads spend from ads_7d rows within date range [start, end]. */
export function sumAdsSpendInRange(rows: { date?: string; spend?: number }[], start: string, end: string): number {
  return rows
    .filter(r => r.date && r.date >= start && r.date <= end)
    .reduce((s, r) => s + (r.spend || 0), 0);
}

/** Slice a sorted period array by specificPeriod + count, or last count. */
export function sliceByPeriod(sorted: string[], specificPeriod: string | null, count: number): string[] {
  if (!specificPeriod) return sorted.slice(-count);
  const idx = sorted.indexOf(specificPeriod);
  if (idx >= 0) return sorted.slice(Math.max(0, idx - count + 1), idx + 1);
  return sorted.slice(-count);
}

/** Anchor period: specificPeriod if set and in available, else latest week with SQP (weekly), else last available. */
export function getEffectivePeriod(
  sqpWeekly: { week_start: string }[],
  periodMode: PeriodMode,
  specificPeriod: string | null,
  availablePeriods: string[]
): string | null {
  if (specificPeriod && availablePeriods.includes(specificPeriod)) return specificPeriod;
  if (periodMode === 'weeks') {
    const latest = latestSqpWeek(sqpWeekly);
    if (latest && availablePeriods.includes(latest)) return latest;
  }
  return availablePeriods.length ? availablePeriods[availablePeriods.length - 1] : null;
}

/** Periods for trend charts: periodTrend periods ending at anchor. */
export function getPeriodsForTrend(sorted: string[], anchorPeriod: string | null, periodTrend: number): string[] {
  return sliceByPeriod(sorted, anchorPeriod, periodTrend);
}

/** Periods for non-trend: single period only. */
export function getPeriodsForNonTrend(sorted: string[], anchorPeriod: string | null): string[] {
  return sliceByPeriod(sorted, anchorPeriod, 1);
}

/** Get periods to include: sliceByPeriod with anchor + count. */
export function getPeriodsToInclude(
  specificPeriod: string | null,
  _periodMode: PeriodMode,
  availablePeriods: string[],
  count: number
): string[] {
  return sliceByPeriod(availablePeriods, specificPeriod, count);
}

export const deltaClass = (v: number | null | undefined): string =>
  v == null ? 'flat' : v > 0 ? 'up' : v < 0 ? 'down' : 'flat';

export const deltaStr = (v: number | null | undefined): string =>
  v == null ? '' : v > 0 ? '+' + fP(v) : fP(v);

/** Simple deterministic short hash (6 chars) for generating action/branch IDs */

/** Returns true if experiment name/id matches the given family (for filtering). */
export function experimentMatchesFamily(nameOrId: string | null | undefined, family: FamilyName): boolean {
  const n = (nameOrId || '').toLowerCase();
  if (family === 'Lollibox') return n.includes('lollibox') || n.includes('box');
  if (family === 'LolliME') return n.includes('lollime') || n.includes('me') || n.includes('mint');
  if (family === 'Bottle') return n.includes('bottle') || n.includes('truth');
  if (family === 'Fresh') return n.includes('fresh');
  if (family === 'Bunny') return n.includes('bunny');
  if (family === 'LolliBall') return n.includes('lolliball') || n.includes('ball');
  return false;
}

export function famFromType(t: string | null | undefined): FamilyName | string | null {
  // Pass-through: BigQuery now returns clean family names via V_PRODUCT_FAMILY_MAP
  // No frontend heuristic needed — new products are handled automatically
  if (!t) return null;
  return t;
}

export function sqpCoverageWeeks(sqpWeekly: { week_start: string }[]): Set<string> {
  return new Set(sqpWeekly.map(r => r.week_start));
}

/** Shift a date string (YYYY-MM-DD) by years. */
export function shiftYear(dateStr: string, years: number): string {
  const d = new Date(dateStr + 'T12:00:00Z');
  d.setUTCFullYear(d.getUTCFullYear() + years);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
}

/** Add days to a date string (YYYY-MM-DD). Returns YYYY-MM-DD. */
export function addDays(dateStr: string, days: number): string {
  const d = new Date(dateStr + 'T12:00:00Z');
  d.setUTCDate(d.getUTCDate() + days);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
}

/** Return week_start values that overlap [startDate, endDate]. Week runs Mon-Sun (week_start to week_start+6). */
export function weeksInDateRange(startDate: string, endDate: string, weekStarts: string[]): string[] {
  return weekStarts.filter(ws => {
    const weekEnd = addDays(ws, 6);
    return ws <= endDate && weekEnd >= startDate;
  });
}

/** Return month keys (YYYY-MM) that overlap [startDate, endDate]. */
export function monthsInDateRange(startDate: string, endDate: string, monthKeys: string[]): string[] {
  return monthKeys.filter(m => {
    const [y, mo] = m.split('-').map(Number);
    const monthStart = `${m}-01`;
    const lastDay = new Date(y, mo, 0).getDate();
    const monthEnd = `${m}-${String(lastDay).padStart(2, '0')}`;
    return monthStart <= endDate && monthEnd >= startDate;
  });
}

export function latestSqpWeek(sqpWeekly: { week_start: string }[]): string | null {
  if (!sqpWeekly.length) return null;
  return sqpWeekly.reduce((max, r) => r.week_start > max ? r.week_start : max, sqpWeekly[0].week_start);
}

/** Ads data gap: 2025-03-11 to 2025-10-02. Returns true if date/period overlaps. */
const ADS_GAP_START = '2025-03-11';
const ADS_GAP_END = '2025-10-02';

export function isInAdsGap(dateOrWeekStart: string): boolean {
  if (!dateOrWeekStart) return false;
  const d = dateOrWeekStart.length === 7 ? dateOrWeekStart + '-01' : dateOrWeekStart;
  return d >= ADS_GAP_START && d <= ADS_GAP_END;
}

/** Returns true if a week (week_start to week_start+6) overlaps the ads gap. */
export function weekOverlapsAdsGap(weekStart: string): boolean {
  if (!weekStart) return false;
  const weekEnd = addDays(weekStart, 6);
  return !(weekEnd < ADS_GAP_START || weekStart > ADS_GAP_END);
}

/** Returns true if a month (YYYY-MM) overlaps the ads gap. */
export function monthOverlapsAdsGap(monthKey: string): boolean {
  if (!monthKey || monthKey.length < 7) return false;
  const [y, m] = monthKey.split('-').map(Number);
  const lastDay = new Date(y, m, 0).getDate();
  const monthStart = `${monthKey}-01`;
  const monthEnd = `${monthKey}-${String(lastDay).padStart(2, '0')}`;
  return monthStart <= ADS_GAP_END && monthEnd >= ADS_GAP_START;
}

/** Card 1: Net ROAS → 0-10 score. */
export function scoreFromRoas(roas: number): number {
  if (roas <= -1) return 0;
  if (roas >= 5) return 10;
  if (roas < 0) return 5 * (roas + 1);
  return 5 + roas;
}

/** Card 2 & 3: Net Profit % delta → 0-10 score. */
export function scoreFromProfitDelta(pct: number): number {
  if (pct <= -20) return 0;
  if (pct >= 20) return 10;
  if (pct < 0) return (5 * (pct + 20)) / 20;
  return 5 + (5 * pct) / 20;
}

export const ACTION_META: Record<string, { label: string; variant: 'red' | 'green' | 'blue' | 'amber' | 'purple' | 'muted'; group: string; criteria: string }> = {
  // ─── Term Actions ───
  STOP_TERM:        { label: 'STOP',           variant: 'red',    group: 'urgent',      criteria: 'Term bleeds money: 0 orders + enough clicks — stop spending on this term' },
  NEGATE_TERM:      { label: 'NEGATE',         variant: 'red',    group: 'urgent',      criteria: 'Term should be negated: sells in other campaigns but not here, or nobody sells' },
  NEGATE_PHRASE:    { label: 'NEGATE PHRASE',  variant: 'red',    group: 'urgent',      criteria: 'Common phrase across 3+ unprofitable terms — negate as phrase match to block all variations' },
  PROMOTE_TO_PEAK_PHRASE: { label: 'PROMOTE',       variant: 'purple', group: 'watch',       criteria: 'Phrase is profitable over 1-year window, but highly seasonal. Negate now, promote to Peak Exact.' },
  PROMOTE_TO_EXACT: { label: 'PROMOTE',        variant: 'blue',   group: 'experiment',  criteria: 'Very successful term + high SQP volume — promote to exact match campaign' },
  START_TERM:       { label: 'NEW',            variant: 'purple', group: 'experiment',  criteria: 'Very successful term + high SQP volume — new keyword opportunity' },
  // ─── Target Actions ───
  STOP_TARGET:      { label: 'STOP TARGET',    variant: 'red',    group: 'urgent',      criteria: 'All terms under target have 0 orders + enough clicks — stop the entire target' },
  INCREASE_BID:     { label: 'INCREASE BID',   variant: 'green',  group: 'growth',      criteria: 'Target ROAS above threshold — graduated bid increase' },
  REDUCE_BID:       { label: 'REDUCE BID',     variant: 'red',    group: 'urgent',      criteria: 'Target ROAS below threshold — graduated bid decrease' },
  KEEP_TARGET:      { label: 'KEEP',           variant: 'green',  group: 'profitable',  criteria: 'Target profitable, no bid action needed' },
  MONITOR_TARGET:   { label: 'MONITOR',        variant: 'muted',  group: 'watch',       criteria: 'Not enough data on target yet — keep watching' },
  // ─── Other ───
  FIX_HERO:         { label: 'FIX HERO',       variant: 'amber',  group: 'fix',         criteria: 'Best converting ASIN ≠ advertised ASIN — switch to hero product' },
  SWITCH_HERO:      { label: 'SWITCH HERO',    variant: 'amber',  group: 'fix',         criteria: 'Current hero underperforming vs alternative ASIN — switch hero' },
  // ─── Boost-specific negation ───
  NEGATE_BOOST_SIMILAR_EXACT: { label: 'NEGATE BOOST', variant: 'red', group: 'urgent', criteria: 'Boost keyword underperforming — negate similar exact match from parent campaign' },
  // ─── Seasonal Campaign Actions ───
  STOP_SEASONAL:    { label: 'STOP SEASONAL',  variant: 'red',    group: 'urgent',      criteria: 'Seasonal campaign past its season — pause campaign to prevent off-season spend' },
  // ─── Cooldown Actions ───
  COOLDOWN_MONITOR: { label: 'COOLDOWN HOLD',  variant: 'muted',  group: 'watch',       criteria: 'Post-peak ROAS ≥ 0.8 — no bid change needed during cooldown' },
  REDUCE_TO_BASELINE: { label: 'REDUCE',       variant: 'amber',  group: 'urgent',      criteria: 'Post-peak ROAS ≥ 0.6 — gradual -10% per cycle toward pre-peak baseline' },
  RESTORE_PRE_PEAK: { label: 'RESTORE',        variant: 'red',    group: 'urgent',      criteria: 'Post-peak ROAS < 0.6 — snap to pre-peak bid immediately' },
  // ─── Budget Actions ───
  GUARDIAN_BUDGET_INCREASE: { label: 'BUDGET ↑', variant: 'green', group: 'growth', criteria: 'Campaign profitable (ROAS ≥ 1.1) + out of budget — increase 10%' },
  GUARDIAN_BUDGET_DECREASE: { label: 'BUDGET ↓', variant: 'red',   group: 'urgent', criteria: 'Campaign losing (ROAS < 0.9) — decrease 15%' },
  BLITZ_BUDGET_INCREASE:    { label: 'BLITZ BUDGET ↑', variant: 'green', group: 'growth', criteria: 'Blitz: profitable + out of budget — increase 20%' },
  BLITZ_BUDGET_DECREASE:    { label: 'BLITZ BUDGET ↓', variant: 'amber', group: 'urgent', criteria: 'Blitz: losing ROAS — decrease 10%' },
  BUDGET_OK:        { label: 'BUDGET OK',      variant: 'muted',  group: 'watch',       criteria: 'Budget within healthy range — no change needed' },
  // ─── Legacy / passive (term-level, rolled up into target actions) ───
  KEEP:             { label: 'KEEP',           variant: 'green',  group: 'profitable',  criteria: 'Term profitable — passive, bid action is on the target' },
  MONITOR:          { label: 'MONITOR',        variant: 'muted',  group: 'watch',       criteria: 'Not enough data — keep watching' },
  STOP:             { label: 'STOP',           variant: 'red',    group: 'urgent',      criteria: 'Legacy — stop spending' },
  NEGATE:           { label: 'NEGATE',         variant: 'red',    group: 'urgent',      criteria: 'Legacy — negate term' },
  BOOST:            { label: 'SCALE',          variant: 'green',  group: 'growth',      criteria: 'Legacy — increase bid' },
  SCALE_UP:         { label: 'SCALE UP',       variant: 'green',  group: 'growth',      criteria: 'Legacy — increase bid to capture more' },
  START:            { label: 'NEW',            variant: 'purple', group: 'experiment',  criteria: 'Legacy — new keyword opportunity' },
};
