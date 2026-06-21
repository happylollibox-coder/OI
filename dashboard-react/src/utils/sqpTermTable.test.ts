import { describe, it, expect } from 'vitest';
import { rollupSqpTerms } from './sqpTermTable';
import type { SqpAdsByTermRow } from '../types';

function row(p: Partial<SqpAdsByTermRow>): SqpAdsByTermRow {
  return {
    reporting_date: '2026-06-13', week_start: '2026-06-07', asin: 'A1',
    parent_name: 'Bunny', product_short_name: 'P', search_term: 'cute keychain',
    impressions: 0, clicks: 0, cart_adds: 0, orders: 0, organic_orders: 0,
    amazon_impressions: null, amazon_orders: null,
    ad_impressions: 0, ad_clicks: 0, ad_orders: 0, ad_units: 0,
    ad_spend: 0, ad_sales: 0, ad_gross_profit: 0,
    show_rate_pct: null, estimated_organic_rank: null, organic_rank_zone: null,
    search_query_score: null, ...p,
  };
}

describe('rollupSqpTerms', () => {
  it('MAX amazon within a week (dedupe ASIN fan-out), SUM your impressions across ASINs', () => {
    const rows = [
      row({ asin: 'A1', impressions: 100, amazon_impressions: 20000 }),
      row({ asin: 'A2', impressions: 50,  amazon_impressions: 20000 }),
    ];
    const [t] = rollupSqpTerms(rows);
    expect(t.impressions).toBe(150);      // summed across ASINs
    expect(t.market_vol).toBe(20000);     // MAX within the (term, week), not 40000
  });

  it('SUMS the per-week market volume across weeks', () => {
    const rows = [
      row({ reporting_date: '2026-06-07', impressions: 10, amazon_impressions: 20000 }),
      row({ reporting_date: '2026-06-13', impressions: 10, amazon_impressions: 18000 }),
    ];
    const [t] = rollupSqpTerms(rows);
    expect(t.market_vol).toBe(38000);     // 20000 + 18000
    expect(t.impressions).toBe(20);
  });

  it('computes net ROAS = gross profit / spend and guards divide-by-zero', () => {
    const rows = [
      row({ ad_spend: 10, ad_sales: 30, ad_gross_profit: 18, ad_clicks: 5 }),
    ];
    const [t] = rollupSqpTerms(rows);
    expect(t.net_roas).toBeCloseTo(1.8);
    expect(t.cpc).toBeCloseTo(2.0);
    const [z] = rollupSqpTerms([row({ ad_spend: 0, ad_sales: 0 })]);
    expect(z.net_roas).toBeNull();
    expect(z.cpc).toBeNull();
  });

  it('impr_share is your_impr/amazon_impr as a percent; rank/zone from latest week', () => {
    const rows = [
      row({ reporting_date: '2026-06-07', impressions: 50, amazon_impressions: 10000,
            estimated_organic_rank: 40, organic_rank_zone: 'lower_p1' }),
      row({ reporting_date: '2026-06-13', impressions: 50, amazon_impressions: 10000,
            estimated_organic_rank: 48, organic_rank_zone: 'page_2_plus' }),
    ];
    const [t] = rollupSqpTerms(rows);
    expect(t.impr_share).toBeCloseTo((100 / 20000) * 100); // 100 impr / 20000 summed mkt
    expect(t.est_rank).toBe(48);          // latest week
    expect(t.zone).toBe('page_2_plus');
  });
});
