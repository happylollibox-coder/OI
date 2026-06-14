import { describe, it, expect } from 'vitest';
import { clusterKey, clusterTerms } from './clusterTerms';
const syn = { gifts: ['gift','present','presents'], girls: ['girl'], birthday: ['bday','b day'] };
describe('clusterKey', () => {
  it('collapses singular/plural + synonyms to one key (bag of words)', () => {
    expect(clusterKey('gift for 7 year old girl', syn)).toBe(clusterKey('gifts for 7 year old girls', syn));
    expect(clusterKey('gifts for 7 year old girls', syn)).toBe('7 gifts girls old year'); // sorted, "for" dropped
  });
  it('order-independent like Amazon broad: same words different order → same cluster', () => {
    expect(clusterKey('journal kit for girls', syn)).toBe(clusterKey('girls journal kit', syn));
  });
  it('handles multi-word variants', () => {
    expect(clusterKey('b day present for girl', syn)).toBe('birthday gifts girls');
  });
  it('word-boundary safe: "presents" maps as a whole word, not "present"+s', () => {
    expect(clusterKey('birthday presents', syn)).toBe('birthday gifts');
  });
  it('leaves unknown content words untouched', () => {
    expect(clusterKey('cute notebook', syn)).toBe('cute notebook');
  });
});
describe('clusterTerms', () => {
  const rows = [
    { query_text: 'gifts for 7 year old girls', market_impressions: 100, market_purchases: 10 },
    { query_text: 'gift for 7 year old girl',   market_impressions: 50,  market_purchases: 4 },
    { query_text: 'cute notebook',              market_impressions: 30,  market_purchases: 1 },
  ];
  it('groups synonym-equivalent terms; representative = top purchases; totals summed', () => {
    const c = clusterTerms(rows, syn);
    expect(c.length).toBe(2);
    const big = c[0];
    expect(big.size).toBe(2);
    expect(big.representative.query_text).toBe('gifts for 7 year old girls');
    expect(big.totalPurchases).toBe(14);
    expect(big.totalImpressions).toBe(150);
  });
  it('singletons become size-1 clusters', () => {
    expect(clusterTerms(rows, syn).find(c => c.key === 'cute notebook')!.size).toBe(1);
  });
});
