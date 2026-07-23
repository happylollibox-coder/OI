// Pure logic for the Ads-page KPI panel. No React, no I/O — unit-tested.
// The panel is Cube-backed: two per-product fetches (Ads cube + UnifiedPerformance)
// for a chosen date range; this module turns those rows into display metrics.

/** One product's ad-attributed metrics (Ads cube, grouped by Product dims). */
export interface AdsKpiProductRow {
  parentName: string;        // Product.parentName — canonical family
  asin: string;              // Product.asin
  productShortName: string;
  spend: number;
  sales: number;             // ad-attributed sales
  orders: number;
  clicks: number;
  impressions: number;
  grossProfit: number;       // ad-attributed sales − cogs
}

/** One product's total/unit-economics metrics (UnifiedPerformance, grouped by product). */
export interface UnifiedKpiProductRow {
  family: string;
  asin: string;
  productShortName: string;
  sales: number;             // total sales (ads + organic)
  adCost: number;
  grossMargin: number;       // total sales − cogs (summable)
  units: number;
}

/** Current selection from the global filters. `product` is an ASIN. */
export interface KpiSelection {
  family: string | null;
  product: string | null;
}

export interface AdsKpis {
  // Volume (ad-attributed)
  spend: number;
  sales: number;
  orders: number;
  clicks: number;
  impressions: number;
  // Efficiency
  roas: number;
  acos: number;              // %
  cpc: number;
  cvr: number;               // %
  ctr: number;               // %
  spendSharePct: number;     // % of all-products ad spend
  tacos: number;             // %
  // Profit
  netProfit: number;         // ad-attributed (Ads cube)
  netRoas: number;
  totalNetProfit: number;    // total business (total sales − cogs − ad spend)
  units: number;             // total units sold (ads + organic)
  profitPerUnit: number;
  ppcPerUnit: number;
  // Highlight
  bestChild: { name: string; netProfit: number } | null;
}

const div = (n: number, d: number): number => (d > 0 ? n / d : 0);

/** Rows matching the selection. Family/product null ⇒ no constraint on that axis. */
function selectAds(rows: AdsKpiProductRow[], sel: KpiSelection): AdsKpiProductRow[] {
  return rows.filter(r =>
    (!sel.family || r.parentName === sel.family) &&
    (!sel.product || r.asin === sel.product));
}
function selectUnified(rows: UnifiedKpiProductRow[], sel: KpiSelection): UnifiedKpiProductRow[] {
  return rows.filter(r =>
    (!sel.family || r.family === sel.family) &&
    (!sel.product || r.asin === sel.product));
}

export function computeKpis(
  ads: AdsKpiProductRow[],
  unified: UnifiedKpiProductRow[],
  sel: KpiSelection,
): AdsKpis {
  const selAds = selectAds(ads, sel);
  const spend = selAds.reduce((s, r) => s + r.spend, 0);
  const sales = selAds.reduce((s, r) => s + r.sales, 0);
  const orders = selAds.reduce((s, r) => s + r.orders, 0);
  const clicks = selAds.reduce((s, r) => s + r.clicks, 0);
  const impressions = selAds.reduce((s, r) => s + r.impressions, 0);
  const grossProfit = selAds.reduce((s, r) => s + r.grossProfit, 0);
  const netProfit = grossProfit - spend;

  const allSpend = ads.reduce((s, r) => s + r.spend, 0);

  const selUni = selectUnified(unified, sel);
  const uSales = selUni.reduce((s, r) => s + r.sales, 0);
  const uAdCost = selUni.reduce((s, r) => s + r.adCost, 0);
  const uGrossMargin = selUni.reduce((s, r) => s + r.grossMargin, 0);
  const uUnits = selUni.reduce((s, r) => s + r.units, 0);

  let bestChild: { name: string; netProfit: number } | null = null;
  for (const r of selUni) {
    const np = r.grossMargin - r.adCost;
    if (!bestChild || np > bestChild.netProfit) {
      bestChild = { name: r.productShortName || r.asin, netProfit: np };
    }
  }

  return {
    spend, sales, orders, clicks, impressions,
    roas: div(sales, spend),
    acos: div(spend, sales) * 100,
    cpc: div(spend, clicks),
    cvr: div(orders, clicks) * 100,
    ctr: div(clicks, impressions) * 100,
    spendSharePct: div(spend, allSpend) * 100,
    tacos: div(uAdCost, uSales) * 100,
    netProfit,
    netRoas: div(netProfit, spend),
    totalNetProfit: uGrossMargin - uAdCost,
    units: uUnits,
    profitPerUnit: div(uGrossMargin - uAdCost, uUnits),
    ppcPerUnit: div(uAdCost, uUnits),
    bestChild,
  };
}

/** Inclusive day count for a `[startISO, endISO]` range. Clamped to a minimum of 1. */
export function daysInRange(startISO: string, endISO: string): number {
  const s = Date.parse(startISO + 'T00:00:00Z');
  const e = Date.parse(endISO + 'T00:00:00Z');
  if (Number.isNaN(s) || Number.isNaN(e)) return 1;
  return Math.max(1, Math.round((e - s) / 86_400_000) + 1);
}

/**
 * Convert window totals to per-day averages: divide the additive flow metrics
 * (spend/sales/orders/clicks/impressions/net profit) by `days`, leaving rate and
 * per-unit metrics (ROAS, ACOS, CPC, CVR, CTR, %Spend, per-unit) unchanged.
 */
export function applyDailyAverage(k: AdsKpis, days: number): AdsKpis {
  const d = Math.max(1, days);
  return {
    ...k,
    spend: k.spend / d,
    sales: k.sales / d,
    orders: k.orders / d,
    clicks: k.clicks / d,
    impressions: k.impressions / d,
    netProfit: k.netProfit / d,
    totalNetProfit: k.totalNetProfit / d,
    units: k.units / d,
    bestChild: k.bestChild ? { ...k.bestChild, netProfit: k.bestChild.netProfit / d } : null,
  };
}

/** 'lifetime' is offered by the Strategy page only — it means "no window", i.e. every day on record. */
export type DateRangePreset = 'lifetime' | 'yesterday' | '7d' | '30d' | 'custom';

const iso = (d: Date): string => d.toISOString().slice(0, 10);
const addDays = (d: Date, n: number): Date => {
  const x = new Date(d);
  x.setUTCDate(x.getUTCDate() + n);
  return x;
};

/**
 * Resolve a preset to a `[startISO, endISO]` pair. `today` is injected for testability.
 * Ranges end at yesterday because ads data lags 1–2 days.
 */
export function resolveDateRange(
  preset: DateRangePreset,
  today: Date,
  customStart?: string,
  customEnd?: string,
): [string, string] {
  const yesterday = iso(addDays(today, -1));
  switch (preset) {
    case 'lifetime':
      // Far enough back to precede any Amazon Ads history we hold. Consumers that can answer
      // "lifetime" from pre-aggregated rows should short-circuit rather than query this range.
      return ['2000-01-01', yesterday];
    case 'yesterday':
      return [yesterday, yesterday];
    case '7d':
      return [iso(addDays(today, -7)), yesterday];
    case '30d':
      return [iso(addDays(today, -30)), yesterday];
    case 'custom':
      return [customStart || yesterday, customEnd || yesterday];
  }
}
