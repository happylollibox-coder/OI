import { describe, it, expect } from 'vitest';
import type { MonthSeasonInfo } from './planTypes';
import {
  buildWeeklyProjection, demandOverWindow, forwardDoc, dailyDemandOn,
  type DemandCurve,
} from './stockProjection';

const SEASON: Record<number, MonthSeasonInfo> = {
  202610: { peakDays: 10, offseasonDays: 21, holidays: 'Halloween' },
  202611: { peakDays: 12, offseasonDays: 18, holidays: 'BFCM' },
  202612: { peakDays: 15, offseasonDays: 16, holidays: 'Christmas' },
};

const DEMAND: Record<number, number> = {
  202608: 900, 202609: 1000, 202610: 1400, 202611: 1800, 202612: 2200,
  202701: 800, 202702: 700, 202703: 700,
};

const NOW = new Date(2026, 7, 7);   // 2026-08-07
const END = new Date(2027, 2, 29);  // 2027-03-29

describe('buildWeeklyProjection', () => {
  const curve: DemandCurve = { productDemand: DEMAND, familySeason: SEASON, growth: 1.0 };

  it('starts on the Monday of the start date', () => {
    const weeks = buildWeeklyProjection({
      currentStock: 5000, shipments: [], curve,
      startDate: new Date(2026, 7, 7), endDate: END, now: NOW,
    });
    expect(weeks[0].week).toBe('2026-08-03');
  });

  it('produces the recorded golden first week', () => {
    const weeks = buildWeeklyProjection({
      currentStock: 5000, shipments: [], curve,
      startDate: NOW, endDate: END, now: NOW,
    });
    // Captured from the parity run against the pre-extraction implementation —
    // these values were proven identical to the inline StockProjectionChart code.
    expect(weeks[0]).toEqual({
      week: '2026-08-03',
      weekLabel: 'Aug 3',
      stock: 4797,
      confirmedStock: 4797,
      arrivals: 0,
      confirmedArrivals: 0,
      demand: 203,
      isPeak: false,
      arrivalDates: [],
      doc: 117,
      docSuggested: 117,
      actualSales: undefined,
      actualSalesLY: undefined,
    });
  });

  it('excludes PO and po_needed shipments from arrivals', () => {
    const weeks = buildWeeklyProjection({
      currentStock: 0, curve, startDate: NOW, endDate: END, now: NOW,
      shipments: [
        { qty: 500, arrival_date: '2026-09-09', status: 'po' },
        { qty: 500, arrival_date: '2026-09-09', status: 'po_needed' },
      ],
    });
    expect(weeks.every(w => w.arrivals === 0)).toBe(true);
  });

  it('counts suggested in stock but not confirmedStock', () => {
    const weeks = buildWeeklyProjection({
      currentStock: 10000, curve, startDate: NOW, endDate: END, now: NOW,
      shipments: [{ qty: 3000, arrival_date: '2026-09-09', status: 'suggested' }],
    });
    const w = weeks.find(x => x.week === '2026-09-07')!;
    expect(w.arrivals).toBe(3000);
    expect(w.confirmedArrivals).toBe(0);
    expect(w.stock).toBeGreaterThan(w.confirmedStock);
  });

  it('floors stock at zero rather than going negative', () => {
    const weeks = buildWeeklyProjection({
      currentStock: 10, shipments: [], curve, startDate: NOW, endDate: END, now: NOW,
    });
    expect(weeks.every(w => w.stock >= 0 && w.confirmedStock >= 0)).toBe(true);
  });
});

describe('demandOverWindow', () => {
  const curve: DemandCurve = { productDemand: DEMAND, familySeason: SEASON, growth: 1.0 };

  it('sums a whole month back to that month total', () => {
    const total = demandOverWindow(new Date(2026, 8, 1), new Date(2026, 9, 1), curve);
    expect(total).toBeCloseTo(1000, 6);
  });

  it('applies the growth multiplier', () => {
    const grown: DemandCurve = { ...curve, growth: 2 };
    const total = demandOverWindow(new Date(2026, 8, 1), new Date(2026, 9, 1), grown);
    expect(total).toBeCloseTo(2000, 6);
  });

  it('returns zero for months with no forecast', () => {
    const total = demandOverWindow(new Date(2028, 0, 1), new Date(2028, 1, 1), curve);
    expect(total).toBe(0);
  });
});

describe('dailyDemandOn', () => {
  const curve: DemandCurve = { productDemand: DEMAND, familySeason: SEASON, growth: 1.0 };

  it('rates a late-October (peak) day at 2x an early-October (offseason) day', () => {
    // SEASON[202610] = { peakDays: 10, offseasonDays: 21 } — October has 31 days,
    // so days 22-31 are peak. Expected numbers come straight from the documented
    // formula (rate = monthUnits / (peakDays*2 + offDays)), not from the function
    // under test.
    const monthUnits = DEMAND[202610]; // 1400
    const offRate = monthUnits / (10 * 2 + 21); // 1400 / 41
    const peakRate = offRate * 2;

    const offDay = dailyDemandOn(new Date(2026, 9, 5), curve);   // Oct 5 — offseason
    const peakDay = dailyDemandOn(new Date(2026, 9, 25), curve); // Oct 25 — peak

    expect(offDay.isPeak).toBe(false);
    expect(offDay.units).toBeCloseTo(offRate, 10);

    expect(peakDay.isPeak).toBe(true);
    expect(peakDay.units).toBeCloseTo(peakRate, 10);
    expect(peakDay.units).toBeCloseTo(offDay.units * 2, 10);
  });
});

describe('forwardDoc', () => {
  it('caps at 365', () => {
    // Needs enough weeks to walk through — a single week can only ever
    // contribute 7 days no matter how large startStock is.
    const manyWeeks = Array.from({ length: 60 }, () => ({ demand: 0 }));
    expect(forwardDoc(manyWeeks, 0, 1_000_000)).toBe(365);
  });

  it('returns 0 for no stock', () => {
    expect(forwardDoc([{ demand: 100 }], 0, 0)).toBe(0);
  });

  it('gives 7 days when stock exactly covers one week', () => {
    expect(forwardDoc([{ demand: 70 }, { demand: 70 }], 0, 70)).toBe(7);
  });
});
