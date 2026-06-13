import { describe, it, expect } from 'vitest';
import { mapRecommendation, mapRecommendationsByType } from './mapRecommendation';

describe('mapRecommendation', () => {
  it('coerces numerics and defaults', () => {
    const r = mapRecommendation({ rec_type: 'BROAD', match_type: 'BROAD', keyword: 'gift cards', market_sales: '740', rank: 58 });
    expect(r.rec_type).toBe('BROAD');
    expect(r.market_sales).toBe(740);
    expect(r.rank).toBe(58);
    expect(r.coverage_count).toBeNull();
    expect(r.status).toBe('NEW');
  });

  it('mapRecommendationsByType always returns all 4 keys', () => {
    const m = mapRecommendationsByType({ EXACT: [{ keyword: 'a' }] });
    expect(Object.keys(m).sort()).toEqual(['BRAND', 'BROAD', 'EXACT', 'PHRASE']);
    expect(m.EXACT).toHaveLength(1);
    expect(m.PHRASE).toEqual([]);
  });
});
