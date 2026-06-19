import { describe, it, expect } from 'vitest';
import {
  resolveWindow, isPeakWindow, classifyDelta, buildBriefModel, todayStr, peakShiftDays,
  type DateMode,
} from './homeBrief';
import { addDays } from './utils';
import type { DashboardData, DailyTrendByAsinRow, Ads7dRow, PeakRow } from './types';

const NOW = new Date('2026-06-18T12:00:00');
const PERF = '2026-06-18';

/* ── window resolution ──────────────────────────────────────────────────── */

describe('resolveWindow', () => {
  it('yesterday → single perf-max day vs trailing 7-day average', () => {
    const w = resolveWindow('yday', PERF, PERF, null, NOW);
    expect(w.curStart).toBe('2026-06-18');
    expect(w.curEnd).toBe('2026-06-18');
    expect(w.baseStart).toBe('2026-06-11');
    expect(w.baseEnd).toBe('2026-06-17');
    expect(w.baseScale).toBeCloseTo(1 / 7);
    expect(w.adsOnly).toBe(false);
  });

  it('7 days → trailing 7-day window vs prior 7 days (sum vs sum)', () => {
    const w = resolveWindow('7d', PERF, PERF, null, NOW);
    expect(w.curStart).toBe('2026-06-12');
    expect(w.curEnd).toBe('2026-06-18');
    expect(w.baseStart).toBe('2026-06-05');
    expect(w.baseEnd).toBe('2026-06-11');
    expect(w.baseScale).toBe(1);
    expect(w.peak).toBe(false);
  });

  it('today → single today vs trailing 7-day average, ads only', () => {
    const w = resolveWindow('today', PERF, '2026-06-18', null, NOW);
    expect(w.curStart).toBe('2026-06-18');
    expect(w.adsOnly).toBe(true);
    expect(w.baseStart).toBe('2026-06-11');
  });

  it('peak override → 7d compares to last-year same dates', () => {
    const pk = { pre_peak_start: '2026-06-01', peak_end: '2026-12-31' } as never;
    const w = resolveWindow('7d', PERF, PERF, pk, NOW);
    expect(w.peak).toBe(true);
    expect(w.baseEnd).toBe('2025-06-19'); // perf 06-18 shifted −364d
    expect(w.label).toContain('last-year peak');
  });
});

describe('peakShiftDays (peak-anchor-relative baseline)', () => {
  const pk = { holiday_name: 'Black Friday', holiday_date: '2026-11-27', peak_start: '2026-11-20' } as PeakRow;

  it('shifts by the gap between this and last year peak anchors (not a flat 364)', () => {
    const holidays = [
      { holiday_name: 'Black Friday', holiday_date: '2026-11-27', peak_start: '2026-11-20' },
      { holiday_name: 'Black Friday', holiday_date: '2025-11-29', peak_start: '2025-11-29' },
    ];
    expect(peakShiftDays(holidays, pk)).toBe(356); // 2026-11-20 minus 2025-11-29
  });
  it('falls back to 364 when no prior-year holiday is found', () => {
    expect(peakShiftDays([{ holiday_name: 'Black Friday', holiday_date: '2026-11-27', peak_start: '2026-11-20' }], pk)).toBe(364);
  });
  it('falls back to 364 when there is no peak', () => {
    expect(peakShiftDays([], null)).toBe(364);
  });
});

describe('resolveWindow peak shift', () => {
  it('peak baseline ends a custom shift before perf-max', () => {
    const pk = { pre_peak_start: '2026-06-01', peak_end: '2026-12-31' } as PeakRow;
    const w = resolveWindow('7d', PERF, PERF, pk, NOW, 371);
    expect(w.peak).toBe(true);
    expect(w.baseEnd).toBe(addDays(PERF, -371));
    expect(w.baseStart).toBe(addDays(addDays(PERF, -371), -6));
  });
});

describe('isPeakWindow', () => {
  const pk = { pre_peak_start: '2026-11-01', peak_end: '2026-12-31' } as never;
  it('true when window overlaps the peak span', () => {
    expect(isPeakWindow('2026-11-15', '2026-11-21', pk)).toBe(true);
  });
  it('false when window is outside the peak span', () => {
    expect(isPeakWindow('2026-06-12', '2026-06-18', pk)).toBe(false);
  });
  it('false when no peak row', () => {
    expect(isPeakWindow('2026-11-15', '2026-11-21', null)).toBe(false);
  });
});

/* ── delta classification ───────────────────────────────────────────────── */

describe('classifyDelta', () => {
  it('money: ≥7% counts as moved', () => {
    expect(classifyDelta('k', 'L', 1000, 800, 'money').moved).toBe(true);
    expect(classifyDelta('k', 'L', 1000, 800, 'money').dir).toBe('up');
    expect(classifyDelta('k', 'L', 103, 100, 'money').moved).toBe(false);
  });
  it('ratio: moves on ≥0.2x absolute', () => {
    expect(classifyDelta('k', 'L', 7.0, 5.6, 'ratio').moved).toBe(true);
    expect(classifyDelta('k', 'L', 5.05, 5.0, 'ratio').moved).toBe(false);
  });
  it('pct (points): moves on ≥2pt', () => {
    expect(classifyDelta('k', 'L', 60, 50, 'pct').moved).toBe(true);
    expect(classifyDelta('k', 'L', 51, 50, 'pct').moved).toBe(false);
  });
});

/* ── model integration ──────────────────────────────────────────────────── */

function dba(product_type: string, product_short_name: string, asin: string, date: string, o: Partial<DailyTrendByAsinRow>): DailyTrendByAsinRow {
  return { product_type, product_short_name, asin, date, sales: 0, orders: 0, units: 0, ad_cost: 0, cogs: 0, net_profit: 0, organic_units: 0, ad_orders: 0, ...o };
}
function ads(name: string, parent: string, date: string, o: Partial<Ads7dRow>): Ads7dRow {
  return {
    row_type: 'campaign', date, campaign_id: 'c', campaign_name: name, campaign_type: null,
    product_short_name: name, parent_name: parent, search_term: null,
    spend: 0, orders: 0, clicks: 0, impressions: 0, sales: 0, gross_profit: null,
    cpc: 0, conv_rate: 0, roas: 0, search_terms_count: null, ...o,
  };
}

function makeData(): DashboardData {
  const dt: DailyTrendByAsinRow[] = [];
  // Lollibox (Box Classic): clearly up on the perf-max day vs the 7-day average.
  dt.push(dba('Lollibox', 'Box Classic', 'A1', '2026-06-18', { sales: 1000, ad_cost: 100, cogs: 300, net_profit: 400, orders: 50, units: 50, organic_units: 30, ad_orders: 20 }));
  for (let d = 11; d <= 17; d++) dt.push(dba('Lollibox', 'Box Classic', 'A1', `2026-06-${d}`, { sales: 800, ad_cost: 100, cogs: 240, net_profit: 300, orders: 40, units: 40, organic_units: 20, ad_orders: 20 }));
  // Bunny: dead flat → steady.
  dt.push(dba('Bunny', 'Bun', 'A2', '2026-06-18', { sales: 500, ad_cost: 50, cogs: 150, net_profit: 100, orders: 25, units: 25, organic_units: 15, ad_orders: 10 }));
  for (let d = 11; d <= 17; d++) dt.push(dba('Bunny', 'Bun', 'A2', `2026-06-${d}`, { sales: 500, ad_cost: 50, cogs: 150, net_profit: 100, orders: 25, units: 25, organic_units: 15, ad_orders: 10 }));
  // Bottle: present so it shows; OOS risk via supply_chain.
  dt.push(dba('Bottle', 'Truth bottle', 'A3', '2026-06-18', { sales: 300, ad_cost: 40, cogs: 90, net_profit: 80, orders: 15, units: 15, organic_units: 9, ad_orders: 6 }));
  for (let d = 11; d <= 17; d++) dt.push(dba('Bottle', 'Truth bottle', 'A3', `2026-06-${d}`, { sales: 320, ad_cost: 40, cogs: 96, net_profit: 85, orders: 16, units: 16, organic_units: 10, ad_orders: 6 }));

  // ads_7d — only used by Today mode.
  const a7: Ads7dRow[] = [];
  a7.push(ads('Box Classic', 'Lollibox', '2026-06-18', { spend: 100, sales: 700, orders: 20 }));
  for (let d = 11; d <= 17; d++) a7.push(ads('Box Classic', 'Lollibox', `2026-06-${d}`, { spend: 100, sales: 560, orders: 20 }));

  return {
    daily_trends_by_asin: dt,
    ads_7d: a7,
    products: [
      { asin: 'A1', product_short_name: 'Box Classic', parent_name: 'Lollibox' },
      { asin: 'A2', product_short_name: 'Bun', parent_name: 'Bunny' },
      { asin: 'A3', product_short_name: 'Truth bottle', parent_name: 'Bottle' },
    ],
    supply_chain: [
      { asin: 'A3', product_short_name: 'Truth bottle', days_of_coverage: 4, days_to_next_shipment: null },
    ],
    asin_oos_days: [],
    actions: [],
    peak: [],
    _meta: { data_freshness: { performance_max_date: PERF, ads_max_date: PERF } },
  } as unknown as DashboardData;
}

describe('buildBriefModel', () => {
  it('enables Today only when ads data reaches today', () => {
    expect(buildBriefModel(makeData(), 'yday', NOW).todayEnabled).toBe(true);
    const stale = makeData();
    stale._meta.data_freshness!.ads_max_date = '2026-06-17';
    const m = buildBriefModel(stale, 'yday', NOW);
    expect(m.todayEnabled).toBe(false);
    expect(m.todayDisabledReason).toBeTruthy();
  });

  it('Lollibox reads as up across sales / profit / ROAS / organic', () => {
    const m = buildBriefModel(makeData(), 'yday', NOW);
    const lolli = m.families.find(f => f.family === 'Lollibox')!;
    const dir = (k: string) => lolli.kpis.find(x => x.key === k)!.dir;
    expect(dir('sales')).toBe('up');
    expect(dir('net_profit')).toBe('up');
    expect(dir('net_roas')).toBe('up');
    expect(dir('organic_pct')).toBe('up');
    expect(lolli.steady).toBe(false);
    expect(lolli.read).toMatch(/sales up and profit up/i);
  });

  it('organic % uses organic_units / units', () => {
    const m = buildBriefModel(makeData(), 'yday', NOW);
    const lolli = m.families.find(f => f.family === 'Lollibox')!;
    const org = lolli.kpis.find(x => x.key === 'organic_pct')!;
    expect(org.cur).toBeCloseTo(60); // 30 organic_units / 50 units
  });

  it('per-product moves use full P&L (sales + profit) outside Today mode', () => {
    const m = buildBriefModel(makeData(), 'yday', NOW);
    const lolli = m.families.find(f => f.family === 'Lollibox')!;
    const box = lolli.products.find(p => p.name === 'Box Classic')!;
    expect(box).toBeTruthy();
    expect(box.text).toMatch(/sales \+25%/);
    expect(box.text).toMatch(/profit \+33%/);
  });

  it('flags Bottle out-of-stock risk and marks it red', () => {
    const m = buildBriefModel(makeData(), 'yday', NOW);
    const bottle = m.families.find(f => f.family === 'Bottle')!;
    expect(bottle.health).toBe('risk');
    expect(bottle.attention.some(a => a.level === 'risk' && /out of stock in ~4/.test(a.text))).toBe(true);
  });

  it('marks dead-flat families steady and sorts them last', () => {
    const m = buildBriefModel(makeData(), 'yday', NOW);
    const bunny = m.families.find(f => f.family === 'Bunny')!;
    expect(bunny.steady).toBe(true);
    expect(m.families[m.families.length - 1].family).toBe('Bunny');
  });

  it('today mode is ads-only (no net-profit KPI)', () => {
    const m = buildBriefModel(makeData(), 'today' as DateMode, NOW);
    const lolli = m.families.find(f => f.family === 'Lollibox')!;
    expect(lolli.adsOnly).toBe(true);
    expect(lolli.kpis.some(k => k.key === 'net_profit')).toBe(false);
    expect(lolli.kpis.some(k => k.key === 'ads_roas')).toBe(true);
  });
});

describe('todayStr', () => {
  it('formats local date as YYYY-MM-DD', () => {
    expect(todayStr(new Date('2026-06-18T12:00:00'))).toBe('2026-06-18');
  });
});
