import { describe, it, expect } from 'vitest';
import {
  deriveMetrics,
  groupByStrategy,
  type CampaignRow,
} from './adsCampaignTable.helpers';

// strategyLabel() and its tests were removed 2026-07-23: the Ads page no longer derives a strategy
// by string-parsing experiment names — it reads the resolved strategy_id from StrategyCampaign.

describe('deriveMetrics', () => {
  it('computes cpc, ctr, cvr, acos and net ROAS (grossProfit/spend)', () => {
    const d = deriveMetrics({ spend: 100, orders: 10, sales: 400, clicks: 200, impressions: 5000, grossProfit: 120 });
    expect(d.cpc).toBeCloseTo(0.5);     // 100/200
    expect(d.ctr).toBeCloseTo(4.0);     // 200/5000*100
    expect(d.cvr).toBeCloseTo(5.0);     // 10/200*100
    expect(d.acos).toBeCloseTo(25.0);   // 100/400*100
    expect(d.netRoas).toBeCloseTo(1.2); // 120/100  → ≥1 = profitable (green)
  });

  it('guards divide-by-zero', () => {
    const d = deriveMetrics({ spend: 0, orders: 0, sales: 0, clicks: 0, impressions: 0, grossProfit: 0 });
    expect(d.cpc).toBe(0);
    expect(d.ctr).toBe(0);
    expect(d.cvr).toBe(0);
    expect(d.acos).toBe(0);
    expect(d.netRoas).toBe(0);
  });
});

const camp = (o: Partial<CampaignRow>): CampaignRow => ({
  campaignId: '', campaignName: '', campaignType: null,
  spend: 0, orders: 0, sales: 0, clicks: 0, impressions: 0, grossProfit: 0, ...o,
});

describe('groupByStrategy', () => {
  it('groups campaigns by mapped strategy, unmapped → Unassigned', () => {
    const campaigns = [
      camp({ campaignId: 'c1', spend: 50 }),
      camp({ campaignId: 'c2', spend: 30 }),
      camp({ campaignId: 'c3', spend: 20 }),
    ];
    const map = { c1: 'Guardian', c2: 'Guardian' };
    const groups = groupByStrategy(campaigns, map);
    expect(groups.map(g => g.strategy)).toEqual(['Guardian', 'Unassigned']);
    expect(groups[0].campaigns.map(c => c.campaignId)).toEqual(['c1', 'c2']);
    expect(groups[1].campaigns.map(c => c.campaignId)).toEqual(['c3']);
  });

  it('orders strategies by total spend desc and campaigns within by spend desc', () => {
    const campaigns = [
      camp({ campaignId: 'a', spend: 10 }),   // Launch
      camp({ campaignId: 'b', spend: 100 }),  // Guardian
      camp({ campaignId: 'c', spend: 40 }),   // Guardian
      camp({ campaignId: 'd', spend: 200 }),  // Launch
    ];
    const map = { a: 'Launch', b: 'Guardian', c: 'Guardian', d: 'Launch' };
    const groups = groupByStrategy(campaigns, map);
    // Launch total 210 > Guardian total 140
    expect(groups.map(g => g.strategy)).toEqual(['Launch', 'Guardian']);
    expect(groups[0].spend).toBe(210);
    expect(groups[0].campaigns.map(c => c.campaignId)).toEqual(['d', 'a']); // 200, 10
    expect(groups[1].campaigns.map(c => c.campaignId)).toEqual(['b', 'c']); // 100, 40
  });

  it('handles empty input', () => {
    expect(groupByStrategy([], {})).toEqual([]);
  });
});
