import { describe, it, expect } from 'vitest';
import { familyActuals, familyModes, dominantMode, clearCase, selectPeak, opportunityPerWeek } from './coachActuals';

// daily_trends rows are keyed by product_type = family. ad_cost & clicks are ad-only.
const trends = [
  { date: '2026-06-01', product_type: 'Lollibox', ad_cost: 70, clicks: 100 },
  { date: '2026-06-02', product_type: 'Lollibox', ad_cost: 70, clicks: 100 },
];
// acts carry the 4w window: net_roas spend-weighted by spend, family via getFamily(product_short_name).
const acts = [
  { product_short_name: 'White Lollibox', spend: 100, net_roas: 1.5 },
  { product_short_name: 'Pink Lollibox',  spend: 100, net_roas: 0.5 },
];
const getFamily = (n?: string | null) => (n ? (n.split(' ').slice(-1)[0] === 'Lollibox' ? 'Lollibox' : null) : null);

describe('familyActuals', () => {
  it('computes last-7d daily ad spend, ad-only CPC, and spend-weighted 4w ROAS per family', () => {
    const out = familyActuals(acts, trends, getFamily);
    const f = out.get('Lollibox')!;
    expect(f.dailyCost).toBeCloseTo(140 / 2);          // 2 days in window -> $70/d
    expect(f.cpc).toBeCloseTo(140 / 200);              // $0.70 ad-only CPC
    expect(f.roas).toBeCloseTo((1.5 * 100 + 0.5 * 100) / 200); // 1.0 spend-weighted
  });
  it('uses only the most recent 7 distinct trend dates (older dates excluded)', () => {
    // First 3 days carry a huge ad_cost; if they were counted, dailyCost would blow up.
    const long = Array.from({ length: 10 }, (_, i) => ({
      date: `2026-06-${String(i + 1).padStart(2, '0')}`, product_type: 'Lollibox',
      ad_cost: i < 3 ? 1000 : 10, clicks: 10,
    }));
    const out = familyActuals([], long, getFamily);
    // Only days 4-10 (the last 7) count: 7 x $10 / 7 = $10/d. The $1000 early days are excluded.
    expect(out.get('Lollibox')!.dailyCost).toBeCloseTo(10);
  });
  it('emits families that appear only in trends (spend, no ROAS) and only in acts (ROAS, no spend)', () => {
    const out = familyActuals(
      [{ product_short_name: 'White Lollibox', spend: 50, net_roas: 2 }],
      [{ date: '2026-06-01', product_type: 'LolliME', ad_cost: 30, clicks: 60 }],
      (n?: string | null) => (n?.includes('Lollibox') ? 'Lollibox' : null),
    );
    expect(out.get('LolliME')!.dailyCost).toBeCloseTo(30);
    expect(out.get('LolliME')!.roas).toBe(0);
    expect(out.get('Lollibox')!.roas).toBeCloseTo(2);
    expect(out.get('Lollibox')!.dailyCost).toBe(0);
  });
  it('never divides by zero (no clicks -> cpc 0, no spend -> roas 0)', () => {
    const out = familyActuals(
      [{ product_short_name: 'White Lollibox', spend: 0, net_roas: 9 }],
      [{ date: '2026-06-01', product_type: 'Lollibox', ad_cost: 5, clicks: 0 }],
      (n?: string | null) => (n?.includes('Lollibox') ? 'Lollibox' : null),
    );
    const f = out.get('Lollibox')!;
    expect(f.cpc).toBe(0);
    expect(f.roas).toBe(0);
  });
});

describe('dominantMode', () => {
  it('returns the most frequent coach_mode', () => {
    expect(dominantMode([{ coach_mode: 'BLITZ' }, { coach_mode: 'BLITZ' }, { coach_mode: 'GUARDIAN' }])).toBe('BLITZ');
  });
  it('defaults to GUARDIAN when empty', () => {
    expect(dominantMode([])).toBe('GUARDIAN');
  });
});

describe('familyModes', () => {
  const rows = [
    { product_short_name: 'White Lollibox', coach_mode: 'BLITZ' },
    { product_short_name: 'Pink Lollibox',  coach_mode: 'BLITZ' },
    { product_short_name: 'Mint LolliME',   coach_mode: 'COOLDOWN' },
  ];
  const fam = (n?: string | null) =>
    n?.includes('Lollibox') ? 'Lollibox' : n?.includes('LolliME') ? 'LolliME' : null;
  it('maps each family to its own dominant mode (keyed by getFamily)', () => {
    const m = familyModes(rows, fam);
    expect(m.get('Lollibox')).toBe('BLITZ');
    expect(m.get('LolliME')).toBe('COOLDOWN'); // NOT the global dominant (BLITZ)
  });
  it('ignores rows with no family or no mode', () => {
    const m = familyModes([{ product_short_name: 'Unknown', coach_mode: 'BLITZ' }], fam);
    expect(m.size).toBe(0);
  });
});

describe('clearCase', () => {
  const base = { spend: 22, clicks: 40, orders: 0, netRoas: 0, mode: 'GUARDIAN', confidence: 'HIGH' };
  it('zero-conversion negate with enough data is the cleanest clear case', () => {
    const v = clearCase({ ...base, action: 'NEGATE_TERM' });
    expect(v.clear).toBe(true);
  });
  it('parks thin data (spend < $5 or clicks < 10 or non-HIGH confidence)', () => {
    expect(clearCase({ ...base, action: 'NEGATE_TERM', spend: 3 }).clear).toBe(false);
    expect(clearCase({ ...base, action: 'NEGATE_TERM', clicks: 4 }).clear).toBe(false);
    expect(clearCase({ ...base, action: 'NEGATE_TERM', confidence: 'LOW' }).clear).toBe(false);
    expect(clearCase({ ...base, action: 'NEGATE_TERM', confidence: 'MEDIUM' }).clear).toBe(false);
    expect(clearCase({ ...base, action: 'NEGATE_TERM', spend: 3 }).reason).toMatch(/spend/i);
  });
  it('parks a negate that HAS orders (halo risk — direct ROAS understates value)', () => {
    const v = clearCase({ ...base, action: 'NEGATE_TERM', orders: 2, netRoas: 0.5 });
    expect(v.clear).toBe(false);
    expect(v.reason).toMatch(/order/i);
  });
  it('REDUCE_BID is clear only when ROAS is decisively below the gray band (<0.9)', () => {
    expect(clearCase({ ...base, action: 'REDUCE_BID', orders: 3, netRoas: 0.6 }).clear).toBe(true);
    expect(clearCase({ ...base, action: 'REDUCE_BID', orders: 3, netRoas: 0.95 }).clear).toBe(false); // gray band
  });
  it('promote needs mode-specific clear bar: GUARDIAN >=1.3, BLITZ >=1.15, COOLDOWN never', () => {
    const p = { ...base, action: 'INCREASE_BID', orders: 3 };
    expect(clearCase({ ...p, netRoas: 1.35, mode: 'GUARDIAN' }).clear).toBe(true);
    expect(clearCase({ ...p, netRoas: 1.2, mode: 'GUARDIAN' }).clear).toBe(false);
    expect(clearCase({ ...p, netRoas: 1.2, mode: 'BLITZ' }).clear).toBe(true);
    expect(clearCase({ ...p, netRoas: 5.0, mode: 'COOLDOWN' }).clear).toBe(false);
  });
  it('promote with fewer than 2 orders is parked even at high ROAS', () => {
    expect(clearCase({ ...base, action: 'INCREASE_BID', orders: 1, netRoas: 2.0 }).clear).toBe(false);
  });
  it('non-actionable types (MONITOR/KEEP/etc.) are never clear cases', () => {
    expect(clearCase({ ...base, action: 'MONITOR' }).clear).toBe(false);
    expect(clearCase({ ...base, action: 'KEEP' }).clear).toBe(false);
  });
  it('covers the legacy/seasonal cut actions (drift guard)', () => {
    for (const action of ['NEGATE', 'STOP_TERM', 'STOP_SEASONAL']) {
      expect(clearCase({ ...base, action }).clear).toBe(true); // 0 orders, enough data
    }
    expect(clearCase({ ...base, action: 'REDUCE_TO_BASELINE', orders: 3, netRoas: 0.6 }).clear).toBe(true);
  });
  it('REDUCE_BID with ROAS above the band parks with a conflict reason (not "gray band")', () => {
    const v = clearCase({ ...base, action: 'REDUCE_BID', orders: 3, netRoas: 5.0 });
    expect(v.clear).toBe(false);
    expect(v.reason).toMatch(/above breakeven/i);
  });
  it('boundary values: floors are exclusive-below, bars inclusive-at', () => {
    expect(clearCase({ ...base, action: 'NEGATE_TERM', spend: 5 }).clear).toBe(true);    // at floor → passes
    expect(clearCase({ ...base, action: 'NEGATE_TERM', clicks: 10 }).clear).toBe(true);  // at floor → passes
    expect(clearCase({ ...base, action: 'REDUCE_BID', orders: 3, netRoas: 0.9 }).clear).toBe(false); // at grayLow → parks
    expect(clearCase({ ...base, action: 'INCREASE_BID', orders: 2, netRoas: 1.3 }).clear).toBe(true);  // GUARDIAN bar inclusive
    expect(clearCase({ ...base, action: 'INCREASE_BID', orders: 2, netRoas: 1.15, mode: 'BLITZ' }).clear).toBe(true);
  });
  it('all three windows bad → definitely waste (clear cut)', () => {
    expect(clearCase({ ...base, action: 'NEGATE_TERM', roas1w: 0, orders1w: 0, peakRoas: 0.4, peakOrders: 1 }).clear).toBe(true);
    expect(clearCase({ ...base, action: 'NEGATE_TERM', roas1w: null, orders1w: null, peakRoas: null, peakOrders: null }).clear).toBe(true); // no extra data = unchanged behavior
  });
  it('1w+4w bad but peak GREAT → parked with boost-before-peak guidance', () => {
    const v = clearCase({ ...base, action: 'NEGATE_TERM', roas1w: 0, orders1w: 0, peakRoas: 2.1, peakOrders: 12 });
    expect(v.clear).toBe(false);
    expect(v.reason).toMatch(/boost before next peak/i);
    const r = clearCase({ ...base, action: 'REDUCE_BID', orders: 3, netRoas: 0.6, peakRoas: 1.8, peakOrders: 5 });
    expect(r.clear).toBe(false);
  });
  it('peak good but below GREAT bar or thin → still waste', () => {
    expect(clearCase({ ...base, action: 'NEGATE_TERM', peakRoas: 1.1, peakOrders: 10 }).clear).toBe(true); // below 1.3
    expect(clearCase({ ...base, action: 'NEGATE_TERM', peakRoas: 3.0, peakOrders: 1 }).clear).toBe(true);  // too few peak orders
  });
  it('this week already good → recovering, parked', () => {
    const v = clearCase({ ...base, action: 'REDUCE_BID', orders: 3, netRoas: 0.6, roas1w: 1.4, orders1w: 2 });
    expect(v.clear).toBe(false);
    expect(v.reason).toMatch(/recovering/i);
  });
  it('REDUCE with all-null window fields behaves exactly as before (no guard misfire)', () => {
    expect(clearCase({ ...base, action: 'REDUCE_BID', orders: 3, netRoas: 0.6, roas1w: null, orders1w: null, peakRoas: null, peakOrders: null }).clear).toBe(true);
  });
});

describe('selectPeak', () => {
  it('picks the stronger window with its matching orders', () => {
    expect(selectPeak({ ly_net_roas: 1.8, ly_orders: 7, q4_peak_net_roas: 2.4, q4_peak_orders: 12 })).toEqual({ roas: 2.4, orders: 12, spend: null, clicks: null, cpc: null });
    expect(selectPeak({ ly_net_roas: 2.5, ly_orders: 7, q4_peak_net_roas: 2.4, q4_peak_orders: 12 })).toEqual({ roas: 2.5, orders: 7, spend: null, clicks: null, cpc: null });
  });
  it('returns null when neither window has positive ROAS', () => {
    expect(selectPeak({})).toBeNull();
    expect(selectPeak({ ly_net_roas: 0, q4_peak_net_roas: null })).toBeNull();
  });
  it('keeps orders null when the winning window has no order data', () => {
    expect(selectPeak({ ly_net_roas: 1.8, ly_orders: null })).toEqual({ roas: 1.8, orders: null, spend: null, clicks: null, cpc: null });
  });
  it('LY win carries spend/clicks/cpc; Q4 win carries spend only (no clicks/cpc data)', () => {
    expect(selectPeak({ ly_net_roas: 2.5, ly_orders: 7, ly_spend: 120, ly_clicks: 80, ly_cpc: 1.5, q4_peak_net_roas: 2.0, q4_peak_spend: 300 }))
      .toEqual({ roas: 2.5, orders: 7, spend: 120, clicks: 80, cpc: 1.5 });
    expect(selectPeak({ ly_net_roas: 1.0, q4_peak_net_roas: 2.0, q4_peak_orders: 12, q4_peak_spend: 300 }))
      .toEqual({ roas: 2.0, orders: 12, spend: 300, clicks: null, cpc: null });
  });
});

describe('opportunityPerWeek', () => {
  it('cut: weekly burn of a zero-order term', () => {
    expect(opportunityPerWeek({ action: 'NEGATE_TERM', spend4w: 84, netProfit4w: -84, netRoas4w: 0 }))
      .toEqual({ kind: 'save', dollars: 21 });
  });
  it('reduce: the weekly loss being stopped', () => {
    expect(opportunityPerWeek({ action: 'REDUCE_BID', spend4w: 400, netProfit4w: -120, netRoas4w: 0.7 }))
      .toEqual({ kind: 'save', dollars: 30 });
  });
  it('reduce falls back to spend×(1−roas) when net profit missing', () => {
    const r = opportunityPerWeek({ action: 'REDUCE_BID', spend4w: 400, netProfit4w: null, netRoas4w: 0.7 });
    expect(r.kind).toBe('save');
    expect(r.dollars).toBeCloseTo(400 * 0.3 / 4);
  });
  it('promote: current weekly profit at stake (scale to beat)', () => {
    expect(opportunityPerWeek({ action: 'INCREASE_BID', spend4w: 388, netProfit4w: 240, netRoas4w: 2.0 }))
      .toEqual({ kind: 'earn', dollars: 60 });
  });
  it('never negative', () => {
    expect(opportunityPerWeek({ action: 'INCREASE_BID', spend4w: 100, netProfit4w: -50, netRoas4w: 0.5 }).dollars).toBe(0);
  });
});
