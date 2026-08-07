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
  targetDoc: 100,
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
  it('sends everything to FBA when the batch cannot reach the DOC target', () => {
    // ~10 units/day => 100 DOC needs ~1000 units. Batch is 300.
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

  it('splits a large batch between both destinations', () => {
    const plan = planSplit({ ...base, cartons: 500, fbaOnHand: 0 });
    const fba = plan.legs.find(l => l.destination === 'FBA')!;
    const awd = plan.legs.find(l => l.destination === 'AWD')!;
    // 100 DOC from 2026-09-18 is exactly 1000 units on the flat curve.
    expect(fba.units).toBe(1000);
    expect(awd.units).toBe(4000);
    expect(plan.targetUnits).toBe(1000);
    expect(plan.onHandAtSellable).toBe(0);
    expect(plan.shortfallUnits).toBe(0);
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

  it('keeps transfer arrivals at least 14 days apart when the pool allows merging', () => {
    const plan = planSplit({ ...base, cartons: 2000, awdOnHand: 20_000 });
    expect(plan.transfers.length).toBeGreaterThan(1);
    for (const t of plan.transfers) expect(parseKey(t.orderDate).getDay()).toBe(1); // Monday
    for (let i = 1; i < plan.transfers.length; i++) {
      const gap = (new Date(plan.transfers[i].arrivalDate).getTime()
        - new Date(plan.transfers[i - 1].arrivalDate).getTime()) / 86400000;
      expect(gap).toBeGreaterThan(14);
    }
  });

  it('reports leftover pool units when the AWD stock outlasts the horizon', () => {
    const plan = planSplit({ ...base, cartons: 10, awdOnHand: 1_000_000 });
    const moved = plan.transfers.reduce((s, t) => s + t.units, 0);
    expect(moved).toBe(2_910);              // all the curve's demand ever asks for
    expect(plan.leftoverAwdUnits).toBe(997_090);
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
      expect(t.docBefore.days).toBeLessThan(base.targetDoc);
      expect(t.docAfter.days).toBeGreaterThan(t.docBefore.days);
    }
  });
});

describe('planSplit — seasonality', () => {
  // Same batch and same 100-day window (2026-09-18 → 2026-12-26), but December's
  // demand is concentrated into its last 15 days. The window catches only 10 of
  // them and pays below-average rates for Dec 1–16, so the requirement lands
  // just under the flat-curve 1000. Monthly totals are identical either way.
  const seasonal: DemandCurve = { productDemand: FLAT, familySeason: SEASON, growth: 1.0 };

  it('sizes the FBA leg off the daily curve, not the monthly average', () => {
    const flat = planSplit({ ...base, cartons: 500 });
    const peaky = planSplit({ ...base, cartons: 500, curve: seasonal });
    expect(flat.legs.find(l => l.destination === 'FBA')!.units).toBe(1000);
    expect(peaky.legs.find(l => l.destination === 'FBA')!.units).toBe(980);
  });

  it('does not cry "too small" over a sub-carton rounding remainder', () => {
    // target 982.6 floors to 980, leaving a 2.6-unit remnant — not a shortfall.
    const exact = planSplit({ ...base, cartons: 98, curve: seasonal });
    expect(exact.legs.find(l => l.destination === 'AWD')).toBeUndefined();
    expect(exact.warnings.join(' ')).not.toMatch(/too small/i);
    // A genuine two-carton gap still warns.
    const short = planSplit({ ...base, cartons: 98 });
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

  it('counts confirmed FBA-bound stock against the DOC target', () => {
    // 900 land 2026-09-01; 170 units of demand burn before the batch is
    // sellable on 09-18, leaving 730 on hand against a 1000 target.
    const plan = planSplit({ ...base, shipments: inbound(900, 'transit', 'PO→MFR→FBA') });
    expect(plan.onHandAtSellable).toBe(730);
    expect(plan.legs.find(l => l.destination === 'FBA')!.units).toBe(270);
    expect(plan.legs.find(l => l.destination === 'AWD')!.units).toBe(730);
  });

  it('does not count AWD-bound stock as FBA cover', () => {
    const plan = planSplit({ ...base, shipments: inbound(900, 'transit', 'MFR→AWD') });
    expect(plan.onHandAtSellable).toBe(0);
    expect(plan.legs.find(l => l.destination === 'FBA')!.units).toBe(1000);
  });

  it('ignores unconfirmed shipments', () => {
    const plan = planSplit({ ...base, shipments: inbound(900, 'suggested', 'PO→MFR→FBA') });
    expect(plan.onHandAtSellable).toBe(0);
    expect(plan.legs.find(l => l.destination === 'FBA')!.units).toBe(1000);
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

  it('refuses a non-positive target DOC', () => {
    expect(planSplit({ ...base, targetDoc: 0 }).error).toMatch(/target days of cover/i);
  });

  it('refuses negative on-hand figures', () => {
    expect(planSplit({ ...base, fbaOnHand: -1 }).error).toMatch(/FBA on-hand/i);
    expect(planSplit({ ...base, awdOnHand: -1 }).error).toMatch(/AWD on-hand/i);
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
    expect(reason).toMatch(/1000 units of demand/);
    expect(reason).toMatch(/batch only holds 300 units/i);
    expect(reason).toMatch(/700 units short of target/i);
    expect(plan.shortfallUnits).toBe(700);
  });

  it('names the carton rounding when that is what bit', () => {
    const seasonal = { productDemand: FLAT, familySeason: SEASON, growth: 1.0 };
    const plan = planSplit({ ...base, cartons: 500, curve: seasonal });
    const reason = plan.legs.find(l => l.destination === 'FBA')!.reason;
    // 983 needed -> 98 cartons -> 980 units.
    expect(reason).toMatch(/983 needed/);
    expect(reason).toMatch(/98 × 10 = 980 units/);
  });

  it('explains the AWD leg on its own terms when nothing goes to FBA', () => {
    const plan = planSplit({ ...base, fbaOnHand: 50_000 });
    const reason = plan.legs.find(l => l.destination === 'AWD')!.reason;
    expect(reason).not.toMatch(/remainder/i);
    expect(reason).toMatch(/already at or above 100 DOC/i);
    expect(reason).toMatch(/only AWD route \(63d\)/);
    expect(reason).toMatch(/14d transit plus 10d inbound/);
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
    expect(plan.series.length).toBe(466); // 365 + targetDoc, inclusive of today
    expect(plan.series[0].date).toBe('2026-08-07');
    expect(plan.series[465].date).toBe('2027-11-15');
  });

  it('names what landed and reports the DOC the engine decided from', () => {
    const plan = planSplit({ ...base, cartons: 800 });
    const batchDay = plan.series.find(d => d.arrivalNote === 'FBA batch')!;
    expect(batchDay.date).toBe('2026-09-18');
    expect(batchDay.arrivals).toBe(1000);
    expect(batchDay.fbaUnits).toBe(1000);
    expect(batchDay.doc).toBe(100); // exactly the target, by construction
    expect(batchDay.docCapped).toBe(false);

    const awdDay = plan.series.find(d => d.arrivalNote === 'AWD batch')!;
    expect(awdDay.date).toBe('2026-10-14');
    expect(awdDay.awdUnits).toBe(7000);
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
  it('says nothing when the batch lands in time and fits the target', () => {
    // 600 on hand runs to 2026-10-06, so the cheapest route lands in time;
    // 870 units is the whole batch and the whole remaining need.
    const plan = planSplit({ ...base, cartons: 87, fbaOnHand: 600 });
    expect(plan.warnings).toEqual([]);
    expect(plan.legs.find(l => l.destination === 'FBA')!.method).toBe('SLOW_SEA');
    expect(plan.legs.find(l => l.destination === 'AWD')).toBeUndefined();
    expect(plan.transfers).toEqual([]);
    expect(plan.fbaDocAtArrival).toEqual({ days: 99, capped: false });
  });

  it('reports days of cover at arrival, flagging a saturated reading', () => {
    expect(planSplit(base).fbaDocAtArrival).toEqual({ days: 100, capped: false });
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
  // Regression: merging used to fold a later week's draw into an earlier row,
  // dating the move before the goods had landed at AWD. The row read
  // "2026-10-12: 160u" while AWD held 100, and the series went to -60.
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

  it('splits rather than merges when the draws straddle a pool arrival', () => {
    const plan = planSplit(straddle);
    const awdLanding = plan.legs.find(l => l.destination === 'AWD')!.arrivalDate;
    // The row that could not absorb the later draw stays at its own size, and
    // the remainder becomes its own executable row after the batch lands.
    const after = plan.transfers.filter(t => t.orderDate > awdLanding);
    expect(after.length).toBeGreaterThan(0);
    for (const t of plan.transfers) {
      expect(t.arrivalDate > t.orderDate).toBe(true);
    }
  });

  it('still conserves the pool through a split', () => {
    const plan = planSplit(straddle);
    const pool = 500 + (plan.legs.find(l => l.destination === 'AWD')?.units ?? 0);
    const moved = plan.transfers.reduce((s, t) => s + t.units, 0);
    expect(moved + plan.leftoverAwdUnits).toBe(pool);
  });
});

describe('planSplit — transfers respect the carton multiple against a ragged pool', () => {
  it('rounds every transfer to whole cartons even when the pool is not a multiple', () => {
    // 353 units at pkg 7 leaves a 3-unit remainder that can never move.
    const plan = planSplit({ ...base, packageQuantity: 7, awdOnHand: 353, cartons: 100 });
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
    qty: 900, arrival_date: date, status: 'transit' as const, route: 'PO→MFR→FBA',
  }];

  it('reads a bare YYYY-MM-DD as a local date, not UTC midnight', () => {
    // Sellable is 2026-09-18. A shipment dated the 19th lands AFTER it and must
    // not count; parsed as UTC it would read as the 18th west of Greenwich and
    // divert 900 units to AWD purely because of the viewer's clock.
    const plan = planSplit({ ...base, cartons: 500, shipments: ship('2026-09-19') });
    expect(plan.onHandAtSellable).toBe(0);
    expect(plan.legs.find(l => l.destination === 'FBA')!.units).toBe(1000);
  });

  it('counts a shipment landing exactly on the sellable date', () => {
    const plan = planSplit({ ...base, cartons: 500, shipments: ship('2026-09-18') });
    expect(plan.onHandAtSellable).toBe(900);
    expect(plan.legs.find(l => l.destination === 'FBA')!.units).toBe(100);
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

  it('measures cover at arrival from the sellable date, not the dock date', () => {
    // Non-flat curve so the 10-day inbound buffer visibly changes the reading:
    // measuring from the 09-08 dock date instead of 09-18 gives a different DOC.
    const seasonal = { productDemand: FLAT, familySeason: SEASON, growth: 1.0 };
    const plan = planSplit({ ...base, cartons: 500, curve: seasonal, fbaOnHand: 300 });
    const fba = plan.legs.find(l => l.destination === 'FBA')!;
    const stock = plan.onHandAtSellable + fba.units;
    expect(docFromStock(stock, parseKey(fba.sellableDate), seasonal, 400))
      .toEqual(plan.fbaDocAtArrival);
    expect(docFromStock(stock, parseKey(fba.arrivalDate), seasonal, 400))
      .not.toEqual(plan.fbaDocAtArrival);
  });
});
