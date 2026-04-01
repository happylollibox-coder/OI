-- =============================================
-- OI Database Project - V_EXPERIMENT_CAMPAIGN_SETTINGS View
-- =============================================
--
-- Purpose: Auto-enriches experiment-campaign links with campaign settings
--          from the warehouse AS OF the experiment start_date.
--          Single source of truth for "what was the recipe for this campaign?"
--
-- Auto-populated (from temporal warehouse data):
--   campaign_type, bidding_strategy, budget, ad_group default_bid,
--   keyword match_types, keyword bids, counts
--
-- Auto-populated (from Fivetran placement data):
--   top_of_search_pct, product_page_pct  (bid adjustment %)
--   Placement-level ROAS, cost, sales, orders during experiment period
--
-- Dependencies:
--   - DIM_EXPERIMENT, DIM_EXPERIMENT_CAMPAIGN, DIM_STRATEGY_TEMPLATE
--   - V_SRC_AmazonAds_campaign_history (temporal)
--   - V_SRC_AmazonAds_ad_group_history (temporal)
--   - V_SRC_AmazonAds_keyword
--   - V_CAMPAIGN_PLACEMENT_BIDDING (SP + SB bid adjustments)
--   - V_CAMPAIGN_PLACEMENT_REPORT (SP + SB placement performance)
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS`
AS
WITH experiment_campaigns AS (
  -- Base: experiment + campaign link + experiment dates
  SELECT
    ec.experiment_id,
    ec.campaign_id,
    ec.campaign_name,
    ec.notes as campaign_notes,
    e.experiment_name,
    e.start_date,
    COALESCE(e.end_date, CURRENT_DATE()) as effective_end_date,
    e.end_date,
    e.status as experiment_status,
    e.strategy_id,
    st.strategy_name,
    st.description as strategy_description
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.DIM_EXPERIMENT` e
    ON ec.experiment_id = e.experiment_id
  LEFT JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st
    ON e.strategy_id = st.strategy_id
),

-- Campaign settings as of experiment start_date (temporal lookup)
campaign_settings AS (
  SELECT
    CAST(ch.campaign_id AS STRING) as campaign_id,
    ch.campaign_type,
    ch.bidding_strategy,
    ch.budget as campaign_budget,
    ch.budget_type as campaign_budget_type,
    ch.state as campaign_state,
    ch.OI_start_date,
    ch.OI_end_date
  FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` ch
),

-- Ad group settings: latest active version per ad group, aggregated per campaign
ad_group_settings AS (
  SELECT
    CAST(campaign_id AS STRING) as campaign_id,
    COUNT(DISTINCT ad_group_id) as num_ad_groups,
    ROUND(AVG(default_bid), 2) as avg_default_bid,
    ROUND(MAX(default_bid), 2) as max_default_bid,
    ROUND(MIN(default_bid), 2) as min_default_bid
  FROM `onyga-482313.OI.V_SRC_AmazonAds_ad_group_history`
  WHERE state = 'enabled'
    AND OI_end_date >= CURRENT_TIMESTAMP()
  GROUP BY CAST(campaign_id AS STRING)
),

-- Keyword settings (latest snapshot per campaign, aggregated)
keyword_settings AS (
  SELECT
    k.campaign_id,
    COUNT(DISTINCT k.keyword_id) as num_keywords,
    ARRAY_AGG(k.match_type ORDER BY cnt DESC LIMIT 1)[OFFSET(0)] as primary_match_type,
    ROUND(AVG(k.bid), 2) as avg_keyword_bid,
    ROUND(MIN(k.bid), 2) as min_keyword_bid,
    ROUND(MAX(k.bid), 2) as max_keyword_bid
  FROM (
    SELECT
      k.campaign_id,
      k.keyword_id,
      k.match_type,
      k.bid,
      COUNT(*) OVER (PARTITION BY k.campaign_id, k.match_type) as cnt
    FROM `onyga-482313.OI.V_SRC_AmazonAds_keyword` k
    WHERE k.state IN ('enabled', '')
      AND k.bid IS NOT NULL
  ) k
  GROUP BY k.campaign_id
),

-- =============================================
-- PLACEMENT BID ADJUSTMENTS (from Fivetran, current settings)
-- Pivoted: one row per campaign with columns per placement
-- =============================================
placement_bidding AS (
  SELECT
    pb.campaign_id,
    MAX(CASE WHEN pb.placement = 'TOP_OF_SEARCH' THEN pb.bid_adjustment_pct END) as top_of_search_pct,
    MAX(CASE WHEN pb.placement = 'DETAIL_PAGE' THEN pb.bid_adjustment_pct END) as product_page_pct,
    MAX(CASE WHEN pb.placement = 'HOMEPAGE' THEN pb.bid_adjustment_pct END) as homepage_pct,
    MAX(CASE WHEN pb.placement = 'OTHER' THEN pb.bid_adjustment_pct END) as other_placement_pct,
    MAX(CASE WHEN pb.placement = 'AMAZON_BUSINESS' THEN pb.bid_adjustment_pct END) as amazon_business_pct
  FROM `onyga-482313.OI.V_CAMPAIGN_PLACEMENT_BIDDING` pb
  GROUP BY pb.campaign_id
),

-- =============================================
-- PLACEMENT PERFORMANCE during experiment period
-- Aggregated per campaign per placement during the experiment window
-- =============================================
placement_performance AS (
  SELECT
    ec.experiment_id,
    ec.campaign_id,
    pr.placement,
    SUM(pr.impressions) as placement_impressions,
    SUM(pr.clicks) as placement_clicks,
    ROUND(SUM(pr.cost), 2) as placement_cost,
    SUM(pr.orders) as placement_orders,
    SUM(pr.units) as placement_units,
    ROUND(SUM(pr.sales), 2) as placement_sales,
    ROUND(SAFE_DIVIDE(SUM(pr.sales), NULLIF(SUM(pr.cost), 0)), 2) as placement_roas,
    ROUND(SAFE_DIVIDE(SUM(pr.cost), NULLIF(SUM(pr.clicks), 0)), 2) as placement_cpc,
    ROUND(SAFE_DIVIDE(SUM(pr.clicks), NULLIF(SUM(pr.impressions), 0)) * 100, 2) as placement_ctr_pct,
    ROUND(SAFE_DIVIDE(SUM(pr.orders), NULLIF(SUM(pr.clicks), 0)) * 100, 2) as placement_conversion_rate_pct
  FROM experiment_campaigns ec
  JOIN `onyga-482313.OI.V_CAMPAIGN_PLACEMENT_REPORT` pr
    ON ec.campaign_id = pr.campaign_id
    AND pr.report_date >= ec.start_date
    AND pr.report_date <= ec.effective_end_date
  GROUP BY ec.experiment_id, ec.campaign_id, pr.placement
),

-- Pivot placement performance: one row per experiment-campaign, columns per placement
placement_perf_pivoted AS (
  SELECT
    experiment_id,
    campaign_id,
    -- Total across all placements
    SUM(placement_cost) as total_placement_cost,
    SUM(placement_sales) as total_placement_sales,
    SUM(placement_orders) as total_placement_orders,

    -- TOP OF SEARCH
    SUM(CASE WHEN placement = 'TOP_OF_SEARCH' THEN placement_impressions END) as tos_impressions,
    SUM(CASE WHEN placement = 'TOP_OF_SEARCH' THEN placement_clicks END) as tos_clicks,
    ROUND(SUM(CASE WHEN placement = 'TOP_OF_SEARCH' THEN placement_cost END), 2) as tos_cost,
    SUM(CASE WHEN placement = 'TOP_OF_SEARCH' THEN placement_orders END) as tos_orders,
    ROUND(SUM(CASE WHEN placement = 'TOP_OF_SEARCH' THEN placement_sales END), 2) as tos_sales,
    MAX(CASE WHEN placement = 'TOP_OF_SEARCH' THEN placement_roas END) as tos_roas,
    MAX(CASE WHEN placement = 'TOP_OF_SEARCH' THEN placement_cpc END) as tos_cpc,

    -- DETAIL PAGE (Product Page)
    SUM(CASE WHEN placement = 'DETAIL_PAGE' THEN placement_impressions END) as dp_impressions,
    SUM(CASE WHEN placement = 'DETAIL_PAGE' THEN placement_clicks END) as dp_clicks,
    ROUND(SUM(CASE WHEN placement = 'DETAIL_PAGE' THEN placement_cost END), 2) as dp_cost,
    SUM(CASE WHEN placement = 'DETAIL_PAGE' THEN placement_orders END) as dp_orders,
    ROUND(SUM(CASE WHEN placement = 'DETAIL_PAGE' THEN placement_sales END), 2) as dp_sales,
    MAX(CASE WHEN placement = 'DETAIL_PAGE' THEN placement_roas END) as dp_roas,
    MAX(CASE WHEN placement = 'DETAIL_PAGE' THEN placement_cpc END) as dp_cpc,

    -- REST OF SEARCH (SP only)
    SUM(CASE WHEN placement = 'REST_OF_SEARCH' THEN placement_impressions END) as ros_impressions,
    SUM(CASE WHEN placement = 'REST_OF_SEARCH' THEN placement_clicks END) as ros_clicks,
    ROUND(SUM(CASE WHEN placement = 'REST_OF_SEARCH' THEN placement_cost END), 2) as ros_cost,
    SUM(CASE WHEN placement = 'REST_OF_SEARCH' THEN placement_orders END) as ros_orders,
    ROUND(SUM(CASE WHEN placement = 'REST_OF_SEARCH' THEN placement_sales END), 2) as ros_sales,
    MAX(CASE WHEN placement = 'REST_OF_SEARCH' THEN placement_roas END) as ros_roas,
    MAX(CASE WHEN placement = 'REST_OF_SEARCH' THEN placement_cpc END) as ros_cpc,

    -- OTHER + OFF_AMAZON + HOMEPAGE combined as "other"
    SUM(CASE WHEN placement IN ('OTHER', 'OFF_AMAZON', 'HOMEPAGE') THEN placement_impressions END) as other_impressions,
    SUM(CASE WHEN placement IN ('OTHER', 'OFF_AMAZON', 'HOMEPAGE') THEN placement_clicks END) as other_clicks,
    ROUND(SUM(CASE WHEN placement IN ('OTHER', 'OFF_AMAZON', 'HOMEPAGE') THEN placement_cost END), 2) as other_cost,
    SUM(CASE WHEN placement IN ('OTHER', 'OFF_AMAZON', 'HOMEPAGE') THEN placement_orders END) as other_orders,
    ROUND(SUM(CASE WHEN placement IN ('OTHER', 'OFF_AMAZON', 'HOMEPAGE') THEN placement_sales END), 2) as other_sales

  FROM placement_performance
  GROUP BY experiment_id, campaign_id
)

-- Final enriched output: one row per experiment-campaign
SELECT
  -- Keys
  CONCAT(ec.experiment_id, '|', ec.campaign_id) as row_key,

  -- Experiment context
  ec.experiment_id,
  ec.experiment_name,
  ec.experiment_status,
  ec.start_date as experiment_start_date,
  ec.end_date as experiment_end_date,

  -- Strategy
  ec.strategy_id,
  ec.strategy_name,
  ec.strategy_description,

  -- Campaign identity
  ec.campaign_id,
  ec.campaign_name,

  -- Auto-populated: campaign settings (temporal - as of experiment start)
  cs.campaign_type,
  cs.bidding_strategy,
  cs.campaign_budget,
  cs.campaign_budget_type,
  cs.campaign_state,

  -- Auto-populated: ad group summary
  ags.num_ad_groups,
  ags.avg_default_bid,
  ags.max_default_bid,
  ags.min_default_bid,

  -- Auto-populated: keyword summary
  ks.num_keywords,
  ks.primary_match_type,
  ks.avg_keyword_bid,
  ks.min_keyword_bid,
  ks.max_keyword_bid,

  -- =============================================
  -- PLACEMENT BID ADJUSTMENTS (auto from Fivetran)
  -- =============================================
  COALESCE(pb.top_of_search_pct, 0) as top_of_search_pct,
  COALESCE(pb.product_page_pct, 0) as product_page_pct,
  COALESCE(pb.homepage_pct, 0) as homepage_pct,
  COALESCE(pb.other_placement_pct, 0) as other_placement_pct,
  COALESCE(pb.amazon_business_pct, 0) as amazon_business_pct,

  -- =============================================
  -- PLACEMENT PERFORMANCE (during experiment period)
  -- =============================================
  -- Cost distribution
  COALESCE(pp.total_placement_cost, 0) as placement_total_cost,
  ROUND(SAFE_DIVIDE(pp.tos_cost, NULLIF(pp.total_placement_cost, 0)) * 100, 1) as tos_cost_share_pct,
  ROUND(SAFE_DIVIDE(pp.dp_cost, NULLIF(pp.total_placement_cost, 0)) * 100, 1) as dp_cost_share_pct,
  ROUND(SAFE_DIVIDE(pp.ros_cost, NULLIF(pp.total_placement_cost, 0)) * 100, 1) as ros_cost_share_pct,
  ROUND(SAFE_DIVIDE(pp.other_cost, NULLIF(pp.total_placement_cost, 0)) * 100, 1) as other_cost_share_pct,

  -- Top of Search performance
  COALESCE(pp.tos_impressions, 0) as tos_impressions,
  COALESCE(pp.tos_clicks, 0) as tos_clicks,
  COALESCE(pp.tos_cost, 0) as tos_cost,
  COALESCE(pp.tos_orders, 0) as tos_orders,
  COALESCE(pp.tos_sales, 0) as tos_sales,
  pp.tos_roas,
  pp.tos_cpc,

  -- Detail Page performance
  COALESCE(pp.dp_impressions, 0) as dp_impressions,
  COALESCE(pp.dp_clicks, 0) as dp_clicks,
  COALESCE(pp.dp_cost, 0) as dp_cost,
  COALESCE(pp.dp_orders, 0) as dp_orders,
  COALESCE(pp.dp_sales, 0) as dp_sales,
  pp.dp_roas,
  pp.dp_cpc,

  -- Rest of Search performance
  COALESCE(pp.ros_impressions, 0) as ros_impressions,
  COALESCE(pp.ros_clicks, 0) as ros_clicks,
  COALESCE(pp.ros_cost, 0) as ros_cost,
  COALESCE(pp.ros_orders, 0) as ros_orders,
  COALESCE(pp.ros_sales, 0) as ros_sales,
  pp.ros_roas,
  pp.ros_cpc,

  -- Other placements performance
  COALESCE(pp.other_impressions, 0) as other_impressions,
  COALESCE(pp.other_clicks, 0) as other_clicks,
  COALESCE(pp.other_cost, 0) as other_cost,
  COALESCE(pp.other_orders, 0) as other_orders,
  COALESCE(pp.other_sales, 0) as other_sales,

  -- Derived: bid range bucket
  CASE
    WHEN COALESCE(ks.avg_keyword_bid, ags.avg_default_bid) < 0.50 THEN 'LOW'
    WHEN COALESCE(ks.avg_keyword_bid, ags.avg_default_bid) < 1.00 THEN 'MEDIUM'
    WHEN COALESCE(ks.avg_keyword_bid, ags.avg_default_bid) >= 1.00 THEN 'HIGH'
    ELSE 'UNKNOWN'
  END as bid_range_bucket,

  -- Derived: has top-of-search boost
  CASE WHEN COALESCE(pb.top_of_search_pct, 0) > 0 THEN TRUE ELSE FALSE END as has_top_of_search_boost,

  -- Notes
  ec.campaign_notes

FROM experiment_campaigns ec

-- Temporal join: campaign settings valid at experiment start_date
LEFT JOIN campaign_settings cs
  ON ec.campaign_id = cs.campaign_id
  AND TIMESTAMP(ec.start_date) >= cs.OI_start_date
  AND TIMESTAMP(ec.start_date) <= cs.OI_end_date

-- Latest snapshot: ad group settings
LEFT JOIN ad_group_settings ags
  ON ec.campaign_id = ags.campaign_id

-- Latest keyword settings
LEFT JOIN keyword_settings ks
  ON ec.campaign_id = ks.campaign_id

-- Placement bid adjustments (current settings from Fivetran)
LEFT JOIN placement_bidding pb
  ON ec.campaign_id = pb.campaign_id

-- Placement performance (aggregated during experiment period)
LEFT JOIN placement_perf_pivoted pp
  ON ec.experiment_id = pp.experiment_id
  AND ec.campaign_id = pp.campaign_id;
