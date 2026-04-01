-- =============================================
-- OI Database Project - V_PROMOTION_RAMP_ANALYSIS View
-- =============================================
--
-- Purpose: Track how promoted keywords perform over time after being
--          added to EXACT_BOOST campaigns. Measures ramp-up speed,
--          starting configuration, and weekly performance progression.
--
-- Uses FACT_CAMPAIGN_CONFIG snapshots to capture starting bid, TOS%,
-- bidding strategy, and budget — enabling learning about optimal
-- launch configurations.
--
-- Dependencies:
--   DIM_EXPERIMENT, DIM_EXPERIMENT_CAMPAIGN, DIM_STRATEGY_TEMPLATE,
--   FACT_AMAZON_ADS, FACT_CAMPAIGN_CONFIG, DIM_PRODUCT, DIM_COSTS_HISTORY
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_PROMOTION_RAMP_ANALYSIS`
AS
WITH

-- Unit economics per ASIN
asin_economics AS (
  SELECT
    p.asin,
    p.product_short_name,
    p.parent_name,
    p.listing_price_amount - COALESCE(ch.TOTAL_COST_PER_UNIT, 0) as margin_per_unit
  FROM `onyga-482313.OI.DIM_PRODUCT` p
  LEFT JOIN (
    SELECT asin, TOTAL_COST_PER_UNIT,
      ROW_NUMBER() OVER (PARTITION BY asin ORDER BY end_date DESC) as rn
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  ) ch ON p.asin = ch.asin AND ch.rn = 1
  WHERE p.asin IS NOT NULL
),

-- EXACT_BOOST experiments (the target of promotions)
boost_experiments AS (
  SELECT
    e.experiment_id,
    e.experiment_name,
    e.start_date,
    e.status,
    e.strategy_id,
    st.recommended_bid_min,
    st.recommended_bid_max,
    st.recommended_daily_budget,
    st.recommended_top_of_search_pct,
    st.recommended_bidding_strategy
  FROM `onyga-482313.OI.DIM_EXPERIMENT` e
  LEFT JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st ON e.strategy_id = st.strategy_id
  WHERE e.strategy_id = 'EXACT_BOOST'
),

-- Per-keyword daily ads data for EXACT_BOOST campaigns
keyword_daily AS (
  SELECT
    ec.experiment_id,
    be.experiment_name,
    be.start_date as experiment_start_date,
    be.status as experiment_status,
    ec.campaign_id,
    fa.campaign_name,
    fa.advertised_asins as asin,
    LOWER(fa.search_term) as search_term,
    fa.date,
    fa.Ads_impressions,
    fa.Ads_clicks,
    fa.Ads_orders,
    fa.Ads_units,
    fa.Ads_cost,
    fa.Ads_sales,
    -- Days since experiment started
    DATE_DIFF(fa.date, be.start_date, DAY) as day_number,
    -- Week number (0-based)
    DIV(DATE_DIFF(fa.date, be.start_date, DAY), 7) as week_number
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN boost_experiments be ON ec.experiment_id = be.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON ec.campaign_id = fa.campaign_id
    AND fa.date >= be.start_date
  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
    AND fa.advertised_asins IS NOT NULL
),

-- Aggregate per keyword per week
keyword_weekly AS (
  SELECT
    experiment_id,
    experiment_name,
    experiment_start_date,
    experiment_status,
    campaign_id,
    campaign_name,
    asin,
    search_term,
    week_number,
    SUM(Ads_impressions) as impressions,
    SUM(Ads_clicks) as clicks,
    SUM(Ads_orders) as orders,
    SUM(Ads_units) as units,
    SUM(Ads_cost) as spend,
    SUM(Ads_sales) as sales
  FROM keyword_daily
  GROUP BY 1,2,3,4,5,6,7,8,9
),

-- Ramp milestones per keyword
keyword_milestones AS (
  SELECT
    experiment_id,
    campaign_id,
    asin,
    search_term,
    MIN(CASE WHEN impressions > 0 THEN date END) as first_impression_date,
    MIN(CASE WHEN clicks > 0 THEN date END) as first_click_date,
    MIN(CASE WHEN orders > 0 THEN date END) as first_order_date
  FROM keyword_daily
  GROUP BY 1,2,3,4
),

-- Starting campaign config (earliest snapshot per campaign)
starting_config AS (
  SELECT
    campaign_id,
    -- Keyword-level bid
    MAX(CASE WHEN entity_type = 'KEYWORD' THEN bid END) as starting_keyword_bid,
    -- Ad group default bid
    MAX(CASE WHEN entity_type = 'AD_GROUP' THEN ad_group_default_bid END) as starting_ag_default_bid,
    -- Daily budget
    MAX(CASE WHEN entity_type IN ('CAMPAIGN', 'KEYWORD', 'AD_GROUP') THEN daily_budget END) as starting_daily_budget,
    -- Bidding strategy
    MAX(CASE WHEN entity_type IN ('CAMPAIGN', 'KEYWORD', 'AD_GROUP') THEN bidding_strategy END) as starting_bidding_strategy,
    -- Placement adjustments
    MAX(CASE WHEN entity_type = 'BIDDING_ADJUSTMENT' AND placement = 'Placement Top' THEN placement_percentage END) as starting_tos_pct,
    MAX(CASE WHEN entity_type = 'BIDDING_ADJUSTMENT' AND placement = 'Placement Product Page' THEN placement_percentage END) as starting_product_page_pct,
    MAX(CASE WHEN entity_type = 'BIDDING_ADJUSTMENT' AND placement = 'Placement Rest Of Search' THEN placement_percentage END) as starting_ros_pct,
    -- Snapshot date (earliest available)
    MIN(snapshot_date) as config_snapshot_date
  FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`
  WHERE snapshot_date = (
    SELECT MIN(snapshot_date) FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`
  )
  GROUP BY campaign_id
),

-- Current campaign config (latest snapshot)
current_config AS (
  SELECT
    campaign_id,
    MAX(CASE WHEN entity_type = 'KEYWORD' THEN bid END) as current_keyword_bid,
    MAX(CASE WHEN entity_type = 'AD_GROUP' THEN ad_group_default_bid END) as current_ag_default_bid,
    MAX(CASE WHEN entity_type IN ('CAMPAIGN', 'KEYWORD', 'AD_GROUP') THEN daily_budget END) as current_daily_budget,
    MAX(CASE WHEN entity_type = 'BIDDING_ADJUSTMENT' AND placement = 'Placement Top' THEN placement_percentage END) as current_tos_pct,
    MIN(snapshot_date) as latest_snapshot_date
  FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`
  WHERE snapshot_date = (
    SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`
  )
  GROUP BY campaign_id
),

-- Overall per-keyword aggregates
keyword_totals AS (
  SELECT
    experiment_id,
    experiment_name,
    experiment_start_date,
    experiment_status,
    campaign_id,
    campaign_name,
    asin,
    search_term,
    -- Total metrics
    SUM(Ads_impressions) as total_impressions,
    SUM(Ads_clicks) as total_clicks,
    SUM(Ads_orders) as total_orders,
    SUM(spend) as total_spend,
    SUM(Ads_sales) as total_sales,
    COUNT(DISTINCT week_number) as weeks_active,
    -- Week 1 metrics (week_number=0)
    SUM(CASE WHEN week_number = 0 THEN impressions ELSE 0 END) as w1_impressions,
    SUM(CASE WHEN week_number = 0 THEN clicks ELSE 0 END) as w1_clicks,
    SUM(CASE WHEN week_number = 0 THEN orders ELSE 0 END) as w1_orders,
    SUM(CASE WHEN week_number = 0 THEN spend ELSE 0 END) as w1_spend,
    -- Week 2 metrics
    SUM(CASE WHEN week_number = 1 THEN impressions ELSE 0 END) as w2_impressions,
    SUM(CASE WHEN week_number = 1 THEN clicks ELSE 0 END) as w2_clicks,
    SUM(CASE WHEN week_number = 1 THEN orders ELSE 0 END) as w2_orders,
    SUM(CASE WHEN week_number = 1 THEN spend ELSE 0 END) as w2_spend,
    -- Week 3 metrics
    SUM(CASE WHEN week_number = 2 THEN impressions ELSE 0 END) as w3_impressions,
    SUM(CASE WHEN week_number = 2 THEN clicks ELSE 0 END) as w3_clicks,
    SUM(CASE WHEN week_number = 2 THEN orders ELSE 0 END) as w3_orders,
    SUM(CASE WHEN week_number = 2 THEN spend ELSE 0 END) as w3_spend,
    -- Week 4 metrics
    SUM(CASE WHEN week_number = 3 THEN impressions ELSE 0 END) as w4_impressions,
    SUM(CASE WHEN week_number = 3 THEN clicks ELSE 0 END) as w4_clicks,
    SUM(CASE WHEN week_number = 3 THEN orders ELSE 0 END) as w4_orders,
    SUM(CASE WHEN week_number = 3 THEN spend ELSE 0 END) as w4_spend
  FROM keyword_weekly
  GROUP BY 1,2,3,4,5,6,7,8
)

-- =============================================
-- Final output
-- =============================================
SELECT
  kt.experiment_id,
  kt.experiment_name,
  kt.experiment_start_date,
  kt.experiment_status,
  kt.campaign_id,
  kt.campaign_name,
  kt.asin,
  ae.product_short_name,
  ae.parent_name,
  kt.search_term,

  -- Ramp milestones
  km.first_impression_date,
  km.first_click_date,
  km.first_order_date,
  DATE_DIFF(km.first_impression_date, kt.experiment_start_date, DAY) as days_to_first_impression,
  DATE_DIFF(km.first_click_date, kt.experiment_start_date, DAY) as days_to_first_click,
  DATE_DIFF(km.first_order_date, kt.experiment_start_date, DAY) as days_to_first_order,

  -- Starting configuration (from FACT_CAMPAIGN_CONFIG)
  COALESCE(sc.starting_keyword_bid, sc.starting_ag_default_bid) as starting_bid,
  sc.starting_daily_budget,
  sc.starting_bidding_strategy,
  sc.starting_tos_pct,
  sc.starting_product_page_pct,
  sc.starting_ros_pct,
  sc.config_snapshot_date,

  -- Current configuration
  COALESCE(cc.current_keyword_bid, cc.current_ag_default_bid) as current_bid,
  cc.current_daily_budget,
  cc.current_tos_pct,
  ROUND(SAFE_DIVIDE(
    COALESCE(cc.current_keyword_bid, cc.current_ag_default_bid) - COALESCE(sc.starting_keyword_bid, sc.starting_ag_default_bid),
    NULLIF(COALESCE(sc.starting_keyword_bid, sc.starting_ag_default_bid), 0)
  ) * 100, 1) as bid_change_pct,

  -- Overall metrics
  kt.total_impressions,
  kt.total_clicks,
  kt.total_orders,
  ROUND(kt.total_spend, 2) as total_spend,
  kt.weeks_active,
  ROUND(SAFE_DIVIDE(kt.total_spend, NULLIF(kt.total_clicks, 0)), 2) as avg_cpc,
  ROUND(SAFE_DIVIDE(kt.total_orders, NULLIF(kt.total_clicks, 0)) * 100, 2) as cvr_pct,
  ROUND(SAFE_DIVIDE(kt.total_orders * ae.margin_per_unit, NULLIF(kt.total_spend, 0)), 2) as net_roas,

  -- Weekly progression
  kt.w1_impressions, kt.w1_clicks, kt.w1_orders, ROUND(kt.w1_spend, 2) as w1_spend,
  kt.w2_impressions, kt.w2_clicks, kt.w2_orders, ROUND(kt.w2_spend, 2) as w2_spend,
  kt.w3_impressions, kt.w3_clicks, kt.w3_orders, ROUND(kt.w3_spend, 2) as w3_spend,
  kt.w4_impressions, kt.w4_clicks, kt.w4_orders, ROUND(kt.w4_spend, 2) as w4_spend,

  -- Weekly ROAS
  ROUND(SAFE_DIVIDE(kt.w1_orders * ae.margin_per_unit, NULLIF(kt.w1_spend, 0)), 2) as w1_net_roas,
  ROUND(SAFE_DIVIDE(kt.w2_orders * ae.margin_per_unit, NULLIF(kt.w2_spend, 0)), 2) as w2_net_roas,
  ROUND(SAFE_DIVIDE(kt.w3_orders * ae.margin_per_unit, NULLIF(kt.w3_spend, 0)), 2) as w3_net_roas,
  ROUND(SAFE_DIVIDE(kt.w4_orders * ae.margin_per_unit, NULLIF(kt.w4_spend, 0)), 2) as w4_net_roas,

  -- Ramp verdict
  CASE
    WHEN kt.total_spend < 5 THEN 'TOO_EARLY'
    WHEN km.first_order_date IS NOT NULL
      AND DATE_DIFF(km.first_order_date, kt.experiment_start_date, DAY) <= 7
      THEN 'FAST_START'
    WHEN km.first_order_date IS NOT NULL
      AND DATE_DIFF(km.first_order_date, kt.experiment_start_date, DAY) <= 14
      THEN 'NORMAL_START'
    WHEN km.first_order_date IS NOT NULL
      AND DATE_DIFF(km.first_order_date, kt.experiment_start_date, DAY) <= 28
      THEN 'SLOW_START'
    WHEN km.first_click_date IS NOT NULL AND km.first_order_date IS NULL
      AND kt.total_clicks >= 20
      THEN 'STALLED'
    WHEN km.first_impression_date IS NULL
      THEN 'NO_IMPRESSIONS'
    WHEN km.first_click_date IS NULL AND kt.total_impressions >= 100
      THEN 'NO_CLICKS'
    ELSE 'RAMPING'
  END as ramp_verdict,

  -- Ramp explanation
  CONCAT(
    CASE
      WHEN km.first_order_date IS NOT NULL THEN
        CONCAT('First order after ', CAST(DATE_DIFF(km.first_order_date, kt.experiment_start_date, DAY) AS STRING), ' days. ')
      WHEN km.first_click_date IS NOT NULL AND km.first_order_date IS NULL THEN
        CONCAT(CAST(kt.total_clicks AS STRING), ' clicks, 0 orders. ')
      WHEN km.first_impression_date IS NOT NULL THEN
        CONCAT(CAST(kt.total_impressions AS STRING), ' impressions, 0 clicks. ')
      ELSE 'No data yet. '
    END,
    'Config: bid $', CAST(ROUND(COALESCE(sc.starting_keyword_bid, sc.starting_ag_default_bid, 0), 2) AS STRING),
    ', TOS ', CAST(COALESCE(sc.starting_tos_pct, 0) AS INT64), '%',
    ', budget $', CAST(COALESCE(sc.starting_daily_budget, 0) AS INT64),
    ', strategy ', COALESCE(sc.starting_bidding_strategy, 'N/A'), '.'
  ) as ramp_explanation

FROM keyword_totals kt
JOIN asin_economics ae ON kt.asin = ae.asin
LEFT JOIN keyword_milestones km
  ON kt.experiment_id = km.experiment_id AND kt.campaign_id = km.campaign_id
  AND kt.asin = km.asin AND kt.search_term = km.search_term
LEFT JOIN starting_config sc ON kt.campaign_id = sc.campaign_id
LEFT JOIN current_config cc ON kt.campaign_id = cc.campaign_id
ORDER BY
  CASE
    WHEN km.first_order_date IS NULL THEN 0
    ELSE 1
  END,
  kt.total_spend DESC;
