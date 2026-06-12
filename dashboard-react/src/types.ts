export interface SummaryRow {
  product_type: string;
  color_hex: string;
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

export interface LegacyActionRow {
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

  action_id: string;
  decision_branch_id: string | null;
  action_type: string;
  action: string;
  action_explanation: string | null;
  priority_score: number;
  ads_signal: string;

  spend: number;
  ads_sales: number;
  ads_roas: number;
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

  target_net_roas_8w: number | null;
  target_clicks_8w: number | null;
  target_orders_8w: number | null;
  target_spend_8w: number | null;
  current_bid: number | null;
  recommended_bid: number | null;
  bid_change_pct: number | null;
  match_type: string | null;

  // Hero
  hero_product_name: string | null;
  hero_net_roas: number | null;
  hero_total_orders: number | null;
  hero_ads_ctr_pct: number | null;
  negate_as: string | null;

  sqp_search_volume: number;
  sqp_organic_rank: number | null;
  is_top_of_page_organic: boolean;
  decision_trace: DecisionStep[] | null;
  peak_phase: string | null;
  occasion: string | null;
  recommendation_object: 'TARGET' | 'TERM' | null;

  // Coach mode (Blitz / Cooldown / Guardian)
  coach_mode: string;
  active_occasion: string;
  current_phase: string;

  // Post-peak metrics (Cooldown only)
  pp_days?: number | null;
  pp_target_net_roas?: number | null;
  pp_target_spend?: number | null;
  pp_target_orders?: number | null;

  // Budget (Cooldown)
  current_budget?: number | null;
  pre_peak_budget?: number | null;
  recommended_budget?: number | null;
  budget_action?: string | null;
  pp_campaign_net_roas?: number | null;

  // Strategic task
  strategic_task?: string;

  // Allow campaign_type for tree grouping
  campaign_type?: string;
}

/** A single step in the backend-computed decision trace */
export interface DecisionStep {
  id: string;
  label: string;
  rule?: string;
  pass: boolean;
  value: string;
  /** SQL column name shown as hover tooltip for debugging */
  sql?: string;
}

/** A 3-day rapid-reaction ads alert */
export interface AdsFocusTermRow {
  week_start: string;
  focus_bucket: 'winner' | 'loser' | 'other_winners' | 'other_losers';
  search_term: string;
  asin: string | null;
  product_short_name: string | null;
  spend: number;
  orders: number;
  sales: number;
  net_profit: number;
  term_count: number;
}

export interface AdsFocusKeywordRow {
  week_start: string;
  focus_bucket: 'winner' | 'loser' | 'other_winners' | 'other_losers';
  keyword: string;
  spend: number;
  orders: number;
  sales: number;
  net_profit: number;
  keyword_count: number;
}

export interface HotSignalRow {
  hot_signal: 'URGENT_STOP' | 'HOT_WINNER' | 'RAPID_DECLINE' | 'POST_PEAK_REDUCE';
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
  // POST_PEAK_REDUCE specific
  current_bid?: number | null;
  recommended_bid?: number | null;
  keyword_id?: string | null;
  keyword_text?: string | null;
}

export interface StorageCostRow {
  week_start_date: string;
  product_type: string;
  asin?: string;
  weekly_storage_cost: number;
}

export interface SupplyChainRow {
  asin: string;
  product_short_name: string;
  product_type: string;
  sellable_qty: number;
  fba_stock_qty: number;
  awd_stock_qty: number;
  in_transit_qty: number;
  mfr_stock_qty: number;
  total_available_qty: number;
  daily_velocity: number;
  days_of_coverage: number | null;
  fba_days_of_coverage: number | null;
  awd_days_of_coverage: number | null;
  next_shipment_date: string | null;
  days_to_next_shipment: number | null;
  next_shipment_qty: number | null;
  awd_target_min: number | null;
  awd_target_max: number | null;
  awd_approved_min: number | null;
  awd_approved_max: number | null;
  awd_diff_pct: number | null;
  last_30d_sold: number;
  last_30d_planned: number;
  next_30d_planned: number;
  next_31_60d_planned: number;
  next_61_90d_planned: number;
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
  boost_start: string;
  peak_start: string;
  category: string;
  ramp_up_days?: number;
}

export interface PeakRelevanceRow {
  holiday_name: string;
  holiday_date: string;
  family: string;
  is_relevant_peak: boolean;
  confidence: string;
  coach_recommendation: string;
  reason: string;
  orders_change_pct: number | null;
  units_change_pct: number | null;
  sales_change_pct: number | null;
  net_roas_delta: number | null;
  baseline_avg_daily_orders: number | null;
  peak_avg_daily_orders: number | null;
  baseline_net_roas: number | null;
  peak_net_roas: number | null;
}

export interface ProductRow {
  asin: string;
  product_short_name: string;
  product_type: string;
  family_name: string;
  parent_asin: string | null;
  parent_name: string;
  cogs: number;
  shipping_cost: number;
  fba_cost: number;
  total_cost_per_unit: number;
  pick_pack_fee: number;
  referral_fee: number;
  package_quantity: number | null;
  manufacture_day: number | null;
  shipment_days: number | null;
  package_cubic_feet: number | null;
  manuf_upfront_percentage: number | null;
  share_carton_in_family: boolean | null;
  listing_price: number | null;
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
  impressions?: number;
  net_roas: number;
  organic_pct?: number;
  tacos?: number;
  np_per_unit?: number;
}

export interface DailyTrendRow {
  product_type: string;
  date: string;
  sales: number;
  orders: number;
  units?: number;
  ad_cost: number;
  cogs: number;
  net_profit: number;
  clicks?: number;
  sessions?: number;
  impressions?: number;
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
  family_name: string;
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
  asin?: string | null;
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
  ads_clicks_1w: number;
  ads_impressions_1w: number;
  ads_spend_1w: number;
  ads_cpc_1w: number | null;
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

export interface ActionRow {
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
  ads_roas_4w: number;
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

  target_net_roas_8w: number | null;
  target_clicks_8w: number | null;
  target_orders_8w: number | null;
  target_spend_8w: number | null;
  current_bid: number | null;
  recommended_bid: number | null;
  bid_change_pct: number | null;
  match_type: string | null;

  // Unified Action Identifiers
  action_id: string;
  decision_branch_id: string | null;
  action_type: string;
  action: string;
  priority_score: number;
  confidence: string;
  reason: string;
  action_explanation: string | null;
  decision_trace: DecisionStep[] | null;

  // Hero ASIN contextual data
  hero_asin: string | null;
  hero_product_name: string | null;
  is_hero_match: boolean;
  hero_net_roas: number | null;
  hero_total_orders: number | null;
  // Coach mode
  coach_mode: string;
  active_occasion: string;
  current_phase: string;
  // Post-peak metrics (Cooldown only)
  pp_days: number | null;
  pp_target_net_roas: number | null;
  pp_target_spend: number | null;
  pp_target_orders: number | null;
  // Cooldown v2: placement adjustments & pre-peak comparison
  tos_pct: number | null;
  product_page_pct: number | null;
  b2b_pct: number | null;
  pre_peak_bid: number | null;
  pre_peak_tos_pct: number | null;
  pre_peak_pp_pct: number | null;
  pre_peak_b2b_pct: number | null;
  pre_peak_avg_cpc: number | null;
  last_day_cpc: number | null;
  current_budget: number | null;
  pre_peak_budget: number | null;
  recommended_budget: number | null;
  budget_action: string | null;
  pp_campaign_net_roas: number | null;
  strategic_task: string | null;
  ads_signal: string | null;
  // ROAS windows + SQP context
  ads_net_roas_3d: number | null;
  ads_orders_3d: number | null;
  ads_units_3d: number | null;
  ads_net_roas_1w: number | null;
  ads_orders_1w: number | null;
  ads_units_1w: number | null;
  ads_cpc_1w: number | null;
  ads_spend_1w: number;
  ads_clicks_1w: number;
  ly_net_roas: number | null;
  ly_orders: number | null;
  ly_units: number | null;
  q4_peak_net_roas: number | null;
  q4_peak_orders: number | null;
  q4_peak_units: number | null;
  sqp_amazon_search_volume_8w: number | null;
  sqp_clicks_8w: number | null;
  sqp_sales_8w: number | null;
  sqp_orders_8w: number | null;
  lt_net_roas: number | null;
  lt_orders: number | null;
  lt_units: number | null;
  lt_first_seen: string | null;
  lt_last_seen: string | null;
}

/** Alias: loadCoachActionsFromCube returns ActionRow shape */
export type CoachActionRow = ActionRow;

export interface CoachStrategyRow {
  coach_mode: string;
  north_star: string;
  north_star_metric: string;
  north_star_target: number | null;
  task_id: string;
  task_name: string;
  task_description: string;
  capability: string;
  capability_direction: string | null;
  display_order: number;
  mitigation: string | null;
  emoji: string;
}

export interface CoachCampaignRow {
  campaign_id: string;
  campaign_name: string;
  campaign_type?: string;
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
  strategy_id: string | null;
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
  sample_terms?: { search_term: string; ads_spend_8w: number; ads_orders_8w: number; ads_clicks_8w: number }[];
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

export interface FamilyOccasionRow {
  parent_name: string;
  occasion: string;
  lift_ratio: number;
  peak_daily_orders: number;
  off_season_daily_orders: number;
  rank_by_lift: number;
  is_primary: boolean;
  is_override: boolean;
}

/* ─── Supply Orders types ─── */
export interface SupplyPORow {
  purchase_order_id: string;
  order_date: string;
  manufacturer_name: string;
  product_name: string;
  product_asin: string;
  product_id: string;
  quantity: number;
  total_amount: number;
  total_paid: number;
  unpaid_manufacturer: number;
  total_shipment_cost: number;
  paid_shipment_cost: number;
  unpaid_shipment: number;
  total_unpaid: number;
  total_quantity_shipped: number;
  remaining_to_ship: number;
  estimated_shipment_cost: number | null;
  payment_status: string;
  is_open: boolean;
  currency: string;
  notes: string | null;
  ready_quantity?: number;
  expected_ready_date: string | null;
}

export interface SupplyPaymentRow {
  payment_id: string;
  payment_date: string;
  payment_amount: number;
  bank_fee: number;
  total_amount: number;
  currency: string;
  payment_method: string;
  vendor_name: string;
  purchase_order_id: string | null;
  shipment_id: string | null;
  notes: string | null;
}

export interface SupplyShipmentRow {
  shipment_id: string;
  shipment_date: string;
  estimated_arrival_date: string | null;
  tracking_number: string | null;
  shipment_type: string;
  total_quantity: number;
  cost_shipped: number;
  is_paid: boolean;
  paid_date: string | null;
  shipment_status: string;
  notes: string | null;
  line_count: number;
  total_allocated_cost: number;
  total_quantity_shipped: number;
  products_list: string;
  unpaid_to_shipment: number;
  is_open: boolean;
}

export interface SupplyOtherPORow {
  other_po_id: string;
  order_date: string;
  service_type: string;
  supplier_name: string;
  total_amount: number;
  currency: string;
  payment_status: string;
  notes: string | null;
}

export interface CampaignLaunchPerfRow {
  campaign_id: string;
  campaign_name: string;
  campaign_type: string;
  campaign_state: string;
  creation_date: string;
  strategy_name: string;
  window_status: string;
  units: number;
  clicks: number;
  orders: number;
  ad_spend: number;
  gross_profit: number;
  net_profit: number;
  cpc: number | null;
  net_roas: number | null;
  active_days: number;
}

export interface CampaignLaunchMonthlyRow {
  campaign_id: string;
  campaign_name: string;
  campaign_type: string;
  campaign_state: string;
  creation_date: string;
  strategy_name: string;
  asin: string | null;
  parent_name: string | null;
  last_active_date: string | null;
  end_date_display: string | null;
  months_active: number;
  total_net_profit: number;
  net_profit_monthly_avg: number;
  m1_units: number; m1_cpc: number | null; m1_ad_spend: number; m1_net_roas: number | null;
  m2_units: number; m2_cpc: number | null; m2_ad_spend: number; m2_net_roas: number | null;
  m3_units: number; m3_cpc: number | null; m3_ad_spend: number; m3_net_roas: number | null;
}

/** One row of the Plan wizard's Ads Path targets — per family / month / ad-channel. */
export interface PlanAdsTargetRow {
  family: string;
  yr: number;
  mo: number;
  channel: string;
  daily_spend_target: number;
  cpc_target: number;
  predicted_cvr: number;
  predicted_roas: number;
  predicted_units: number;
  predicted_net_profit: number;
  ads_share: number;
  season_type: string;
  multiplier_k: number;
}

export interface DashboardData {
  summary: SummaryRow[];
  legacy_actions_deprecated: LegacyActionRow[];
  upcoming: UpcomingEvent[];
  peak: PeakRow[];
  products: ProductRow[];
  hero_asins: HeroAsin[];
  keyword_product_map: KeywordMapRow[];
  weekly_trends: TrendRow[];
  daily_trends: DailyTrendRow[];
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
  actions: ActionRow[];
  coach_campaigns: CoachCampaignRow[];
  experiment_evaluations: ExperimentEvaluationRow[];
  keyword_predictions: StrategicPrediction[];
  brand_strength_weekly: BrandStrengthWeeklyRow[];
  coach_phrase_negatives: PhraseNegativeRow[];
  phrase_negatives: PhraseNegativeRow[];
  hot_signals: HotSignalRow[];
  ads_focus_terms: AdsFocusTermRow[];
  ads_focus_keywords: AdsFocusKeywordRow[];
  product_creatives: ProductCreativeRow[];
  storage_costs: StorageCostRow[];
  supply_chain: SupplyChainRow[];
  supply_pos: SupplyPORow[];
  supply_payments: SupplyPaymentRow[];
  supply_shipments: SupplyShipmentRow[];
  supply_other_pos: SupplyOtherPORow[];
  peak_relevance: PeakRelevanceRow[];
  family_occasions: FamilyOccasionRow[];
  coach_strategy: CoachStrategyRow[];
  campaign_launch_perf: CampaignLaunchPerfRow[];
  campaign_launch_monthly: CampaignLaunchMonthlyRow[];
  plan_ads_targets: PlanAdsTargetRow[];
  launch_models: { product: string; daily_rate: number }[];
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

export type PageId = 'home' | 'actions' | 'peak' | 'family' | 'sqp' | 'learn' | 'kwds' | 'log' | 'health' | 'experiment' | 'ads' | 'strategies' | 'admin' | 'do' | 'brand' | 'plan' | 'supply' | 'alerts' | 'products' | 'kpi' | 'research';

export interface BrandStrengthWeeklyRow {
  week_start_date: string;
  brand_keyword: string;
  parent_name: string;
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
  sqp_month_impressions: number | null;
  sqp_ly_month_impressions: number | null;
}
export interface ProductCreativeRow {
  product_family: string;
  brand_entity_id: string;
  brand_name: string;
  video_asset_id: string;
}

export type FamilyName = 'Lollibox' | 'LolliME' | 'Bottle' | 'Fresh' | 'Bunny' | 'LolliBall';

export const FAMILIES: Record<FamilyName, { code: string; color: string }> = {
  Lollibox:  { code: 'BOX', color: '#3b82f6' },
  LolliME:   { code: 'ME',  color: '#a855f7' },
  Bottle:    { code: 'BTL', color: '#22c55e' },
  Fresh:     { code: 'FSH', color: '#f59e0b' },
  Bunny:     { code: 'BNY', color: '#ec4899' },
  LolliBall: { code: 'BAL', color: '#06b6d4' },
};

export interface LovRow {
  value_id: string;
  value_caption: string;
  is_default: boolean;
  attr1_name: string | null;
  attr1_value: string | null;
  attr2_name: string | null;
  attr2_value: string | null;
}

/** Legacy ShipmentPlanRow (saved to DE_PLAN_SHIPMENTS via plan_id) */
export interface ShipmentPlanRow {
  plan_id: string;
  shipment_week: number;
  ship_number: number;
  ship_date: string;
  est_arrival: string;
  route: string;
  route_reason: string | null;
  shipment_type: string;
  product: string;
  quantity: number;
  num_boxes: number | null;
  total_cubic_feet: number | null;
  est_ship_cost: number | null;
  est_mfr_cost: number | null;
  status: string;
  updated_at?: string;
  _isEditing?: boolean;
  mfr_ready_date?: string; // date manufacturing completes (PO ready to ship)
  oos_date?: string; // projected OOS month (e.g. "Jun 2026")
}

/** From FACT_SHIPMENT_PLAN — SP-generated suggestions (not yet approved) */
export interface ShipmentPlanFactRow {
  schedule_id: string;
  product: string;
  asin: string;
  shipment_type: number;
  shipment_type_name: string;
  route: string;
  transit_type: string;
  transit_days: number;
  priority: number;
  days_until_oos: number;
  ship_qty: number;
  ship_cartons: number;
  mfr_ready_before: number;
  in_production: number;
  prior_type_allocations: number;
  needs_new_po: boolean;
  new_po_qty: number | null;
  po_ready_date: string | null;
  ship_wednesday: string;
  amazon_plan_date: string;
  arrival_date: string;
  shipment_num: number | null;
  available_stock: number;
  fba_stock: number;
  awd_stock: number;
  in_transit: number;
  demand_window: number;
  demand_awd_window: number;
  shipment_trigger_reason: string;
  ship_qty_reason: string;
}

/** From DE_SCHEDULED_SHIPMENTS — user-approved or manufacturer-confirmed */
export interface ScheduledShipmentRow {
  schedule_id: string;
  product: string;
  asin: string;
  shipment_type: number;
  shipment_type_name: string;
  route: string;
  transit_type: string;
  ship_qty: number;
  ship_cartons: number;
  ship_wednesday: string;
  amazon_plan_date: string;
  arrival_date: string;
  shipment_num: number | null;
  status: 'APPROVED' | 'SCHEDULED';
  shipment_trigger_reason: string;
  ship_qty_reason: string;
  approved_at: string;
  scheduled_at: string | null;
}

/** Combined view of a shipment row for UI (suggested + approved + scheduled) */
export interface UnifiedShipmentRow {
  product: string;
  asin: string;
  shipment_type: number;
  shipment_type_name: string;
  route: string;
  transit_type: string;
  ship_qty: number;
  ship_cartons: number;
  ship_wednesday: string;
  arrival_date: string;
  shipment_num: number | null;
  shipment_trigger_reason: string;
  ship_qty_reason: string;
  _status: 'suggested' | 'approved' | 'scheduled' | 'po' | 'po_needed' | 'transit';
  _schedule_id?: string;
  _po_id?: string;
  _has_manual_eta?: boolean;
}

/** Per-product replenishment flow for pipeline visualization */
export interface ReplenishmentFlowData {
  product: string;
  yearlyPlan: number;
  arrived: number;
  arrivedRemaining: number;
  inTransit: number;
  inTransitDetails: { shipment_id?: string; type: string; qty: number; eta: string; ship_date: string }[];
  transitRemaining: number;
  approved: number;
  approvedDetails: { schedule_id: string; type: string; qty: number; ship_date: string; arrival_date: string }[];
  approvedRemaining: number;
  scheduled: number;
  scheduledDetails: { schedule_id: string; type: string; qty: number; ship_date: string; arrival_date: string }[];
  scheduledRemaining: number;
  suggested: number;
  suggestedDetails: { type: string; qty: number; ship_date: string; arrival_date: string }[];
  suggestedRemaining: number;
  toShip: number;
}


export interface AlertRow {
  id: string;
  alert_type: 'CREATE_PO' | 'CREATE_SHIPMENT' | 'AWD_LIMITS' | 'AMAZON_PLAN' | 'SALES_DEVIATION' | 'UPDATE_AWD_TARGET' | 'PLAN_DRIFT';
  product_asin: string;
  product_name: string;
  severity: 'CRITICAL' | 'WARNING' | 'INFO';
  title: string;
  description: string;
  suggested_qty: number;
  suggested_split_fba: number;
  suggested_split_awd: number;
  fba_doc: number;
  system_doc: number;
  breach_date: string | null;
  related_po_id: string | null;
  related_shipment_id: string | null;
  status: 'OPEN' | 'DONE' | 'CANCELLED' | 'AUTO_RESOLVED' | 'SNOOZED';
  created_at: string;
  resolved_at: string | null;
  resolved_by: string | null;
  notes: string | null;
  fire_day: string | null;
  
  // New Remediation Fields
  action_type: string | null;
  action_payload: string | Record<string, any> | null;
  snooze_until: string | null;
  related_plan_id: string | null;
  updated_at: string | null;
}
