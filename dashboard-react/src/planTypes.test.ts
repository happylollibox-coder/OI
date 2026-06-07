import { describe, it, expect } from 'vitest';
import { allocateOrder, unitsAtSpend, profitMaxSpend, monthKey, composeMonthlyPlan, splitTrajectoryToProducts, buildEffectiveProjs, monthFractions, latestCompleteWeekRange, blendedNetRoas, aggregateAdsTargetSpend, offSeasonTrend, scaleHorizonPlan, dataCutoffDay, weightedRunRate, detectLaunchMonth, seasonalShape, launchOrderPhases } from './planTypes';

describe('blendedNetRoas', () => {
  it('returns (sales − cogs) / adCost summed over rows', () => {
    const rows = [{ sales: 100, cogs: 40, adCost: 20 }, { sales: 200, cogs: 80, adCost: 30 }];
    expect(blendedNetRoas(rows)).toBeCloseTo(3.6, 6); // (300−120)/50
  });
  it('returns null when there is no ad spend', () => {
    expect(blendedNetRoas([{ sales: 100, cogs: 40, adCost: 0 }])).toBeNull();
    expect(blendedNetRoas([])).toBeNull();
  });
});

describe('latestCompleteWeekRange', () => {
  it('returns Mon..Sun of the most recent complete week before today', () => {
    const r = latestCompleteWeekRange(new Date('2026-05-21T12:00:00'), 0); // Thu
    expect(r).toEqual(['2026-05-11', '2026-05-17']);
  });
  it('stepsBack shifts to earlier weeks', () => {
    const r = latestCompleteWeekRange(new Date('2026-05-21T12:00:00'), 1);
    expect(r).toEqual(['2026-05-04', '2026-05-10']);
  });
});

describe('buildEffectiveProjs', () => {
  const effFams = [{
    family: 'F', asp: 10, costPerUnit: 4,
    variations: [
      { name: 'A', asp: 10, costPerUnit: 4, inventory: 100 },
      { name: 'B', asp: 10, costPerUnit: 4, inventory: 50 },
    ],
  }];
  const mkVar = (demand: number) => ({ demand, revenue: demand * 10, cogs: demand * 4, adSpend: 5, netProfit: 1, invEnd: 0, isOos: false });
  const mkProj = (key: string, a: number, b: number) => ({
    month: key, key, days: 30,
    families: { F: { demand: a + b, revenue: 0, cogs: 0, adSpend: 0, netProfit: 0, invEnd: 0, isOos: false, vars: { A: mkVar(a), B: mkVar(b) } } },
    totalDemand: a + b, totalRevenue: 0, totalCogs: 0, totalAdSpend: 0, totalNetProfit: 0,
  });
  const projs = [mkProj('may26', 999, 999), mkProj('jun26', 999, 999)]; // runSim values (should be overridden)
  const plannedUnits = { A: { may26: 30, jun26: 40 }, B: { may26: 10, jun26: 20 } };
  const plannedSpend = { F: { may26: 100, jun26: 200 } };

  it('rebuilds planned-family P&L from snapshot units + target spend, carrying inventory', () => {
    const out = buildEffectiveProjs(projs, plannedUnits, plannedSpend, effFams, () => true);
    const may = out[0].families.F;
    expect(may.demand).toBe(40);
    expect(may.revenue).toBe(400);   // 40 × 10
    expect(may.cogs).toBe(160);      // 40 × 4
    expect(may.adSpend).toBe(100);   // from target
    expect(may.netProfit).toBe(140); // 400 − 160 − 100
    expect(may.vars.A.adSpend).toBe(75);  // 100 × 30/40
    expect(may.vars.A.invEnd).toBe(70);   // 100 − 30
    expect(may.vars.B.invEnd).toBe(40);   // 50 − 10
    // inventory carries into June: A 70 − 40 = 30
    expect(out[1].families.F.vars.A.invEnd).toBe(30);
    // per-product ad spend sums to the family spend
    expect(out[0].families.F.vars.A.adSpend + out[0].families.F.vars.B.adSpend).toBeCloseTo(100, 6);
    // month totals reflect the rebuilt family
    expect(out[0].totalRevenue).toBe(400);
    expect(out[0].totalNetProfit).toBe(140);
  });

  it('passes unplanned families through runSim unchanged', () => {
    const out = buildEffectiveProjs(projs, plannedUnits, plannedSpend, effFams, () => false);
    expect(out[0].families.F).toEqual(projs[0].families.F); // byte-for-byte
    expect(out[0].families.F.vars.A.demand).toBe(999);
  });

  it('falls back to runSim demand for a planned product missing that month', () => {
    const partial = { A: { may26: 30 } }; // A has no jun26, B absent entirely
    const out = buildEffectiveProjs(projs, partial, plannedSpend, effFams, () => true);
    expect(out[1].families.F.vars.A.demand).toBe(999); // jun26 → runSim fallback
    expect(out[0].families.F.vars.B.demand).toBe(999); // B → runSim fallback
    expect(out[0].families.F.vars.A.demand).toBe(30);  // A may26 → planned
  });
});

describe('monthFractions', () => {
  it('returns 1.0 for a full single month', () => {
    expect(monthFractions('2026-05-01', '2026-05-31')).toEqual({ may26: 1 });
  });
  it('returns a partial fraction within one month', () => {
    const f = monthFractions('2026-05-01', '2026-05-07');
    expect(f.may26).toBeCloseTo(7 / 31, 6);
    expect(Object.keys(f)).toEqual(['may26']);
  });
  it('splits a week spanning two months', () => {
    const f = monthFractions('2026-04-29', '2026-05-05');
    expect(f.apr26).toBeCloseTo(2 / 30, 6);
    expect(f.may26).toBeCloseTo(5 / 31, 6);
  });
  it('spans multiple whole + partial months (since-approval style)', () => {
    const f = monthFractions('2026-05-10', '2026-07-15');
    expect(f.may26).toBeCloseTo(22 / 31, 6);
    expect(f.jun26).toBeCloseTo(1, 6);
    expect(f.jul26).toBeCloseTo(15 / 31, 6);
  });
  it('crosses the year boundary', () => {
    const f = monthFractions('2026-12-28', '2027-01-03');
    expect(f.dec26).toBeCloseTo(4 / 31, 6);
    expect(f.jan27).toBeCloseTo(3 / 31, 6);
  });
});

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

  it('uses per-product forecast (forecastByProduct) instead of splitPct when provided', () => {
    // splitPct would over-allocate White (54.4% of 14549 = 7914 > stock 6913 → looks short)
    // and under-allocate Pink. The velocity forecast is the truth: White is overstocked → 0,
    // Pink's demand (3302) exceeds its stock (2923) → orders the 379 gap.
    const v = vars(['White', 0.544, 1, 6913], ['Pink', 0.151, 1, 2923]);
    const fcst = { White: 5996, Pink: 3302 };
    const { byProduct, totalGap } = allocateOrder(v, 379, 14549, false, fcst);
    expect(byProduct.White).toBe(0);
    expect(byProduct.Pink).toBe(379);
    expect(totalGap).toBeCloseTo(379, 6);
  });
});

describe('aggregateAdsTargetSpend', () => {
  it('sums daily spend × days-in-month per month, across channel rows', () => {
    const { spendByMonth } = aggregateAdsTargetSpend([
      { yr: 2026, mo: 6, daily_spend_target: 100 }, // June (30d) → 3000
      { yr: 2026, mo: 6, daily_spend_target: 50 },  // June (30d) → 1500
      { yr: 2026, mo: 7, daily_spend_target: 10 },  // July (31d) → 310
    ]);
    expect(spendByMonth[monthKey(6, 2026)]).toBe(4500);
    expect(spendByMonth[monthKey(7, 2026)]).toBe(310);
  });

  it('computes spend-weighted CPC per month and ignores zero/absent cpc', () => {
    const { cpcByMonth } = aggregateAdsTargetSpend([
      { yr: 2026, mo: 6, daily_spend_target: 100, cpc_target: 0.40 }, // spend 3000
      { yr: 2026, mo: 6, daily_spend_target: 100, cpc_target: 0.60 }, // spend 3000
      { yr: 2026, mo: 6, daily_spend_target: 100, cpc_target: 0 },    // ignored for cpc
    ]);
    // (0.40×3000 + 0.60×3000) / 6000 = 0.50
    expect(cpcByMonth[monthKey(6, 2026)]).toBeCloseTo(0.50, 6);
  });

  it('returns empty maps for no targets', () => {
    expect(aggregateAdsTargetSpend([])).toEqual({ spendByMonth: {}, cpcByMonth: {} });
  });
});

describe('offSeasonTrend', () => {
  const allOff = () => true;
  // history: months of units for ONE channel (both years)
  const h = (rows: [number, number, number][]) => rows.map(([year, month, units]) => ({ year, month, units }));

  it('splits post-warmup off-season months into two periods; momentum = 2nd-period rate / 1st-period rate', () => {
    // launch Jun 2025 → warmup Jun/Jul/Aug 2025 excluded.
    // usable off-season (ascending): Feb26(28d,280→10/d) Mar26(31d,310→10/d) | Apr26(30d,360→12/d) May26(31d,372→12/d)
    // first half = [Feb,Mar] → 590/59 = 10/d ; second half = [Apr,May] → 732/61 = 12/d ; momentum = 1.2
    const res = offSeasonTrend(
      h([[2025,6,50],[2025,7,60],[2025,8,70],[2026,2,280],[2026,3,310],[2026,4,360],[2026,5,372]]),
      allOff,
      { year: 2025, month: 6 },
      { year: 2026, month: 5, prorate: 1 },
    );
    expect(res.usable).toBe(true);
    expect(res.priorRate).toBeCloseTo(10, 6);  // 1st-period rate
    expect(res.recentRate).toBeCloseTo(12, 6); // 2nd-period rate (the projection base)
    expect(res.momentum).toBeCloseTo(1.2, 6);
    expect(res.launch).toEqual({ year: 2025, month: 6 });
    // gap between period midpoints = 2 months → per-month growth g = 1.2^(1/2) ≈ 1.09545
    // anchored at the last usable month (May): Jun is k=1 → 12 × 30 × 1.09545 ≈ 394
    expect(res.forecastUnits(2026, 6)).toBe(394);
    // Jul is k=2 → g^2 = 1.2 → 12 × 31 × 1.2 = 446.4
    expect(res.forecastUnits(2026, 7)).toBe(446);
  });

  it('excludes the first 3 post-launch months; a single usable period yields flat momentum=1', () => {
    // launch auto-detected = Jan26; warmup Jan/Feb/Mar26 excluded; only Apr26 usable → one period
    const res = offSeasonTrend(
      h([[2026,1,100],[2026,2,100],[2026,3,100],[2026,4,360]]),
      allOff,
      null,
      { year: 2026, month: 4, prorate: 1 },
    );
    expect(res.usable).toBe(true);
    expect(res.launch).toEqual({ year: 2026, month: 1 });
    expect(res.momentum).toBe(1);                 // single period → no trend
    expect(res.recentRate).toBeCloseTo(12, 6);
    expect(res.forecastUnits(2026, 5)).toBe(372); // 12 × 31 × 1
  });

  it('is not usable when there is no post-warmup off-season data', () => {
    const res = offSeasonTrend(h([[2026,1,100],[2026,2,100],[2026,3,100]]), allOff, null, { year: 2026, month: 3, prorate: 1 });
    expect(res.usable).toBe(false);
    expect(res.forecastUnits(2026, 6)).toBe(0);
  });

  it('clamps momentum to [0.5, 1.8]', () => {
    // 1st period 10/d, 2nd period 30/d → raw 3.0 → clamp 1.8
    const res = offSeasonTrend(
      h([[2025,6,1],[2025,7,1],[2025,8,1],[2026,2,280],[2026,3,310],[2026,4,900],[2026,5,930]]),
      allOff, { year: 2025, month: 6 }, { year: 2026, month: 5, prorate: 1 },
    );
    expect(res.momentum).toBeCloseTo(1.8, 6);
  });

  it('prorates the current (cutoff) month when computing its run-rate', () => {
    // May26 is the cutoff, half elapsed: 186 units over 15.5 effective days → 12/d (2nd-period rate)
    const res = offSeasonTrend(
      h([[2025,6,1],[2025,7,1],[2025,8,1],[2026,4,360],[2026,5,186]]),
      allOff, { year: 2025, month: 6 }, { year: 2026, month: 5, prorate: 0.5 },
    );
    expect(res.recentRate).toBeCloseTo(12, 6); // 186 / (31×0.5)
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

describe('scaleHorizonPlan', () => {
  const plan = [
    { mo: 5, spend: 1000, units: 100, units0: 100, spend0: 1000, anchored: true, e: 0.5 },
    { mo: 6, spend: 2000, units: 200, units0: 200, spend0: 2000, anchored: true, e: 0.5 },
  ];
  const months = [{ month: 5 }, { month: 6 }] as { month: number }[];

  it('sums spend & units over the horizon at k=1 with no current-month proration', () => {
    const r = scaleHorizonPlan(plan, months, 1, -1, 1);
    expect(r.spend).toBe(3000);
    expect(r.units).toBeCloseTo(300, 6);
  });

  it('scales spend by k and re-derives units via the elasticity', () => {
    const r = scaleHorizonPlan(plan, months, 2, -1, 1);
    expect(r.spend).toBe(6000);
    expect(r.units).toBeCloseTo(141.421 + 282.842, 2);
  });

  it('prorates the current month to remFrac (spend AND units)', () => {
    const r = scaleHorizonPlan(plan, months, 1, 4, 0.25); // curMoIdx=4 (May, 0-based)
    expect(r.spend).toBe(1000 * 0.25 + 2000);
    expect(r.units).toBeCloseTo(100 * 0.25 + 200, 6);
  });

  it('falls back to units*k for unanchored months', () => {
    const p2 = [{ mo: 5, spend: 1000, units: 100, units0: 0, spend0: 0, anchored: false, e: 0.5 }];
    const r = scaleHorizonPlan(p2, [{ month: 5 }], 3, -1, 1);
    expect(r.spend).toBe(3000);
    expect(r.units).toBe(300);
  });
});

describe('dataCutoffDay', () => {
  it('uses the latest data date day-of-month when it is in the current month', () => {
    // Orders through Jun 4, today is Jun 6 — should be 4, not the wall-clock fallback.
    expect(dataCutoffDay(new Date(2026, 5, 4), 2026, 6, 2)).toBe(4);
  });

  it('clamps day to >= 1', () => {
    expect(dataCutoffDay(new Date(2026, 5, 1), 2026, 6, 5)).toBe(1);
  });

  it('returns 1 when the latest data is in an earlier month (no current-month data yet)', () => {
    expect(dataCutoffDay(new Date(2026, 4, 31), 2026, 6, 4)).toBe(1);
    expect(dataCutoffDay(new Date(2025, 11, 31), 2026, 6, 4)).toBe(1);
  });

  it('falls back to the wall-clock day when latestDataDate is missing or invalid', () => {
    expect(dataCutoffDay(null, 2026, 6, 4)).toBe(4);
    expect(dataCutoffDay(undefined, 2026, 6, 4)).toBe(4);
    expect(dataCutoffDay(new Date('nope'), 2026, 6, 4)).toBe(4);
  });

  it('clamps the fallback to >= 1', () => {
    expect(dataCutoffDay(null, 2026, 6, -3)).toBe(1);
  });
});

describe('launchOrderPhases', () => {
  const vars = [{ name: 'A', inventory: 0, cartonQty: 12 }];
  it('Phase 1 = ceilCarton(rate×90 − stock); Phase 2 = ceilCarton(forecast − stock − phase1)', () => {
    const r = launchOrderPhases(vars, { A: 1 }, { A: 300 }, false);
    expect(r.phase1.A).toBe(96);   // 90 → ceil(90/12)*12
    expect(r.phase2.A).toBe(204);  // 300 − 0 − 96 = 204 (÷12 exact)
    expect(r.phase1Total).toBe(96);
    expect(r.phase2Total).toBe(204);
  });
  it('subtracts existing stock from both phases', () => {
    const r = launchOrderPhases([{ name: 'B', inventory: 50, cartonQty: 10 }], { B: 2 }, { B: 400 }, false);
    expect(r.phase1.B).toBe(130);  // 180 − 50 = 130
    expect(r.phase2.B).toBe(220);  // 400 − 50 − 130
  });
  it('rate 0 → Phase 1 = 0 (seed-PO case); Phase 2 still sized', () => {
    const r = launchOrderPhases([{ name: 'C', inventory: 20, cartonQty: 5 }], { C: 0 }, { C: 100 }, false);
    expect(r.phase1.C).toBe(0);
    expect(r.phase2.C).toBe(80);   // 100 − 20 − 0
  });
  it('never negative when stock covers the need', () => {
    const r = launchOrderPhases([{ name: 'D', inventory: 500, cartonQty: 10 }], { D: 1 }, { D: 100 }, false);
    expect(r.phase1.D).toBe(0);
    expect(r.phase2.D).toBe(0);
  });
  it('friendly mode rounds to the next 100', () => {
    const r = launchOrderPhases(vars, { A: 1 }, { A: 300 }, true);
    expect(r.phase1.A).toBe(100);  // 90 → 100
    expect(r.phase2.A).toBe(200);  // 300 − 0 − 100 = 200
  });
});

describe('weightedRunRate', () => {
  it('returns a flat per-day rate for uniform weeks', () => {
    expect(weightedRunRate([70, 70, 70, 70])).toBeCloseTo(10, 6);
  });
  it('weights the most recent week most heavily', () => {
    expect(weightedRunRate([70, 0, 0, 0])).toBeCloseTo(4, 6);
    expect(weightedRunRate([0, 0, 0, 70])).toBeCloseTo(1, 6);
  });
  it('treats missing buckets as 0 (fewer than 4 weeks)', () => {
    expect(weightedRunRate([70])).toBeCloseTo(4, 6);
    expect(weightedRunRate([])).toBe(0);
  });
  it('accepts custom weights', () => {
    expect(weightedRunRate([7, 7], [0.5, 0.5])).toBeCloseTo(1, 6);
  });
});

describe('detectLaunchMonth', () => {
  const lollibox = [745, 891, 1058, 2040, 898, 666, 481, 692, 972, 944, 2066, 6225];
  const lollime  = [0, 0, 0, 0, 0, 0, 354, 520, 843, 983, 2929, 7620];
  it('returns null for a mature family with January sales', () => {
    expect(detectLaunchMonth(lollibox)).toBeNull();
  });
  it('returns the launch month when 2025 starts mid-year', () => {
    expect(detectLaunchMonth(lollime)).toBe(7);
  });
  it('returns null when there is no 2025 data at all', () => {
    expect(detectLaunchMonth(Array(12).fill(0))).toBeNull();
  });
});

describe('seasonalShape', () => {
  const lollibox = [745, 891, 1058, 2040, 898, 666, 481, 692, 972, 944, 2066, 6225];
  const lollime  = [0, 0, 0, 0, 0, 0, 354, 520, 843, 983, 2929, 7620];
  const empty    = Array(12).fill(0);

  it('current month is always 1', () => {
    expect(seasonalShape(lollibox, lollibox, 6, null)[5]).toBeCloseTo(1, 6);
    expect(seasonalShape(lollime, lollibox, 6, 7)[5]).toBeCloseTo(1, 6);
  });
  it('mature family uses its own shape (reference unused)', () => {
    const s = seasonalShape(lollibox, lollibox, 6, null);
    expect(s[11]).toBeCloseTo(6225 / 666, 4);
    expect(s[6]).toBeCloseTo(481 / 666, 4);
  });
  it('new family keeps own Oct-Dec peak, borrows June anchor from reference', () => {
    const s = seasonalShape(lollime, lollibox, 6, 7);
    expect(s[11]).toBeGreaterThan(8.5);
    expect(s[11]).toBeLessThan(10);
    expect(s[10]).toBeCloseTo(2929 / (1.228 * 666), 1);
  });
  it('brand-new family (no clean own months) falls back to pure reference shape', () => {
    const s = seasonalShape(empty, lollibox, 6, null);
    expect(s[11]).toBeCloseTo(6225 / 666, 4);
    expect(s[5]).toBeCloseTo(1, 6);
  });
  it('never produces NaN when reference current month is also 0', () => {
    const s = seasonalShape(empty, empty, 6, null);
    expect(s.every(x => Number.isFinite(x))).toBe(true);
    expect(s[5]).toBe(1);
  });
});
