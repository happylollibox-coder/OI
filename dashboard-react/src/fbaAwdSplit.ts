// Pure FBA/AWD split engine. Given a batch of cartons ready at the
// manufacturer, decide how much goes to FBA now, how much to AWD, by which
// method, and what AWD->FBA transfers hold FBA near its DOC target.
//
// Advisory only: nothing here writes, and nothing here is a commitment.
// Modelling note: unmet demand is lost, not backlogged. Stock floors at zero.
import {
  addDays, localDateKey, getMonday, demandOverWindow, dailyDemandOn,
  CONFIRMED_STATUSES, EXCLUDED_STATUSES, parseLocalDate,
  type DemandCurve, type ProjectionShipment,
} from './stockProjection';

export type FbaMethod = 'SLOW_SEA' | 'FAST_SEA';

/** Cheapest first. AIR is deliberately absent — never auto-selected, never offered. */
export const FBA_METHODS: readonly FbaMethod[] = ['SLOW_SEA', 'FAST_SEA'];

/**
 * Transit days by shipment method, read from DE_LIST_OF_VALUES at runtime.
 * Extra keys (AIR) are fine; the four the engine needs are not optional, so a
 * dropped LOV row is a compile error here and a `fail()` at runtime.
 */
export type TransitDayMap =
  Record<FbaMethod | 'AWD_SLOW_SEA' | 'AWD_TRANSFER', number> & Record<string, number>;

const REQUIRED_TRANSIT_KEYS: readonly string[] = [...FBA_METHODS, 'AWD_SLOW_SEA', 'AWD_TRANSFER'];

/**
 * Operator-facing names for the transit tokens. This is the shared home for
 * them — the engine and the Excel export in ShipmentEngine.tsx both read here.
 * Day counts are deliberately left out: a caption saying "60 Days" outlived the
 * LOV moving to 63. Callers that want the number read it off `transitDays`.
 */
export const METHOD_CAPTIONS: Record<string, string> = {
  AIR: 'Air',
  SLOW_SEA: 'Slow Sea',
  FAST_SEA: 'Fast Sea',
  AWD_SLOW_SEA: 'AWD Slow Sea',
  AWD_TRANSFER: 'AWD → FBA Transfer',
};

export const methodCaption = (m: string): string => METHOD_CAPTIONS[m] ?? m;

/** Transfers landing this close together are one move, not two. */
const TRANSFER_MERGE_WINDOW_DAYS = 14;

/**
 * How far `docFromStock` will count before giving up. Four times the target is
 * far past any level worth acting on, and it keeps the walk terminating when
 * the demand curve runs out and cover is nominally infinite.
 */
const DOC_CAP_MULTIPLE = 4;

const DAY_MS = 86_400_000;

export interface SplitInput {
  cartons: number;
  packageQuantity: number;
  fbaOnHand: number;
  awdOnHand: number;
  shipments: ProjectionShipment[];
  curve: DemandCurve;
  transitDays: TransitDayMap;
  fbaInboundBufferDays: number;
  today: Date;
  targetDoc: number;
  methodOverride?: FbaMethod;
}

/** A days-of-cover reading. `capped` means the walk hit its cap — render "400+". */
export interface DocReading {
  days: number;
  capped: boolean;
}

export interface SplitLeg {
  destination: 'FBA' | 'AWD';
  units: number;
  cartons: number;
  method: string;
  shipDate: string;
  transitDays: number;
  arrivalDate: string;
  sellableDate: string;
  reason: string;
}

export interface TransferRow {
  orderDate: string;
  arrivalDate: string;
  units: number;
  cartons: number;
  docBefore: DocReading;
  docAfter: DocReading;
}

/** One day of the projection the engine actually decided from. */
export interface SeriesDay {
  date: string;
  fbaUnits: number;
  awdUnits: number;
  doc: number;
  docCapped: boolean;
  arrivals: number;
  arrivalNote?: string;
}

export interface SplitPlan {
  ok: boolean;
  error?: string;
  units: number;
  legs: SplitLeg[];
  transfers: TransferRow[];
  series: SeriesDay[];
  /** Ledger numbers behind the split, so the panel never parses the prose. */
  targetUnits: number;
  onHandAtSellable: number;
  shortfallUnits: number;
  autoMethod: FbaMethod;
  methodOverridden: boolean;
  shipDate: string;
  /** The date targetUnits and onHandAtSellable are keyed to — readable even with no FBA leg. */
  sellableDate: string;
  /** Span of the series actually built, so the panel never infers it by reading `series`. */
  walkWindow: { from: string; to: string } | null;
  fbaDocAtArrival: DocReading;
  fbaOosDate: string | null;
  leftoverAwdUnits: number;
  warnings: string[];
}

const fail = (error: string): SplitPlan => ({
  ok: false, error, units: 0, legs: [], transfers: [], series: [],
  targetUnits: 0, onHandAtSellable: 0, shortfallUnits: 0,
  autoMethod: 'SLOW_SEA', methodOverridden: false, shipDate: '',
  sellableDate: '', walkWindow: null,
  fbaDocAtArrival: { days: 0, capped: false }, fbaOosDate: null,
  leftoverAwdUnits: 0, warnings: [],
});

/** Midnight of the same local day, so every date in the engine is comparable. */
function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

/** Whole days between two local midnights. Rounds, so DST hours never leak in. */
function daysBetween(later: Date, earlier: Date): number {
  return Math.round((later.getTime() - earlier.getTime()) / DAY_MS);
}

/** Ship dates snap to Wednesday, matching the plan engine's ship_wednesday convention. */
export function nextWednesday(from: Date): Date {
  const d = startOfDay(from);
  return addDays(d, (3 - d.getDay() + 7) % 7);
}

function isConfirmed(s: ProjectionShipment): boolean {
  return CONFIRMED_STATUSES.has(s.status);
}

/** Destination is not stored — it is read off the route, as the Excel export does. */
export function destinationOf(s: ProjectionShipment): 'FBA' | 'AWD' {
  return (s.route || '').includes('AWD') ? 'AWD' : 'FBA';
}

export function confirmedFbaInbound(shipments: ProjectionShipment[]): ProjectionShipment[] {
  return shipments.filter(s =>
    !EXCLUDED_STATUSES.has(s.status) && isConfirmed(s) && destinationOf(s) === 'FBA');
}

interface Arrival { date: Date; units: number; note?: string }

function shipmentArrivals(shipments: ProjectionShipment[], note?: string): Arrival[] {
  const out: Arrival[] = [];
  for (const s of shipments) {
    const a = parseLocalDate(s.arrival_date);
    if (!a) continue;
    out.push({ date: startOfDay(a), units: s.qty, note });
  }
  return out;
}

function arrivalsByDay(arrivals: Arrival[]): Map<string, { units: number; notes: string[] }> {
  const byDay = new Map<string, { units: number; notes: string[] }>();
  for (const a of arrivals) {
    if (!(a.units > 0)) continue;
    const key = localDateKey(a.date);
    const slot = byDay.get(key) ?? { units: 0, notes: [] };
    slot.units += a.units;
    if (a.note && !slot.notes.includes(a.note)) slot.notes.push(a.note);
    byDay.set(key, slot);
  }
  return byDay;
}

/**
 * Day-by-day FBA balance from `from` across `days` days.
 * `onHand[i]` is the stock on day `from + i` after that day's arrivals and
 * before that day's demand — the number a DOC reading at that date works from.
 * Stock floors at zero every day: unmet demand is lost, never backlogged.
 * `oosIndex` is the first day the balance is exhausted, or -1.
 */
function walkFba(
  startStock: number, arrivals: Arrival[], curve: DemandCurve, from: Date, days: number,
): { onHand: number[]; oosIndex: number } {
  const byDay = arrivalsByDay(arrivals);
  const onHand: number[] = new Array(days + 1);
  let stock = Math.max(0, startStock);
  let oosIndex = -1;
  for (let i = 0; i <= days; i++) {
    const day = addDays(from, i);
    stock += byDay.get(localDateKey(day))?.units ?? 0;
    onHand[i] = stock;
    stock -= dailyDemandOn(day, curve).units;
    if (stock <= 0) {
      if (oosIndex < 0) oosIndex = i;
      stock = 0;
    }
  }
  return { onHand, oosIndex };
}

/** FBA units on hand at `when`, given confirmed FBA-bound arrivals. Floors at zero. */
export function projectedFbaAt(
  when: Date, fbaOnHand: number, inbound: ProjectionShipment[], curve: DemandCurve, today: Date,
): number {
  const from = startOfDay(today);
  const days = daysBetween(startOfDay(when), from);
  if (days < 0) return Math.max(0, fbaOnHand);
  return walkFba(fbaOnHand, shipmentArrivals(inbound), curve, from, days).onHand[days];
}

/** First day FBA hits zero, walking day by day. Null if it never does inside `horizonDays`. */
export function firstOosDate(
  fbaOnHand: number, inbound: ProjectionShipment[], curve: DemandCurve, today: Date, horizonDays: number,
): Date | null {
  const from = startOfDay(today);
  const { oosIndex } = walkFba(fbaOnHand, shipmentArrivals(inbound), curve, from, horizonDays - 1);
  return oosIndex < 0 ? null : addDays(from, oosIndex);
}

/**
 * Cheapest method that still lands before FBA runs out. Escalating costs money,
 * so the reason names the cheaper option it rejected and when that would have
 * landed. If even the fastest lands late, take it and report the gap.
 */
export function selectFbaMethod(
  shipDate: Date, oos: Date | null, transitDays: TransitDayMap, bufferDays: number,
): { method: FbaMethod; reason: string; lateDays: number } {
  const landed = (m: FbaMethod) => addDays(shipDate, transitDays[m] + bufferDays);
  const fmt = (d: Date) => localDateKey(d);
  const name = (m: FbaMethod) => methodCaption(m);

  if (!oos) {
    return {
      method: 'SLOW_SEA',
      reason: `FBA does not run out inside the horizon, so the cheapest route wins — ${name('SLOW_SEA')} lands ${fmt(landed('SLOW_SEA'))}`,
      lateDays: 0,
    };
  }

  const rejected: string[] = [];
  for (const m of FBA_METHODS) {
    if (landed(m) <= oos) {
      const why = rejected.length
        ? `${rejected.join('; ')}, so ${name(m)} lands ${fmt(landed(m))} — escalated to land before FBA runs out ${fmt(oos)}`
        : `${name(m)} lands ${fmt(landed(m))}, before FBA runs out ${fmt(oos)} — cheapest route, no escalation needed`;
      return { method: m, reason: why, lateDays: 0 };
    }
    rejected.push(`${name(m)} would land ${fmt(landed(m))}, after FBA runs out ${fmt(oos)}`);
  }

  const fastest = FBA_METHODS[FBA_METHODS.length - 1];
  const lateDays = daysBetween(landed(fastest), oos);
  return {
    method: fastest,
    reason: `${name(fastest)} is the fastest route allowed and still lands ${fmt(landed(fastest))}, ${lateDays}d after FBA runs out ${fmt(oos)} — unavoidable stockout`,
    lateDays,
  };
}

const floorToCartons = (units: number, pkg: number) => Math.floor(Math.max(0, units) / pkg) * pkg;

/**
 * Days of cover from a stock level at a date: how many whole days the stock
 * fully covers, walking the daily curve. Stock sized to cover exactly N days
 * reads N, not N-1 — the boundary matters because `>= targetDoc` decides
 * whether a transfer is ordered.
 */
export function docFromStock(stock: number, from: Date, curve: DemandCurve, maxDays: number): DocReading {
  let rem = stock;
  for (let i = 0; i < maxDays; i++) {
    const need = dailyDemandOn(addDays(from, i), curve).units;
    if (rem < need) return { days: i, capped: false };
    rem -= need;
  }
  return { days: maxDays, capped: true };
}

export function planSplit(input: SplitInput): SplitPlan {
  const {
    cartons, packageQuantity: pkg, fbaOnHand, awdOnHand, shipments, curve,
    transitDays, fbaInboundBufferDays: buffer, targetDoc, methodOverride,
  } = input;

  if (!Number.isFinite(pkg) || pkg <= 0) return fail('Invalid package quantity — cannot convert cartons to units.');
  if (!Number.isFinite(cartons) || cartons <= 0) return fail('Enter a number of cartons greater than zero.');
  if (!Number.isFinite(targetDoc) || targetDoc <= 0) return fail('Target days of cover must be greater than zero.');
  if (!Number.isFinite(fbaOnHand) || fbaOnHand < 0) return fail('FBA on-hand units must be zero or more.');
  if (!Number.isFinite(awdOnHand) || awdOnHand < 0) return fail('AWD on-hand units must be zero or more.');
  if (!Number.isFinite(buffer) || buffer < 0) return fail('FBA inbound buffer days must be zero or more.');
  // The transit map comes off a network response, so a dropped LOV row must not
  // silently become a zero-day leg that lands the day it ships.
  // Zero is as wrong as absent: a 0-day leg arrives the day it ships, and a
  // negative one arrives before it ships. Both silently move the schedule.
  const badTransit = REQUIRED_TRANSIT_KEYS.filter(k => !(transitDays?.[k] > 0));
  if (badTransit.length) {
    return fail(`Missing or non-positive shipment transit days for ${badTransit.map(methodCaption).join(', ')} — check the SHIPMENT_TYPE list of values.`);
  }
  // growth scales every day of the curve, so growth 0 is as blank as an empty forecast.
  if (!(curve.growth > 0) || Object.values(curve.productDemand).every(v => !v)) {
    return fail('No demand forecast for this product — cannot compute days of cover.');
  }

  const today = startOfDay(input.today);
  const units = Math.round(cartons * pkg);
  const warnings: string[] = [];
  const inbound = confirmedFbaInbound(shipments);
  const shipDate = nextWednesday(today);
  const docCap = targetDoc * DOC_CAP_MULTIPLE;

  // Horizon must outrun the display window: forward DOC at the last shown week
  // needs targetDoc days of demand beyond it, and transfers run past year-end.
  const horizonDays = 365 + targetDoc;
  const oos = firstOosDate(fbaOnHand, inbound, curve, today, horizonDays);

  const selected = selectFbaMethod(shipDate, oos, transitDays, buffer);
  // An override must name a method we actually offer. AIR is in the injected
  // transit map, so an un-narrowed string reaching here must not become a plan.
  const override = methodOverride && FBA_METHODS.includes(methodOverride) ? methodOverride : undefined;
  const method: FbaMethod = override ?? selected.method;
  if (methodOverride && !override) {
    warnings.push(`Ignored the requested method "${methodCaption(methodOverride)}" — not an FBA route this engine offers. Used ${methodCaption(method)} instead.`);
  }
  const methodReason = override
    ? `${methodCaption(method)} chosen manually (auto pick was ${methodCaption(selected.method)}: ${selected.reason})`
    : selected.reason;
  // An override cannot fix a late landing, only make it later — always say so.
  if (selected.lateDays > 0) {
    warnings.push(`FBA runs out ${selected.lateDays} day(s) before the fastest allowed method can land. Stockout is unavoidable from this batch alone.`);
  }

  const fbaTransit = transitDays[method];
  const fbaArrival = addDays(shipDate, fbaTransit);
  const fbaSellable = addDays(fbaArrival, buffer);
  const lastCoveredDay = addDays(fbaSellable, targetDoc - 1);

  // targetDoc DOC at the sellable date means holding exactly the demand of the next targetDoc days.
  const target = demandOverWindow(fbaSellable, addDays(fbaSellable, targetDoc), curve);
  const onHandAtSellable = projectedFbaAt(fbaSellable, fbaOnHand, inbound, curve, today);
  const needUnits = Math.max(0, target - onHandAtSellable);
  // Round once and derive, so prose and the structured fields beside it agree.
  const targetShown = Math.round(target);
  const onHandShown = Math.round(onHandAtSellable);
  const needShown = Math.max(0, targetShown - onHandShown);
  const batchUnits = floorToCartons(units, pkg);
  const fbaUnits = Math.min(floorToCartons(needUnits, pkg), batchUnits);
  const awdUnits = units - fbaUnits;
  const batchIsBinding = batchUnits < floorToCartons(needUnits, pkg);

  const stockAtSellable = onHandAtSellable + fbaUnits;
  const docAtArrival: DocReading = stockAtSellable > 0
    ? docFromStock(stockAtSellable, fbaSellable, curve, docCap)
    : { days: 0, capped: false };

  if (fbaUnits === 0) {
    warnings.push(`FBA is already at or above ${targetDoc} DOC on ${localDateKey(fbaSellable)} — the whole batch goes to AWD.`);
  }
  if (awdUnits === 0) {
    // Anything under a carton is the rounding-down remainder, not a real shortfall.
    const shortfall = needUnits - fbaUnits;
    if (shortfall > pkg) {
      const shortDays = Math.max(0, targetDoc - docAtArrival.days);
      warnings.push(`Batch is too small to reach ${targetDoc} DOC — short by ${Math.round(shortfall)} units (~${shortDays} days).`);
    }
  }

  const awdTransit = transitDays.AWD_SLOW_SEA;
  const awdArrival = addDays(shipDate, awdTransit);
  const transferTransit = transitDays.AWD_TRANSFER;

  const legs: SplitLeg[] = [];
  if (fbaUnits > 0) {
    const ledger = `${targetDoc} DOC from ${localDateKey(fbaSellable)} is ${targetShown} units of demand (through ${localDateKey(lastCoveredDay)}), less ${onHandShown} projected on hand = ${needShown} needed`;
    const sizing = batchIsBinding
      ? `The batch only holds ${units} units, so all of it goes to FBA and still lands ${needShown - fbaUnits} units short of target.`
      : `Rounded down to whole cartons: ${fbaUnits / pkg} × ${pkg} = ${fbaUnits} units.`;
    legs.push({
      destination: 'FBA', units: fbaUnits, cartons: fbaUnits / pkg, method,
      shipDate: localDateKey(shipDate), transitDays: fbaTransit,
      arrivalDate: localDateKey(fbaArrival), sellableDate: localDateKey(fbaSellable),
      reason: `${methodReason}. ${ledger}. ${sizing}`,
    });
  }
  if (awdUnits > 0) {
    const origin = fbaUnits > 0
      ? `Remainder after topping FBA to ${targetDoc} DOC.`
      : `FBA is already at or above ${targetDoc} DOC on ${localDateKey(fbaSellable)}, so none of this batch is needed there yet.`;
    legs.push({
      destination: 'AWD', units: awdUnits, cartons: awdUnits / pkg, method: 'AWD_SLOW_SEA',
      shipDate: localDateKey(shipDate), transitDays: awdTransit,
      arrivalDate: localDateKey(awdArrival), sellableDate: localDateKey(awdArrival),
      reason: `${origin} ${methodCaption('AWD_SLOW_SEA')} is the only AWD route (${awdTransit}d), landing ${localDateKey(awdArrival)}. Not sellable there — each transfer into FBA adds ${transferTransit}d transit plus ${buffer}d inbound processing.`,
    });
  }

  const { transfers, leftover, series } = scheduleTransfers({
    curve, today, horizonDays, targetDoc, pkg, docCap,
    transferLeadDays: transferTransit + buffer,
    fbaOnHand, inbound,
    batchArrival: fbaUnits > 0 ? { date: fbaSellable, units: fbaUnits, note: 'FBA batch' } : null,
    pool: [
      { availableFrom: today, units: awdOnHand },
      ...(awdUnits > 0 ? [{ availableFrom: awdArrival, units: awdUnits, note: 'AWD batch' }] : []),
    ].filter(t => t.units > 0),
  });

  if (leftover > 0) {
    warnings.push(`${leftover} units remain at AWD at the end of the horizon — not needed to hold ${targetDoc} DOC.`);
  }

  return {
    ok: true, units, legs, transfers, series,
    targetUnits: targetShown,
    onHandAtSellable: onHandShown,
    shortfallUnits: Math.max(0, needShown - fbaUnits),
    autoMethod: selected.method,
    methodOverridden: override !== undefined,
    shipDate: localDateKey(shipDate),
    sellableDate: localDateKey(fbaSellable),
    walkWindow: series.length
      ? { from: series[0].date, to: series[series.length - 1].date }
      : null,
    fbaDocAtArrival: docAtArrival,
    fbaOosDate: oos ? localDateKey(oos) : null,
    leftoverAwdUnits: leftover,
    warnings,
  };
}

export interface PoolTranche { availableFrom: Date; units: number; note?: string }

/**
 * The AWD pool as a single object: what is available on a date, what can be
 * drawn from it, and what is left. Keeping the arithmetic here is what makes
 * `drawn total + leftover === opening total` a property of one small unit.
 */
export function createAwdPool(tranches: PoolTranche[]) {
  const opening: PoolTranche[] = tranches.map(t => ({ ...t, availableFrom: startOfDay(t.availableFrom) }));
  const remaining = opening.map(t => ({ ...t }));

  return {
    /** Untouched tranches, for projecting the AWD balance over time. */
    opening: opening as readonly PoolTranche[],

    total(): number {
      return opening.reduce((s, t) => s + t.units, 0);
    },

    availableAt(when: Date): number {
      return remaining.reduce((s, t) => (t.availableFrom <= when ? s + t.units : s), 0);
    },

    /** Draws up to `qty` from tranches that have landed by `when`. Returns what it got. */
    draw(when: Date, qty: number): number {
      let left = qty;
      for (const t of remaining) {
        if (left <= 0) break;
        if (t.availableFrom > when) continue;
        const take = Math.min(t.units, left);
        t.units -= take;
        left -= take;
      }
      return qty - left;
    },

    leftover(): number {
      return remaining.reduce((s, t) => s + t.units, 0);
    },
  };
}

interface TransferParams {
  curve: DemandCurve;
  today: Date;
  horizonDays: number;
  targetDoc: number;
  pkg: number;
  docCap: number;
  transferLeadDays: number;
  fbaOnHand: number;
  inbound: ProjectionShipment[];
  batchArrival: Arrival | null;
  pool: PoolTranche[];
}

interface PlannedTransfer { orderDate: Date; arrival: Date; units: number; docBefore: DocReading }

/**
 * Walk weekly. At each week, look ahead by the transfer lead time: if FBA DOC
 * would be under target by the time a transfer ordered that week could land,
 * order one sized to restore the target, capped by the pool available on the
 * order date and floored to whole cartons. A transfer landing within
 * TRANSFER_MERGE_WINDOW_DAYS of the previous one is folded into it, so the
 * output is roughly monthly moves rather than a weekly dribble.
 *
 * Every unit drawn from the pool lands in an emitted transfer: the projection
 * reads its arrivals straight off `emitted`, so the two can never drift apart.
 */
export function scheduleTransfers(
  p: TransferParams,
): { transfers: TransferRow[]; leftover: number; series: SeriesDay[] } {
  const {
    curve, today, horizonDays, targetDoc, pkg, docCap,
    transferLeadDays, fbaOnHand, inbound, batchArrival, pool,
  } = p;
  const emitted: PlannedTransfer[] = [];
  const awd = createAwdPool(pool);

  const baseArrivals = shipmentArrivals(inbound, 'Inbound shipment');
  if (batchArrival) baseArrivals.push(batchArrival);

  const transferArrivals = (): Arrival[] =>
    emitted.map(e => ({ date: e.arrival, units: e.units, note: 'AWD→FBA transfer' }));

  let onHandCache: number[] | null = null;
  const fbaOnHandByDay = (): number[] => {
    if (!onHandCache) {
      onHandCache = walkFba(
        fbaOnHand, baseArrivals.concat(transferArrivals()), curve, today, horizonDays,
      ).onHand;
    }
    return onHandCache;
  };
  const stockAt = (when: Date): number => {
    const arr = fbaOnHandByDay();
    const i = daysBetween(when, today);
    return arr[Math.min(Math.max(i, 0), arr.length - 1)];
  };

  // Orders are placed on Mondays, never in the past.
  const firstMonday = getMonday(today) < today ? addDays(getMonday(today), 7) : getMonday(today);
  const weeks = Math.floor((horizonDays - daysBetween(firstMonday, today)) / 7);

  for (let w = 0; w < weeks; w++) {
    const orderDate = addDays(firstMonday, w * 7);
    const arrival = addDays(orderDate, transferLeadDays);
    if (daysBetween(arrival, today) > horizonDays) break; // would land past what we model

    const before = stockAt(arrival);
    const docBefore = docFromStock(before, arrival, curve, docCap);
    if (docBefore.days >= targetDoc) continue;

    const need = demandOverWindow(arrival, addDays(arrival, targetDoc), curve) - before;

    // Merging folds this week's move into the previous row, which means it
    // ships on THAT row's earlier order date. Only legal if the stock had
    // already landed at AWD by then — otherwise the row would instruct moving
    // goods that are still at sea. When they straddle a pool arrival we split
    // instead, so every row stays executable exactly as written.
    const prev = emitted[emitted.length - 1];
    const inMergeWindow = prev !== undefined
      && daysBetween(arrival, prev.arrival) <= TRANSFER_MERGE_WINDOW_DAYS;
    const mergeQty = inMergeWindow
      ? floorToCartons(Math.min(need, awd.availableAt(prev!.orderDate)), pkg)
      : 0;

    if (inMergeWindow && mergeQty > 0) {
      const drawn = awd.draw(prev!.orderDate, mergeQty);
      if (drawn > 0) {
        prev!.units += drawn;
        onHandCache = null; // the projection must see these units
        continue;
      }
    }

    const qty = floorToCartons(Math.min(need, awd.availableAt(orderDate)), pkg);
    if (qty <= 0) continue;

    const drawn = awd.draw(orderDate, qty);
    if (drawn <= 0) continue;
    onHandCache = null; // the projection must see these units

    emitted.push({ orderDate, arrival, units: drawn, docBefore });
  }

  // docAfter is read from the finished plan, so merges are already reflected.
  const transfers: TransferRow[] = emitted.map(e => ({
    orderDate: localDateKey(e.orderDate),
    arrivalDate: localDateKey(e.arrival),
    units: e.units,
    cartons: Math.round(e.units / pkg),
    docBefore: e.docBefore,
    docAfter: docFromStock(stockAt(e.arrival), e.arrival, curve, docCap),
  }));

  return {
    transfers,
    leftover: awd.leftover(),
    series: buildSeries({
      curve, today, horizonDays, docCap,
      fbaByDay: fbaOnHandByDay(),
      arrivals: baseArrivals.concat(transferArrivals()),
      pool: awd.opening,
      transfers: emitted,
    }),
  };
}

interface SeriesParams {
  curve: DemandCurve;
  today: Date;
  horizonDays: number;
  docCap: number;
  fbaByDay: number[];
  arrivals: Arrival[];
  pool: readonly PoolTranche[];
  transfers: PlannedTransfer[];
}

/**
 * The day-by-day picture the engine decided from, so the panel's chart and
 * table read the same numbers the split did — no weekly re-interpolation.
 * Units leave AWD on a transfer's order date and reach FBA on its arrival
 * date; in between they belong to neither, which is what actually happens.
 * Both columns are opening balances: after that day's arrivals, before that
 * day's outflow (FBA's demand, AWD's departures).
 */
function buildSeries(p: SeriesParams): SeriesDay[] {
  const { curve, today, horizonDays, docCap, fbaByDay, arrivals, pool, transfers } = p;
  const inbound = arrivalsByDay(arrivals);

  const awdIn = arrivalsByDay(
    pool.filter(t => t.availableFrom > today).map(t => ({ date: t.availableFrom, units: t.units, note: t.note })),
  );
  const awdOut = new Map<string, number>();
  for (const t of transfers) {
    const key = localDateKey(t.orderDate);
    awdOut.set(key, (awdOut.get(key) ?? 0) + t.units);
  }

  let awdBalance = pool.reduce((s, t) => (t.availableFrom <= today ? s + t.units : s), 0);
  const out: SeriesDay[] = [];

  for (let i = 0; i <= horizonDays; i++) {
    const day = addDays(today, i);
    const key = localDateKey(day);
    const landedFba = inbound.get(key);
    const landedAwd = awdIn.get(key);

    awdBalance += landedAwd?.units ?? 0;
    const doc = docFromStock(fbaByDay[i], day, curve, docCap);
    const notes = [...(landedFba?.notes ?? []), ...(landedAwd?.notes ?? [])];

    out.push({
      date: key,
      fbaUnits: Math.round(fbaByDay[i]),
      awdUnits: Math.round(awdBalance),
      doc: doc.days,
      docCapped: doc.capped,
      arrivals: Math.round((landedFba?.units ?? 0) + (landedAwd?.units ?? 0)),
      ...(notes.length ? { arrivalNote: notes.join(' + ') } : {}),
    });

    awdBalance -= awdOut.get(key) ?? 0;
  }

  return out;
}
