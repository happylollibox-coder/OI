export interface SummaryRow {
  product_type: string;
  sales_7d: number;
  ad_cost_7d: number;
  cogs_7d: number;
  net_profit_7d: number;
  orders_7d: number;
  organic_units_7d: number;
  ad_orders_7d: number;
  clicks_7d: number;
  sessions_7d: number;
  organic_pct: number;
  net_roas: number;
  sales_prev_7d: number;
  ad_cost_prev_7d: number;
  cogs_prev_7d: number;
  net_profit_prev_7d: number;
  orders_prev_7d: number;
  organic_units_prev_7d: number;
  net_roas_prev: number;
  organic_pct_prev: number;
  sales_change_pct: number;
  cost_change_pct: number;
  period_start: string;
  period_end: string;
}

export interface ActionRow {
  search_term: string;
  product_short_name: string;
  experiment_id: string;
  strategy_id: string;
  campaign_id: string;
  ad_group_id: string;
  campaign_name: string;
  portfolio_name: string;
  asin: string;
  hero_asin: string;
  is_hero_match: boolean;

  action: string;
  reason: string;
  priority_score: number;
  ads_signal: string;

  spend: number;
  orders: number;
  clicks: number;
  ads_clicks_recent: number;
  cpc: number;
  conv_rate: number;
  net_roas: number;
  market_volume: number;
  impression_share: number;
  margin_per_unit: number;

  // Target keyword (dual-grain)
  targeting: string | null;
  keyword_id: string | null;
  target_action: string | null;
  effective_roas: number | null;
  weighted_total_net_roas: number | null;
  target_net_roas_8w: number | null;
  target_clicks_8w: number | null;
  target_orders_8w: number | null;
  target_spend_8w: number | null;
  current_bid: number | null;
  recommended_bid: number | null;
  match_type: string | null;

  // Hero & action explanation
  hero_product_name: string | null;
  hero_action: string | null;
  hero_action_explanation: string | null;
  hero_net_roas: number | null;
  hero_total_orders: number | null;
  hero_ads_ctr_pct: number | null;
  negate_as: string | null;
  action_explanation: string | null;
  weighted_total_net_roas_dim: number | null;
  sqp_search_volume: number;
  sqp_organic_rank: number | null;
  is_top_of_page_organic: boolean;
  decision_trace: DecisionStep[] | null;
}

/** A single step in the backend-computed decision trace */
export interface DecisionStep {
  id: string;
  label: string;
  rule: string;
  pass: boolean;
  value: string;
}

/** A 3-day rapid-reaction ads alert */
export interface HotSignalRow {
  hot_signal: 'URGENT_STOP' | 'HOT_WINNER' | 'RAPID_DECLINE';
  hot_signal_reason: string;
  search_term: string;
  asin: string;
  product_short_name: string;
  parent_name: string;
  experiment_id: string;
  experiment_name: string;
  strategy_id: string;
  strategy_name: string;
  campaign_id: string;
  campaign_name: string;
  campaign_type: string;
  ad_group_id: string;
  spend_3d: number;
  orders_3d: number;
  clicks_3d: number;
  impressions_3d: number;
  cpc_3d: number | null;
  cvr_3d: number | null;
  ads_roas_3d: number | null;
  net_profit_3d: number | null;
  margin_per_unit: number;
  coach_8w_action: string | null;
  coach_8w_roas: number | null;
  coach_8w_signal: string | null;
  priority_score: number;
  sqp_search_volume_4w: number;
  sqp_organic_rank: number | null;
  days_with_data: number;
}

export interface StrategicPrediction {
  search_term: string;
  asin: string;
  product_short_name: string;
  strategic_signal: string;
  predicted_net_roas: number;
  prediction_confidence: number;
  lifetime_net_roas: number;
  // 6 factors
  seasonality_multiplier: number;
  has_seasonal_data: boolean;
  best_season_month: number | null;
  best_season_month_cvr: number | null;
  hero_product_name: string | null;
  peak_multiplier: number;
  peak_description: string;
  cpc_inflation_ratio: number;
  predicted_cpc: number;
  tos_cvr_boost: number;
  organic_halo_multiplier: number;
  organic_weekly_velocity: number;
  // Baseline
  base_cvr: number;
  base_cpc: number;
  total_clicks: number;
  total_orders: number;
  total_spend: number;
  days_with_data: number;
}
export interface UpcomingEvent {
  holiday_name: string;
  holiday_date: string;
  status: string;
  days_until_holiday: number;
  category: string;
  pre_season_start: string;
  days_until_pre_season: number;
}

export interface PeakRow {
  holiday_name: string;
  holiday_date: string;
  peak_start: string;
  peak_end: string;
  readiness_start: string;
  pre_peak_start: string;
  boost_start: string;
  current_stage: string;
  days_until_peak_start: number;
}

export interface HolidayRow {
  holiday_name: string;
  holiday_date: string;
  pre_season_start: string;
  category: string;
  ramp_up_days?: number;
}

export interface ProductRow {
  asin: string;
  product_short_name: string;
  product_type: string;
  cogs: number;
  shipping_cost: number;
  fba_cost: number;
  total_cost_per_unit: number;
  pick_pack_fee: number;
  referral_fee: number;
}

export interface HeroAsin {
  asin: string;
  search_term?: string;
  parent_name?: string;
  product_short_name: string;
  product_type: string;
  hero_rank?: number;
  sqp_cvr_pct?: number;
  sqp_ctr_pct?: number;
  sqp_impressions?: number;
  sqp_clicks?: number;
  sqp_conversions?: number;
  ads_spend?: number;
  ads_orders?: number;
  ads_clicks?: number;
  ads_net_roas?: number;
  blended_cvr_pct?: number;
  margin_per_unit?: number;
  market_purchases?: number;
  reason?: string;
}

export interface KeywordMapRow {
  search_term: string;
  experiment_id?: string;
  product_short_name: string;
  hero_asin: string;
  is_hero_match: boolean;
  spend_60d: number;
  orders_60d: number;
  clicks_60d?: number;
  impressions_60d?: number;
  cpc_60d?: number;
  conv_rate_60d: number;
  net_roas_60d: number;
  market_volume: number;
  impression_share: number;
  action: string;
  reason?: string;
}

export interface TrendRow {
  product_type: string;
  week_start?: string;
  month_start?: string;
  sales: number;
  orders: number;
  units?: number;
  ad_cost: number;
  cogs: number;
  net_profit: number;
  clicks?: number;
  sessions?: number;
  net_roas: number;
  organic_pct?: number;
  tacos?: number;
  np_per_unit?: number;
}

export interface TrendRowByAsin extends TrendRow {
  asin: string;
  product_short_name: string;
}

export interface LearningRow {
  learning_dimension: string;
  [key: string]: string | number;
}

export interface ExperimentRow {
  row_key?: string;
  experiment_id: string;
  experiment_name: string;
  description?: string;
  strategy_id: string;
  status: string;
  start_date?: string;
  end_date?: string;
  running_days?: number;
  days_running?: number;
  days_active?: number;
  baseline_days?: number;
  total_ad_spend: number;
  total_orders: number;
  net_roas: number;
  organic_lift_pct: number;
  action_signal?: string;
  verdict?: string;
  tracked_search_terms?: number;
  terms_positive_organic_lift?: number;
  terms_negative_organic_lift?: number;
  terms_neutral?: number;
  search_avg_organic_lift_pct?: number;
  search_ads_roas?: number;
  search_baseline_amazon_total_orders?: number;
  search_experiment_amazon_total_orders?: number;
  tracked_asins?: number;
  performance_baseline_total_orders?: number;
  performance_experiment_total_orders?: number;
  performance_baseline_organic_units?: number;
  performance_experiment_organic_units?: number;
  performance_baseline_total_sales?: number;
  performance_experiment_total_sales?: number;
  performance_total_orders_lift_pct?: number;
  performance_organic_units_lift_pct?: number;
  performance_sessions_lift_pct?: number;
  ads_total_spend?: number;
  ads_total_revenue?: number;
  ads_avg_roas?: number;
  total_avg_roas?: number;
  performance_total_gross_profit?: number;
  search_bl_impressions_share_pct?: number;
  search_bl_clicks_share_pct?: number;
  search_bl_orders_share_pct?: number;
  search_bl_conversion_rate_pct?: number;
  search_bl_ctr_pct?: number;
  search_exp_impressions_share_pct?: number;
  search_exp_clicks_share_pct?: number;
  search_exp_orders_share_pct?: number;
  search_exp_conversion_rate_pct?: number;
  search_exp_ctr_pct?: number;
  search_impressions_share_delta_pp?: number;
  search_clicks_share_delta_pp?: number;
  search_orders_share_delta_pp?: number;
  search_conversion_rate_delta_pp?: number;
  search_ctr_delta_pp?: number;
  organic_verdict?: string;
}

export interface BudgetHealthRow {
  experiment_id: string;
  budget_utilization_pct: number;
  action_signal?: string;
}

export interface DriverRow {
  search_term: string;
  product_short_name: string;
  product_type: string;
  experiment_id?: string;
  spend: number;
  orders: number;
  clicks?: number;
  cpc?: number;
  conv_rate: number;
  net_roas: number;
  margin_per_unit?: number;
  impression_share?: number;
  action: string;
}

export interface ChangeLogRow {
  change_date?: string;
  created_at?: string;
  experiment_id: string;
  change_type: string;
  field_changed: string;
  old_value: string;
  new_value: string;
  reason: string;
}

export interface NegativeKeyword {
  campaign_name: string;
  negative_keyword: string;
  spend_30d: number;
}

export interface ExperimentWeeklyRow {
  experiment_id: string;
  experiment_name: string;
  strategy_id: string;
  week_start: string;
  sales: number;
  ads_spend: number;
  total_orders: number;
  ads_orders: number;
  organic_units: number;
  sessions: number;
  conv_rate: number;
  net_roas: number;
  organic_pct: number;
}

export interface GroundTruth {
  id: string;
  experiment_id: string;
  experiment_name: string;
  metric: string;
  op: string;
  ref: string;
  source_week: string;
  description: string;
  approved_at: string;
  keyword?: string;
}

export interface BusinessConclusion {
  id: string;
  conclusion: string;
  evidence: string;
  recommendation?: string;
  family?: string;
  experiment_id?: string;
  impact: 'scale' | 'reduce' | 'adjust' | 'test';
  status: 'active' | 'archived' | 'approved';
  created_at: string;
  tags: string[];
}

export interface SqpWeeklyRow {
  product_type: string;
  asin: string;
  product_short_name: string;
  week_start: string;
  search_term: string;
  impressions: number;
  clicks: number;
  cart_adds: number;
  orders: number;
  amazon_impressions: number;
  amazon_clicks: number;
  amazon_orders: number;
  ads_impressions: number;
  ads_clicks: number;
  ads_orders: number;
  show_rate_pct: number;
  estimated_organic_rank: number;
  organic_rank_zone: string;
  search_query_score: number;
}

export interface ExperimentCampaignRow {
  experiment_id: string | null;
  campaign_id: string;
  campaign_name: string;
  campaign_type: string;
  top_of_search_pct: number | null;
  product_page_pct: number | null;
  rest_of_search_pct: number | null;
  notes: string | null;
  spend: number;
  orders: number;
  clicks: number;
  impressions: number;
  first_date: string | null;
  last_date: string | null;
}

export interface CampaignSearchTermRow {
  campaign_id: string;
  search_term: string;
  spend: number;
  orders: number;
  clicks: number;
  impressions: number;
  conv_rate: number;
  cpc: number;
}

export interface Ads7dRow {
  row_type: 'campaign' | 'search_term';
  /** Report date (YYYY-MM-DD). Used for month/year filtering. */
  date?: string;
  week_start?: string;
  campaign_id: string;
  campaign_name: string;
  campaign_type: string | null;
  /** Amazon portfolio name (from campaign_history join). Use this for portfolio grouping instead of campaign_name. */
  portfolio_name?: string | null;
  /** Product from DIM_PRODUCT via most_advertised_asin (ads_7d query). */
  product_short_name?: string | null;
  /** Parent product / collection from DIM_PRODUCT. */
  parent_name?: string | null;
  search_term: string | null;
  spend: number;
  orders: number;
  clicks: number;
  impressions: number;
  sales: number;
  cogs?: number;
  gross_profit: number | null;
  cpc: number;
  conv_rate: number;
  roas: number;
  /** Sales ÷ Spend (Ads ROAS). From backend or computed in frontend. */
  gross_roas?: number;
  search_terms_count: number | null;
  /** Aggregated metrics for coach/signals */
  spend_4w?: number;
  orders_4w?: number;
  clicks_4w?: number;
  sales_4w?: number;
  cogs_4w?: number;
  roas_4w?: number;
  conv_rate_4w?: number;
  spend_ly_peak?: number;
  orders_ly_peak?: number;
  sales_ly_peak?: number;
  roas_ly_peak?: number;
  sqp_volume_ly_peak?: number;
  sqp_orders_ly_peak?: number;
  sqp_organic_units?: number;
  sqp_organic_pct?: number;
  /** Best product by revenue for the last 4 weeks (to support SWITCH_HERO signal) */
  best_product_by_revenue_4w?: string;
}

export interface ExperimentTemplateRow {
  strategy_id: string;
  experiment_id: string;
  experiment_name: string;
  description: string | null;
  status: string;
  start_date: string | null;
  end_date: string | null;
  baseline_days: number | null;
  outcome_score: number | null;
  outcome_tags: string | null;
  outcome_notes: string | null;
  lifecycle_stage: string | null;
  graduation_confidence: string | null;
  season_context: string | null;
  days_running: number;
  total_spend: number | null;
  total_orders: number | null;
  total_clicks: number | null;
  total_impressions: number | null;
  total_sales: number | null;
  net_roas: number | null;
  conv_rate: number | null;
  cpc: number | null;
  unique_search_terms: number | null;
}

export interface CoachDecisionRow {
  search_term: string;
  best_asin: string;
  product_short_name: string;
  parent_name: string;
  margin_per_unit: number;
  // Ads 4w
  campaign_count_4w: number;
  selling_campaigns_4w: number;
  ads_spend_4w: number;
  ads_orders_4w: number;
  ads_units_4w: number;
  ads_clicks_4w: number;
  ads_impressions_4w: number;
  ads_sales_4w: number;
  ads_cpc_4w: number | null;
  ads_cvr_pct_4w: number | null;
  ads_cost_per_order_4w: number | null;
  ads_net_roas_4w: number;
  ads_net_profit_4w: number;
  // Ads Lifetime
  ads_spend_lifetime: number;
  ads_orders_lifetime: number;
  ads_net_roas_lifetime: number;
  // 7d activity (stale-action detection)
  ads_impressions_7d: number;
  ads_spend_7d: number;
  ads_active_last_7d: boolean;
  // Ads LY Peak
  ads_spend_ly_peak: number;
  ads_orders_ly_peak: number;
  ads_units_ly_peak: number;
  ads_clicks_ly_peak: number;
  ads_impressions_ly_peak: number;
  ads_sales_ly_peak: number;
  ads_cpc_ly_peak: number | null;
  ads_cvr_pct_ly_peak: number | null;
  ads_net_roas_ly_peak: number | null;
  // SQP 4w Your ASIN
  sqp_impressions_4w: number;
  sqp_clicks_4w: number;
  sqp_cart_adds_4w: number;
  sqp_orders_4w: number;
  sqp_sales_4w: number;
  sqp_organic_units_4w: number;
  sqp_show_rate_4w: number;
  sqp_impression_share_4w: number;
  sqp_organic_rank_4w: number;
  // SQP 4w Amazon market
  sqp_amazon_impressions_4w: number;
  sqp_amazon_clicks_4w: number;
  sqp_amazon_cart_adds_4w: number;
  sqp_amazon_orders_4w: number;
  sqp_amazon_search_volume_4w: number;
  // SQP LY Peak Your ASIN
  sqp_impressions_ly_peak: number;
  sqp_clicks_ly_peak: number;
  sqp_cart_adds_ly_peak: number;
  sqp_orders_ly_peak: number;
  sqp_sales_ly_peak: number;
  sqp_show_rate_ly_peak: number;
  sqp_impression_share_ly_peak: number;
  sqp_organic_rank_ly_peak: number;
  // SQP LY Peak Amazon market
  sqp_amazon_impressions_ly_peak: number;
  sqp_amazon_clicks_ly_peak: number;
  sqp_amazon_cart_adds_ly_peak: number;
  sqp_amazon_orders_ly_peak: number;
  sqp_amazon_search_volume_ly_peak: number;
  // Decision
  signal: string;
  decision: string;
  priority_score: number;
  confidence: string;
  reason: string;
}

export interface CoachTermRow {
  campaign_id: string;
  campaign_name: string;
  campaign_type: string;
  search_term: string;
  asin: string;
  product_short_name: string;
  parent_name: string;
  experiment_name: string | null;
  strategy_id: string | null;
  strategy_name: string | null;
  ads_spend_4w: number;
  ads_orders_4w: number;
  ads_clicks_4w: number;
  ads_sales_4w: number;
  ads_cpc_4w: number | null;
  ads_cvr_pct_4w: number | null;
  ads_net_roas_4w: number;
  ads_net_profit_4w: number;
  margin_per_unit: number;
  term_spend_4w: number;
  term_orders_4w: number;
  term_campaign_count: number;
  term_selling_campaigns: number;
  spend_share_pct: number | null;
  orders_share_pct: number | null;
  sqp_orders_4w: number;
  // Target keyword (dual-grain)
  targeting: string | null;
  keyword_id: string | null;
  target_action: string | null;
  effective_roas: number | null;
  weighted_total_net_roas: number | null;
  target_net_roas_8w: number | null;
  target_clicks_8w: number | null;
  target_orders_8w: number | null;
  target_spend_8w: number | null;
  target_decision_trace: DecisionStep[] | null;
  recommendation_object: 'TARGET' | 'TERM';
  current_bid: number | null;
  recommended_bid: number | null;
  bid_change_pct: number | null;
  match_type: string | null;
  action: string;
  priority_score: number;
  confidence: string;
  reason: string;
  // Hero ASIN
  hero_asin: string | null;
  hero_product_name: string | null;
  is_hero_match: boolean;
  hero_action: string | null;
  hero_action_explanation: string | null;
  hero_net_roas: number | null;
  hero_total_orders: number | null;
}

export interface CoachCampaignRow {
  campaign_id: string;
  campaign_name: string;
  experiment_name: string | null;
  strategy_id: string | null;
  strategy_name: string | null;
  total_terms: number;
  total_spend_4w: number;
  total_orders_4w: number;
  total_net_profit_4w: number;
  campaign_net_roas_4w: number | null;
  campaign_avg_cpc_4w: number | null;
  terms_negate: number;
  terms_reduce: number;
  terms_keep: number;
  terms_scale: number;
  terms_monitor: number;
  spend_on_negate_terms: number;
  campaign_action: string;
  est_weekly_savings: number;
  top_negate_terms: string;
  top_scale_terms: string;
  action_summary: string;
  total_priority_score: number;
  // Hero mismatch
  terms_hero_mismatch: number;
  spend_on_wrong_hero: number;
  // Placement
  placement_action: string;
}

export interface PhraseNegativeRow {
  phrase: string;
  ngram_size: number;
  campaign_id: string;
  ad_group_id: string;
  campaign_name: string;
  campaign_type: string;
  portfolio_name: string;
  phrase_term_count: number;
  phrase_spend_8w: number;
  phrase_orders_8w: number;
  phrase_clicks_8w: number;
  phrase_orders_1y: number;
  phrase_spend_1y: number;
  phrase_sales_1y: number;
  phrase_roas_1y: number;
  top3_months_pct: number;
  peak_months: string;
  seasonal_theme: string;
  action: string;
  priority_score: number;
  reason: string;
}

export interface ExperimentEvaluationRow {
  experiment_id: string;
  experiment_name: string;
  strategy_id: string;
  strategy_name: string;
  status: string;
  experiment_description: string | null;
  strategy_goal: string | null;
  total_spend: number;
  total_orders: number;
  total_sales: number;
  days_with_data: number;
  unique_terms: number;
  converting_terms: number;
  avg_cpc: number | null;
  cvr_pct: number | null;
  gross_roas: number | null;
  wasted_spend: number;
  wasted_pct: number | null;
  terms_graduated_to_exact: number;
  top_converting_terms: string | null;
  top_wasted_terms: string | null;
  check_1_cpc: string;
  check_2_roas: string;
  check_3_data: string;
  check_4_discovery: string;
  check_5_graduated: string;
  check_6_waste: string;
  check_7_cvr: string;
  verdict: string;
  verdict_reason: string;
}

export interface DashboardData {
  summary: SummaryRow[];
  actions: ActionRow[];
  upcoming: UpcomingEvent[];
  peak: PeakRow[];
  products: ProductRow[];
  hero_asins: HeroAsin[];
  keyword_product_map: KeywordMapRow[];
  weekly_trends: TrendRow[];
  monthly_trends: TrendRow[];
  weekly_trends_by_asin: TrendRowByAsin[];
  monthly_trends_by_asin: TrendRowByAsin[];
  learnings: LearningRow[];
  experiments: ExperimentRow[];
  budget_health: BudgetHealthRow[];
  drivers: DriverRow[];
  change_log: ChangeLogRow[];
  negative_keywords: NegativeKeyword[];
  experiment_weekly: ExperimentWeeklyRow[];
  sqp_weekly: SqpWeeklyRow[];
  sqp_coverage_weeks: { week_start: string }[];
  sqp_volume_4w: Record<string, number>;
  experiment_campaigns: ExperimentCampaignRow[];
  campaign_search_terms: CampaignSearchTermRow[];
  ads_7d_summary: Ads7dRow[];
  ads_7d: Ads7dRow[];
  holidays: HolidayRow[];
  experiment_templates: ExperimentTemplateRow[];
  coach_decisions: CoachDecisionRow[];
  coach_terms: CoachTermRow[];
  coach_campaigns: CoachCampaignRow[];
  experiment_evaluations: ExperimentEvaluationRow[];
  keyword_predictions: StrategicPrediction[];
  brand_strength_weekly: BrandStrengthWeeklyRow[];
  coach_phrase_negatives: PhraseNegativeRow[];
  product_creatives: ProductCreativeRow[];
  hot_signals: HotSignalRow[];
  _meta: {
    refreshed_at?: string;
    cube_source?: 'preagg' | 'live';
    queries_run?: number;
    queries_failed?: number;
    failed_queries?: string[];
    date_ranges?: { summary_7d?: { start: string; end: string } };
    data_freshness?: { ads_max_date?: string; performance_max_date?: string };
    files?: Record<string, { status: string; rows?: number; error?: string; source?: string }>;
  };
}

export type PageId = 'home' | 'actions' | 'peak' | 'family' | 'sqp' | 'learn' | 'kwds' | 'log' | 'health' | 'experiment' | 'ads' | 'strategies' | 'admin' | 'do' | 'brand';

export interface BrandStrengthWeeklyRow {
  week_start_date: string;
  brand_keyword: string;
  phrase_type: string | null;
  requested_product: string | null;
  tag: string | null;
  sqp_impressions: number;
  sqp_clicks: number;
  sqp_conversions: number;
  sqp_cart_adds: number;
  avg_show_rate: number | null;
  avg_impression_share: number | null;
  avg_organic_rank: number | null;
  total_search_volume: number;
  brand_asin_count: number;
  ads_impressions: number;
  ads_clicks: number;
  ads_orders: number;
  ads_units: number;
  ads_spend: number;
  ads_sales: number;
  ads_cpc: number | null;
  brand_cvr: number | null;
  brand_dominance_score: number | null;
}
export interface ProductCreativeRow {
  product_family: string;
  brand_entity_id: string;
  brand_name: string;
  video_asset_id: string;
}

export type FamilyName = 'Lollibox' | 'LolliME' | 'Bottle' | 'Fresh';

export const FAMILIES: Record<FamilyName, { code: string; color: string }> = {
  Lollibox: { code: 'BOX', color: '#3b82f6' },
  LolliME:  { code: 'ME',  color: '#a855f7' },
  Bottle:   { code: 'BTL', color: '#22c55e' },
  Fresh:    { code: 'FSH', color: '#f59e0b' },
};
