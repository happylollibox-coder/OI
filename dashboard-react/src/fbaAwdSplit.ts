// Pure FBA/AWD split engine. Given a batch of cartons ready at the
// manufacturer, decide how much goes to FBA now, how much to AWD, by which
// method, and what AWD->FBA transfers hold FBA at its DOC target.
//
// FOUR levels, deliberately named apart, because each governs a different
// decision and mistaking one for another is the class of bug this file exists
// to prevent.
//
//   fbaReorderDoc  — cover ORDERS a transfer here (Seller Central MIN)
//   fbaTargetDoc   — a TRANSFER restores to here (Seller Central MAX)
//   fbaBatchDoc    — a DIRECT manufacturer delivery FILLS FBA to here
//   totalTargetDoc — FBA and AWD hold this TOGETHER
//
// `fbaTargetDoc` is what a move out of AWD puts back: only enough to survive
// until the next transfer can land, because FBA storage is expensive and
// roughly triples in Q4, and because every transferred unit pays outbound
// processing plus per-cubic-foot freight. `fbaReorderDoc` is the level cover is
// allowed to fall to before that move is ordered — min and max, the pair the
// operator sets in Seller Central (architecture/SOP_AWD_REPLENISHMENT.md).
//
// `fbaBatchDoc` sits ABOVE `fbaTargetDoc` on purpose. A leg travelling direct
// from the manufacturer to FBA pays no transfer handling at all — the freight
// is being paid anyway — so the marginal cost of landing deeper is storage
// alone. Filling only to `fbaTargetDoc` starts the drain at exactly the level a
// transfer restores, reaching the reorder point in `fbaTargetDoc -
// fbaReorderDoc` days and paying handling almost at once for stock that could
// have travelled free. See `FBA_BATCH_DOC` in splitPanelData.ts for the
// per-unit arithmetic.
//
// `totalTargetDoc` is what FBA and AWD hold TOGETHER; AWD holds the balance
// cheaply. Sizing the FBA leg to the combined number is the bug this split
// exists to prevent: it sent a 12,000-unit batch 11,760/240 into the expensive
// warehouse.
//
// Advisory only: nothing here writes, and nothing here is a commitment.
// Modelling note: unmet demand is lost, not backlogged. Stock floors at zero.
import {
  addDays, localDateKey, demandOverWindow, dailyDemandOn,
  CONFIRMED_STATUSES, EXCLUDED_STATUSES, parseLocalDate,
  type DemandCurve, type ProjectionShipment,
} from './stockProjection';

export type FbaMethod = 'SLOW_SEA' | 'FAST_SEA';

/** Cheapest first. AIR is deliberately absent — never auto-selected, never offered. */
export const FBA_METHODS: readonly FbaMethod[] = ['SLOW_SEA', 'FAST_SEA'];

/**
 * Routes the AWD leg may take. `AWD_SLOW_SEA` is the default and the cheapest;
 * the two sea routes are the same ones the FBA leg uses, on the assumption that
 * a batch can be sent to AWD by them. AIR is absent here for the same reason it
 * is absent from `FBA_METHODS`: the operator excluded it outright.
 */
export type AwdMethod = 'AWD_SLOW_SEA' | 'SLOW_SEA' | 'FAST_SEA';

/** Default first, then the sea routes. AIR is deliberately absent. */
export const AWD_METHODS: readonly AwdMethod[] = ['AWD_SLOW_SEA', 'SLOW_SEA', 'FAST_SEA'];

/** What the AWD leg takes when nothing overrides it. */
export const DEFAULT_AWD_METHOD: AwdMethod = 'AWD_SLOW_SEA';

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

/**
 * NO MERGE WINDOW. There used to be one — transfers landing within 14 days of
 * each other were folded into a single earlier row — and it is gone on purpose.
 *
 * It existed to stop a weekly dribble, and both things that caused the dribble
 * are gone: the trigger is now a genuine reorder point rather than "anything
 * under target", and the walk is daily rather than weekly. What is left is a
 * move every `fbaTargetDoc - fbaReorderDoc` days, which is the operating rule
 * working, not a dribble.
 *
 * Kept, it now DISTORTS. Folding a later move onto an earlier row back-dates it
 * by up to the window, so the stock lands up to a fortnight before it is needed
 * and leaves FBA sitting at `fbaTargetDoc + window` days of cover — measured at
 * 58 against a 45-day target on the flat fixture. 45 is the MAX limit set in
 * Seller Central; Amazon physically stops pulling there, so a plan showing 58 is
 * not merely expensive, it is not executable. And it bought nothing: across
 * every fixture the engine is tested on, removing it left the count of days FBA
 * spends at zero completely unchanged.
 *
 * The invariant it needed care around — never move stock that has not landed at
 * AWD — is not its to enforce and never was: `createAwdPool` dates every tranche
 * and `draw(orderDate, …)` cannot reach past that date. Removing the fold
 * removes the one path that could ever have dated a move earlier than the day it
 * was decided on.
 */

/**
 * How far `docFromStock` will count before giving up. Four times the COMBINED
 * target is far past any level worth acting on, and it keeps the walk
 * terminating when the demand curve runs out and cover is nominally infinite.
 * It is keyed to the combined target rather than the FBA one so a reading of
 * the whole position can still count well past where it should have stopped.
 */
const DOC_CAP_MULTIPLE = 4;

/**
 * How far past `totalTargetDoc` the combined position may sit before it is
 * called overstock rather than prudence. A batch quantised to whole cartons
 * lands a few days either side of the target by construction; a tenth of the
 * target is the point where the excess is a decision rather than rounding.
 */
const OVERSTOCK_TOLERANCE = 0.10;

const DAY_MS = 86_400_000;

/**
 * Stock already on the water to AWD. Owned, landing in the reserve, and able to
 * feed a transfer into FBA once — and not one day before — it lands.
 *
 * `arrivalDate` is optional because the authority for this quantity is Amazon's
 * inventory snapshot, which reports a quantity and no date. An undated tranche
 * is placed at AWD_SLOW_SEA transit from today and the assumption is stated on
 * `SplitPlan.assumptions`, never buried.
 */
export interface AwdInboundTranche {
  units: number;
  /** Local YYYY-MM-DD. Omit when the source does not know. */
  arrivalDate?: string;
}

export interface SplitInput {
  cartons: number;
  packageQuantity: number;
  fbaOnHand: number;
  awdOnHand: number;
  /**
   * Stock in transit to AWD. Counted in the combined position because it is
   * owned, and joined to the transfer pool at its arrival date so it can never
   * feed a transfer early. Absent means none, not unknown.
   */
  awdInbound?: AwdInboundTranche[];
  shipments: ProjectionShipment[];
  curve: DemandCurve;
  transitDays: TransitDayMap;
  fbaInboundBufferDays: number;
  today: Date;
  /**
   * Days of cover held LIVE at FBA — the MAX limit, what a TRANSFER restores
   * to. Not the whole position: only enough to survive until the next transfer
   * from AWD can land. The physical floor is the `AWD_TRANSFER` lead and
   * nothing else: transfers are evaluated every day, so there is no ordering
   * cadence to add on top, and the FBA inbound buffer is not part of it either
   * — `AWD_TRANSFER` is already door to SELLABLE. Below that lead the reserve
   * cannot arrive in time and is useless.
   *
   * NOT what sizes the batch's FBA leg — that is `fbaBatchDoc`. This level is
   * deliberately the tighter of the two, because every unit it moves has paid
   * transfer handling to get there.
   */
  fbaTargetDoc: number;
  /**
   * Days of cover at which a transfer is ORDERED — the MIN limit. Cover is
   * allowed to fall to here and no further; crossing down through it with stock
   * at AWD triggers a move sized to restore `fbaTargetDoc`. Must sit strictly
   * between zero and `fbaTargetDoc`: at or above the target every day would
   * trigger, and at zero nothing ever would. It should also sit above the
   * `AWD_TRANSFER` lead, or the move it orders lands after the shelf is empty.
   */
  fbaReorderDoc: number;
  /**
   * Days of cover a DIRECT manufacturer → FBA delivery leaves FBA holding. The
   * only thing this sizes is the batch's FBA leg.
   *
   * Above `fbaTargetDoc` on purpose: the direct leg is the one route into FBA
   * that pays no transfer handling, so filling it deeper buys transfer-free
   * days for storage cost alone. Landing at exactly `fbaTargetDoc` would start
   * the drain at the level a transfer restores and order one within
   * `fbaTargetDoc - fbaReorderDoc` days.
   *
   * Must sit between `fbaTargetDoc` and `totalTargetDoc` inclusive: below the
   * transfer target a delivery would land FBA under the level a move puts it
   * back to, and above the combined target it would fill FBA past what FBA and
   * AWD are meant to hold together, leaving the reserve a negative share.
   */
  fbaBatchDoc: number;
  /**
   * Days of cover FBA and AWD hold TOGETHER. AWD holds the balance
   * (`totalTargetDoc - fbaBatchDoc` days — the share left once a delivery has
   * filled FBA to `fbaBatchDoc`) at a fraction of FBA's storage cost.
   */
  totalTargetDoc: number;
  methodOverride?: FbaMethod;
  /** Route for the AWD leg. Out-of-band values fall back to the default and warn. */
  awdMethodOverride?: AwdMethod;
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
  /** Route the AWD leg took, stated even when nothing went to AWD. */
  awdMethod: AwdMethod;
  awdMethodOverridden: boolean;
  shipDate: string;
  /** The date targetUnits and onHandAtSellable are keyed to — readable even with no FBA leg. */
  sellableDate: string;
  /** Span of the series actually built, so the panel never infers it by reading `series`. */
  walkWindow: { from: string; to: string } | null;
  /** Cover from FBA alone at the sellable date — the sellable position, read against `fbaBatchDoc`. */
  fbaDocAtArrival: DocReading;
  /**
   * Cover from FBA and AWD together at the same date, read against
   * `totalTargetDoc`. AWD is counted at full value: it is owned stock, just not
   * sellable until it is transferred. The pair is the point — ~60 at FBA on the
   * day a delivery lands and ~100 combined is the plan working, and either
   * number alone hides that.
   */
  combinedDocAtArrival: DocReading;
  fbaOosDate: string | null;
  leftoverAwdUnits: number;
  warnings: string[];
  /**
   * Things the engine had to decide for itself because the input did not say.
   * Separate from `warnings`: nothing here is wrong, but every line is a place
   * the plan would move if the real figure turned up.
   */
  assumptions: string[];
}

const fail = (error: string): SplitPlan => ({
  ok: false, error, units: 0, legs: [], transfers: [], series: [],
  targetUnits: 0, onHandAtSellable: 0, shortfallUnits: 0,
  autoMethod: 'SLOW_SEA', methodOverridden: false,
  awdMethod: DEFAULT_AWD_METHOD, awdMethodOverridden: false, shipDate: '',
  sellableDate: '', walkWindow: null,
  fbaDocAtArrival: { days: 0, capped: false },
  combinedDocAtArrival: { days: 0, capped: false }, fbaOosDate: null,
  leftoverAwdUnits: 0, warnings: [], assumptions: [],
});

/** Midnight of the same local day, so every date in the engine is comparable. */
function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

/** Whole days between two local midnights. Rounds, so DST hours never leak in. */
function daysBetween(later: Date, earlier: Date): number {
  return Math.round((later.getTime() - earlier.getTime()) / DAY_MS);
}

/**
 * Days `planSplit` walks beyond today. A year, plus the combined target: a
 * forward DOC reading at the last day shown needs `totalTargetDoc` days of
 * demand beyond it, and transfers run past year-end.
 */
export function walkHorizonDays(totalTargetDoc: number): number {
  return 365 + totalTargetDoc;
}

/**
 * The span `planSplit` will walk for these inputs, statable BEFORE a plan
 * exists. The ledger has to judge "did this arrival land inside the modelled
 * window?" in order to decide which shipments the engine is even given — a
 * chicken-and-egg the panel used to dodge by reading `plan.walkWindow` after
 * the fact. `planSplit` builds its series from `walkHorizonDays` too, and a
 * test pins the two together, so the window judged and the window walked cannot
 * drift apart.
 */
export function plannedWalkWindow(today: Date, totalTargetDoc: number): { from: string; to: string } {
  const from = startOfDay(today);
  return {
    from: localDateKey(from),
    to: localDateKey(addDays(from, walkHorizonDays(totalTargetDoc))),
  };
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

/** A DOC reading as operator prose — a capped walk reads "400+", never a flat "400". */
const docDays = (r: DocReading): string => (r.capped ? `${r.days}+` : `${r.days}`);

/**
 * Days of cover from a stock level at a date: how many whole days the stock
 * fully covers, walking the daily curve. Stock sized to cover exactly N days
 * reads N, not N-1 — the boundary matters because `>= fbaTargetDoc` decides
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
    transitDays, fbaInboundBufferDays: buffer, fbaTargetDoc, fbaReorderDoc,
    fbaBatchDoc, totalTargetDoc, methodOverride, awdMethodOverride,
  } = input;
  const awdInboundRows = input.awdInbound ?? [];

  if (!Number.isFinite(pkg) || pkg <= 0) return fail('Invalid package quantity — cannot convert cartons to units.');
  if (!Number.isFinite(cartons) || cartons <= 0) return fail('Enter a number of cartons greater than zero.');
  if (!Number.isFinite(fbaTargetDoc) || fbaTargetDoc <= 0) return fail('FBA target days of cover must be greater than zero.');
  // Min and max, in that order. A reorder point at or above the target would
  // trigger a transfer every single day — the level is never above it — and one
  // at or below zero can never be crossed, so no transfer would ever be ordered.
  if (!Number.isFinite(fbaReorderDoc) || fbaReorderDoc <= 0 || fbaReorderDoc >= fbaTargetDoc) {
    return fail('FBA reorder days of cover must be greater than zero and below the FBA target — cover falls to the reorder point, and a transfer restores it to the target.');
  }
  // A delivery fills FBA to the batch level, and a transfer only ever puts it
  // back to the target. A batch level UNDER the target would mean a fresh
  // delivery leaves FBA below where a move out of AWD would have restored it —
  // the direct leg is the cheap route, so it can never be the shallower one.
  if (!Number.isFinite(fbaBatchDoc) || fbaBatchDoc < fbaTargetDoc) {
    return fail('Batch fill days of cover must be at least the FBA target — a manufacturer delivery pays no transfer handling, so it can never leave FBA below the level a paid AWD → FBA move restores it to.');
  }
  // AWD holds the balance left once a delivery has filled FBA, so a combined
  // target under the batch level asks the reserve to hold a negative number of
  // days — not a plan.
  if (!Number.isFinite(totalTargetDoc) || totalTargetDoc < fbaBatchDoc) {
    return fail('Combined target days of cover must be at least the batch fill — AWD holds the balance between them, and a delivery filling FBA past the combined target would leave the reserve a negative share.');
  }
  if (!Number.isFinite(fbaOnHand) || fbaOnHand < 0) return fail('FBA on-hand units must be zero or more.');
  if (!Number.isFinite(awdOnHand) || awdOnHand < 0) return fail('AWD on-hand units must be zero or more.');
  if (awdInboundRows.some(t => !Number.isFinite(t.units) || t.units < 0)) {
    return fail('AWD in-transit units must be zero or more.');
  }
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
  const assumptions: string[] = [];
  const inbound = confirmedFbaInbound(shipments);
  const shipDate = nextWednesday(today);
  const docCap = totalTargetDoc * DOC_CAP_MULTIPLE;

  // Horizon must outrun the display window, which follows the combined target.
  // Shared with `plannedWalkWindow` so a caller can state this span before the
  // plan exists without re-deriving it.
  const horizonDays = walkHorizonDays(totalTargetDoc);
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

  // Only a leg arriving at FBA DIRECT from the manufacturer pays the inbound
  // buffer. AWD_TRANSFER already covers getting stock sellable at FBA, so the
  // transfer lead below is that transit alone.
  const fbaTransit = transitDays[method];
  const fbaArrival = addDays(shipDate, fbaTransit);
  const fbaSellable = addDays(fbaArrival, buffer);
  const lastCoveredDay = addDays(fbaSellable, fbaBatchDoc - 1);

  // The AWD leg's route is selectable in the same way the FBA leg's is, and
  // guarded the same way: AIR is in the injected transit map and must never
  // become a plan just because a string reached here un-narrowed.
  const awdOverride = awdMethodOverride && AWD_METHODS.includes(awdMethodOverride)
    ? awdMethodOverride : undefined;
  const awdMethod: AwdMethod = awdOverride ?? DEFAULT_AWD_METHOD;
  if (awdMethodOverride && !awdOverride) {
    warnings.push(`Ignored the requested AWD method "${methodCaption(awdMethodOverride)}" — not an AWD route this engine offers. Used ${methodCaption(awdMethod)} instead.`);
  }
  const awdTransit = transitDays[awdMethod];
  const awdArrival = addDays(shipDate, awdTransit);
  const transferTransit = transitDays.AWD_TRANSFER;
  // Stock already on the water to AWD went by the default route, whatever the
  // batch's leg is being sent by — changing this batch's route must not move
  // the assumed landing date of goods that shipped weeks ago.
  const awdSlowSeaTransit = transitDays.AWD_SLOW_SEA;

  // Stock already on the water to AWD. It joins the same dated pool the batch's
  // AWD leg does, so a transfer can never be ordered against units still at
  // sea. Where the source gives no date — the inventory snapshot reports a
  // quantity only — assume this engine's own AWD_SLOW_SEA leg from today and
  // say so, rather than assuming it is available now (which would let a
  // transfer be ordered against goods that have not landed).
  const assumedAwdArrival = addDays(today, awdSlowSeaTransit);
  const awdInboundTranches: PoolTranche[] = [];
  let assumedAwdInboundUnits = 0;
  for (const t of awdInboundRows) {
    if (!(t.units > 0)) continue;
    const dated = parseLocalDate(t.arrivalDate);
    if (dated) awdInboundTranches.push({ availableFrom: startOfDay(dated), units: t.units, note: 'AWD in transit' });
    else assumedAwdInboundUnits += t.units;
  }
  if (assumedAwdInboundUnits > 0) {
    awdInboundTranches.push({ availableFrom: assumedAwdArrival, units: assumedAwdInboundUnits, note: 'AWD in transit' });
    assumptions.push(`${assumedAwdInboundUnits} units already in transit to AWD carry no arrival date, so they are assumed to land ${localDateKey(assumedAwdArrival)} — ${methodCaption('AWD_SLOW_SEA')} (${awdSlowSeaTransit}d) from today. They count towards the combined position from now, but nothing can be transferred out of them before that date.`);
  }
  // Landing order: what is at AWD now, then what is at sea, then the batch —
  // so `draw` empties the oldest stock first.
  const awdInboundUnits = awdInboundTranches.reduce((s, t) => s + t.units, 0);

  // The FBA leg is sized to fbaBatchDoc — how full a DIRECT delivery leaves FBA
  // — and to neither of the other two levels. Not the combined target, which
  // would put the whole batch in the expensive warehouse; and not fbaTargetDoc,
  // which is what a PAID move out of AWD restores to and would have this free
  // leg stop exactly where the drain toward the reorder point begins.
  const target = demandOverWindow(fbaSellable, addDays(fbaSellable, fbaBatchDoc), curve);
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

  // The AWD leg is not a leftover. It holds the balance of the combined target,
  // measured from its OWN arrival date — that is when the reserve starts
  // covering anything, and it lands weeks after the FBA leg does.
  //
  // The balance is against `fbaBatchDoc`, not `fbaTargetDoc`. Both legs come
  // out of the same batch and the combined target is a claim about that batch's
  // landed position: this delivery puts `fbaBatchDoc` days at FBA, so the share
  // left for the reserve is `totalTargetDoc - fbaBatchDoc`. Keeping the old
  // `totalTargetDoc - fbaTargetDoc` share would size the pair to
  // `totalTargetDoc + (fbaBatchDoc - fbaTargetDoc)` days while the overstock
  // check below still measures against `totalTargetDoc` — a well-sized batch
  // would read as overstock, and the sentence would claim a share the split
  // never produced.
  const reserveDoc = totalTargetDoc - fbaBatchDoc;
  const reserveTarget = reserveDoc > 0
    ? demandOverWindow(awdArrival, addDays(awdArrival, reserveDoc), curve)
    : 0;
  const reserveShown = Math.round(reserveTarget);

  const stockAtSellable = onHandAtSellable + fbaUnits;
  const docAtArrival: DocReading = stockAtSellable > 0
    ? docFromStock(stockAtSellable, fbaSellable, curve, docCap)
    : { days: 0, capped: false };

  // The combined position: everything owned that is either live at FBA or
  // waiting at AWD. AWD stock is not sellable, but it is stock — leaving it out
  // would read as a shortfall the operator has already paid for. Stock still on
  // the water to AWD is owned on exactly the same terms as the batch's own AWD
  // leg, which is counted here too; omitting it would over-order the reserve.
  const combinedAtSellable = stockAtSellable + awdOnHand + awdUnits + awdInboundUnits;
  const combinedDocAtArrival: DocReading = combinedAtSellable > 0
    ? docFromStock(combinedAtSellable, fbaSellable, curve, docCap)
    : { days: 0, capped: false };
  const totalTargetUnits = demandOverWindow(fbaSellable, addDays(fbaSellable, totalTargetDoc), curve);

  if (fbaUnits === 0) {
    warnings.push(`FBA is already at or above ${fbaBatchDoc} DOC on ${localDateKey(fbaSellable)} — the whole batch goes to AWD.`);
  }
  // THREE different shortfalls that must never share a message, because they
  // are three different events with three different responses.
  //
  //  1. Missing `fbaTargetDoc` with nothing reaching the reserve is a STOCKOUT
  //     RISK: the delivery lands FBA below the level a move out of AWD would
  //     have restored, and there is no AWD stock to move. Needs a faster,
  //     bigger shipment.
  //  2. Missing `fbaBatchDoc` while still clearing `fbaTargetDoc` costs MONEY,
  //     not stock. Cover is safe; the free direct leg simply stopped short, so
  //     the first paid transfer comes sooner than it needed to.
  //  3. Holding less than `totalTargetDoc` across both is a REORDER signal with
  //     weeks of runway to act in.
  //
  // Anything under a carton is the rounding-down remainder in any of the three,
  // not a real shortfall.
  const fbaShortfall = needUnits - fbaUnits;
  const missedBatchFill = awdUnits === 0 && fbaShortfall > pkg;
  // Measured in its own units. `fbaShortfall` is the gap to `fbaBatchDoc`, so
  // quoting it beside the `fbaTargetDoc` level would print a subtraction that
  // does not hold — the exact prose drift this file has been bitten by before.
  const transferTargetUnits = demandOverWindow(fbaSellable, addDays(fbaSellable, fbaTargetDoc), curve);
  const belowTransferTarget = missedBatchFill && docAtArrival.days < fbaTargetDoc;

  if (belowTransferTarget) {
    const shortDays = Math.max(0, fbaTargetDoc - docAtArrival.days);
    const shortUnits = Math.round(Math.max(0, transferTargetUnits - stockAtSellable));
    warnings.push(`Batch is too small to put ${fbaTargetDoc} days live at FBA — the level an AWD → FBA move restores to — short by ${shortUnits} units (~${shortDays} days), and none of it reaches the AWD reserve. FBA is the only sellable position, so this is a stockout risk.`);
  } else {
    // Not exclusive with the combined check below, unlike the stockout case:
    // this one is not urgent, so there is nothing to dilute, and staying silent
    // about the reserve would hide that a batch which went entirely to FBA left
    // the pair short as well.
    if (missedBatchFill) {
      const shortDays = Math.max(0, fbaBatchDoc - docAtArrival.days);
      warnings.push(`Batch is too small to fill FBA to ${fbaBatchDoc} days — short by ${Math.round(fbaShortfall)} units (~${shortDays} days). Cover still clears the ${fbaTargetDoc}-day transfer target, so nothing is at risk; the first AWD → FBA transfer just comes sooner, and its handling is the cost a direct delivery would have avoided.`);
    }
    const combinedShortfall = totalTargetUnits - combinedAtSellable;
    if (combinedShortfall > pkg) {
      const shortDays = Math.max(0, totalTargetDoc - combinedDocAtArrival.days);
      // The FBA figure is the reading the engine measured, not the level it was
      // aiming at: a batch that fell a rounding remainder short, or one that
      // landed on FBA already deep in stock, would otherwise be described as
      // sitting at a level it is not sitting at.
      warnings.push(`FBA is covered to ${docDays(docAtArrival)} days, but FBA and AWD together hold ${docDays(combinedDocAtArrival)} days against the ${totalTargetDoc}-day combined target — short by ${Math.round(combinedShortfall)} units (~${shortDays} days). Reorder to refill the reserve; nothing goes out of stock over this.`);
    } else if (combinedAtSellable > totalTargetUnits * (1 + OVERSTOCK_TOLERANCE)) {
      warnings.push(`FBA and AWD together hold ${docDays(combinedDocAtArrival)} days against the ${totalTargetDoc}-day combined target — ${Math.round(combinedAtSellable - totalTargetUnits)} units beyond it. Past the target this is overstock, not prudence: cash and storage sitting in the reserve.`);
    }
  }

  const legs: SplitLeg[] = [];
  if (fbaUnits > 0) {
    const ledger = `${fbaBatchDoc} DOC from ${localDateKey(fbaSellable)} is ${targetShown} units of demand (through ${localDateKey(lastCoveredDay)}), less ${onHandShown} projected on hand = ${needShown} needed`;
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
      ? `The batch beyond the ${fbaUnits} units going live at FBA.`
      : `FBA is already at or above ${fbaBatchDoc} DOC on ${localDateKey(fbaSellable)}, so none of this batch is needed there yet.`;
    // Say what the reserve is holding and against which target. "What is left
    // over" is not a purpose, and reading it as one is how the FBA leg came to
    // be sized at the combined number in the first place.
    // Compare against the rounded figure the sentence prints, so "0 short of
    // it" can never appear next to a claim that it is short.
    const spare = awdUnits - reserveShown;
    const holds = reserveDoc <= 0
      ? `The combined target is the level a delivery already fills FBA to, so the reserve carries no days of its own — this is stock held ahead of the next batch.`
      : spare >= 0
        ? `Holds the ${reserveDoc}-day AWD share of the ${totalTargetDoc}-day combined target — what is left once this delivery puts ${fbaBatchDoc} days at FBA — ${reserveShown} units of demand from ${localDateKey(awdArrival)}${spare > 0 ? `, with ${spare} units to spare` : ', exactly'}.`
        : `Holds ${awdUnits} of the ${reserveShown} units the ${reserveDoc}-day AWD share of the ${totalTargetDoc}-day combined target asks for from ${localDateKey(awdArrival)} — the share left once this delivery puts ${fbaBatchDoc} days at FBA — ${-spare} short of it.`;
    // The route sentence names how it was picked, so a manual choice is never
    // mistaken for the engine's own recommendation.
    const route = awdOverride
      ? `${methodCaption(awdMethod)} chosen manually (${awdTransit}d, default is ${methodCaption(DEFAULT_AWD_METHOD)})`
      : `${methodCaption(awdMethod)} is the default AWD route (${awdTransit}d)`;
    legs.push({
      destination: 'AWD', units: awdUnits, cartons: awdUnits / pkg, method: awdMethod,
      shipDate: localDateKey(shipDate), transitDays: awdTransit,
      arrivalDate: localDateKey(awdArrival), sellableDate: localDateKey(awdArrival),
      reason: `${origin} ${holds} ${route}, landing ${localDateKey(awdArrival)}. Not sellable there — each transfer into FBA takes ${transferTransit}d door to sellable, ordered when cover falls to ${fbaReorderDoc} days and sized to restore ${fbaTargetDoc}.`,
    });
  }

  const { transfers, leftover, series } = scheduleTransfers({
    curve, today, horizonDays, fbaTargetDoc, fbaReorderDoc, pkg, docCap,
    // Door to sellable for an AWD → FBA transfer is AWD_TRANSFER alone. The FBA
    // inbound buffer is NOT added on top: it belongs to a leg arriving at FBA
    // direct from the manufacturer, and AWD_TRANSFER already covers receiving.
    transferLeadDays: transferTransit,
    fbaOnHand, inbound,
    batchArrival: fbaUnits > 0 ? { date: fbaSellable, units: fbaUnits, note: 'FBA batch' } : null,
    pool: [
      { availableFrom: today, units: awdOnHand },
      ...awdInboundTranches,
      ...(awdUnits > 0 ? [{ availableFrom: awdArrival, units: awdUnits, note: 'AWD batch' }] : []),
    ].filter(t => t.units > 0),
  });

  if (leftover > 0) {
    warnings.push(`${leftover} units remain at AWD at the end of the horizon — more than the transfers need to hold FBA at ${fbaTargetDoc} DOC.`);
  }

  return {
    ok: true, units, legs, transfers, series,
    targetUnits: targetShown,
    onHandAtSellable: onHandShown,
    shortfallUnits: Math.max(0, needShown - fbaUnits),
    autoMethod: selected.method,
    methodOverridden: override !== undefined,
    awdMethod,
    awdMethodOverridden: awdOverride !== undefined,
    shipDate: localDateKey(shipDate),
    sellableDate: localDateKey(fbaSellable),
    walkWindow: series.length
      ? { from: series[0].date, to: series[series.length - 1].date }
      : null,
    fbaDocAtArrival: docAtArrival,
    combinedDocAtArrival,
    fbaOosDate: oos ? localDateKey(oos) : null,
    leftoverAwdUnits: leftover,
    warnings,
    assumptions,
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
  /** Transfers restore the LIVE level, not the combined one — AWD keeps the balance. */
  fbaTargetDoc: number;
  /** Cover at or below this on the landing date is what orders a transfer. */
  fbaReorderDoc: number;
  pkg: number;
  docCap: number;
  /** Door to sellable for an AWD → FBA move: AWD_TRANSFER, with no inbound buffer on top. */
  transferLeadDays: number;
  fbaOnHand: number;
  inbound: ProjectionShipment[];
  batchArrival: Arrival | null;
  pool: PoolTranche[];
}

interface PlannedTransfer { orderDate: Date; arrival: Date; units: number; docBefore: DocReading }

/**
 * Walk DAILY. On each day, look ahead by the transfer lead time: if FBA DOC
 * would be AT OR BELOW `fbaReorderDoc` by the time a transfer ordered that day
 * could land, order one sized to restore `fbaTargetDoc` at that landing date,
 * capped by the pool available on the order date and floored to whole cartons.
 *
 * Daily, not weekly. An AWD → FBA move is internal — nothing waits for a
 * sailing — so the transfer is ordered on the day cover actually crosses down
 * through the reorder point, not on the next Monday after it. The weekly walk
 * this replaced borrowed the plan engine's `ship_wednesday` cadence, which
 * governs manufacturer shipments and has no bearing here; it cost up to six
 * days of avoidable delay and put a cadence term into the physical floor that
 * does not exist.
 *
 * Min and max, the operating rule the operator has set in Seller Central: cover
 * is allowed to run down to the reorder point and no further, and a move brings
 * it back to the target. Firing at the target instead — which this used to do —
 * makes every single day a trigger, because the level is under the target on
 * all but the day a transfer lands. Nothing is merged; see the note where the
 * merge window used to be defined.
 *
 * Evaluating seven times as often is only safe because a scheduled move is
 * visible to the very next day's reading: `onHandCache` is dropped the instant
 * the pool is drawn, so `stockAt` re-walks with the new arrival in it and
 * tomorrow sees cover back at the target rather than ordering the same move
 * again. `planSplit — daily evaluation` pins that.
 *
 * Every unit drawn from the pool lands in an emitted transfer: the projection
 * reads its arrivals straight off `emitted`, so the two can never drift apart.
 * A move is only ever drawn from stock that has landed at AWD by its order
 * date — `createAwdPool` dates every tranche and `draw` will not reach past it.
 */
export function scheduleTransfers(
  p: TransferParams,
): { transfers: TransferRow[]; leftover: number; series: SeriesDay[] } {
  const {
    curve, today, horizonDays, fbaTargetDoc, fbaReorderDoc, pkg, docCap,
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

  // Every day from today forward. Never in the past: the walk starts at today.
  for (let day = 0; day <= horizonDays; day++) {
    const orderDate = addDays(today, day);
    const arrival = addDays(orderDate, transferLeadDays);
    if (daysBetween(arrival, today) > horizonDays) break; // would land past what we model

    const before = stockAt(arrival);
    const docBefore = docFromStock(before, arrival, curve, docCap);
    // Crossing DOWN THROUGH the reorder point is the trigger; sitting between it
    // and the target is the level doing its job and is left alone.
    if (docBefore.days > fbaReorderDoc) continue;

    const need = demandOverWindow(arrival, addDays(arrival, fbaTargetDoc), curve) - before;

    // Never more than has actually landed at AWD by the order date. This is the
    // whole of the "do not move stock that is still at sea" rule: `availableAt`
    // and `draw` both filter the pool by `availableFrom <= orderDate`, and no
    // row is ever dated earlier than the day it was decided on.
    const qty = floorToCartons(Math.min(need, awd.availableAt(orderDate)), pkg);
    if (qty <= 0) continue;

    const drawn = awd.draw(orderDate, qty);
    if (drawn <= 0) continue;
    onHandCache = null; // the projection must see these units

    emitted.push({ orderDate, arrival, units: drawn, docBefore });
  }

  // docAfter is read from the FINISHED plan, so it reflects every later move too.
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
