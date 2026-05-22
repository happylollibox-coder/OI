import { describe, it, expect } from 'vitest';
import { allocateOrder, unitsAtSpend, profitMaxSpend } from './planTypes';

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
