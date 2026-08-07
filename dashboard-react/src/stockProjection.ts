// Pure stock-projection math, extracted from StockProjectionChart so the
// Weekly Stock Projection chart and the FBA/AWD split engine share one
// implementation. No React, no fetch — everything here is deterministic.
import type { MonthSeasonInfo } from './planTypes';

export interface ProjectionWeek {
  week: string;       // YYYY-MM-DD (Monday)
  weekLabel: string;  // Short label for x-axis
  stock: number;      // Projected stock at end of week (with suggested)
  confirmedStock: number; // Without suggested shipments
  arrivals: number;   // Units arriving this week (all sources)
  confirmedArrivals: number; // Only in-transit + approved + scheduled
  demand: number;     // Weekly demand consumed
  isPeak: boolean;
  arrivalDates: string[]; // Actual arrival dates within this week
  doc: number;        // Days of Cover (confirmed stock)
  docSuggested: number; // Days of Cover (confirmed + suggested stock)
  actualSales?: number;
  actualSalesLY?: number;
}

export type ShipmentStatus =
  | 'arrived' | 'transit' | 'approved' | 'scheduled'
  | 'suggested' | 'po_needed' | 'po';

export interface ProjectionShipment {
  qty: number;
  arrival_date: string;
  status: ShipmentStatus;
  route?: string;
}

/** product demand + family seasonality + growth override, as one curve */
export interface DemandCurve {
  productDemand: Record<number, number>;          // yyyyMM -> units
  familySeason: Record<number, MonthSeasonInfo>;  // yyyyMM -> peak/offseason days
  growth: number;                                 // growth override multiplier
}

/** Real, committed movements. Everything else is a proposal. */
export const CONFIRMED_STATUSES: ReadonlySet<ShipmentStatus> = new Set(['transit', 'approved', 'scheduled']);

/** PO completion means goods sit at the manufacturer, not in a warehouse. */
export const EXCLUDED_STATUSES: ReadonlySet<ShipmentStatus> = new Set(['po_needed', 'po']);

export function getMonday(d: Date): Date {
  const day = d.getDay();
  const diff = d.getDate() - day + (day === 0 ? -6 : 1);
  return new Date(d.getFullYear(), d.getMonth(), diff);
}

export function addDays(d: Date, n: number): Date {
  const r = new Date(d);
  r.setDate(r.getDate() + n);
  return r;
}

/** Format a local Date as YYYY-MM-DD without the UTC shift toISOString applies. */
export function localDateKey(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/**
 * Parse a date string as a LOCAL date. `new Date('2026-09-19')` is UTC
 * midnight, which reads back as the 18th anywhere west of UTC — and OI's
 * FACT_/V_ layer runs America/Los_Angeles, so production sits on the wrong
 * side of that. Bare YYYY-MM-DD is built field by field; anything else falls
 * through to the platform parser. Returns null for anything unparseable.
 */
export function parseLocalDate(raw: string | null | undefined): Date | null {
  if (!raw) return null;
  const ymd = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw.trim());
  const d = ymd
    ? new Date(Number(ymd[1]), Number(ymd[2]) - 1, Number(ymd[3]))
    : new Date(raw);
  return isNaN(d.getTime()) ? null : d;
}

export const MONTH_ABBR = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

export function fmtWeekLabel(d: Date): string {
  return `${MONTH_ABBR[d.getMonth()]} ${d.getDate()}`;
}

export function daysInMonth(year: number, month: number): number {
  return new Date(year, month + 1, 0).getDate();
}

/**
 * Demand for a single day. Peak days carry ~2x the rate of offseason days in
 * the same month: totalUnits = peakDays*rate*2 + offDays*rate.
 * Peak days are assumed to be the last N days of the month (holiday rush).
 */
export function dailyDemandOn(day: Date, curve: DemandCurve): { units: number; isPeak: boolean } {
  const yr = day.getFullYear();
  const mo = day.getMonth();
  const yearMonth = yr * 100 + (mo + 1);
  const monthUnits = (curve.productDemand[yearMonth] || 0) * curve.growth;
  if (monthUnits <= 0) return { units: 0, isPeak: false };

  const totalDaysInMo = daysInMonth(yr, mo);
  const season = curve.familySeason[yearMonth];
  const peakDays = season?.peakDays ?? 0;
  const offDays = season?.offseasonDays ?? (totalDaysInMo - peakDays);

  if (peakDays > 0 && offDays > 0) {
    const rate = monthUnits / (peakDays * 2 + offDays);
    const isPeakDay = day.getDate() > (totalDaysInMo - peakDays);
    return { units: isPeakDay ? rate * 2 : rate, isPeak: isPeakDay };
  }
  return { units: monthUnits / totalDaysInMo, isPeak: false };
}

/** Demand across a week (Mon-Sun), stopping at endDate. */
export function weeklyDemand(weekStart: Date, curve: DemandCurve, endDate: Date): { demand: number; isPeak: boolean } {
  let totalDemand = 0;
  let hasPeak = false;
  for (let d = 0; d < 7; d++) {
    const day = addDays(weekStart, d);
    if (day > endDate) break;
    const { units, isPeak } = dailyDemandOn(day, curve);
    totalDemand += units;
    if (isPeak) hasPeak = true;
  }
  return { demand: Math.round(totalDemand), isPeak: hasPeak };
}

/** Total demand over [start, endExclusive). Used to size a DOC target exactly. */
export function demandOverWindow(start: Date, endExclusive: Date, curve: DemandCurve): number {
  let total = 0;
  for (let d = new Date(start); d < endExclusive; d = addDays(d, 1)) {
    total += dailyDemandOn(d, curve).units;
  }
  return total;
}

/**
 * Days of cover: walk forward from week `fromIndex` consuming `startStock`
 * against each week's demand until it runs out. Capped at 365.
 */
export function forwardDoc(weeks: Array<{ demand: number }>, fromIndex: number, startStock: number): number {
  let rem = Math.max(0, startStock);
  let days = 0;
  for (let j = fromIndex; j < weeks.length && rem > 0; j++) {
    const futDemand = weeks[j].demand;
    if (futDemand <= 0) { days += 7; continue; }
    const dailyD = futDemand / 7;
    days += Math.min(7, rem / dailyD);
    rem -= futDemand;
  }
  return Math.min(Math.round(days), 365);
}

export interface ProjectionParams {
  currentStock: number;
  shipments: ProjectionShipment[];
  curve: DemandCurve;
  startDate: Date;  // snapped to its Monday internally
  endDate: Date;
  now: Date;
  weeklySales?: Record<string, number>;
  weeklySalesLY?: Record<string, number>;
}

/** Weekly stock projection. Past weeks carry no demand and no arrivals. */
export function buildWeeklyProjection(p: ProjectionParams): ProjectionWeek[] {
  const { currentStock, shipments, curve, endDate, now, weeklySales, weeklySalesLY } = p;
  const startMonday = getMonday(p.startDate);
  const currentMonday = getMonday(now);
  const weeks: ProjectionWeek[] = [];

  const arrivalByWeek = new Map<string, { confirmed: number; total: number; dates: Set<string> }>();
  for (const sh of shipments) {
    if (EXCLUDED_STATUSES.has(sh.status)) continue;
    const arrDate = parseLocalDate(sh.arrival_date);
    if (!arrDate) continue;
    const key = localDateKey(getMonday(arrDate));
    const entry = arrivalByWeek.get(key) || { confirmed: 0, total: 0, dates: new Set<string>() };
    entry.total += sh.qty;
    if (CONFIRMED_STATUSES.has(sh.status)) entry.confirmed += sh.qty;
    entry.dates.add(`${MONTH_ABBR[arrDate.getMonth()]} ${arrDate.getDate()}`);
    arrivalByWeek.set(key, entry);
  }

  let runningConfirmed = currentStock;
  let runningTotal = currentStock;
  let weekStart = new Date(startMonday);

  while (weekStart <= endDate) {
    const key = localDateKey(weekStart);
    const isPast = weekStart < currentMonday;
    const { demand: rawDemand, isPeak } = weeklyDemand(weekStart, curve, endDate);
    const demand = isPast ? 0 : rawDemand;
    const arrival = arrivalByWeek.get(key) || { confirmed: 0, total: 0, dates: new Set<string>() };
    const adjArrivalConf = isPast ? 0 : arrival.confirmed;
    const adjArrivalTotal = isPast ? 0 : arrival.total;

    runningConfirmed = runningConfirmed - demand + adjArrivalConf;
    runningTotal = runningTotal - demand + adjArrivalTotal;

    weeks.push({
      week: key,
      weekLabel: fmtWeekLabel(weekStart),
      stock: Math.max(0, Math.round(runningTotal)),
      confirmedStock: Math.max(0, Math.round(runningConfirmed)),
      arrivals: isPast ? 0 : arrival.total,
      confirmedArrivals: isPast ? 0 : arrival.confirmed,
      demand,
      isPeak,
      arrivalDates: isPast ? [] : [...arrival.dates],
      doc: 0,
      docSuggested: 0,
      actualSales: weeklySales?.[key],
      actualSalesLY: weeklySalesLY?.[key],
    });

    weekStart = addDays(weekStart, 7);
  }

  for (let i = 0; i < weeks.length; i++) {
    weeks[i].doc = forwardDoc(weeks, i, weeks[i].confirmedStock);
    weeks[i].docSuggested = forwardDoc(weeks, i, weeks[i].stock);
  }

  return weeks;
}
