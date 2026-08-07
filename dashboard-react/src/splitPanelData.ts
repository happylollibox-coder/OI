// Pure data prep for the FBA/AWD split panel (`components/FbaAwdSplitPanel.tsx`).
//
// The panel is advisory and writes nothing; its job is to show the operator
// every input that produced the recommendation. Anything in here that looks
// like arithmetic or partitioning lives here rather than in the component so
// it can be tested without React — and so the ledger's view of "what counted"
// is checked against the engine's own filter rather than eyeballed.
import {
  FBA_METHODS, destinationOf,
  type DocReading, type TransitDayMap,
} from './fbaAwdSplit';
import {
  CONFIRMED_STATUSES, EXCLUDED_STATUSES, MONTH_ABBR,
  dailyDemandOn, daysInMonth, localDateKey,
  type DemandCurve, type ProjectionShipment, type ShipmentStatus,
} from './stockProjection';
import type { ForecastDemandMap, ForecastMetaMap, MonthSeasonMap } from './planTypes';

/**
 * The operating rule: FBA holds 100 days of cover. A level maintained over
 * time, not a one-time top-up — which is why the panel shows a transfer
 * schedule and not just a single shipment.
 */
export const TARGET_DOC = 100;

// ─── Cartons ↔ units ────────────────────────────────────────

const usablePkg = (pkg: number | undefined | null): number =>
  Number.isFinite(pkg) && (pkg as number) > 0 ? (pkg as number) : 0;

/**
 * Cartons the operator would ship if they sent everything ready at the
 * manufacturer. Floors — a part carton is not a shippable carton. A missing
 * or zero package quantity yields 0 rather than Infinity/NaN, so the input
 * placeholder degrades to "enter it yourself" instead of showing nonsense.
 */
export function cartonPrefill(readyUnits: number | undefined | null, packageQuantity: number | undefined | null): number {
  const pkg = usablePkg(packageQuantity);
  if (!pkg || !Number.isFinite(readyUnits) || (readyUnits as number) <= 0) return 0;
  return Math.floor((readyUnits as number) / pkg);
}

/** The live "= N units" readout. Matches how `planSplit` converts cartons to units. */
export function unitsFromCartons(cartons: number | undefined | null, packageQuantity: number | undefined | null): number {
  const pkg = usablePkg(packageQuantity);
  if (!pkg || !Number.isFinite(cartons) || (cartons as number) <= 0) return 0;
  return Math.round((cartons as number) * pkg);
}

export interface BatchInput {
  packageQuantity: number;
  readyUnits: number;
  prefillCartons: number;
  /** What the plan is sized from. NaN when the operator typed something unreadable —
   *  `planSplit` then says so, rather than the panel quietly substituting the default. */
  cartons: number;
  batchUnits: number;
  /** True while the field is empty and the prefill is standing in — drives "entered vs defaulted". */
  isDefaulted: boolean;
}

/**
 * Resolve the cartons input for the selected product: what the manufacturer has
 * ready, what that is in cartons, and whether the operator has overridden it.
 * An empty field means "use the default"; anything else — including nonsense —
 * is the operator's number and is passed through as typed.
 */
export function resolveBatchInput(args: {
  product: string;
  products: Array<{ product: string; packageQuantity: number }>;
  mfrReadyMap: Record<string, number>;
  typed: string;
}): BatchInput {
  const packageQuantity = args.products.find(p => p.product === args.product)?.packageQuantity ?? 0;
  const readyUnits = args.mfrReadyMap[args.product] ?? 0;
  const prefillCartons = cartonPrefill(readyUnits, packageQuantity);
  const isDefaulted = args.typed.trim() === '';
  const cartons = isDefaulted ? prefillCartons : Number(args.typed);
  return {
    packageQuantity, readyUnits, prefillCartons, isDefaulted, cartons,
    batchUnits: unitsFromCartons(cartons, packageQuantity),
  };
}

// ─── Days of cover ──────────────────────────────────────────

/**
 * The single place a `DocReading` becomes text. A capped reading means the
 * engine stopped counting, so it renders "400+" — printing a flat "400" would
 * claim a precision the walk never had.
 */
export function docLabel(reading: DocReading | null | undefined): string {
  if (!reading) return '—';
  return reading.capped ? `${reading.days}+` : `${reading.days}d`;
}

// ─── Transit constants: the boundary narrowing ──────────────

/**
 * The four transit tokens `planSplit` reads. `useShipmentConstants` returns an
 * open `Record<string, number>` off a network response; `SplitInput.transitDays`
 * is the closed `TransitDayMap`. They do not assign, deliberately — a missing
 * key once fabricated an arrival date by reading as `undefined` and adding 0
 * days. This list is that boundary.
 */
export const REQUIRED_TRANSIT_KEYS = ['SLOW_SEA', 'FAST_SEA', 'AWD_SLOW_SEA', 'AWD_TRANSFER'] as const;

export type TransitNarrowing =
  | { ok: true; transitDays: TransitDayMap }
  | { ok: false; missing: string[] };

/**
 * Narrow a live LOV map to the engine's closed map, or say which keys are
 * missing so the panel can render its "constants unavailable" state instead of
 * planning off a bad map. The four keys are written out literally below rather
 * than copied in a loop: an index signature does not satisfy a required
 * property in TypeScript, so dropping one here is a compile error, not a
 * runtime surprise. `planSplit` re-checks the same keys — belt and braces,
 * because the map still comes off the network.
 */
export function narrowTransitDays(raw: Record<string, number> | undefined | null): TransitNarrowing {
  const missing = REQUIRED_TRANSIT_KEYS.filter(k => !Number.isFinite(raw?.[k]));
  if (missing.length || !raw) return { ok: false, missing: [...missing] };
  return {
    ok: true,
    transitDays: {
      ...raw,
      SLOW_SEA: raw.SLOW_SEA,
      FAST_SEA: raw.FAST_SEA,
      AWD_SLOW_SEA: raw.AWD_SLOW_SEA,
      AWD_TRANSFER: raw.AWD_TRANSFER,
    },
  };
}

/** Methods the panel may offer. AIR is absent from `FBA_METHODS` and stays absent. */
export const OFFERED_FBA_METHODS = FBA_METHODS;

export interface TransitLedgerEntry { key: string; days: number; used: boolean }

/**
 * Every transit value the LOV supplied, for the ledger. The four the split
 * actually reads come first and are flagged `used`; anything else the LOV
 * carries (AIR) follows, so the operator can see it exists without it looking
 * like an option that was considered.
 */
export function transitLedgerEntries(transitDays: Record<string, number>): TransitLedgerEntry[] {
  const required: string[] = [...REQUIRED_TRANSIT_KEYS];
  const extras = Object.keys(transitDays).filter(k => !required.includes(k)).sort();
  return [...required, ...extras].map(key => ({
    key, days: transitDays[key], used: required.includes(key),
  }));
}

// ─── Inbound shipment ledger ────────────────────────────────

/**
 * Why a shipment did not feed the projection. Shown next to the greyed row so
 * an omission is arguable rather than silent.
 */
export const EXCLUSION_REASONS = {
  PO: 'PO — still at manufacturer',
  UNAPPROVED: 'Suggested, not approved',
  ARRIVED_FBA: 'Already arrived — already inside the FBA on-hand figure',
  ARRIVED_AWD: 'Already arrived at AWD — already inside the AWD on-hand figure',
  AWD_BOUND: 'AWD-bound — lands in reserve, not sellable at FBA',
  NO_UNITS: 'No units on the shipment — nothing for the projection to add',
  NO_ARRIVAL_DATE: 'No readable arrival date — the projection cannot place it',
  ALREADY_LANDED: 'Arrival date has already passed — assumed to be inside the FBA on-hand figure, not counted a second time',
  BEYOND_HORIZON: 'Arrives after the projection horizon ends — outside the window this plan models',
} as const;

export interface LedgerShipment {
  shipment: ProjectionShipment;
  qty: number;
  /** The day the engine places it, not the raw field — they differ for a timestamp. */
  arrivalDate: string;
  status: ShipmentStatus;
  destination: 'FBA' | 'AWD';
  /** null on a counted row; the reason string on an excluded one. */
  exclusionReason: string | null;
}

export interface ShipmentLedger {
  counted: LedgerShipment[];
  excluded: LedgerShipment[];
}

/** The window the engine's walk actually covers, read off the series it produced. */
export interface WalkWindow { from: string; to: string }

/**
 * The day key the engine files this arrival under — `localDateKey(new Date(...))`,
 * exactly what `arrivalsByDay` builds its map from. Deriving it the same way is
 * what lets the window comparison below be true rather than approximately true:
 * a `2026-09-10T00:00:00Z` arrival is a different local day in a timezone behind
 * UTC, and the ledger must agree with the walk, not with the raw string.
 */
function arrivalKey(s: ProjectionShipment): string | null {
  if (!s.arrival_date) return null;
  const d = new Date(s.arrival_date);
  return isNaN(d.getTime()) ? null : localDateKey(d);
}

/**
 * First reason that applies, most fundamental first: not shipped > not
 * committed > not FBA > nothing in it > cannot be placed > lands outside the
 * modelled window.
 *
 * `window` is null only when there is no plan to have a window — no window
 * judgement is made in that case, and the panel renders no ledger anyway.
 */
function exclusionReasonFor(s: ProjectionShipment, window: WalkWindow | null): string | null {
  if (EXCLUDED_STATUSES.has(s.status)) return EXCLUSION_REASONS.PO;
  const destination = destinationOf(s);
  if (!CONFIRMED_STATUSES.has(s.status)) {
    if (s.status !== 'arrived') return EXCLUSION_REASONS.UNAPPROVED;
    // Destination qualifies the reason: an arrived AWD shipment is in the AWD figure.
    return destination === 'AWD' ? EXCLUSION_REASONS.ARRIVED_AWD : EXCLUSION_REASONS.ARRIVED_FBA;
  }
  if (destination !== 'FBA') return EXCLUSION_REASONS.AWD_BOUND;
  if (!(s.qty > 0)) return EXCLUSION_REASONS.NO_UNITS;
  const key = arrivalKey(s);
  if (!key) return EXCLUSION_REASONS.NO_ARRIVAL_DATE;
  if (window && key < window.from) return EXCLUSION_REASONS.ALREADY_LANDED;
  if (window && key > window.to) return EXCLUSION_REASONS.BEYOND_HORIZON;
  return null;
}

/**
 * Split the product's shipments into the ones the projection counted and the
 * ones it did not.
 *
 * "Counted" is a stronger claim than `confirmedFbaInbound`: it means the units
 * actually moved the projection. The engine drops three further classes of
 * shipment silently, inside `shipmentArrivals` / `arrivalsByDay` / `walkFba` —
 * an unparseable date, a non-positive quantity, and an arrival outside the
 * walked window. `walkFba` starts at today and reads no key before it, so a
 * past-dated arrival contributes nothing; that is correct, because such stock
 * is presumed to be inside the live `fbaOnHand` snapshot already and adding it
 * again would double-count. The ledger's job is to say so out loud. Printing
 * "adds 9,000 units" for a delivery the walk never saw would invite confidence
 * instead of a question — worse than the silent omission this exists to prevent.
 */
export function partitionShipmentsForLedger(
  shipments: ProjectionShipment[], window: WalkWindow | null,
): ShipmentLedger {
  const counted: LedgerShipment[] = [];
  const excluded: LedgerShipment[] = [];
  for (const shipment of shipments) {
    const exclusionReason = exclusionReasonFor(shipment, window);
    const row: LedgerShipment = {
      shipment,
      qty: shipment.qty,
      arrivalDate: arrivalKey(shipment) ?? shipment.arrival_date,
      status: shipment.status,
      destination: destinationOf(shipment),
      exclusionReason,
    };
    (exclusionReason === null ? counted : excluded).push(row);
  }
  return { counted, excluded };
}

/** The engine's walk window, taken from the series it produced. Null when there is no plan. */
export function walkWindowOf(series: Array<{ date: string }>): WalkWindow | null {
  return series.length ? { from: series[0].date, to: series[series.length - 1].date } : null;
}

/** Units the projection actually adds — the counted rows only. */
export function countedInboundUnits(ledger: ShipmentLedger): number {
  return ledger.counted.reduce((s, r) => s + r.qty, 0);
}

// ─── Demand curve assembly ──────────────────────────────────

export interface DemandCurveArgs {
  product: string;
  demandMap: ForecastDemandMap;
  seasonMap: MonthSeasonMap;
  metaMap: ForecastMetaMap;
  growthOverrides?: Record<string, number>;
}

/**
 * The same three-part curve `StockProjectionChart` builds, so the split panel
 * and the Weekly Stock Projection cannot disagree about a product's demand.
 * A product with no family carries no seasonality — flat months, not a
 * borrowed neighbour's peak.
 */
export function buildDemandCurve(a: DemandCurveArgs): DemandCurve {
  const family = a.metaMap[a.product]?.family;
  return {
    productDemand: a.demandMap[a.product] || {},
    familySeason: family ? (a.seasonMap[family] || {}) : {},
    growth: a.growthOverrides?.[a.product] ?? 1.0,
  };
}

// ─── Demand ledger ──────────────────────────────────────────

export interface DemandLedgerRow {
  yearMonth: number;          // 202611
  label: string;              // 'Nov 2026'
  forecastUnits: number;      // straight from the forecast, before growth
  growth: number;             // the growth override in force
  units: number;              // forecastUnits x growth — what the curve actually spends
  daysInMonth: number;
  peakDays: number;
  offseasonDays: number;
  holidays: string | null;
  offseasonDailyUnits: number;
  peakDailyUnits: number;     // equals the offseason rate when no peak weighting applies
}

/** Parse a `YYYY-MM-DD` key as a local date. Returns null when it will not parse. */
function parseDateKey(key: string): Date | null {
  const parts = (key || '').split('-').map(Number);
  if (parts.length !== 3 || parts.some(n => !Number.isFinite(n))) return null;
  const [y, m, d] = parts;
  const date = new Date(y, m - 1, d);
  return isNaN(date.getTime()) ? null : date;
}

/**
 * Monthly forecast figures across the horizon, with growth applied and the
 * family's peak-day weighting shown per month.
 *
 * The daily rates are read back out of `dailyDemandOn` — the function the
 * engine itself consumes — rather than re-derived here, so the ledger reports
 * the split's real inputs instead of a second opinion about them. `from`/`to`
 * are the first and last day of the engine's own series, so the horizon shown
 * is the horizon planned.
 */
export function buildDemandLedger(curve: DemandCurve, from: string, to: string): DemandLedgerRow[] {
  const start = parseDateKey(from);
  const end = parseDateKey(to);
  if (!start || !end || end < start) return [];

  const rows: DemandLedgerRow[] = [];
  const cursor = new Date(start.getFullYear(), start.getMonth(), 1);
  const lastMonth = new Date(end.getFullYear(), end.getMonth(), 1);

  while (cursor <= lastMonth) {
    const year = cursor.getFullYear();
    const month = cursor.getMonth();               // 0-based
    const yearMonth = year * 100 + (month + 1);
    const days = daysInMonth(year, month);
    const season = curve.familySeason[yearMonth];
    const peakDays = season?.peakDays ?? 0;
    const forecastUnits = curve.productDemand[yearMonth] || 0;

    rows.push({
      yearMonth,
      label: `${MONTH_ABBR[month]} ${year}`,
      forecastUnits,
      growth: curve.growth,
      units: forecastUnits * curve.growth,
      daysInMonth: days,
      peakDays,
      offseasonDays: season?.offseasonDays ?? (days - peakDays),
      holidays: season?.holidays ?? null,
      // Day 1 is always an offseason day (peak days are the tail of the month);
      // the last day is the peak day whenever the month has any.
      offseasonDailyUnits: dailyDemandOn(new Date(year, month, 1), curve).units,
      peakDailyUnits: dailyDemandOn(new Date(year, month, days), curve).units,
    });

    cursor.setMonth(cursor.getMonth() + 1);
  }

  return rows;
}
