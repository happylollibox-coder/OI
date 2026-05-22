-- =============================================
-- V_ADS_COACH_ACTIONS — Thin passthrough view
-- =============================================
-- Data is materialized by SP_REFRESH_ADS_COACH_ACTIONS
-- into FACT_ADS_COACH_ACTIONS. This view provides
-- human-friendly column ordering for ad-hoc queries.
--
-- Column order:
--   1. action_id
--   2. Action Segmentation (+ key context fields)
--   3. Action Results (dashboard output)
--   4. Keys & Descriptions
--   5. Measures Directly Affecting Actions
--   6. Other (context / display)
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_COACH_ACTIONS` AS
SELECT
  -- ═══ 1. ROW IDENTIFIER ═══
  action_id,

  -- ═══ 2. ACTION SEGMENTATION ═══
  action_type,
  asin,
  product_short_name,
  campaign_name,
  targeting,
  search_term,
  action,
  strategic_task,
  coach_mode,
  active_occasion,
  current_phase,
  confidence,
  ads_signal,
  priority_score,

  -- ═══ 3. ACTION RESULTS (dashboard) ═══
  action_explanation,
  decision_trace,
  recommendation_object,
  current_bid,
  recommended_bid,
  bid_change_pct,
  recommended_bid_max,
  current_budget,
  recommended_budget,

  -- ═══ 4. KEYS & DESCRIPTIONS ═══
  campaign_id,
  campaign_type,
  campaign_state,
  parent_name,
  keyword_id,
  match_type,
  experiment_id,
  experiment_name,
  strategy_id,
  strategy_name,
  experiment_status,

  -- ═══ 5. MEASURES DIRECTLY AFFECTING ACTIONS ═══
  ads_spend_4w,
  ads_orders_4w,
  ads_clicks_4w,
  ads_impressions_4w,
  ads_sales_4w,
  ads_cpc_4w,
  ads_cvr_pct_4w,
  net_profit_4w,
  net_roas_4w,
  margin_per_unit,
  term_spend_4w,
  term_orders_4w,
  term_campaign_count,
  term_selling_campaigns,
  spend_share_pct,
  orders_share_pct,
  target_net_roas_8w,
  target_clicks_8w,
  target_orders_8w,
  target_spend_8w,
  pp_target_net_roas,
  pp_target_spend,
  pp_target_orders,
  pp_days,
  pre_peak_bid,
  pre_peak_budget,
  pp_campaign_net_roas,
  pp_campaign_spend,
  pp_campaign_orders,
  pp_campaign_sales,
  pp_campaign_days,
  hero_net_roas,
  hero_total_orders,
  is_hero_match,

  -- ═══ 6. OTHER (context / display) ═══
  hero_asin,
  hero_product_name,
  hero_ads_ctr_pct,
  sqp_orders_4w,
  sqp_show_rate_4w,
  tos_pct,
  product_page_pct,
  b2b_pct,
  pre_peak_tos_pct,
  pre_peak_pp_pct,
  pre_peak_b2b_pct,
  pre_peak_avg_cpc,
  last_day_cpc,

  -- ═══ 7. ROAS WINDOWS + SQP ═══
  ads_net_roas_3d,
  ads_orders_3d,
  ads_net_roas_1w,
  ads_orders_1w,
  ly_net_roas,
  ly_orders,
  q4_peak_net_roas,
  q4_peak_orders,
  sqp_amazon_search_volume_8w,
  sqp_clicks_8w,
  sqp_sales_8w,
  sqp_orders_8w,
  lt_net_roas,
  lt_orders,
  lt_first_seen,
  lt_last_seen

FROM `onyga-482313.OI.FACT_ADS_COACH_ACTIONS`
