import type { StrategyCampaignRow } from '../types';

export const STRATEGY_ORDER = ['EXACT','PHRASE','BROAD_SP','BROAD_VIDEO','BROAD_SPOTLIGHT','COMPETITOR','BRAND_DEFENSE','PRODUCT_DEFENSE','AUTO','UNCLASSIFIED'];

export interface StrategyGroup {
  id: string;
  campaigns: StrategyCampaignRow[];
  activeCount: number;
  totalSpend: number;
  totalSales: number;
  avgRoas: number;
}

export function groupByStrategy(rows: StrategyCampaignRow[]): StrategyGroup[] {
  const by: Record<string, StrategyCampaignRow[]> = {};
  rows.forEach(r => { (by[r.strategy_id] = by[r.strategy_id] || []).push(r); });
  const groups = Object.entries(by).map(([id, campaigns]) => {
    const totalSpend = campaigns.reduce((s, c) => s + (c.spend || 0), 0);
    const totalSales = campaigns.reduce((s, c) => s + (c.sales || 0), 0);
    return {
      id, campaigns,
      activeCount: campaigns.filter(c => c.is_active).length,
      totalSpend, totalSales,
      avgRoas: totalSpend > 0 ? (totalSales - totalSpend) / totalSpend : 0,
    };
  });
  const rank = (id: string) => { const i = STRATEGY_ORDER.indexOf(id); return i === -1 ? STRATEGY_ORDER.length : i; };
  return groups.sort((a, b) => rank(a.id) - rank(b.id) || b.totalSpend - a.totalSpend);
}
