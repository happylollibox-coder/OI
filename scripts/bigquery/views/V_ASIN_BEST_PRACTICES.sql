-- =============================================
-- OI Database Project - V_ASIN_BEST_PRACTICES View
-- =============================================
--
-- Purpose: The "memory" of what worked per ASIN.
--          Saves the winning recipe from each experiment enriched with segment performance.
--          Used by V_EXPERIMENT_SUGGESTIONS to recommend next experiments.
--
-- Grain: One row per experiment_id + asin + experiment_segment
--        (shows how each segment responded to the experiment)
--
-- Dependencies:
--   V_EXPERIMENT_RESULTS_ASIN, V_EXPERIMENT_RESULTS_SEARCH_TERM,
--   V_EXPERIMENT_CAMPAIGN_SETTINGS, V_SEARCH_TERM_SEGMENT, DIM_PRODUCT
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ASIN_BEST_PRACTICES`
AS
WITH experiment_recipe AS (
  -- The "recipe" per experiment: campaign settings used
  SELECT
    cs.experiment_id,
    cs.experiment_name,
    cs.experiment_status,
    cs.strategy_id,
    cs.strategy_name,
    cs.campaign_type,
    cs.bidding_strategy,
    cs.primary_match_type,
    cs.avg_keyword_bid,
    cs.top_of_search_pct,
    cs.product_page_pct,
    cs.campaign_budget,
    cs.bid_range_bucket,
    cs.tos_roas,
    cs.tos_cost_share_pct
  FROM `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS` cs
),

asin_results AS (
  -- ASIN-level results from Business Reports
  SELECT
    experiment_id,
    asin,
    ads_experiment_campaign_roas as ads_roas,
    total_experiment_roas,
    performance_total_orders_lift_pct,
    performance_organic_units_lift_pct,
    performance_seasonal_total_orders_lift_pct,
    performance_seasonal_organic_units_lift_pct,
    seasonal_adjustment_ratio
  FROM `onyga-482313.OI.V_EXPERIMENT_RESULTS_ASIN`
),

-- Per experiment + search term + segment: how each segment performed
term_segment_results AS (
  SELECT
    st.experiment_id,
    st.asin,
    seg.experiment_segment,
    seg.intent_segment,
    seg.occasion,
    seg.product_match,
    -- Counts
    COUNT(DISTINCT st.search_term) as terms_in_segment,
    -- Share changes
    ROUND(AVG(st.search_impressions_share_delta_pp), 2) as avg_impressions_share_delta_pp,
    ROUND(AVG(st.search_orders_share_delta_pp), 2) as avg_orders_share_delta_pp,
    ROUND(AVG(st.search_cart_adds_share_delta_pp), 2) as avg_cart_adds_share_delta_pp,
    ROUND(AVG(st.search_ctr_delta_pp), 2) as avg_ctr_delta_pp,
    -- Ad performance in this segment
    SUM(st.ads_term_cost) as segment_ad_cost,
    SUM(st.ads_term_sales) as segment_ad_sales,
    SUM(st.ads_term_orders) as segment_ad_orders,
    ROUND(SAFE_DIVIDE(SUM(st.ads_term_sales), NULLIF(SUM(st.ads_term_cost), 0)), 2) as segment_ads_roas,
    -- Normalized lift
    ROUND(AVG(st.normalized_total_lift_pct), 1) as avg_normalized_total_lift_pct,
    -- Market size
    ROUND(AVG(st.search_experiment_amazon_avg_weekly_orders), 1) as avg_market_weekly_orders,
    -- Data quality
    COUNTIF(st.organic_data_unreliable) as terms_unreliable_organic
  FROM `onyga-482313.OI.V_EXPERIMENT_RESULTS_SEARCH_TERM` st
  LEFT JOIN `onyga-482313.OI.V_SEARCH_TERM_SEGMENT` seg
    ON LOWER(st.search_term) = seg.search_term AND st.asin = seg.asin
  GROUP BY 1, 2, 3, 4, 5, 6
),

-- Cross-ASIN: find sibling ASINs (same product_type)
product_siblings AS (
  SELECT
    p1.asin,
    p1.product_type,
    p1.product_short_name,
    p1.parent_asin,
    ARRAY_AGG(DISTINCT p2.asin IGNORE NULLS) as sibling_asins
  FROM `onyga-482313.OI.DIM_PRODUCT` p1
  LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p2
    ON p1.product_type = p2.product_type
    AND p1.asin != p2.asin
    AND p2.asin IS NOT NULL
  WHERE p1.asin IS NOT NULL
  GROUP BY 1, 2, 3, 4
)

SELECT
  -- Keys
  CONCAT(tsr.experiment_id, '|', tsr.asin, '|', COALESCE(tsr.experiment_segment, '')) as row_key,
  CONCAT(tsr.experiment_id, '|', tsr.asin) as experiment_asin_key,
  CONCAT(tsr.asin, '|', COALESCE(tsr.experiment_segment, '')) as asin_segment_key,

  -- Experiment identity
  tsr.experiment_id,
  er.experiment_name,
  er.experiment_status,
  tsr.asin,
  ps.product_short_name,
  ps.product_type,
  ps.parent_asin,
  ARRAY_LENGTH(ps.sibling_asins) as sibling_count,

  -- The recipe that was used
  er.strategy_id,
  er.strategy_name,
  er.campaign_type,
  er.bidding_strategy,
  er.primary_match_type,
  er.avg_keyword_bid,
  er.top_of_search_pct,
  er.product_page_pct,
  er.campaign_budget,
  er.bid_range_bucket,
  er.tos_roas,
  er.tos_cost_share_pct,

  -- ASIN-level results (the overall verdict)
  ar.ads_roas as asin_ads_roas,
  ar.total_experiment_roas as asin_total_roas,
  ar.performance_total_orders_lift_pct as asin_total_lift_pct,
  ar.performance_seasonal_total_orders_lift_pct as asin_seasonal_total_lift_pct,
  ar.seasonal_adjustment_ratio,

  -- Segment-level performance (how this segment responded)
  tsr.experiment_segment,
  tsr.intent_segment,
  tsr.occasion,
  tsr.product_match,
  tsr.terms_in_segment,
  tsr.avg_impressions_share_delta_pp,
  tsr.avg_orders_share_delta_pp,
  tsr.avg_cart_adds_share_delta_pp,
  tsr.avg_ctr_delta_pp,
  tsr.segment_ad_cost,
  tsr.segment_ad_sales,
  tsr.segment_ad_orders,
  tsr.segment_ads_roas,
  tsr.avg_normalized_total_lift_pct,
  tsr.avg_market_weekly_orders,
  tsr.terms_unreliable_organic,

  -- Verdict per segment
  CASE
    WHEN tsr.segment_ads_roas >= 3.0 AND tsr.avg_orders_share_delta_pp > 0 THEN 'STRONG_WIN'
    WHEN tsr.segment_ads_roas >= 2.0 AND tsr.avg_impressions_share_delta_pp > 0 THEN 'MODERATE_WIN'
    WHEN tsr.segment_ads_roas >= 1.0 THEN 'BREAK_EVEN'
    WHEN tsr.segment_ad_cost > 0 AND tsr.segment_ads_roas < 1.0 THEN 'LOSS'
    WHEN tsr.segment_ad_cost = 0 OR tsr.segment_ad_cost IS NULL THEN 'NO_SPEND'
    ELSE 'INSUFFICIENT_DATA'
  END as segment_verdict

FROM term_segment_results tsr
LEFT JOIN experiment_recipe er ON tsr.experiment_id = er.experiment_id
LEFT JOIN asin_results ar ON tsr.experiment_id = ar.experiment_id AND tsr.asin = ar.asin
LEFT JOIN product_siblings ps ON tsr.asin = ps.asin;
