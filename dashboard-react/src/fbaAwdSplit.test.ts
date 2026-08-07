import { describe, it, expect } from 'vitest';
import type { MonthSeasonInfo } from './planTypes';
import type { DemandCurve, ProjectionShipment } from './stockProjection';
import {
  planSplit, nextWednesday, selectFbaMethod, destinationOf, confirmedFbaInbound,
  docFromStock, createAwdPool, METHOD_CAPTIONS,
  type SplitInput, type FbaMethod,
} from './fbaAwdSplit';

const SEASON: Record<number, MonthSeasonInfo> = {
  202611: { peakDays: 12, offseasonDays: 18, holidays: 'BFCM' },
  202612: { peakDays: 15, offseasonDays: 16, holidays: 'Christmas' },
};

// Flat 300/month everywhere = ~10/day, so DOC arithmetic is easy to reason about.
const FLAT: Record<number, number> = {
  202608: 300, 202609: 300, 202610: 310, 202611: 300, 202612: 310,
  202701: 310, 202702: 280, 202703: 310, 202704: 300, 202705: 310, 202706: 300,
};

const CURVE: DemandCurve = { productDemand: FLAT, familySeason: {}, growth: 1.0 };
const TODAY = new Date(2026, 7, 7); // Friday 2026-08-07

/** Parse a YYYY-MM-DD key as a LOCAL date; `new Date(str)` would read it as UTC. */
const parseKey = (k: string) => {
  const [y, m, d] = k.split('-').map(Number);
  return new Date(y, m - 1, d);
};

const base: SplitInput = {
  cartons: 100,
  packageQuantity: 10,
  fbaOnHand: 0,
  awdOnHand: 0,
  shipments: [],
  curve: CURVE,
  transitDays: { FAST_SEA: 27, SLOW_SEA: 33, AWD_SLOW_SEA: 63, AWD_TRANSFER: 14 },
  fbaInboundBufferDays: 10,
  today: TODAY,
  // Four levels. A direct delivery fills FBA to 60 days; transfers are ordered
  // when cover falls to 30 — the Seller Central min — and restore 45, the max.
  // FBA and AWD hold 100 together. On the flat curve, from the 2026-09-18
  // sellable date, those are 600 / 450 / 1000 units respectively.
  fbaTargetDoc: 45,
  fbaReorderDoc: 30,
  fbaBatchDoc: 60,
  totalTargetDoc: 100,
};

describe('nextWednesday', () => {
  it('moves a Friday forward to the following Wednesday', () => {
    expect(nextWednesday(new Date(2026, 7, 7))).toEqual(new Date(2026, 7, 12));
  });

  it('returns the same day when already Wednesday', () => {
    expect(nextWednesday(new Date(2026, 7, 12))).toEqual(new Date(2026, 7, 12));
  });
});

describe('planSplit — input handling', () => {
  it('converts cartons to units via package quantity', () => {
    const plan = planSplit(base);
    expect(plan.units).toBe(1000);
  });

  it('refuses to compute with no demand forecast', () => {
    const plan = planSplit({ ...base, curve: { productDemand: {}, familySeason: {}, growth: 1 } });
    expect(plan.ok).toBe(false);
    expect(plan.error).toMatch(/no demand forecast/i);
  });

  it('refuses to compute with a non-positive package quantity', () => {
    const plan = planSplit({ ...base, packageQuantity: 0 });
    expect(plan.ok).toBe(false);
    expect(plan.error).toMatch(/package quantity/i);
  });

  it('refuses to compute with zero cartons', () => {
    const plan = planSplit({ ...base, cartons: 0 });
    expect(plan.ok).toBe(false);
    expect(plan.error).toMatch(/cartons/i);
  });
});

describe('selectFbaMethod', () => {
  const transit = { FAST_SEA: 27, SLOW_SEA: 33, AWD_SLOW_SEA: 63, AWD_TRANSFER: 14 };
  const ship = new Date(2026, 7, 12); // Wed 2026-08-12

  it('takes the cheapest method when it lands in time', () => {
    // SLOW_SEA lands 2026-08-12 + 33 + 10 = 2026-09-24
    const r = selectFbaMethod(ship, new Date(2026, 9, 30), transit, 10);
    expect(r.method).toBe('SLOW_SEA');
    expect(r.lateDays).toBe(0);
  });

  it('escalates to FAST_SEA when SLOW_SEA lands late', () => {
    // FAST_SEA lands 2026-09-18, SLOW_SEA 2026-09-24
    const r = selectFbaMethod(ship, new Date(2026, 8, 20), transit, 10);
    expect(r.method).toBe('FAST_SEA');
    expect(r.lateDays).toBe(0);
  });

  it('never selects AIR even when FAST_SEA is late', () => {
    const r = selectFbaMethod(ship, new Date(2026, 7, 20), transit, 10);
    expect(r.method).toBe('FAST_SEA');
    expect(r.lateDays).toBeGreaterThan(0);
    expect(r.reason).toMatch(/unavoidable stockout/i);
  });

  it('defaults to the cheapest when FBA never runs out', () => {
    const r = selectFbaMethod(ship, null, transit, 10);
    expect(r.method).toBe('SLOW_SEA');
  });
});

describe('shipment classification', () => {
  it('reads destination off the route', () => {
    expect(destinationOf({ qty: 1, arrival_date: '2026-09-01', status: 'transit', route: 'MFR→AWD' })).toBe('AWD');
    expect(destinationOf({ qty: 1, arrival_date: '2026-09-01', status: 'transit', route: 'PO→MFR→FBA' })).toBe('FBA');
    expect(destinationOf({ qty: 1, arrival_date: '2026-09-01', status: 'transit' })).toBe('FBA');
  });

  it('keeps only confirmed FBA-bound shipments', () => {
    const all: ProjectionShipment[] = [
      { qty: 100, arrival_date: '2026-09-01', status: 'transit', route: 'PO→MFR→FBA' },
      { qty: 200, arrival_date: '2026-09-01', status: 'suggested', route: 'PO→MFR→FBA' },
      { qty: 300, arrival_date: '2026-09-01', status: 'approved', route: 'MFR→AWD' },
      { qty: 400, arrival_date: '2026-09-01', status: 'po', route: 'MFR' },
    ];
    expect(confirmedFbaInbound(all).map(s => s.qty)).toEqual([100]);
  });
});

describe('planSplit — sizing', () => {
  it('sends everything to FBA when the batch cannot even fill the delivery level', () => {
    // 10 units/day => the 60-day delivery fill needs 600 units at FBA. Batch is 300.
    const plan = planSplit({ ...base, cartons: 30, fbaOnHand: 0 });
    expect(plan.ok).toBe(true);
    const fba = plan.legs.find(l => l.destination === 'FBA')!;
    expect(fba.units).toBe(300);
    expect(plan.legs.find(l => l.destination === 'AWD')).toBeUndefined();
    expect(plan.warnings.join(' ')).toMatch(/too small/i);
  });

  it('sends everything to AWD when FBA is already above target', () => {
    const plan = planSplit({ ...base, cartons: 100, fbaOnHand: 50_000 });
    expect(plan.legs.find(l => l.destination === 'FBA')).toBeUndefined();
    const awd = plan.legs.find(l => l.destination === 'AWD')!;
    expect(awd.units).toBe(1000);
    expect(awd.method).toBe('AWD_SLOW_SEA');
    expect(plan.warnings.join(' ')).toMatch(/already at or above/i);
  });

  it('splits a large batch between both destinations, sizing FBA to the delivery fill only', () => {
    const plan = planSplit({ ...base, cartons: 500, fbaOnHand: 0 });
    const fba = plan.legs.find(l => l.destination === 'FBA')!;
    const awd = plan.legs.find(l => l.destination === 'AWD')!;
    // 60 DOC from 2026-09-18 is exactly 600 units on the flat curve — 13 days
    // of September, 31 of October and 16 of November at 10/day. The other 4,400
    // sit at AWD, where storage is cheap. Sized to the 100-day combined target
    // the FBA leg would have been 1,000 — this is the whole original fix.
    expect(fba.units).toBe(600);
    expect(awd.units).toBe(4400);
    expect(plan.targetUnits).toBe(600);
    expect(plan.onHandAtSellable).toBe(0);
    expect(plan.shortfallUnits).toBe(0);
  });

  it('sizes the FBA leg to the DELIVERY level, never to the transfer level', () => {
    // The distinction the fourth level exists for. Same batch, same curve: the
    // free manufacturer → FBA leg lands 60 days of cover, not the 45 a paid
    // move out of AWD would restore. 150 units — 15 days — is what the deeper
    // fill buys, and it is the gap between the two levels on the flat curve.
    const plan = planSplit({ ...base, cartons: 500 });
    const asIfTransfer = planSplit({ ...base, cartons: 500, fbaBatchDoc: base.fbaTargetDoc });
    expect(plan.legs.find(l => l.destination === 'FBA')!.units).toBe(600);
    expect(asIfTransfer.legs.find(l => l.destination === 'FBA')!.units).toBe(450);
    expect(plan.fbaDocAtArrival).toEqual({ days: 60, capped: false });
    expect(asIfTransfer.fbaDocAtArrival).toEqual({ days: 45, capped: false });
  });

  it('rounds the FBA leg down to whole cartons', () => {
    const plan = planSplit({ ...base, cartons: 500, packageQuantity: 7 });
    const fba = plan.legs.find(l => l.destination === 'FBA')!;
    expect(fba.units % 7).toBe(0);
    expect(fba.cartons * 7).toBe(fba.units);
  });

  it('conserves units across both legs', () => {
    const plan = planSplit({ ...base, cartons: 333, packageQuantity: 12 });
    const total = plan.legs.reduce((s, l) => s + l.units, 0);
    expect(total).toBe(plan.units);
  });

  it('honours a manual method override', () => {
    const plan = planSplit({ ...base, cartons: 500, methodOverride: 'FAST_SEA' });
    const fba = plan.legs.find(l => l.destination === 'FBA')!;
    expect(fba.method).toBe('FAST_SEA');
    expect(fba.transitDays).toBe(27);
    expect(fba.reason).toMatch(/chosen manually/i);
    expect(plan.methodOverridden).toBe(true);
    expect(plan.autoMethod).toBe('FAST_SEA');
  });

  it('reports the FBA OOS date it computed', () => {
    // 100 units against August's 300/31 = 9.68/day runs dry on day 11.
    const plan = planSplit({ ...base, fbaOnHand: 100 });
    expect(plan.fbaOosDate).toBe('2026-08-17');
  });
});

describe('planSplit — transfers', () => {
  it('schedules AWD to FBA transfers when a pool exists', () => {
    const plan = planSplit({ ...base, cartons: 800, fbaOnHand: 0, awdOnHand: 0 });
    expect(plan.transfers.length).toBeGreaterThan(0);
    for (const t of plan.transfers) {
      expect(t.units).toBeGreaterThan(0);
      expect(t.units % base.packageQuantity).toBe(0);
      expect(new Date(t.arrivalDate).getTime()).toBeGreaterThan(new Date(t.orderDate).getTime());
    }
  });

  it('schedules nothing when there is no AWD pool at all', () => {
    const plan = planSplit({ ...base, cartons: 30, awdOnHand: 0 });
    expect(plan.transfers).toEqual([]);
  });

  it('orders on any day of the week, not only Mondays', () => {
    // The weekly walk this replaced could only order on a Monday, which delayed
    // every move by up to six days for no reason an AWD → FBA transfer has.
    const plan = planSplit({ ...base, cartons: 2000, awdOnHand: 20_000 });
    expect(plan.transfers.length).toBeGreaterThan(1);
    const weekdays = new Set(plan.transfers.map(t => parseKey(t.orderDate).getDay()));
    expect(weekdays.size).toBeGreaterThan(1);
  });

  it('reports leftover pool units when the AWD stock outlasts the horizon', () => {
    const plan = planSplit({ ...base, cartons: 10, awdOnHand: 1_000_000 });
    const moved = plan.transfers.reduce((s, t) => s + t.units, 0);
    expect(moved).toBe(3_030);              // all the curve's demand ever asks for
    expect(plan.leftoverAwdUnits).toBe(996_970);
    // The 100-unit batch is under the live target, so all of it goes to FBA and
    // the pool is exactly the million already at AWD.
    expect(moved + plan.leftoverAwdUnits).toBe(1_000_000);
    expect(plan.warnings.join(' ')).toMatch(/remain at AWD/i);
  });
});

describe('planSplit — transfer invariants', () => {
  it('conserves the pool: every unit moved plus the leftover is the pool', () => {
    const plan = planSplit({ ...base, cartons: 400, awdOnHand: 2_500 });
    const pool = 2_500 + (plan.legs.find(l => l.destination === 'AWD')?.units ?? 0);
    const moved = plan.transfers.reduce((s, t) => s + t.units, 0);
    expect(moved).toBeGreaterThan(0);
    expect(moved + plan.leftoverAwdUnits).toBe(pool);
  });

  it('never orders a transfer before the batch has landed at AWD', () => {
    const plan = planSplit({ ...base, cartons: 800, awdOnHand: 0 });
    const awdArrival = plan.legs.find(l => l.destination === 'AWD')!.arrivalDate;
    expect(plan.transfers.length).toBeGreaterThan(0);
    for (const t of plan.transfers) {
      expect(t.orderDate >= awdArrival).toBe(true);
    }
  });

  it('only moves stock that is short of target, and the move improves cover', () => {
    const plan = planSplit({ ...base, cartons: 800, awdOnHand: 0 });
    expect(plan.transfers.length).toBeGreaterThan(0);
    for (const t of plan.transfers) {
      expect(t.docBefore.days).toBeLessThan(base.fbaTargetDoc);
      expect(t.docAfter.days).toBeGreaterThan(t.docBefore.days);
    }
  });
});

// ─── Daily evaluation, and why it does not stutter ──────────
//
// The scheduler used to walk Mondays. It now walks every day, which runs the
// trigger seven times as often — so the thing that has to hold is that a move,
// once scheduled, is visible to the very next day's reading. `scheduleTransfers`
// drops its on-hand cache the instant the pool is drawn, so `stockAt` re-walks
// with the new arrival in it and tomorrow sees cover back near the target. If it
// did not, every day after the first trigger would see the same shortfall and
// order the same move again — a burst of duplicates instead of a schedule.
describe('planSplit — daily evaluation', () => {
  /** A million units at AWD, so the pool never binds and only the trigger is under test. */
  const deepPool: SplitInput = { ...base, cartons: 10, awdOnHand: 1_000_000 };
  /** Whole days between two local midnights — rounded, so a DST hour never leaks in. */
  const gapDays = (a: string, b: string) =>
    Math.round((parseKey(b).getTime() - parseKey(a).getTime()) / 86_400_000);
  /** Cover a move buys back: it restores the target from the reorder point. */
  const RESTORED = base.fbaTargetDoc - base.fbaReorderDoc; // 15

  it('emits a handful of moves across the horizon, not one per day', () => {
    const plan = planSplit(deepPool);
    expect(plan.transfers.length).toBeGreaterThan(1);
    // 466 modelled days. At one move per `RESTORED` days the schedule cannot
    // exceed ~31 rows; a loop that re-fired daily would emit hundreds.
    expect(plan.transfers.length).toBeLessThanOrEqual(Math.ceil(466 / RESTORED));
  });

  it('separates consecutive moves by the cover a move buys back', () => {
    const plan = planSplit(deepPool);
    for (let i = 1; i < plan.transfers.length; i++) {
      const prev = plan.transfers[i - 1];
      const next = plan.transfers[i];
      // One day of slack for flooring the move to whole cartons, which can
      // leave the restored level a day under the target. Never the 1-day gap a
      // duplicate would show.
      expect(gapDays(prev.orderDate, next.orderDate)).toBeGreaterThanOrEqual(RESTORED - 1);
      expect(gapDays(prev.arrivalDate, next.arrivalDate)).toBeGreaterThanOrEqual(RESTORED - 1);
    }
  });

  it('leaves cover above the reorder point, which is what stops the next day re-ordering', () => {
    const plan = planSplit(deepPool);
    expect(plan.transfers.length).toBeGreaterThan(1);
    for (const t of plan.transfers) {
      expect(t.docBefore.days).toBeLessThanOrEqual(base.fbaReorderDoc);
      expect(t.docAfter.days).toBeGreaterThan(base.fbaReorderDoc);
    }
  });

  it('never issues two moves on the same day', () => {
    for (const input of [deepPool, { ...base, cartons: 800 }, { ...base, cartons: 30, awdInbound: [{ units: 5_000 }] }]) {
      const plan = planSplit(input);
      const dates = plan.transfers.map(t => t.orderDate);
      expect(new Set(dates).size).toBe(dates.length);
    }
  });

  it('orders on the day cover crosses, not on the following Monday', () => {
    // TODAY is a Friday and FBA is empty from day one, so the move is due
    // immediately. The weekly walk could not act until Monday the 10th.
    const plan = planSplit({ ...base, cartons: 30, awdOnHand: 5_000 });
    expect(plan.transfers[0].orderDate).toBe('2026-08-07');
    expect(parseKey(plan.transfers[0].orderDate).getDay()).toBe(5); // Friday
  });
});

describe('planSplit — seasonality', () => {
  // Same batch and same 60-day window (2026-09-18 → 2026-11-16), but November's
  // demand is concentrated into its last 12 days (BFCM). The window catches
  // Nov 1-16, all of which pay the below-average offseason rate of 300/42 =
  // 7.14 rather than the flat 10, so the requirement lands under the flat-curve
  // 600. Monthly totals are identical either way.
  const seasonal: DemandCurve = { productDemand: FLAT, familySeason: SEASON, growth: 1.0 };

  it('sizes the FBA leg off the daily curve, not the monthly average', () => {
    const flat = planSplit({ ...base, cartons: 500 });
    const peaky = planSplit({ ...base, cartons: 500, curve: seasonal });
    expect(flat.legs.find(l => l.destination === 'FBA')!.units).toBe(600);
    // 13x10 + 31x10 + 16x(300/42) = 130 + 310 + 114.29 = 554.29 -> 55 cartons -> 550.
    expect(peaky.legs.find(l => l.destination === 'FBA')!.units).toBe(550);
  });

  it('does not cry "too small" over a sub-carton rounding remainder', () => {
    // target 554.29 floors to 550, leaving a 4.29-unit remnant — not a shortfall.
    const exact = planSplit({ ...base, cartons: 55, curve: seasonal });
    expect(exact.legs.find(l => l.destination === 'AWD')).toBeUndefined();
    expect(exact.warnings.join(' ')).not.toMatch(/too small/i);
    // A genuine three-carton gap against the flat curve's 600 still warns.
    const short = planSplit({ ...base, cartons: 57 });
    expect(short.warnings.join(' ')).toMatch(/too small/i);
  });
});

describe('planSplit — method override safety', () => {
  it('warns about an unavoidable stockout even when the method was overridden', () => {
    // FBA is empty today, so even FAST_SEA lands ~42 days late. Overriding to
    // the slower method makes that worse, never better.
    const plan = planSplit({ ...base, cartons: 500, methodOverride: 'SLOW_SEA' });
    expect(plan.warnings.join(' ')).toMatch(/unavoidable/i);
    const fba = plan.legs.find(l => l.destination === 'FBA')!;
    expect(fba.method).toBe('SLOW_SEA');
    expect(fba.reason).toMatch(/chosen manually/i);
    expect(fba.reason).toMatch(/unavoidable stockout/i);
  });

  it('ignores an override naming a method that is not on offer', () => {
    // AIR really is in the injected transit map, so without a membership check
    // this would quietly produce a 10-day air plan for a route Ori banned.
    const plan = planSplit({
      ...base,
      cartons: 500,
      transitDays: { ...base.transitDays, AIR: 10 },
      methodOverride: 'AIR' as unknown as FbaMethod,
    });
    const fba = plan.legs.find(l => l.destination === 'FBA')!;
    expect(fba.method).toBe('FAST_SEA'); // the auto pick, not AIR
    expect(fba.transitDays).toBe(27);
    expect(plan.methodOverridden).toBe(false);
    // The rejection is said out loud, not swallowed.
    expect(plan.warnings.join(' ')).toMatch(/ignored the requested method "Air"/i);
    expect(plan.warnings.join(' ')).toMatch(/used Fast Sea instead/i);
  });
});

describe('planSplit — growth guard', () => {
  it('refuses to compute when growth zeroes out the whole curve', () => {
    const plan = planSplit({ ...base, curve: { ...CURVE, growth: 0 } });
    expect(plan.ok).toBe(false);
    expect(plan.error).toMatch(/no demand forecast/i);
  });
});

describe('planSplit — inbound shipments', () => {
  const inbound = (qty: number, status: ProjectionShipment['status'], route: string): ProjectionShipment[] =>
    [{ qty, arrival_date: '2026-09-01', status, route }];

  it('counts confirmed FBA-bound stock against the delivery fill', () => {
    // 300 land 2026-09-01; 170 units of demand burn before the batch is
    // sellable on 09-18, leaving 130 on hand against the 600-unit delivery fill.
    const plan = planSplit({ ...base, shipments: inbound(300, 'transit', 'PO→MFR→FBA') });
    expect(plan.onHandAtSellable).toBe(130);
    expect(plan.legs.find(l => l.destination === 'FBA')!.units).toBe(470);
    expect(plan.legs.find(l => l.destination === 'AWD')!.units).toBe(530);
  });

  it('does not count AWD-bound stock as FBA cover', () => {
    const plan = planSplit({ ...base, shipments: inbound(900, 'transit', 'MFR→AWD') });
    expect(plan.onHandAtSellable).toBe(0);
    expect(plan.legs.find(l => l.destination === 'FBA')!.units).toBe(600);
  });

  it('ignores unconfirmed shipments', () => {
    const plan = planSplit({ ...base, shipments: inbound(900, 'suggested', 'PO→MFR→FBA') });
    expect(plan.onHandAtSellable).toBe(0);
    expect(plan.legs.find(l => l.destination === 'FBA')!.units).toBe(600);
  });
});

describe('planSplit — constants and guards', () => {
  it('refuses to compute when a transit day value is missing', () => {
    // parseTransitDays drops any LOV row with an unparseable days value, so a
    // single blank attribute lands here. Silently shipping a 0-day leg would
    // fabricate an arrival date and quietly move the transfer schedule.
    const partial: Record<string, number> = { ...base.transitDays };
    delete partial.AWD_SLOW_SEA;
    const plan = planSplit({ ...base, transitDays: partial as SplitInput['transitDays'] });
    expect(plan.ok).toBe(false);
    expect(plan.error).toMatch(/missing or non-positive/i);
    expect(plan.error).toMatch(/AWD Slow Sea/);
    expect(plan.legs).toEqual([]);
  });

  it('names every missing transit key at once', () => {
    const partial: Record<string, number> = { ...base.transitDays };
    delete partial.AWD_TRANSFER;
    delete partial.SLOW_SEA;
    const plan = planSplit({ ...base, transitDays: partial as SplitInput['transitDays'] });
    expect(plan.error).toMatch(/Slow Sea/);
    expect(plan.error).toMatch(/AWD → FBA Transfer/);
  });

  it('refuses a non-positive FBA target DOC', () => {
    expect(planSplit({ ...base, fbaTargetDoc: 0 }).error).toMatch(/FBA target days of cover/i);
  });

  it('refuses a combined target below the batch fill, which would ask AWD to hold negative days', () => {
    const plan = planSplit({ ...base, fbaTargetDoc: 45, fbaBatchDoc: 60, totalTargetDoc: 30 });
    expect(plan.ok).toBe(false);
    expect(plan.error).toMatch(/combined target days of cover/i);
    expect(plan.legs).toEqual([]);
  });

  it('accepts a combined target equal to the batch fill — a reserve of zero days is coherent', () => {
    const plan = planSplit({
      ...base, cartons: 500, fbaTargetDoc: 45, fbaBatchDoc: 45, totalTargetDoc: 45,
    });
    expect(plan.ok).toBe(true);
    expect(plan.legs.find(l => l.destination === 'FBA')!.units).toBe(450);
    expect(plan.legs.find(l => l.destination === 'AWD')!.reason).toMatch(/reserve carries no days of its own/i);
  });

  it('refuses negative on-hand figures', () => {
    expect(planSplit({ ...base, fbaOnHand: -1 }).error).toMatch(/FBA on-hand/i);
    expect(planSplit({ ...base, awdOnHand: -1 }).error).toMatch(/AWD on-hand/i);
  });
});

// ─── The four levels must stack in one order ────────────────
//
//   0 < fbaReorderDoc < fbaTargetDoc <= fbaBatchDoc <= totalTargetDoc
//
// Each link is a physical claim, not a convention. Cover falls TO the reorder
// point, so it must sit under the level a move restores; a delivery costs no
// transfer handling, so it can never stop shallower than a paid move would;
// and the pair cannot be asked to hold less than one of its halves already does.
describe('planSplit — the four-level ordering guard', () => {
  const ok = (over: Partial<SplitInput>) => planSplit({ ...base, ...over });

  it('accepts the levels in their intended order', () => {
    expect(ok({}).ok).toBe(true);
    // And accepts both ends collapsed: a delivery that fills exactly to the
    // transfer target, and one that fills the whole combined position.
    expect(ok({ fbaBatchDoc: 45 }).ok).toBe(true);
    expect(ok({ fbaBatchDoc: 100 }).ok).toBe(true);
  });

  it('refuses a reorder point at or below zero — nothing would ever trigger a move', () => {
    expect(ok({ fbaReorderDoc: 0 }).ok).toBe(false);
    expect(ok({ fbaReorderDoc: 0 }).error).toMatch(/FBA reorder days of cover/i);
    expect(ok({ fbaReorderDoc: -5 }).error).toMatch(/FBA reorder days of cover/i);
  });

  it('refuses a reorder point at or above the transfer target — every day would trigger', () => {
    expect(ok({ fbaReorderDoc: 45 }).error).toMatch(/FBA reorder days of cover/i);
    expect(ok({ fbaReorderDoc: 50 }).error).toMatch(/FBA reorder days of cover/i);
  });

  it('refuses a batch fill below the transfer target — the free leg cannot be the shallow one', () => {
    const plan = ok({ fbaBatchDoc: 44 });
    expect(plan.ok).toBe(false);
    expect(plan.error).toMatch(/batch fill days of cover/i);
    expect(plan.error).toMatch(/no transfer handling/i);
    expect(plan.legs).toEqual([]);
  });

  it('refuses a batch fill above the combined target — the reserve would owe days', () => {
    const plan = ok({ fbaBatchDoc: 101 });
    expect(plan.ok).toBe(false);
    expect(plan.error).toMatch(/combined target days of cover/i);
    expect(plan.legs).toEqual([]);
  });

  it('refuses a non-finite batch fill rather than sizing the leg off NaN', () => {
    expect(ok({ fbaBatchDoc: NaN }).error).toMatch(/batch fill days of cover/i);
    expect(ok({ fbaBatchDoc: Infinity }).ok).toBe(false);
  });

  it('rejects, never silently reorders: each bad arrangement fails on its own message', () => {
    // Four distinct complaints, so the operator is told which relationship broke.
    const messages = [
      ok({ fbaTargetDoc: 0 }).error,
      ok({ fbaReorderDoc: 45 }).error,
      ok({ fbaBatchDoc: 30 }).error,
      ok({ totalTargetDoc: 50 }).error,
    ];
    expect(new Set(messages).size).toBe(4);
    expect(messages.every(m => typeof m === 'string' && m.length > 0)).toBe(true);
  });
});

describe('docFromStock', () => {
  const from = new Date(2026, 8, 18); // September runs a flat 10/day
  const cap = 400;

  it('counts a stock that exactly covers N days as N', () => {
    expect(docFromStock(100, from, CURVE, cap)).toEqual({ days: 10, capped: false });
  });

  it('does not credit a day it cannot fully cover', () => {
    expect(docFromStock(99, from, CURVE, cap)).toEqual({ days: 9, capped: false });
    expect(docFromStock(0, from, CURVE, cap)).toEqual({ days: 0, capped: false });
  });

  it('flags a reading that saturated the cap', () => {
    expect(docFromStock(50_000, from, CURVE, cap)).toEqual({ days: 400, capped: true });
  });
});

describe('createAwdPool', () => {
  const today = new Date(2026, 7, 7);
  const landed = new Date(2026, 9, 14);
  const build = () => createAwdPool([
    { availableFrom: today, units: 500 },
    { availableFrom: landed, units: 1000, note: 'AWD batch' },
  ]);

  it('only offers stock that has landed', () => {
    const pool = build();
    expect(pool.total()).toBe(1500);
    expect(pool.availableAt(new Date(2026, 8, 1))).toBe(500);
    expect(pool.availableAt(landed)).toBe(1500);
  });

  it('draws no more than has landed, and conserves the total', () => {
    const pool = build();
    const early = pool.draw(new Date(2026, 8, 1), 800); // batch has not landed
    const later = pool.draw(new Date(2026, 9, 20), 300);
    expect(early).toBe(500);
    expect(later).toBe(300);
    expect(early + later + pool.leftover()).toBe(pool.total());
  });
});

describe('planSplit — reasons that match the arithmetic', () => {
  it('says the batch is the binding constraint instead of stating a false equation', () => {
    const plan = planSplit({ ...base, cartons: 30 });
    const reason = plan.legs.find(l => l.destination === 'FBA')!.reason;
    expect(reason).toMatch(/600 units of demand/);
    expect(reason).toMatch(/batch only holds 300 units/i);
    expect(reason).toMatch(/300 units short of target/i);
    expect(plan.shortfallUnits).toBe(300);
  });

  it('names the carton rounding when that is what bit', () => {
    const seasonal = { productDemand: FLAT, familySeason: SEASON, growth: 1.0 };
    const plan = planSplit({ ...base, cartons: 500, curve: seasonal });
    const reason = plan.legs.find(l => l.destination === 'FBA')!.reason;
    // 554 needed -> 55 cartons -> 550 units.
    expect(reason).toMatch(/554 needed/);
    expect(reason).toMatch(/55 × 10 = 550 units/);
  });

  it('names the DELIVERY level in the FBA leg ledger, not the transfer level', () => {
    // The sentence has to say which of the four levels produced the number
    // beside it, or the ledger reads as though a transfer had been sized.
    const reason = planSplit({ ...base, cartons: 500 }).legs.find(l => l.destination === 'FBA')!.reason;
    expect(reason).toMatch(/60 DOC from 2026-09-18 is 600 units of demand \(through 2026-11-16\)/);
    expect(reason).not.toMatch(/45 DOC/);
  });

  it('explains the AWD leg on its own terms when nothing goes to FBA', () => {
    const plan = planSplit({ ...base, fbaOnHand: 50_000 });
    const reason = plan.legs.find(l => l.destination === 'AWD')!.reason;
    expect(reason).not.toMatch(/remainder/i);
    expect(reason).toMatch(/already at or above 60 DOC/i);
    expect(reason).toMatch(/AWD Slow Sea is the default AWD route \(63d\)/);
    // The transfer lead is AWD_TRANSFER alone — door to sellable, with no FBA
    // inbound buffer added on top of it.
    expect(reason).toMatch(/takes 14d door to sellable/);
    expect(reason).not.toMatch(/10d inbound/);
    // Transfers are untouched by the deeper delivery fill: still ordered at the
    // reorder point, still sized to the transfer target.
    expect(reason).toMatch(/ordered when cover falls to 30 days and sized to restore 45/);
  });

  it('says what the AWD leg holds and against which target, not just that it is what is left', () => {
    // The reserve's share is the combined target LESS THE DELIVERY FILL — 100 −
    // 60 = 40 days — because both legs come out of one batch and this delivery
    // already put 60 days at FBA. Measured from the AWD leg's own 2026-10-14
    // landing: 40 x 10 = 400 units on the flat curve.
    const plan = planSplit({ ...base, cartons: 500 });
    const reason = plan.legs.find(l => l.destination === 'AWD')!.reason;
    expect(reason).not.toMatch(/remainder/i);
    expect(reason).toMatch(/40-day AWD share of the 100-day combined target/);
    expect(reason).toMatch(/400 units of demand from 2026-10-14/);
    // 4,400 against a 400-unit share — it covers it, and says by how much.
    expect(reason).toMatch(/4000 units to spare/);
    // And it says where the 40 came from, so the subtraction is checkable.
    expect(reason).toMatch(/what is left once this delivery puts 60 days at FBA/);
  });

  it('says how far short the AWD leg falls when the reserve is underfilled', () => {
    // 650-unit batch: 600 fill FBA to 60 days, leaving 50 for a 400-unit share.
    const plan = planSplit({ ...base, cartons: 65 });
    const reason = plan.legs.find(l => l.destination === 'AWD')!.reason;
    expect(reason).toMatch(/Holds 50 of the 400 units/);
    expect(reason).toMatch(/350 short of it/);
  });

  it('keeps the reserve share consistent with the combined target arithmetic', () => {
    // The regression guard for prose drift. Whatever the delivery fill is, the
    // share the sentence claims plus that fill must be the combined target —
    // otherwise a perfectly sized batch would read as overstock.
    for (const fbaBatchDoc of [45, 60, 80]) {
      const plan = planSplit({ ...base, cartons: 500, fbaBatchDoc });
      const reason = plan.legs.find(l => l.destination === 'AWD')!.reason;
      const share = Number(/(\d+)-day AWD share of the (\d+)-day combined target/.exec(reason)![1]);
      expect(share + fbaBatchDoc).toBe(base.totalTargetDoc);
    }
  });

  it('names the cheaper option it rejected when it escalates', () => {
    const transit = { FAST_SEA: 27, SLOW_SEA: 33, AWD_SLOW_SEA: 63, AWD_TRANSFER: 14 };
    const r = selectFbaMethod(new Date(2026, 7, 12), new Date(2026, 8, 20), transit, 10);
    expect(r.method).toBe('FAST_SEA');
    expect(r.reason).toMatch(/Slow Sea would land 2026-09-24, after FBA runs out 2026-09-20/);
    expect(r.reason).toMatch(/Fast Sea lands 2026-09-18/);
  });

  it('uses human captions, never raw enum tokens, in operator prose', () => {
    const plan = planSplit({ ...base, cartons: 500 });
    for (const leg of plan.legs) {
      expect(leg.reason).not.toMatch(/FAST_SEA|SLOW_SEA|AWD_TRANSFER/);
    }
  });

  // A caption that hardcodes a day count outlives the LOV that moved it — the
  // export said "AWD Slow Sea 60 Days" long after AWD_SLOW_SEA became 63.
  it('keeps day counts out of the captions themselves', () => {
    for (const caption of Object.values(METHOD_CAPTIONS)) {
      expect(caption).not.toMatch(/\d/);
    }
  });
});

describe('planSplit — daily series', () => {
  it('spans the whole horizon, one entry per day', () => {
    const plan = planSplit({ ...base, cartons: 800 });
    expect(plan.series.length).toBe(466); // 365 + totalTargetDoc, inclusive of today
    expect(plan.series[0].date).toBe('2026-08-07');
    expect(plan.series[465].date).toBe('2027-11-15');
  });

  it('names what landed and reports the DOC the engine decided from', () => {
    const plan = planSplit({ ...base, cartons: 800 });
    const batchDay = plan.series.find(d => d.arrivalNote === 'FBA batch')!;
    expect(batchDay.date).toBe('2026-09-18');
    expect(batchDay.arrivals).toBe(600);
    expect(batchDay.fbaUnits).toBe(600);
    expect(batchDay.doc).toBe(60); // exactly the delivery fill, by construction
    expect(batchDay.docCapped).toBe(false);

    const awdDay = plan.series.find(d => d.arrivalNote === 'AWD batch')!;
    expect(awdDay.date).toBe('2026-10-14');
    expect(awdDay.awdUnits).toBe(7400);
  });

  it('moves units out of AWD on the order date and into FBA on arrival', () => {
    const plan = planSplit({ ...base, cartons: 800 });
    const first = plan.transfers[0];
    const idx = plan.series.findIndex(d => d.date === first.orderDate);
    // Balances are opening figures, so the draw shows on the following day.
    expect(plan.series[idx].awdUnits - plan.series[idx + 1].awdUnits).toBe(first.units);

    const arriveDay = plan.series.find(d => d.date === first.arrivalDate)!;
    expect(arriveDay.arrivalNote).toContain('AWD→FBA transfer');
    expect(arriveDay.arrivals).toBe(first.units);
  });

  it('ends with exactly the leftover it reports', () => {
    const plan = planSplit({ ...base, cartons: 800, awdOnHand: 400 });
    expect(plan.series[plan.series.length - 1].awdUnits).toBe(plan.leftoverAwdUnits);
  });
});

describe('planSplit — a plan with nothing to warn about', () => {
  it('says nothing when the batch fills FBA to the delivery level and the pair to the combined one', () => {
    // 600 on hand runs to 2026-10-06, so the cheapest route lands in time and
    // the sellable date is 09-24. 128 units survive to it; the 60-day fill from
    // 09-24 is 7x10 + 31x10 + 22x10 = 600 units, so 472 are needed and 470
    // whole cartons go. That makes 598 live (59 DOC), and the 400 sent to AWD
    // bring the pair to 998 — two units under the 1,000 the 100-day combined
    // target asks for, which is inside a carton.
    const plan = planSplit({ ...base, cartons: 87, fbaOnHand: 600 });
    expect(plan.warnings).toEqual([]);
    expect(plan.legs.find(l => l.destination === 'FBA')!.method).toBe('SLOW_SEA');
    expect(plan.legs.find(l => l.destination === 'FBA')!.units).toBe(470);
    expect(plan.legs.find(l => l.destination === 'AWD')!.units).toBe(400);
    expect(plan.fbaDocAtArrival).toEqual({ days: 59, capped: false });
    expect(plan.combinedDocAtArrival).toEqual({ days: 99, capped: false });
    // Three moves at the min/max cadence empty the 400-unit reserve. The first
    // can only be ordered once the AWD leg lands on 10-14; by its 10-28 landing
    // FBA is down to 258 units (25 DOC), and 190 whole cartons is what the
    // 45-day transfer target asks for. Each later move fires as cover reaches
    // 30 again, 14 days apart, restoring what the pool can still afford.
    expect(plan.transfers.map(t => [t.orderDate, t.arrivalDate, t.units])).toEqual([
      ['2026-10-14', '2026-10-28', 190],
      ['2026-10-28', '2026-11-11', 140],
      ['2026-11-11', '2026-11-25', 70],
    ]);
    expect(plan.transfers.reduce((s, t) => s + t.units, 0)).toBe(400);
    expect(plan.leftoverAwdUnits).toBe(0);
  });

  it('reports days of cover at arrival, flagging a saturated reading', () => {
    expect(planSplit(base).fbaDocAtArrival).toEqual({ days: 60, capped: false });
    expect(planSplit({ ...base, fbaOnHand: 50_000 }).fbaDocAtArrival).toEqual({ days: 400, capped: true });
  });
});

/** Units ordered by date D must never exceed pool landed by D, on any date. */
function assertPoolNeverOverdrawn(plan: ReturnType<typeof planSplit>, awdOnHand: number) {
  const landedByDate = (d: string) => {
    const awdLeg = plan.legs.find(l => l.destination === 'AWD');
    return awdOnHand + (awdLeg && awdLeg.arrivalDate <= d ? awdLeg.units : 0);
  };
  for (const t of plan.transfers) {
    const orderedByThen = plan.transfers
      .filter(x => x.orderDate <= t.orderDate)
      .reduce((s, x) => s + x.units, 0);
    expect(orderedByThen).toBeLessThanOrEqual(landedByDate(t.orderDate));
  }
}

describe('planSplit — the pool is never overdrawn', () => {
  // Regression: a merge window used to fold a later draw into an earlier row,
  // dating the move before the goods had landed at AWD. The row read
  // "2026-10-12: 160u" while AWD held 100, and the series went to -60. The fold
  // is gone entirely; `createAwdPool` dating every tranche is now the only thing
  // standing between the schedule and that bug, so it is pinned here directly.
  const straddle = { ...base, fbaOnHand: 1000, awdOnHand: 500, cartons: 100 };

  it('never dates a move before the stock is at AWD', () => {
    const plan = planSplit(straddle);
    expect(plan.transfers.length).toBeGreaterThan(1);
    assertPoolNeverOverdrawn(plan, 500);
  });

  it('never lets the AWD balance go negative', () => {
    for (const cartons of [100, 500, 2000]) {
      const plan = planSplit({ ...straddle, cartons });
      const lowest = Math.min(...plan.series.map(d => d.awdUnits));
      expect(lowest).toBeGreaterThanOrEqual(0);
    }
  });

  it('keeps every row executable exactly as written', () => {
    const plan = planSplit(straddle);
    const awdLanding = plan.legs.find(l => l.destination === 'AWD')!.arrivalDate;
    // Moves continue past the batch's own landing, and none of them arrives
    // before it was ordered.
    expect(plan.transfers.filter(t => t.orderDate > awdLanding).length).toBeGreaterThan(0);
    for (const t of plan.transfers) {
      expect(t.arrivalDate > t.orderDate).toBe(true);
    }
  });

  it('still conserves the pool across the whole schedule', () => {
    const plan = planSplit(straddle);
    const pool = 500 + (plan.legs.find(l => l.destination === 'AWD')?.units ?? 0);
    const moved = plan.transfers.reduce((s, t) => s + t.units, 0);
    expect(moved + plan.leftoverAwdUnits).toBe(pool);
  });
});

describe('planSplit — transfers respect the carton multiple against a ragged pool', () => {
  it('rounds every transfer to whole cartons even when the pool is not a multiple', () => {
    // 353 units at pkg 7 leaves a 3-unit remainder that can never move. 60
    // cartons = 420 units, under the 600-unit delivery fill, so the whole batch
    // goes to FBA and the pool stays exactly the ragged 353 on hand.
    const plan = planSplit({ ...base, packageQuantity: 7, awdOnHand: 353, cartons: 60 });
    expect(plan.transfers.length).toBeGreaterThan(0);
    for (const t of plan.transfers) {
      expect(t.units % 7).toBe(0);
      expect(t.cartons * 7).toBe(t.units);
    }
    const movedFromOnHand = Math.min(
      plan.transfers.reduce((s, t) => s + t.units, 0), 353);
    expect(353 - movedFromOnHand).toBeGreaterThanOrEqual(3);
  });
});

describe('planSplit — timezone safety', () => {
  const ship = (date: string) => [{
    qty: 200, arrival_date: date, status: 'transit' as const, route: 'PO→MFR→FBA',
  }];

  it('reads a bare YYYY-MM-DD as a local date, not UTC midnight', () => {
    // Sellable is 2026-09-18. A shipment dated the 19th lands AFTER it and must
    // not count; parsed as UTC it would read as the 18th west of Greenwich and
    // divert 200 units to AWD purely because of the viewer's clock.
    const plan = planSplit({ ...base, cartons: 500, shipments: ship('2026-09-19') });
    expect(plan.onHandAtSellable).toBe(0);
    expect(plan.legs.find(l => l.destination === 'FBA')!.units).toBe(600);
  });

  it('counts a shipment landing exactly on the sellable date', () => {
    const plan = planSplit({ ...base, cartons: 500, shipments: ship('2026-09-18') });
    expect(plan.onHandAtSellable).toBe(200);
    expect(plan.legs.find(l => l.destination === 'FBA')!.units).toBe(400);
  });
});

describe('planSplit — transit days must be positive', () => {
  it('rejects a zero transit rather than shipping and arriving the same day', () => {
    const plan = planSplit({ ...base, transitDays: { ...base.transitDays, AWD_SLOW_SEA: 0 } });
    expect(plan.ok).toBe(false);
    expect(plan.error).toMatch(/missing or non-positive/i);
  });

  it('rejects a negative transit rather than arriving before it ships', () => {
    expect(planSplit({ ...base, transitDays: { ...base.transitDays, SLOW_SEA: -33 } }).ok).toBe(false);
    expect(planSplit({ ...base, transitDays: { ...base.transitDays, AWD_TRANSFER: -14 } }).ok).toBe(false);
  });
});

describe('planSplit — ledger prose agrees with the structured fields', () => {
  it('states a subtraction that actually holds', () => {
    const seasonal = { productDemand: FLAT, familySeason: SEASON, growth: 1.0 };
    const plan = planSplit({ ...base, cartons: 500, curve: seasonal, fbaOnHand: 427 });
    const reason = plan.legs.find(l => l.destination === 'FBA')!.reason;
    const m = /is (\d+) units of demand \(through [\d-]+\), less (\d+) projected on hand = (\d+) needed/.exec(reason)!;
    expect(m).toBeTruthy();
    const [, target, onHand, need] = m.map(Number);
    expect(target - onHand).toBe(need);           // the prose adds up
    expect(target).toBe(plan.targetUnits);        // and matches the fields beside it
    expect(onHand).toBe(plan.onHandAtSellable);
  });
});

describe('planSplit — the panel’s anchors', () => {
  it('names the date the ledger is keyed to, even with no FBA leg', () => {
    // Well stocked, so FBA never runs out and the cheapest route wins:
    // 2026-08-12 + 33 + 10. The empty-FBA base case escalates and lands sooner.
    const allAwd = planSplit({ ...base, fbaOnHand: 50_000 });
    expect(allAwd.legs.find(l => l.destination === 'FBA')).toBeUndefined();
    expect(allAwd.sellableDate).toBe('2026-09-24');
    expect(planSplit(base).sellableDate).toBe('2026-09-18');
  });

  it('reports the window the series actually spans', () => {
    const plan = planSplit({ ...base, cartons: 800 });
    expect(plan.walkWindow).toEqual({ from: '2026-08-07', to: '2027-11-15' });
    expect(plan.walkWindow!.from).toBe(plan.series[0].date);
    expect(plan.walkWindow!.to).toBe(plan.series[plan.series.length - 1].date);
    expect(planSplit({ ...base, cartons: 0 }).walkWindow).toBeNull();
  });

  it('reports the combined position alongside the live one', () => {
    // 5,000-unit batch, nothing on hand: 600 live at FBA (60 DOC) and 4,400 at
    // AWD. The pair is 5,000 units from 2026-09-18, which at 10/day is 400 days
    // — the cap, so the reading says so rather than claiming a precise 500.
    const plan = planSplit({ ...base, cartons: 500 });
    expect(plan.fbaDocAtArrival).toEqual({ days: 60, capped: false });
    expect(plan.combinedDocAtArrival).toEqual({ days: 400, capped: true });
  });

  it('counts AWD stock already on hand in the combined position', () => {
    // Same batch, plus 2,000 already sitting at AWD. FBA is untouched by it —
    // it is not sellable — but the pair is 2,000 units richer.
    const withReserve = planSplit({ ...base, cartons: 60, awdOnHand: 2_000 });
    const without = planSplit({ ...base, cartons: 60 });
    expect(withReserve.fbaDocAtArrival).toEqual(without.fbaDocAtArrival);
    // The 600-unit batch fills FBA to exactly 60 days and nothing is left for
    // the AWD leg, so 600 live + 2,000 on hand = 2,600 units at 10/day = 260 days.
    expect(withReserve.combinedDocAtArrival).toEqual({ days: 260, capped: false });
    expect(without.combinedDocAtArrival).toEqual({ days: 60, capped: false });
  });

  it('measures cover at arrival from the sellable date, not the dock date', () => {
    // A curve that steps — 10/day in September, 20/day in October, 60/day in
    // November — so the 10-day inbound buffer visibly changes the reading. The
    // 60-day fill from the 09-18 sellable date is 13x10 + 31x20 + 16x60 = 1,710
    // units; read from the 09-08 dock date the same stock lasts 68 days,
    // because it starts by spending ten cheap September days and then runs out
    // partway through expensive November instead of on its last day.
    const step: DemandCurve = {
      productDemand: { ...FLAT, 202609: 300, 202610: 620, 202611: 1800 },
      familySeason: {}, growth: 1.0,
    };
    const plan = planSplit({ ...base, cartons: 500, curve: step, fbaOnHand: 300 });
    const fba = plan.legs.find(l => l.destination === 'FBA')!;
    const stock = plan.onHandAtSellable + fba.units;
    expect(stock).toBe(1710); // 13x10 + 31x20 + 16x60
    expect(docFromStock(stock, parseKey(fba.sellableDate), step, 400))
      .toEqual(plan.fbaDocAtArrival);
    expect(docFromStock(stock, parseKey(fba.arrivalDate), step, 400))
      .toEqual({ days: 68, capped: false });
    expect(plan.fbaDocAtArrival).toEqual({ days: 60, capped: false });
  });
});

// ─── The batch this engine got wrong ────────────────────────
//
// A real 12,000-unit batch (package quantity 12). Demand is a flat 120/day, so
// every month is 120 x its day count and the arithmetic is checkable by hand.
// 5,280 on hand at FBA burns 120/day for the 42 days to the sellable date and
// leaves exactly 240 there — which is what made the old engine's answer
// 11,760 to FBA and 240 to AWD, the split that prompted this fix.
const D120: Record<number, number> = {
  202608: 3720, 202609: 3600, 202610: 3720, 202611: 3600, 202612: 3720,
  202701: 3720, 202702: 3360, 202703: 3720, 202704: 3600, 202705: 3720, 202706: 3600,
  202707: 3720, 202708: 3720, 202709: 3600, 202710: 3720, 202711: 3600, 202712: 3720,
};

const realBatch: SplitInput = {
  ...base,
  cartons: 1000,
  packageQuantity: 12,
  fbaOnHand: 5_280,
  curve: { productDemand: D120, familySeason: {}, growth: 1.0 },
};

describe('planSplit — the 12,000-unit batch', () => {
  it('sized the FBA leg at 11,760 of 12,000 when FBA was sized to the combined target', () => {
    // The bug, reproduced through the new API: point the delivery fill at the
    // 100-day number and the expensive warehouse takes 98% of the batch.
    const old = planSplit({ ...realBatch, fbaTargetDoc: 100, fbaBatchDoc: 100 });
    expect(old.ok).toBe(true);
    expect(old.targetUnits).toBe(12_000);          // 100 x 120
    expect(old.onHandAtSellable).toBe(240);
    expect(old.legs.find(l => l.destination === 'FBA')!.units).toBe(11_760);
    expect(old.legs.find(l => l.destination === 'AWD')!.units).toBe(240);
  });

  it('sends 6,960 to FBA and 5,040 to AWD once FBA is sized to the delivery fill', () => {
    const plan = planSplit(realBatch);
    expect(plan.ok).toBe(true);
    expect(plan.units).toBe(12_000);
    expect(plan.sellableDate).toBe('2026-09-18');

    const fba = plan.legs.find(l => l.destination === 'FBA')!;
    const awd = plan.legs.find(l => l.destination === 'AWD')!;
    // 60 x 120 = 7,200 at FBA, less the 240 already there = 6,960 (580 cartons).
    expect(plan.targetUnits).toBe(7_200);
    expect(plan.onHandAtSellable).toBe(240);
    expect(fba.units).toBe(6_960);
    expect(fba.cartons).toBe(580);
    expect(awd.units).toBe(5_040);
    expect(awd.cartons).toBe(420);

    // 4,800 units still kept out of the expensive warehouse against the
    // original bug — the deeper fill spends 1,800 of the 6,600 the 45-day
    // sizing saved, and buys 15 transfer-free days with it.
    expect(11_760 - fba.units).toBe(4_800);
    expect(planSplit({ ...realBatch, fbaBatchDoc: 45 })
      .legs.find(l => l.destination === 'FBA')!.units).toBe(5_160);
    expect(fba.units + awd.units).toBe(plan.units);
  });

  it('lands 60 days at FBA and 102 across the pair', () => {
    const plan = planSplit(realBatch);
    // 240 + 6,960 = 7,200 = 60 days at 120/day.
    expect(plan.fbaDocAtArrival).toEqual({ days: 60, capped: false });
    // The pair is 12,240 units = 102 days — the whole batch plus what survived
    // at FBA, against a 100-day combined target. Unchanged by the split: moving
    // the line between the legs cannot move their sum.
    expect(plan.combinedDocAtArrival).toEqual({ days: 102, capped: false });
    // 102 against 100 is carton quantisation, not overstock: it stays quiet.
    expect(plan.warnings.join(' ')).not.toMatch(/overstock/i);
    expect(plan.warnings.join(' ')).not.toMatch(/short by/i);
  });
});

// ─── Stock already on the water to AWD ──────────────────────
//
// The inventory snapshot reports a quantity and no date, so an undated tranche
// lands at AWD_SLOW_SEA from today: 2026-08-07 + 63 = 2026-10-09. It is owned
// from now (so it counts in the combined position) but unusable until then (so
// no transfer may be ordered against it earlier).
describe('planSplit — inbound AWD stock', () => {
  const LANDS = '2026-10-09';

  it('counts it in the combined position exactly as AWD stock on hand would be', () => {
    // 600-unit batch: all 600 fill FBA to its 60-day level, plus 2,000 owned
    // elsewhere = 2,600 units from 2026-09-18, which at 10/day is 260 days.
    const inTransit = planSplit({ ...base, cartons: 60, awdInbound: [{ units: 2_000 }] });
    const onHand = planSplit({ ...base, cartons: 60, awdOnHand: 2_000 });
    const neither = planSplit({ ...base, cartons: 60 });

    expect(inTransit.combinedDocAtArrival).toEqual({ days: 260, capped: false });
    expect(inTransit.combinedDocAtArrival).toEqual(onHand.combinedDocAtArrival);
    expect(neither.combinedDocAtArrival).toEqual({ days: 60, capped: false });
    // FBA is untouched by it — it is not sellable, and it is not even at AWD yet.
    expect(inTransit.fbaDocAtArrival).toEqual(neither.fbaDocAtArrival);
    expect(inTransit.legs.find(l => l.destination === 'FBA')!.units).toBe(600);
  });

  it('states the arrival it had to assume instead of burying it', () => {
    const plan = planSplit({ ...base, cartons: 60, awdInbound: [{ units: 2_000 }] });
    expect(plan.assumptions).toHaveLength(1);
    expect(plan.assumptions[0]).toMatch(/2000 units already in transit to AWD carry no arrival date/);
    expect(plan.assumptions[0]).toMatch(new RegExp(`assumed to land ${LANDS}`));
    expect(plan.assumptions[0]).toMatch(/AWD Slow Sea \(63d\) from today/);
    // An assumption is not a warning: nothing here is wrong.
    expect(plan.warnings.join(' ')).not.toMatch(/assumed to land/);
  });

  it('says nothing when the caller supplied a real arrival date', () => {
    const plan = planSplit({ ...base, cartons: 60, awdInbound: [{ units: 600, arrivalDate: '2026-09-01' }] });
    expect(plan.assumptions).toEqual([]);
    const landing = plan.series.find(d => d.date === '2026-09-01')!;
    expect(landing.awdUnits).toBe(600);
    expect(landing.arrivalNote).toContain('AWD in transit');
  });

  it('never lets a transfer be ordered before the stock has landed at AWD', () => {
    // A 300-unit batch against a 600-unit delivery fill goes entirely to FBA, so
    // the AWD leg is empty and the only pool is the 5,000 units at sea. They are
    // unusable until 2026-10-09, and with daily evaluation that landing day is
    // itself the first day a move can be ordered against them.
    const plan = planSplit({ ...base, cartons: 30, awdInbound: [{ units: 5_000 }] });
    expect(plan.legs.find(l => l.destination === 'AWD')).toBeUndefined();
    expect(plan.transfers.length).toBeGreaterThan(0);
    expect(plan.transfers[0].orderDate).toBe(LANDS);
    for (const t of plan.transfers) {
      expect(t.orderDate >= LANDS).toBe(true);
      expect(t.arrivalDate > t.orderDate).toBe(true);
    }
    // Held back, not ignored: the same units already at AWD move from today,
    // because FBA is empty from day one and the pool is right there.
    const onHand = planSplit({ ...base, cartons: 30, awdOnHand: 5_000 });
    expect(onHand.transfers[0].orderDate).toBe('2026-08-07');
    expect(onHand.transfers[0].orderDate < plan.transfers[0].orderDate).toBe(true);
  });

  it('conserves the pool once the new tranche is part of it', () => {
    const plan = planSplit({ ...base, cartons: 400, awdOnHand: 2_500, awdInbound: [{ units: 1_000 }] });
    const pool = 2_500 + 1_000 + (plan.legs.find(l => l.destination === 'AWD')?.units ?? 0);
    const moved = plan.transfers.reduce((s, t) => s + t.units, 0);
    expect(pool).toBe(6_900); // 2,500 on hand + 1,000 at sea + 3,400 of the batch
    expect(moved).toBeGreaterThan(0);
    expect(moved + plan.leftoverAwdUnits).toBe(pool);
    expect(Math.min(...plan.series.map(d => d.awdUnits))).toBeGreaterThanOrEqual(0);
  });

  it('shows the tranche landing in the AWD balance on the day it lands, not before', () => {
    const plan = planSplit({ ...base, cartons: 30, fbaOnHand: 50_000, awdInbound: [{ units: 5_000 }] });
    const on = (d: string) => plan.series.find(s => s.date === d)!;
    expect(on('2026-10-08').awdUnits).toBe(0);
    expect(on(LANDS).awdUnits).toBe(5_000);
    expect(on(LANDS).arrivalNote).toContain('AWD in transit');
  });

  it('treats an absent, empty or zero tranche list as no inbound AWD stock at all', () => {
    const none = planSplit({ ...base, cartons: 60 });
    for (const awdInbound of [[], [{ units: 0 }]]) {
      const plan = planSplit({ ...base, cartons: 60, awdInbound });
      expect(plan.combinedDocAtArrival).toEqual(none.combinedDocAtArrival);
      expect(plan.assumptions).toEqual([]);
      expect(plan.transfers).toEqual(none.transfers);
    }
  });

  it('refuses a negative in-transit quantity rather than crediting the reserve', () => {
    const plan = planSplit({ ...base, cartons: 60, awdInbound: [{ units: -100 }] });
    expect(plan.ok).toBe(false);
    expect(plan.error).toMatch(/AWD in-transit units/i);
    expect(plan.legs).toEqual([]);
  });
});

describe('planSplit — the three shortfalls are different problems', () => {
  it('calls out the TRANSFER target when the batch cannot even reach it', () => {
    // 300 units. The 45-day transfer target asks for 450 from 2026-09-18, so
    // FBA lands at 30 days — under the level a move out of AWD would have
    // restored — and nothing is left for the reserve to send. A stockout risk,
    // and it is quoted against the 45-day level it names: 450 − 300 = 150 units
    // and 45 − 30 = 15 days. Never the 60-day gap, which would print 300 units
    // beside a 15-day figure and add up to nothing.
    const plan = planSplit({ ...base, cartons: 30 });
    const said = plan.warnings.join(' ');
    expect(said).toMatch(/too small to put 45 days live at FBA/);
    expect(said).toMatch(/short by 150 units \(~15 days\)/);
    expect(said).toMatch(/stockout risk/);
    // Not the reorder message — this one is urgent and must not be diluted.
    expect(said).not.toMatch(/combined target/);
    expect(said).not.toMatch(/reorder/i);
    // And not the 60-day complaint: a batch this small has a bigger problem.
    expect(said).not.toMatch(/fill FBA to 60 days/);
  });

  it('calls out the DELIVERY fill when the batch clears 45 but misses 60', () => {
    // 500 units: FBA lands at 50 days, comfortably above the 45 a transfer
    // restores, so nothing is at risk — the batch simply stopped short of the
    // free fill and the first paid move comes sooner. 600 − 500 = 100 units,
    // 60 − 50 = 10 days.
    const plan = planSplit({ ...base, cartons: 50 });
    const said = plan.warnings.join(' ');
    expect(plan.fbaDocAtArrival).toEqual({ days: 50, capped: false });
    expect(said).toMatch(/too small to fill FBA to 60 days/);
    expect(said).toMatch(/short by 100 units \(~10 days\)/);
    expect(said).toMatch(/clears the 45-day transfer target/);
    // Explicitly NOT the stockout message: cover is fine, this costs money.
    expect(said).not.toMatch(/stockout risk/);
    expect(said).not.toMatch(/45 days live at FBA/);
  });

  it('calls out the combined position when FBA is filled but the pair is thin', () => {
    // 600 units: all of them fill FBA to its 60-day level and nothing reaches
    // AWD, so the pair holds 600 of the 1,000 units the 100-day combined
    // target asks for.
    const plan = planSplit({ ...base, cartons: 60 });
    const said = plan.warnings.join(' ');
    expect(said).toMatch(/FBA is covered to 60 days/);
    expect(said).toMatch(/hold 60 days against the 100-day combined target/);
    expect(said).toMatch(/short by 400 units \(~40 days\)/);
    expect(said).toMatch(/Reorder/);
    // Neither of the FBA messages — FBA is filled, this is a next-batch signal.
    expect(said).not.toMatch(/too small/i);
    expect(said).not.toMatch(/stockout risk/);
  });

  it('reports the delivery-fill gap and the combined gap together when both are real', () => {
    // 500 units short-fills FBA AND leaves the pair at half the combined
    // target. Neither is urgent, so neither is suppressed — the mutual
    // exclusion exists to protect the stockout message, and there isn't one.
    const said = planSplit({ ...base, cartons: 50 }).warnings.join(' ');
    expect(said).toMatch(/too small to fill FBA to 60 days/);
    expect(said).toMatch(/hold 50 days against the 100-day combined target/);
  });

  it('calls the pair overstock once it runs materially past the combined target', () => {
    // 1,500 units against a 1,000-unit combined target — 50% over.
    const plan = planSplit({ ...base, cartons: 150 });
    const said = plan.warnings.join(' ');
    expect(said).toMatch(/hold 150 days against the 100-day combined target/);
    expect(said).toMatch(/500 units beyond it/);
    expect(said).toMatch(/overstock, not prudence/);
  });

  it('stays quiet at a tenth over the target, where the excess is still rounding', () => {
    // 1,100 units is exactly 110% of the 1,000-unit target: the boundary is
    // inclusive of prudence, so nothing is said either way.
    const plan = planSplit({ ...base, cartons: 110 });
    const said = plan.warnings.join(' ');
    expect(said).not.toMatch(/overstock/i);
    expect(said).not.toMatch(/short by/);
    expect(planSplit({ ...base, cartons: 111 }).warnings.join(' ')).toMatch(/overstock/i);
  });
});

// ─── Does 45 days survive a peak ramp? ──────────────────────
//
// The thinnest a 45-day buffer ever gets, in units, is during a steep ramp into
// peak — exactly when the transfer lead has the least slack, because 45 days of
// cover measured today buys fewer than 45 days once the ramp steepens. Demand
// quadruples from 100/day in September to 800/day on Christmas peak days, with
// every rate an exact integer so the arithmetic is checkable:
//   Sep 3,000/30 = 100    Oct 6,200/31 = 200
//   Nov 12,600 over (12 peak x2 + 18 off) = 300 off / 600 peak
//   Dec 18,400 over (15 peak x2 + 16 off) = 400 off / 800 peak
const RAMP: Record<number, number> = {
  202608: 3100, 202609: 3000, 202610: 6200, 202611: 12600, 202612: 18400,
  202701: 3100, 202702: 2800, 202703: 3100, 202704: 3000, 202705: 3100, 202706: 3000,
  202707: 3100, 202708: 3100, 202709: 3000, 202710: 6200, 202711: 12600, 202712: 18400,
};
const RAMP_SEASON: Record<number, MonthSeasonInfo> = {
  202611: { peakDays: 12, offseasonDays: 18, holidays: 'BFCM' },
  202612: { peakDays: 15, offseasonDays: 16, holidays: 'Christmas' },
};

describe('planSplit — a 45-day buffer through a peak ramp', () => {
  // AWD is deliberately deep, so the pool never binds and the only question
  // left is the one being asked: can a 45-day level, ordered at 30 and restored
  // daily, carry FBA through a ramp? (The deep reserve trips the overstock
  // warning by construction — that is the fixture, not a finding.)
  const ramp: SplitInput = {
    ...base,
    cartons: 1000,
    packageQuantity: 12,
    fbaOnHand: 12_000,
    awdOnHand: 60_000,
    curve: { productDemand: RAMP, familySeason: RAMP_SEASON, growth: 1.0 },
  };
  const upTo = (plan: ReturnType<typeof planSplit>, last: string) =>
    plan.series.filter(d => d.date <= last);

  it('sizes the legs off the ramp, not an average', () => {
    const plan = planSplit(ramp);
    // Slow Sea lands in time (FBA runs to 2026-11-01), so sellable is 09-24.
    expect(plan.sellableDate).toBe('2026-09-24');
    // 60 days from 09-24 = 7x100 + 31x200 + 18x300 + 4x600 = 700 + 6,200 +
    // 5,400 + 2,400 = 14,700, less the 7,200 still on hand = 7,500 to FBA; the
    // other 4,500 of the 12,000-unit batch go to the reserve.
    expect(plan.onHandAtSellable).toBe(7_200);
    expect(plan.targetUnits).toBe(14_700);
    expect(plan.legs.find(l => l.destination === 'FBA')!.units).toBe(7_500);
    expect(plan.legs.find(l => l.destination === 'AWD')!.units).toBe(4_500);
    expect(plan.fbaDocAtArrival).toEqual({ days: 60, capped: false });
  });

  it('holds off until cover actually reaches the reorder point, then moves', () => {
    const plan = planSplit(ramp);
    // 14,700 units covers 09-24 through 11-22 exactly, so cover at a landing
    // date X is simply the days from X to 11-22 — it first reads 30 on 10-24,
    // which is 14 days after 10-10. Nothing is ordered before that.
    //
    // The move restores the 45-day TRANSFER target, not the 60-day delivery
    // fill: 45 days from 10-24 is 8x200 + 12,600 + 7x400 = 17,000 units against
    // 9,400 on hand, so 7,600 are needed and 633 whole cartons — 7,596 — move.
    // The 4-unit carton remainder is what leaves cover at 44 rather than 45.
    expect(plan.transfers[0]).toMatchObject({
      orderDate: '2026-10-10', arrivalDate: '2026-10-24', units: 7_596,
    });
    expect(plan.transfers[0].docBefore.days).toBe(30);
    expect(plan.transfers[0].docAfter.days).toBe(44);
  });

  it('never runs FBA dry through the ramp', () => {
    const plan = planSplit(ramp);
    const through = upTo(plan, '2027-01-31');
    expect(through.length).toBeGreaterThan(170);
    expect(Math.min(...through.map(d => d.fbaUnits))).toBeGreaterThan(0);
  });

  it('holds cover at or above the reorder point for the whole ramp', () => {
    // The reorder point is the level cover is allowed to fall to, and the
    // AWD_TRANSFER lead is the floor under THAT — the time a move needs to
    // land. Restoring to 45 days measured against FORWARD demand is what makes
    // this hold: the level self-scales as the ramp steepens.
    const plan = planSplit(ramp);
    const ramping = plan.series.filter(d => d.date >= '2026-10-01' && d.date <= '2026-12-31');
    expect(Math.min(...ramping.map(d => d.doc))).toBeGreaterThanOrEqual(base.fbaReorderDoc);
    expect(base.fbaReorderDoc).toBeGreaterThan(base.transitDays.AWD_TRANSFER);
  });
});

describe('planSplit — a cold start, now that the cadence is gone', () => {
  // A finding, and a changed one. When AWD is EMPTY at plan time the reserve is
  // 63d at sea before it can feed anything, while the FBA leg only holds 45 —
  // so the handover is tight either way. What used to turn tight into a
  // stockout was the schedule, not the arithmetic: the batch reached AWD on
  // 10-14, the walk could not order until Monday the 19th, and a lead that
  // wrongly added the FBA inbound buffer put it on the shelf 11-12 — ten days
  // after FBA had emptied. Ordering the day the stock lands and paying only the
  // AWD_TRANSFER lead closes that window completely.
  it('no longer strands FBA at zero while the reserve waits for a Monday', () => {
    const plan = planSplit(realBatch);
    const on = (date: string) => plan.series.find(d => d.date === date)!;

    expect(plan.legs.find(l => l.destination === 'AWD')!.arrivalDate).toBe('2026-10-14');
    // The 60-day fill puts 7,200 units at FBA on 09-18, which at 120/day lasts
    // to 11-16 — so the handover is no longer tight at all. The first move is
    // still ordered the very day the reserve lands, because by its 10-28
    // landing FBA is down to 2,400 units (20 DOC), under the 30-day reorder
    // point. It is sized to the 45-day transfer target: 5,400 − 2,400 = 3,000.
    expect(plan.transfers[0]).toMatchObject({
      orderDate: '2026-10-14', arrivalDate: '2026-10-28', units: 3_000,
    });
    expect(on('2026-10-28').fbaUnits).toBe(5_400);  // restored to the 45-day level
    expect(on('2026-11-02').fbaUnits).toBe(4_800);  // where the old plan read zero

    const dark = plan.series.filter(d => d.fbaUnits === 0 && d.date >= '2026-09-18' && d.date <= '2026-11-30');
    expect(dark).toEqual([]);
  });

  it('still runs dry when the position itself is too small, and says exactly when', () => {
    // 5,280 at FBA plus a 12,000-unit batch is 17,280 units, which at 120/day
    // is 144 days from 2026-08-07. No schedule can conjure more: FBA empties on
    // 2026-12-29 because the whole position is spent, not because a move was
    // late, and nothing is left at AWD to send.
    const plan = planSplit(realBatch);
    const dark = plan.series.filter(d => d.fbaUnits === 0 && d.date <= '2026-12-31');
    expect(dark.map(d => d.date)).toEqual(['2026-12-29', '2026-12-30', '2026-12-31']);
    expect(plan.leftoverAwdUnits).toBe(0);
  });

  it('does not arise once AWD already holds stock, which is the steady state', () => {
    // Same batch, but 3,000 units already at AWD: a transfer can be ordered
    // from day one, so the 45-day level is restored before it runs out.
    const plan = planSplit({ ...realBatch, awdOnHand: 3_000 });
    const dark = plan.series.filter(d => d.fbaUnits === 0 && d.date <= '2026-12-31');
    expect(dark).toEqual([]);
  });
});
