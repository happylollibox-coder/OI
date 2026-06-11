import { describe, it, expect } from 'vitest';
import { mapResearchRow } from './mapRow';

describe('mapResearchRow', () => {
  it('defaults counters to 0 and optionals to null on empty input', () => {
    const r = mapResearchRow({ query_text: 'x' });
    expect(r.market_impressions).toBe(0);
    expect(r.ads_family_orders).toBe(0);
    expect(r.weekly_market_purchases).toBe(0);
    expect(r.family_purchases).toBe(0);
    expect(r.median_click_price).toBeNull();
    expect(r.rank_score).toBeNull();
    expect(r.cps_source).toBeNull();
    expect(r.is_holiday_active).toBeNull();
    expect(r.gender_score).toBeNull();
    expect(r.match_type).toBe('direct');
    expect(r.is_brand_term).toBe(false);
  });

  it('passes through API values and coerces numerics', () => {
    const r = mapResearchRow({
      query_text: 'gift',
      match_type: 'related',
      rank_score: '72',
      seg_fit: 60,
      cps_source: 'curve',
      is_holiday_active: false,
      weekly_market_purchases: 120,
      est_cps: 9.4,
      gender_score: -1,
    });
    expect(r.match_type).toBe('related');
    expect(r.rank_score).toBe(72);
    expect(r.seg_fit).toBe(60);
    expect(r.cps_source).toBe('curve');
    expect(r.is_holiday_active).toBe(false);
    expect(r.weekly_market_purchases).toBe(120);
    expect(r.est_cps).toBeCloseTo(9.4);
    expect(r.gender_score).toBe(-1);
  });
});
