// Pure logic for the Strategy → Campaign → Keyword → Search-term drill-down.
// No React, no I/O — unit-tested. Rows at every grain share the same additive base.

/** Additive base metrics available at every grain (from the Ads cube). */
export interface AdsRowBase {
  spend: number;
  orders: number;
  sales: number;         // ad-attributed sales
  clicks: number;
  impressions: number;
  grossProfit: number;   // ad sales − cogs
}

/** Ratios derived from the additive base. */
export interface DerivedMetrics {
  cpc: number;
  ctr: number;   // %
  cvr: number;   // %
  acos: number;  // %
  netRoas: number; // grossProfit / spend — ≥1 = ad gross profit covers spend (profitable)
}

const div = (n: number, d: number): number => (d > 0 ? n / d : 0);

export function deriveMetrics(m: AdsRowBase): DerivedMetrics {
  return {
    cpc: div(m.spend, m.clicks),
    ctr: div(m.clicks, m.impressions) * 100,
    cvr: div(m.orders, m.clicks) * 100,
    acos: div(m.spend, m.sales) * 100,
    netRoas: div(m.grossProfit, m.spend),
  };
}

export interface CampaignRow extends AdsRowBase {
  campaignId: string;
  campaignName: string;
  campaignType: string | null;
}

export interface KeywordRow extends AdsRowBase {
  targeting: string;     // keyword / targeting text (the real keyword grain in FACT_AMAZON_ADS)
  matchType: string;     // targeting_type (BROAD / PHRASE / EXACT / auto…)
  bid: number | null;    // latest set bid joined on text+match, null when unknown
}

export interface SearchTermRow extends AdsRowBase {
  searchTerm: string;
  bid: number | null;    // inherited from the parent keyword
}

export interface StrategyGroup {
  strategy: string;
  spend: number;             // total spend across the group
  campaigns: CampaignRow[];  // sorted by spend desc
}

export const UNASSIGNED = 'Unassigned';

/** Reduce an experiment name to its base strategy. Experiment names follow
 * "<Product> - <Strategy> (<qualifier>)"; we drop the leading product prefix (first " - ")
 * AND the trailing " (qualifier)" so variants collapse into one group
 * (e.g. "LolliME - Broad Hunter (10yo)" → "Broad Hunter"). */
export function strategyLabel(experimentName: string): string {
  const i = experimentName.indexOf(' - ');
  const afterProduct = i >= 0 ? experimentName.slice(i + 3) : experimentName;
  const p = afterProduct.indexOf(' (');
  const base = p >= 0 ? afterProduct.slice(0, p) : afterProduct;
  return base.trim();
}

/**
 * Group campaigns by their assigned strategy (from the campaign→experiment map).
 * Campaigns with no mapping fall under `Unassigned`. Strategies are ordered by
 * total spend desc; campaigns within each strategy by spend desc.
 */
export function groupByStrategy(
  campaigns: CampaignRow[],
  strategyMap: Record<string, string>,
): StrategyGroup[] {
  const byStrategy = new Map<string, CampaignRow[]>();
  for (const c of campaigns) {
    const strat = strategyMap[c.campaignId] || UNASSIGNED;
    const list = byStrategy.get(strat);
    if (list) list.push(c);
    else byStrategy.set(strat, [c]);
  }
  const groups: StrategyGroup[] = [];
  for (const [strategy, list] of byStrategy) {
    list.sort((a, b) => b.spend - a.spend);
    groups.push({ strategy, spend: list.reduce((s, c) => s + c.spend, 0), campaigns: list });
  }
  groups.sort((a, b) => b.spend - a.spend);
  return groups;
}
