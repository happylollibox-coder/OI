import { describe, it, expect } from 'vitest';
import type { MonthSeasonInfo } from './planTypes';
import type { DemandCurve } from './stockProjection';
import { planSplit, nextWednesday, type SplitInput } from './fbaAwdSplit';

const SEASON: Record<number, MonthSeasonInfo> = {
  202611: { peakDays: 12, offseasonDays: 18, holidays: 'BFCM' },
  202612: { peakDays: 15, offseasonDays: 16, holidays: 'Christmas' },
};

// Flat 300/month everywhere = ~10/day, so DOC arithmetic is easy to reason about.
const FLAT: Record<number, number> = {
  202608: 300, 202609: 300, 202610: 310, 202611: 300, 202612: 310,
  202701: 310, 202702: 280, 202703: 310, 202704: 300, 202705: 310, 202706: 300,
};

const CURVE: DemandCurve = { productDemand: FLAT, familySeason: SEASON, growth: 1.0 };
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
