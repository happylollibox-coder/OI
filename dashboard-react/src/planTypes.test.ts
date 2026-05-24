import { describe, it, expect } from 'vitest';
import { allocateOrder, unitsAtSpend, profitMaxSpend, monthKey, composeMonthlyPlan, splitTrajectoryToProducts } from './planTypes';

describe('monthKey', () => {
  it('formats month + 2-digit year like the snapshot keys', () => {
    expect(monthKey(5, 2026)).toBe('may26');
    expect(monthKey(1, 2027)).toBe('jan27');
    expect(monthKey(12, 2026)).toBe('dec26');
  });
});

describe('composeMonthlyPlan', () => {
  const keys = ['jan26', 'may26', 'jun26', 'jan27'];

  it('sums actual + forecast per month and totals over ordered keys', () => {
    const actual = { jan26: 100, may26: 30 };   // elapsed + current-MTD
    const forecast = { may26: 20, jun26: 80, jan27: 50 }; // current-remainder + future
    const r = composeMonthlyPlan(keys, actual, forecast);
    expect(r.byMonth).toEqual({ jan26: 100, may26: 50, jun26: 80, jan27: 50 });
    expect(r.total).toBe(280);
  });

  it('treats missing months as zero', () => {
    const r = composeMonthlyPlan(['jan26', 'feb26'], {}, { jan26: 10 });
    expect(r.byMonth).toEqual({ jan26: 10, feb26: 0 });
    expect(r.total).toBe(10);
  });
});

describe('splitTrajectoryToProducts', () => {
  const splitVars = [
    { name: 'White', splitPct: 0.75 },
    { name: 'Purple', splitPct: 0.25 },
  ];
  const inHorizon = () => true;

  it('distributes each family month total by per-month runSim share (no seasonality double-count)', () => {
    const traj = [
      { mo: 5, yr: 2026, totalUnits: 40, isActual: true },   // current MTD — excluded
      { mo: 5, yr: 2026, totalUnits: 100, isActual: false },  // May family total
      { mo: 12, yr: 2026, totalUnits: 200 },                  // Dec family total
    ];
    // runSim share shifts by month: May White-heavy (80/20), Dec Purple-heavy (25/75)
    const runSim = (name: string, mo: number) =>
      mo === 5 ? (name === 'White' ? 80 : 20) : mo === 12 ? (name === 'White' ? 50 : 150) : 0;
    const out = splitTrajectoryToProducts(traj, splitVars, inHorizon, runSim);
    expect(out.White).toEqual({ may26: 80, dec26: 50 });    // 100×0.8, 200×0.25
    expect(out.Purple).toEqual({ may26: 20, dec26: 150 });  // 100×0.2, 200×0.75
  });

  it('falls back to static splitPct when a month has no runSim demand', () => {
    const traj = [{ mo: 6, yr: 2026, totalUnits: 100 }];
    const out = splitTrajectoryToProducts(traj, splitVars, inHorizon, () => 0);
    expect(out.White).toEqual({ jun26: 75 });
    expect(out.Purple).toEqual({ jun26: 25 });
  });

  it('drops months outside the horizon', () => {
    const traj = [{ mo: 3, yr: 2027, totalUnits: 100 }];
    const out = splitTrajectoryToProducts(traj, splitVars, (mo, yr) => !(mo === 3 && yr === 2027), () => 50);
    expect(out.White).toEqual({});
    expect(out.Purple).toEqual({});
  });

  it('equal-splits when neither runSim nor splitPct have data', () => {
    const traj = [{ mo: 6, yr: 2026, totalUnits: 100 }];
    const out = splitTrajectoryToProducts(traj, [{ name: 'A', splitPct: 0 }, { name: 'B', splitPct: 0 }], inHorizon, () => 0);
    expect(out.A).toEqual({ jun26: 50 });
    expect(out.B).toEqual({ jun26: 50 });
  });
});

type Row = Pick<import('./planTypes').VarBaseline, 'name' | 'splitPct' | 'cartonQty' | 'inventory'>;
const vars = (...rows: [string, number, number, number?][]): Row[] =>
  rows.map(([name, splitPct, cartonQty, inventory = 0]) => ({ name, splitPct, cartonQty, inventory }));

describe('allocateOrder', () => {
  it('rounds each product up to its carton multiple (no stock, target = total gap)', () => {
    // gaps = forecast×share − 0: A 2366, B 1419.6, C 946.4 ; target = totalGap (4732)
    const { byProduct, total, totalGap } = allocateOrder(
      vars(['A', 0.5, 144], ['B', 0.3, 240], ['C', 0.2, 96]), 4732, 4732, false);
    expect(byProduct).toEqual({ A: 2448, B: 1440, C: 960 });
    expect(total).toBe(4848);
    expect(totalGap).toBeCloseTo(4732, 6);
  });

  it('rounds up to the next 100 in friendly mode', () => {
    const { byProduct } = allocateOrder(
      vars(['A', 0.5, 144], ['B', 0.3, 240], ['C', 0.2, 96]), 4732, 4732, true);
    expect(byProduct).toEqual({ A: 2400, B: 1500, C: 1000 });
  });

  it('orders ~0 for a product already overstocked vs its own forecast share', () => {
    // B's share of forecast = 0.3×4732 = 1419.6, but it holds 5000 → gap 0
    const { byProduct, totalGap } = allocateOrder(
      vars(['A', 0.5, 144, 0], ['B', 0.3, 240, 5000]), 2366, 4732, false);
    expect(byProduct.B).toBe(0);
    expect(byProduct.A).toBe(2448);
    expect(totalGap).toBeCloseTo(2366, 6); // only A contributes
  });

  it('subtracts a product\'s own stock from its gap', () => {
    // A share 1.0 of 1000, holds 500 → gap 500 → ceil(500/144)=4 cartons → 576
    const { byProduct } = allocateOrder(vars(['A', 1, 144, 500]), 500, 1000, false);
    expect(byProduct.A).toBe(576);
  });

  it('target scales the gaps (manual override below total gap)', () => {
    const { byProduct } = allocateOrder(vars(['A', 1, 1, 0]), 500, 1000, false);
    expect(byProduct.A).toBe(500); // half of the 1000 gap
  });

  it('falls back to unit granularity when cartonQty is missing/zero', () => {
    const { byProduct } = allocateOrder(vars(['A', 1, 0]), 37, 37, false);
    expect(byProduct.A).toBe(37);
  });

  it('splits gap evenly when splitPct is absent', () => {
    const { byProduct, total } = allocateOrder(vars(['A', 0, 1], ['B', 0, 1]), 10, 10, false);
    expect(byProduct).toEqual({ A: 5, B: 5 });
    expect(total).toBe(10);
  });
});

describe('unitsAtSpend', () => {
  it('reproduces the anchor exactly at S = spend0', () => {
    expect(unitsAtSpend(30236, 2040, 30236, 0.65)).toBeCloseTo(2040, 6);
  });
  it('scales sub-linearly with spend (diminishing returns)', () => {
    // doubling spend at e=0.65 → 2^0.65 ≈ 1.57×, not 2×
    expect(unitsAtSpend(60472, 2040, 30236, 0.65) / 2040).toBeCloseTo(Math.pow(2, 0.65), 4);
  });
  it('returns 0 when there is no anchor', () => {
    expect(unitsAtSpend(5000, 0, 0, 0.6)).toBe(0);
  });
});

describe('profitMaxSpend', () => {
  it('Easter (profitable peak): nudges spend slightly above 2025', () => {
    // Apr 2025 Lollibox: units 2040, spend $30,236, margin $23.81, PEAK e=0.65
    const s = profitMaxSpend(2040, 30236, 23.81, 0.65)!;
    expect(s).toBeGreaterThan(33000);
    expect(s).toBeLessThan(35000); // ≈ $34.2K
  });
  it('off-season (over-spent): cuts spend hard', () => {
    // Jul 2025 Lollibox: units 481, spend $10,424, OFF e=0.58
    const s = profitMaxSpend(481, 10424, 23.81, 0.58)!;
    expect(s).toBeGreaterThan(3000);
    expect(s).toBeLessThan(4000); // ≈ $3.6K (down from $10.4K)
  });
  it('clamps to the extrapolation cap (3× by default)', () => {
    // a wildly profitable month would otherwise blow past 3×
    const s = profitMaxSpend(50000, 10000, 23.81, 0.65)!;
    expect(s).toBe(30000); // capped at 3 × spend0
  });
  it('returns null with no usable anchor (caller falls back)', () => {
    expect(profitMaxSpend(0, 0, 23.81, 0.65)).toBeNull();
    expect(profitMaxSpend(100, 5000, 23.81, 1)).toBeNull(); // e must be < 1
  });
});
