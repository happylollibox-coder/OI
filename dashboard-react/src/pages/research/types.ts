// Shared types for the Research page (pages/research/*).
// Scoring semantics live in SQL (V_RESEARCH_RANKED) — see architecture/RESEARCH_PAGE.md.

export interface ResearchRow {
  query_text: string;
  match_type: 'direct' | 'related';
  asin_overlap: number;
  total_seed_asins: number;
  overlap_pct: number | null;
  weeks_appeared: number;
  market_impressions: number;
  market_clicks: number;
  market_purchases: number;
  market_cvr_pct: number | null;
  brand_impressions: number;
  brand_clicks: number;
  brand_purchases: number;
  brand_sales: number;
  show_rate_pct: number | null;
  median_click_price: number | null;
  cost_tier: string | null;
  gender: string | null;
  age_group: string | null;
  occasion: string | null;
  holiday: string | null;
  cpc_12m: number | null;
  cpc_30d: number | null;
  product_type: string | null;
  is_brand_term: boolean;
  brand: string | null;
  units_cvr_30d: number | null;
  units_cvr_12m: number | null;
  ads_family_orders: number;
  ads_units_30d: number | null;
  ads_units_12m: number | null;
  roas_30d: number | null;
  // Seasonal CVR (18-month lookback per holiday window)
  cvr_christmas: number | null;
  cvr_easter: number | null;
  cvr_valentines: number | null;
  cvr_graduation: number | null;
  cvr_back_to_school: number | null;
  cvr_mothers_day: number | null;
  // Family-specific SQP data
  family_purchases: number;
  family_clicks: number;
  family_impressions: number;
  // Weekly (last week) market data
  last_week: string | null;
  weekly_market_impressions: number;
  weekly_market_clicks: number;
  weekly_market_purchases: number;
  weekly_market_cvr_pct: number | null;
  clicks_median: number | null;
  // Pre-computed scores from V_RESEARCH_RANKED
  seg_fit: number | null;
  cps_fit: number | null;
  overall_fit: number | null;
  purchase_rank_score: number | null;
  rank_score: number | null;
  ads_purch: number | null;
  ads_cps: number | null;
  est_cps: number | null;
  // Explanation columns (SQL-computed; tooltips format these)
  gender_score: number | null;
  age_score: number | null;
  occasion_score: number | null;
  pt_score: number | null;
  cps_source: 'ads_30d' | 'ads_12m' | 'curve' | null;
  effective_cps: number | null;
  price_bucket: string | null;
  est_cps_curve: number | null;
  intent_factor: number | null;
  is_holiday_active: boolean | null;
}

export interface ConversionCurveRow {
  parent_name: string;
  price_bucket: string;
  price_ratio_low: number;
  price_ratio_high: number;
  holiday_name: string;
  clicks_per_sale: number | null;
  cvr_pct: number | null;
  cost_per_sale: number | null;
  avg_cpc: number | null;
}

export type SortKey = keyof ResearchRow | 'est_clicks_per_sale' | 'match_rank' | 'purchase_rank' | 'rank';
export type SortDir = 'asc' | 'desc';

export interface ProductInfo {
  name: string;
  price: number;
  product_count: number;
  ads_profit: number;
  ads_units: number;
  ads_cps: number | null;
}

export interface FamilyProduct {
  parent_name: string;
  asin: string;
  product_short_name: string;
  product_type: string;
  variant: string;
  current_price: number | null;
  segments: {
    gender: string | null;
    age_group: string | null;
    occasion: string | null;
    product_type: string | null;
  };
}

export interface FamilySummary {
  parent_name: string;
  product_count: number;
  product_types: string[];
  min_price: number | null;
  max_price: number | null;
  avg_price: number | null;
  avg_cogs: number | null;
  avg_referral_fee: number | null;
  avg_fba_fee: number | null;
  avg_shipping_cost: number | null;
  avg_total_cost: number | null;
  gross_profit_per_unit: number | null;
  segments: {
    gender: string | null;
    age_group: string | null;
    occasion: string | null;
    product_type: string | null;
  };
}

export interface FamilyInfo {
  summary: FamilySummary;
  products: FamilyProduct[];
}

export interface SegmentReason {
  value: string;
  pct: number;
  orders: number;
  clicks_per_sale: number | null;
}

/** Parent-level reasoning keyed by segment type, plus per-ASIN breakdown. */
export type SegmentReasoning = Record<string, SegmentReason[]> & {
  by_asin?: Record<string, Record<string, SegmentReason[]>>;
};

export interface TermRank {
  parent_name: string;
  rank: number | null;
  purchase_rank: number | null;
  overall_fit: number | null;
  seg_fit: number | null;
  cps_fit: number | null;
  ads_cps: number | null;
  est_cps: number | null;
}

export type TermRanksMap = Record<string, TermRank[]>;

export const SEASONS = [
  { key: '_ALL', label: 'All Year' },
  { key: 'Off-Season', label: 'Off-Season' },
  { key: 'Christmas', label: '🎄 Christmas' },
  { key: 'Easter', label: '🐰 Easter' },
  { key: 'Valentines Day', label: '💝 Valentines' },
];
