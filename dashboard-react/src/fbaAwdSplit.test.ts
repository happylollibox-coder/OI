import { describe, it, expect } from 'vitest';
import type { MonthSeasonInfo } from './planTypes';
import type { DemandCurve, ProjectionShipment } from './stockProjection';
import {
  planSplit, nextWednesday, selectFbaMethod, destinationOf, confirmedFbaInbound,
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

const base: SplitInput = {
  product: 'Bottle',
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
    expect(fba.units + awd.units).toBe(5000);
    expect(fba.units).toBeGreaterThan(0);
    expect(awd.units).toBeGreaterThan(0);
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
  });

  it('reports the FBA OOS date it computed', () => {
    const plan = planSplit({ ...base, fbaOnHand: 100 });
    expect(plan.fbaOosDate).toMatch(/^\d{4}-\d{2}-\d{2}$/);
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

  it('never transfers more than the pool holds', () => {
    const plan = planSplit({ ...base, cartons: 200, awdOnHand: 500 });
    const moved = plan.transfers.reduce((s, t) => s + t.units, 0);
    const awdLeg = plan.legs.find(l => l.destination === 'AWD');
    expect(moved).toBeLessThanOrEqual(500 + (awdLeg?.units ?? 0));
  });

  it('schedules nothing when there is no AWD pool at all', () => {
    const plan = planSplit({ ...base, cartons: 30, awdOnHand: 0 });
    expect(plan.transfers).toEqual([]);
  });

  it('keeps transfer arrivals at least 14 days apart after merging', () => {
    const plan = planSplit({ ...base, cartons: 2000, awdOnHand: 20_000 });
    for (let i = 1; i < plan.transfers.length; i++) {
      const gap = (new Date(plan.transfers[i].arrivalDate).getTime()
        - new Date(plan.transfers[i - 1].arrivalDate).getTime()) / 86400000;
      expect(gap).toBeGreaterThan(14);
    }
  });

  it('reports leftover pool units when the AWD stock outlasts the horizon', () => {
    const plan = planSplit({ ...base, cartons: 10, awdOnHand: 1_000_000 });
    expect(plan.leftoverAwdUnits).toBeGreaterThan(0);
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
    for (const t of plan.transfers) {
      expect(t.docBefore).toBeLessThan(base.targetDoc);
      expect(t.docAfter).toBeGreaterThan(t.docBefore);
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
    expect(fba.reason).not.toMatch(/chosen manually/i);
  });
});

describe('planSplit — growth guard', () => {
  it('refuses to compute when growth zeroes out the whole curve', () => {
    const plan = planSplit({ ...base, curve: { ...CURVE, growth: 0 } });
    expect(plan.ok).toBe(false);
    expect(plan.error).toMatch(/no demand forecast/i);
  });
});
