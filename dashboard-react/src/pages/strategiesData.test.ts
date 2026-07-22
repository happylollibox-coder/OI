import { describe, it, expect } from 'vitest';
import { groupByStrategy, STRATEGY_ORDER } from './strategiesData';
import type { StrategyCampaignRow } from '../types';

const mk = (id: string, strat: string, spend: number, sales: number, active = true): StrategyCampaignRow => ({
  campaign_id: id, campaign_name: id, campaign_type: 'SP', parent_name: 'Fresh',
  strategy_id: strat, strategy_source: 'mapping', is_active: active,
  spend, orders: 1, clicks: 10, impressions: 100, sales,
  net_roas: null, conv_rate: null, cpc: null, last_date: '2026-07-20',
});

describe('groupByStrategy', () => {
  it('aggregates spend + net ROAS per strategy and counts active campaigns', () => {
    const g = groupByStrategy([mk('a','AUTO',100,150), mk('b','AUTO',50,0,false), mk('c','INTENT',200,400)]);
    const auto = g.find(s => s.id === 'AUTO')!;
    expect(auto.totalSpend).toBe(150);
    expect(auto.activeCount).toBe(1);
    expect(auto.avgRoas).toBeCloseTo((150 - 150) / 150); // (sales-spend)/spend = 0
    expect(g.map(s => s.id)).toContain('INTENT');
  });
  it('places UNCLASSIFIED last regardless of spend', () => {
    const g = groupByStrategy([mk('u','UNCLASSIFIED',9999,0), mk('c','INTENT',1,0)]);
    expect(g[g.length - 1].id).toBe('UNCLASSIFIED');
  });
});
