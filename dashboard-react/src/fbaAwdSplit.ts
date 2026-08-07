// Pure FBA/AWD split engine. Given a batch of cartons ready at the
// manufacturer, decide how much goes to FBA now, how much to AWD, by which
// method, and what AWD->FBA transfers hold FBA near its DOC target.
//
// Advisory only: nothing here writes, and nothing here is a commitment.
// Modelling note: unmet demand is lost, not backlogged. Stock floors at zero.
import {
  addDays, localDateKey, getMonday, demandOverWindow, dailyDemandOn,
  CONFIRMED_STATUSES, EXCLUDED_STATUSES,
  type DemandCurve, type ProjectionShipment,
} from './stockProjection';

export type FbaMethod = 'SLOW_SEA' | 'FAST_SEA';

/** Cheapest first. AIR is deliberately absent — never auto-selected, never offered. */
export const FBA_METHODS: readonly FbaMethod[] = ['SLOW_SEA', 'FAST_SEA'];

/** Transfers landing this close together are one move, not two. */
const TRANSFER_MERGE_WINDOW_DAYS = 14;

const DAY_MS = 86_400_000;

export interface SplitInput {
  product: string;
  cartons: number;
  packageQuantity: number;
  fbaOnHand: number;
  awdOnHand: number;
  shipments: ProjectionShipment[];
  curve: DemandCurve;
  transitDays: Record<string, number>;
  fbaInboundBufferDays: number;
  today: Date;
  targetDoc: number;
  methodOverride?: FbaMethod;
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
  docBefore: number;
  docAfter: number;
}

export interface SplitPlan {
  ok: boolean;
  error?: string;
  units: number;
  legs: SplitLeg[];
  transfers: TransferRow[];
  fbaDocAtArrival: number;
  fbaOosDate: string | null;
  leftoverAwdUnits: number;
  warnings: string[];
}

const fail = (error: string): SplitPlan => ({
  ok: false, error, units: 0, legs: [], transfers: [],
  fbaDocAtArrival: 0, fbaOosDate: null, leftoverAwdUnits: 0, warnings: [],
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

export function isConfirmed(s: ProjectionShipment): boolean {
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

interface Arrival { date: Date; units: number }

function shipmentArrivals(shipments: ProjectionShipment[]): Arrival[] {
  const out: Arrival[] = [];
  for (const s of shipments) {
    const a = new Date(s.arrival_date);
    if (isNaN(a.getTime())) continue;
    out.push({ date: startOfDay(a), units: s.qty });
  }
  return out;
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
  const byDay = new Map<string, number>();
  for (const a of arrivals) {
    if (!(a.units > 0)) continue;
    const key = localDateKey(a.date);
    byDay.set(key, (byDay.get(key) ?? 0) + a.units);
  }

  const onHand: number[] = new Array(days + 1);
  let stock = Math.max(0, startStock);
  let oosIndex = -1;
  for (let i = 0; i <= days; i++) {
    const day = addDays(from, i);
    stock += byDay.get(localDateKey(day)) ?? 0;
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
export function fbaOosDate(
  fbaOnHand: number, inbound: ProjectionShipment[], curve: DemandCurve, today: Date, horizonDays: number,
): Date | null {
  const from = startOfDay(today);
  const { oosIndex } = walkFba(fbaOnHand, shipmentArrivals(inbound), curve, from, horizonDays - 1);
  return oosIndex < 0 ? null : addDays(from, oosIndex);
}

/**
 * Cheapest method that still lands before FBA runs out. If even the fastest
 * lands late, take the fastest and report the gap rather than hiding it.
 */
export function selectFbaMethod(
  shipDate: Date, oos: Date | null, transitDays: Record<string, number>, bufferDays: number,
): { method: FbaMethod; reason: string; lateDays: number } {
  const landed = (m: FbaMethod) => addDays(shipDate, (transitDays[m] ?? 0) + bufferDays);
  const fmt = (d: Date) => localDateKey(d);

  if (!oos) {
    return { method: 'SLOW_SEA', reason: `FBA does not run out inside the horizon — cheapest method`, lateDays: 0 };
  }
  for (const m of FBA_METHODS) {
    if (landed(m) <= oos) {
      return { method: m, reason: `${m} lands ${fmt(landed(m))}, FBA OOS ${fmt(oos)} — no further escalation needed`, lateDays: 0 };
    }
  }
  const fastest = FBA_METHODS[FBA_METHODS.length - 1];
  const lateDays = daysBetween(landed(fastest), oos);
  return {
    method: fastest,
    reason: `${fastest} lands ${fmt(landed(fastest))}, ${lateDays}d after FBA OOS ${fmt(oos)} — unavoidable stockout`,
    lateDays,
  };
}

const floorToCartons = (units: number, pkg: number) => Math.floor(Math.max(0, units) / pkg) * pkg;

export function planSplit(input: SplitInput): SplitPlan {
  const {
    cartons, packageQuantity: pkg, fbaOnHand, awdOnHand, shipments, curve,
    transitDays, fbaInboundBufferDays: buffer, targetDoc, methodOverride,
  } = input;

  if (!Number.isFinite(pkg) || pkg <= 0) return fail('Invalid package quantity — cannot convert cartons to units.');
  if (!Number.isFinite(cartons) || cartons <= 0) return fail('Enter a number of cartons greater than zero.');
  if (Object.values(curve.productDemand).every(v => !v)) {
    return fail('No demand forecast for this product — cannot compute days of cover.');
  }

  const today = startOfDay(input.today);
  const units = Math.round(cartons * pkg);
  const warnings: string[] = [];
  const inbound = confirmedFbaInbound(shipments);
  const shipDate = nextWednesday(today);

  // Horizon must outrun the display window: forward DOC at the last shown week
  // needs targetDoc days of demand beyond it, and transfers run past year-end.
  const horizonDays = 365 + targetDoc;
  const oos = fbaOosDate(fbaOnHand, inbound, curve, today, horizonDays);

  const selected = selectFbaMethod(shipDate, oos, transitDays, buffer);
  const method: FbaMethod = methodOverride ?? selected.method;
  const methodReason = methodOverride
    ? `${method} chosen manually (auto pick was ${selected.method})`
    : selected.reason;
  if (selected.lateDays > 0 && !methodOverride) {
    warnings.push(`FBA runs out ${selected.lateDays} day(s) before the fastest allowed method can land. Stockout is unavoidable from this batch alone.`);
  }

  const fbaTransit = transitDays[method] ?? 0;
  const fbaArrival = addDays(shipDate, fbaTransit);
  const fbaSellable = addDays(fbaArrival, buffer);

  // 100 DOC at the sellable date means holding exactly the demand of the next 100 days.
  const target = demandOverWindow(fbaSellable, addDays(fbaSellable, targetDoc), curve);
  const onHandAtSellable = projectedFbaAt(fbaSellable, fbaOnHand, inbound, curve, today);
  const fbaUnits = Math.min(floorToCartons(target - onHandAtSellable, pkg), floorToCartons(units, pkg));
  const awdUnits = units - fbaUnits;

  if (fbaUnits === 0) {
    warnings.push(`FBA is already at or above ${targetDoc} DOC on ${localDateKey(fbaSellable)} — the whole batch goes to AWD.`);
  }
  if (awdUnits === 0 && fbaUnits < target - onHandAtSellable) {
    const shortUnits = Math.round(target - onHandAtSellable - fbaUnits);
    const shortDays = Math.round(targetDoc * (shortUnits / Math.max(1, target)));
    warnings.push(`Batch is too small to reach ${targetDoc} DOC — short by ${shortUnits} units (~${shortDays} days).`);
  }

  const awdTransit = transitDays.AWD_SLOW_SEA ?? 0;
  const awdArrival = addDays(shipDate, awdTransit);

  const legs: SplitLeg[] = [];
  if (fbaUnits > 0) {
    legs.push({
      destination: 'FBA', units: fbaUnits, cartons: Math.round(fbaUnits / pkg), method,
      shipDate: localDateKey(shipDate), transitDays: fbaTransit,
      arrivalDate: localDateKey(fbaArrival), sellableDate: localDateKey(fbaSellable),
      reason: `${methodReason}. ${fbaUnits} units = demand ${localDateKey(fbaSellable)}–${localDateKey(addDays(fbaSellable, targetDoc - 1))} (${targetDoc} DOC, ${Math.round(target)} units) minus ${Math.round(onHandAtSellable)} projected on hand.`,
    });
  }
  if (awdUnits > 0) {
    legs.push({
      destination: 'AWD', units: awdUnits, cartons: Math.round(awdUnits / pkg), method: 'AWD_SLOW_SEA',
      shipDate: localDateKey(shipDate), transitDays: awdTransit,
      arrivalDate: localDateKey(awdArrival), sellableDate: localDateKey(awdArrival),
      reason: `Remainder after topping FBA to ${targetDoc} DOC. Held at AWD until transferred.`,
    });
  }

  const { transfers, leftover } = scheduleTransfers({
    curve, today, horizonDays, targetDoc, pkg,
    transferLeadDays: (transitDays.AWD_TRANSFER ?? 0) + buffer,
    fbaOnHand, inbound,
    batchArrival: fbaUnits > 0 ? { date: fbaSellable, units: fbaUnits } : null,
    pool: [
      { availableFrom: today, units: awdOnHand },
      ...(awdUnits > 0 ? [{ availableFrom: awdArrival, units: awdUnits }] : []),
    ].filter(t => t.units > 0),
  });

  if (leftover > 0) {
    warnings.push(`${leftover} units remain at AWD at the end of the horizon — not needed to hold ${targetDoc} DOC.`);
  }

  const stockAtSellable = onHandAtSellable + fbaUnits;
  const docAtArrival = stockAtSellable > 0
    ? docFromStock(stockAtSellable, fbaSellable, curve, targetDoc * 4)
    : 0;

  return {
    ok: true, units, legs, transfers,
    fbaDocAtArrival: docAtArrival,
    fbaOosDate: oos ? localDateKey(oos) : null,
    leftoverAwdUnits: leftover,
    warnings,
  };
}

/** Days of cover from a stock level at a date, walking the daily curve. */
export function docFromStock(stock: number, from: Date, curve: DemandCurve, maxDays: number): number {
  let rem = stock;
  for (let i = 0; i < maxDays; i++) {
    rem -= dailyDemandOn(addDays(from, i), curve).units;
    if (rem <= 0) return i;
  }
  return maxDays;
}

interface PoolTranche { availableFrom: Date; units: number }

interface TransferParams {
  curve: DemandCurve;
  today: Date;
  horizonDays: number;
  targetDoc: number;
  pkg: number;
  transferLeadDays: number;
  fbaOnHand: number;
  inbound: ProjectionShipment[];
  batchArrival: Arrival | null;
  pool: PoolTranche[];
}

interface PlannedTransfer { orderDate: Date; arrival: Date; units: number; docBefore: number }

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
export function scheduleTransfers(p: TransferParams): { transfers: TransferRow[]; leftover: number } {
  const { curve, today, horizonDays, targetDoc, pkg, transferLeadDays, fbaOnHand, inbound, batchArrival, pool } = p;
  const emitted: PlannedTransfer[] = [];
  const tranches = pool.map(t => ({ availableFrom: startOfDay(t.availableFrom), units: t.units }));

  const baseArrivals = shipmentArrivals(inbound);
  if (batchArrival) baseArrivals.push(batchArrival);

  let onHandCache: number[] | null = null;
  const stockAt = (when: Date): number => {
    if (!onHandCache) {
      const arrivals = baseArrivals.concat(emitted.map(e => ({ date: e.arrival, units: e.units })));
      onHandCache = walkFba(fbaOnHand, arrivals, curve, today, horizonDays).onHand;
    }
    const i = daysBetween(when, today);
    return onHandCache[Math.min(Math.max(i, 0), onHandCache.length - 1)];
  };

  const availableAt = (when: Date): number =>
    tranches.reduce((s, t) => (t.availableFrom <= when ? s + t.units : s), 0);

  const drawFrom = (when: Date, qty: number): number => {
    let left = qty;
    for (const t of tranches) {
      if (left <= 0) break;
      if (t.availableFrom > when) continue;
      const take = Math.min(t.units, left);
      t.units -= take;
      left -= take;
    }
    return qty - left;
  };

  // Orders are placed on Mondays, never in the past.
  const firstMonday = getMonday(today) < today ? addDays(getMonday(today), 7) : getMonday(today);
  const weeks = Math.floor((horizonDays - daysBetween(firstMonday, today)) / 7);

  for (let w = 0; w < weeks; w++) {
    const orderDate = addDays(firstMonday, w * 7);
    const arrival = addDays(orderDate, transferLeadDays);
    if (daysBetween(arrival, today) > horizonDays) break; // would land past what we model

    const before = stockAt(arrival);
    const docBefore = docFromStock(before, arrival, curve, targetDoc * 4);
    if (docBefore >= targetDoc) continue;

    const need = demandOverWindow(arrival, addDays(arrival, targetDoc), curve) - before;
    const capped = Math.min(need, availableAt(orderDate));
    const qty = floorToCartons(capped, pkg);
    if (qty <= 0) continue;

    const drawn = drawFrom(orderDate, qty);
    if (drawn <= 0) continue;
    onHandCache = null; // the projection must see these units

    const prev = emitted[emitted.length - 1];
    if (prev && daysBetween(arrival, prev.arrival) <= TRANSFER_MERGE_WINDOW_DAYS) {
      // Same move, pulled forward to the earlier landing date.
      prev.units += drawn;
      continue;
    }
    emitted.push({ orderDate, arrival, units: drawn, docBefore });
  }

  // docAfter is read from the finished plan, so merges are already reflected.
  const transfers: TransferRow[] = emitted.map(e => ({
    orderDate: localDateKey(e.orderDate),
    arrivalDate: localDateKey(e.arrival),
    units: e.units,
    cartons: Math.round(e.units / pkg),
    docBefore: e.docBefore,
    docAfter: docFromStock(stockAt(e.arrival), e.arrival, curve, targetDoc * 4),
  }));

  return { transfers, leftover: tranches.reduce((s, t) => s + t.units, 0) };
}
