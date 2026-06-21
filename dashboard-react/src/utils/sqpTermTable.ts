import type { SqpAdsByTermRow } from '../types';

export interface SqpTermAgg {
  term: string;
  impressions: number;
  clicks: number;
  cart_adds: number;
  orders: number;
  organic_orders: number;
  market_vol: number;        // SUM over weeks of per-week MAX(amazon_impressions)
  amazon_orders: number;     // SUM over weeks of per-week MAX(amazon_orders)
  ad_impressions: number;
  ad_clicks: number;
  ad_orders: number;
  ad_units: number;
  ad_spend: number;
  ad_sales: number;
  ad_gross_profit: number;
  ctr: number | null;        // %
  cvr: number | null;        // %
  impr_share: number | null; // %
  cpc: number | null;
  acos: number | null;       // %
  net_roas: number | null;
  est_rank: number | null;
  zone: string | null;
  asins: string[];
  rows: SqpAdsByTermRow[];
}

const pct = (num: number, den: number): number | null => (den > 0 ? (num / den) * 100 : null);

export function rollupSqpTerms(rows: SqpAdsByTermRow[]): SqpTermAgg[] {
  // Step 1: collapse to (term_key, week): MAX amazon across ASINs, SUM everything else.
  type WeekAcc = {
    term: string; week: string;
    impressions: number; clicks: number; cart_adds: number; orders: number; organic_orders: number;
    amazon_impressions: number; amazon_orders: number;
    ad_impressions: number; ad_clicks: number; ad_orders: number; ad_units: number;
    ad_spend: number; ad_sales: number; ad_gross_profit: number;
    dominant_impr: number; est_rank: number | null; zone: string | null;
  };
  const byWeek = new Map<string, WeekAcc>();
  for (const r of rows) {
    const term = (r.search_term || '').trim();
    if (!term) continue;
    const key = `${term.toLowerCase()}__${r.reporting_date}`;
    let w = byWeek.get(key);
    if (!w) {
      w = { term, week: r.reporting_date,
        impressions: 0, clicks: 0, cart_adds: 0, orders: 0, organic_orders: 0,
        amazon_impressions: 0, amazon_orders: 0,
        ad_impressions: 0, ad_clicks: 0, ad_orders: 0, ad_units: 0,
        ad_spend: 0, ad_sales: 0, ad_gross_profit: 0,
        dominant_impr: -1, est_rank: null, zone: null };
      byWeek.set(key, w);
    }
    w.impressions += r.impressions;
    w.clicks += r.clicks;
    w.cart_adds += r.cart_adds;
    w.orders += r.orders;
    w.organic_orders += r.organic_orders;
    w.amazon_impressions = Math.max(w.amazon_impressions, r.amazon_impressions ?? 0);
    w.amazon_orders = Math.max(w.amazon_orders, r.amazon_orders ?? 0);
    w.ad_impressions += r.ad_impressions;
    w.ad_clicks += r.ad_clicks;
    w.ad_orders += r.ad_orders;
    w.ad_units += r.ad_units;
    w.ad_spend += r.ad_spend;
    w.ad_sales += r.ad_sales;
    w.ad_gross_profit += r.ad_gross_profit;
    // dominant ASIN within the week carries the rank/zone
    if (r.impressions > w.dominant_impr) {
      w.dominant_impr = r.impressions;
      w.est_rank = r.estimated_organic_rank;
      w.zone = r.organic_rank_zone;
    }
  }

  // Step 2: roll weeks up to (term): SUM across weeks (incl. the per-week amazon).
  type TermAcc = Omit<SqpTermAgg, 'ctr'|'cvr'|'impr_share'|'cpc'|'acos'|'net_roas'> & { latestWeek: string };
  const byTerm = new Map<string, TermAcc>();
  const asinsByTerm = new Map<string, Set<string>>();
  for (const r of rows) {
    const t = (r.search_term || '').trim().toLowerCase();
    if (!t) continue;
    if (!asinsByTerm.has(t)) asinsByTerm.set(t, new Set());
    if (r.asin) asinsByTerm.get(t)!.add(r.asin);
  }
  for (const w of byWeek.values()) {
    const t = w.term.toLowerCase();
    let a = byTerm.get(t);
    if (!a) {
      a = { term: w.term,
        impressions: 0, clicks: 0, cart_adds: 0, orders: 0, organic_orders: 0,
        market_vol: 0, amazon_orders: 0,
        ad_impressions: 0, ad_clicks: 0, ad_orders: 0, ad_units: 0,
        ad_spend: 0, ad_sales: 0, ad_gross_profit: 0,
        est_rank: null, zone: null, asins: Array.from(asinsByTerm.get(t) ?? []),
        rows: rows.filter(r => (r.search_term || '').trim().toLowerCase() === t),
        latestWeek: '' };
      byTerm.set(t, a);
    }
    a.impressions += w.impressions;
    a.clicks += w.clicks;
    a.cart_adds += w.cart_adds;
    a.orders += w.orders;
    a.organic_orders += w.organic_orders;
    a.market_vol += w.amazon_impressions;
    a.amazon_orders += w.amazon_orders;
    a.ad_impressions += w.ad_impressions;
    a.ad_clicks += w.ad_clicks;
    a.ad_orders += w.ad_orders;
    a.ad_units += w.ad_units;
    a.ad_spend += w.ad_spend;
    a.ad_sales += w.ad_sales;
    a.ad_gross_profit += w.ad_gross_profit;
    if (w.week >= a.latestWeek) { a.latestWeek = w.week; a.est_rank = w.est_rank; a.zone = w.zone; }
  }

  // Derived metrics from totals.
  return Array.from(byTerm.values()).map(a => ({
    term: a.term,
    impressions: a.impressions, clicks: a.clicks, cart_adds: a.cart_adds,
    orders: a.orders, organic_orders: a.organic_orders,
    market_vol: a.market_vol, amazon_orders: a.amazon_orders,
    ad_impressions: a.ad_impressions, ad_clicks: a.ad_clicks, ad_orders: a.ad_orders,
    ad_units: a.ad_units, ad_spend: a.ad_spend, ad_sales: a.ad_sales, ad_gross_profit: a.ad_gross_profit,
    ctr: pct(a.clicks, a.impressions),
    cvr: pct(a.orders, a.clicks),
    impr_share: pct(a.impressions, a.market_vol),
    cpc: a.ad_clicks > 0 ? a.ad_spend / a.ad_clicks : null,
    acos: pct(a.ad_spend, a.ad_sales),
    net_roas: a.ad_spend > 0 ? a.ad_gross_profit / a.ad_spend : null,
    est_rank: a.est_rank, zone: a.zone,
    asins: a.asins, rows: a.rows,
  }));
}
