import { describe, it, expect } from 'vitest';
import {
  computeKpis,
  resolveDateRange,
  daysInRange,
  applyDailyAverage,
  type AdsKpiProductRow,
  type UnifiedKpiProductRow,
} from './adsKpiPanel.helpers';

const ad = (o: Partial<AdsKpiProductRow>): AdsKpiProductRow => ({
  parentName: '', asin: '', productShortName: '',
  spend: 0, sales: 0, orders: 0, clicks: 0, impressions: 0, grossProfit: 0, ...o,
});
const uni = (o: Partial<UnifiedKpiProductRow>): UnifiedKpiProductRow => ({
  family: '', asin: '', productShortName: '',
  sales: 0, adCost: 0, grossMargin: 0, units: 0, ...o,
});

describe('computeKpis', () => {
  it('aggregates ad-attributed metrics and ratios for the whole account when no filter', () => {
    const ads = [
      ad({ parentName: 'Bottle', asin: 'A', spend: 100, sales: 300, orders: 30, clicks: 200, impressions: 5000, grossProfit: 180 }),
      ad({ parentName: 'Fresh', asin: 'B', spend: 100, sales: 100, orders: 10, clicks: 300, impressions: 5000, grossProfit: 40 }),
    ];
    const k = computeKpis(ads, [], { family: null, product: null });
    expect(k.spend).toBe(200);
    expect(k.sales).toBe(400);
    expect(k.orders).toBe(40);
    expect(k.clicks).toBe(500);
    expect(k.impressions).toBe(10000);
    expect(k.roas).toBeCloseTo(2.0);            // 400/200
    expect(k.acos).toBeCloseTo(50.0);           // 200/400*100
    expect(k.netProfit).toBeCloseTo(20);        // (180+40) - 200
    expect(k.netRoas).toBeCloseTo(0.1);         // 20/200
    expect(k.cpc).toBeCloseTo(0.4);             // 200/500
    expect(k.cvr).toBeCloseTo(8.0);             // 40/500*100
    expect(k.ctr).toBeCloseTo(5.0);             // 500/10000*100
  });

  it('applies the family filter to the ad-attributed selection', () => {
    const ads = [
      ad({ parentName: 'Bottle', asin: 'A', spend: 100, sales: 300 }),
      ad({ parentName: 'Fresh', asin: 'B', spend: 100, sales: 100 }),
    ];
    const k = computeKpis(ads, [], { family: 'Bottle', product: null });
    expect(k.spend).toBe(100);
    expect(k.sales).toBe(300);
  });

  it('applies the product (asin) filter', () => {
    const ads = [
      ad({ parentName: 'Bottle', asin: 'A', spend: 100 }),
      ad({ parentName: 'Bottle', asin: 'A2', spend: 40 }),
    ];
    const k = computeKpis(ads, [], { family: 'Bottle', product: 'A2' });
    expect(k.spend).toBe(40);
  });

  it('%Spend = selection spend / all-products spend, even under a filter', () => {
    const ads = [
      ad({ parentName: 'Bottle', asin: 'A', spend: 100 }),
      ad({ parentName: 'Fresh', asin: 'B', spend: 300 }),
    ];
    const k = computeKpis(ads, [], { family: 'Bottle', product: null });
    expect(k.spendSharePct).toBeCloseTo(25.0); // 100 / (100+300) * 100
  });

  it('derives TACOS, profit/unit, ppc/unit and total net profit from the unified selection', () => {
    const unified = [
      uni({ family: 'Bottle', asin: 'A', productShortName: 'Truth', sales: 1000, adCost: 200, grossMargin: 500, units: 100 }),
      uni({ family: 'Fresh', asin: 'B', productShortName: 'Bath', sales: 999, adCost: 999, grossMargin: 1, units: 5 }),
    ];
    const k = computeKpis([], unified, { family: 'Bottle', product: null });
    expect(k.tacos).toBeCloseTo(20.0);          // 200/1000*100
    expect(k.profitPerUnit).toBeCloseTo(3.0);   // (500-200)/100
    expect(k.ppcPerUnit).toBeCloseTo(2.0);      // 200/100
    expect(k.totalNetProfit).toBeCloseTo(300);  // grossMargin 500 - adCost 200 (Bottle only)
    expect(k.units).toBeCloseTo(100);           // Bottle units only
  });

  it('Best Child = selection product with the highest total net profit', () => {
    const unified = [
      uni({ family: 'Bottle', asin: 'A', productShortName: 'Truth', grossMargin: 500, adCost: 100 }), // np 400
      uni({ family: 'Bottle', asin: 'A2', productShortName: 'Dare', grossMargin: 900, adCost: 100 }), // np 800
      uni({ family: 'Fresh', asin: 'B', productShortName: 'Bath', grossMargin: 5000, adCost: 0 }),    // excluded by filter
    ];
    const k = computeKpis([], unified, { family: 'Bottle', product: null });
    expect(k.bestChild).toEqual({ name: 'Dare', netProfit: 800 });
  });

  it('guards against divide-by-zero (empty data yields zeros, null best child)', () => {
    const k = computeKpis([], [], { family: null, product: null });
    expect(k.roas).toBe(0);
    expect(k.acos).toBe(0);
    expect(k.cpc).toBe(0);
    expect(k.tacos).toBe(0);
    expect(k.profitPerUnit).toBe(0);
    expect(k.spendSharePct).toBe(0);
    expect(k.bestChild).toBeNull();
  });
});

describe('daysInRange', () => {
  it('counts inclusive days', () => {
    expect(daysInRange('2026-07-07', '2026-07-13')).toBe(7);
    expect(daysInRange('2026-07-13', '2026-07-13')).toBe(1);
    expect(daysInRange('2026-06-14', '2026-07-13')).toBe(30);
  });
  it('never returns less than 1', () => {
    expect(daysInRange('2026-07-13', '2026-07-07')).toBe(1);
    expect(daysInRange('', '')).toBe(1);
  });
});

describe('applyDailyAverage', () => {
  const base = computeKpis(
    [{ parentName: 'B', asin: 'A', productShortName: 'P', spend: 700, sales: 1400, orders: 70, clicks: 350, impressions: 7000, grossProfit: 840 }],
    [{ family: 'B', asin: 'A', productShortName: 'P', sales: 2100, adCost: 700, grossMargin: 1050, units: 140 }],
    { family: null, product: null },
  );

  it('divides flow metrics by the day count', () => {
    const d = applyDailyAverage(base, 7);
    expect(d.spend).toBeCloseTo(100);
    expect(d.sales).toBeCloseTo(200);
    expect(d.orders).toBeCloseTo(10);
    expect(d.clicks).toBeCloseTo(50);
    expect(d.impressions).toBeCloseTo(1000);
    expect(d.netProfit).toBeCloseTo(20);       // (840-700)/7
    expect(d.totalNetProfit).toBeCloseTo(50);  // (1050-700)/7
    expect(d.units).toBeCloseTo(20);           // 140/7
    expect(d.bestChild?.netProfit).toBeCloseTo(50);
  });

  it('leaves ratios and per-unit metrics untouched', () => {
    const d = applyDailyAverage(base, 7);
    expect(d.roas).toBeCloseTo(base.roas);
    expect(d.acos).toBeCloseTo(base.acos);
    expect(d.tacos).toBeCloseTo(base.tacos);
    expect(d.cpc).toBeCloseTo(base.cpc);
    expect(d.cvr).toBeCloseTo(base.cvr);
    expect(d.ctr).toBeCloseTo(base.ctr);
    expect(d.netRoas).toBeCloseTo(base.netRoas);
    expect(d.spendSharePct).toBeCloseTo(base.spendSharePct);
    expect(d.profitPerUnit).toBeCloseTo(base.profitPerUnit);
    expect(d.ppcPerUnit).toBeCloseTo(base.ppcPerUnit);
  });

  it('days=1 is a no-op for flow metrics', () => {
    const d = applyDailyAverage(base, 1);
    expect(d.spend).toBeCloseTo(base.spend);
    expect(d.totalNetProfit).toBeCloseTo(base.totalNetProfit);
  });
});

describe('resolveDateRange', () => {
  const today = new Date('2026-07-14T00:00:00Z');

  it('yesterday is a single prior day', () => {
    expect(resolveDateRange('yesterday', today)).toEqual(['2026-07-13', '2026-07-13']);
  });

  it('7d spans the 7 days ending yesterday', () => {
    expect(resolveDateRange('7d', today)).toEqual(['2026-07-07', '2026-07-13']);
  });

  it('30d spans the 30 days ending yesterday', () => {
    expect(resolveDateRange('30d', today)).toEqual(['2026-06-14', '2026-07-13']);
  });

  it('custom passes through the supplied start/end', () => {
    expect(resolveDateRange('custom', today, '2026-01-01', '2026-01-31')).toEqual(['2026-01-01', '2026-01-31']);
  });
});
