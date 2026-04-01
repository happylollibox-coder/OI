-- =============================================
-- OI Database Project - V_ADS_COACH_DATA View
-- =============================================
--
-- Purpose: PURE DATA — all metrics at campaign × asin × search_term grain.
--          NO decision logic. This view is the data foundation for V_ADS_COACH.
--
-- Grain: campaign_id × asin × search_term  (ACTIVE_TERM rows)
--        NULL campaign × asin × search_term (OPPORTUNITY rows — SQP only, no ads)
--
-- Dual-grain support:
--   • search_term grain: for NEGATE, PROMOTE_TO_EXACT decisions
--   • target keyword grain (via target_* columns): for INCREASE/REDUCE_BID, SCALE_UP
--
-- Windows provided per row:
--   • Per-campaign 8w ads metrics (search term level)
--   • Per-campaign 1w + 4w ads metrics (for weighted ROAS)
--   • Weighted Net ROAS = 1w×0.5 + 4w×0.3 + 8w×0.2
--   • Target keyword rollup (aggregate all search terms under same target)
--   • Recent 5d ads activity (bleeding detection)
--   • Cross-campaign 8w aggregates (same keyword across ALL campaigns)
--   • Lifetime (all-time) ads metrics
--   • LY Peak ads metrics (last year's matching holiday season)
--   • SQP 8w: your ASIN + Amazon market measures
--   • SQP LY Peak: your ASIN + Amazon market measures
--   • Hero ASIN context (best child for this keyword)
--   • Search term segment/classification
--   • Unit economics (margin)
--
-- Dependencies:
--   FACT_AMAZON_ADS, FACT_SEARCH_QUERY,
--   DIM_PRODUCT, DIM_COSTS_HISTORY, DIM_EXPERIMENT, DIM_EXPERIMENT_CAMPAIGN,
--   DIM_STRATEGY_TEMPLATE, DIM_US_HOLIDAYS,
--   V_PARENT_HERO_ASIN, V_SEARCH_TERM_SEGMENT,
--   V_SRC_AmazonAds_campaign_history, fivetran portfolio_history
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_COACH_DATA`
AS
WITH

-- =============================================
-- Unit economics per ASIN
-- =============================================
asin_economics AS (
  SELECT
    p.asin,
    p.product_short_name,
    p.parent_name,
    p.listing_price_amount,
    COALESCE(ch.TOTAL_COST_PER_UNIT, 0) as total_cost_per_unit,
    p.listing_price_amount - COALESCE(ch.TOTAL_COST_PER_UNIT, 0) as margin_per_unit
  FROM `onyga-482313.OI.DIM_PRODUCT` p
  LEFT JOIN (
    SELECT asin, TOTAL_COST_PER_UNIT,
      ROW_NUMBER() OVER (PARTITION BY asin ORDER BY end_date DESC NULLS FIRST) as rn
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  ) ch ON p.asin = ch.asin AND ch.rn = 1
  WHERE p.asin IS NOT NULL
),

-- =============================================
-- Active experiments + campaigns → strategy mapping
-- =============================================
active_experiments AS (
  SELECT
    e.experiment_id,
    e.experiment_name,
    e.strategy_id,
    e.start_date,
    st.strategy_name,
    st.recommended_bid_min,
    st.recommended_bid_max
  FROM `onyga-482313.OI.DIM_EXPERIMENT` e
  LEFT JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st ON e.strategy_id = st.strategy_id
  WHERE e.status = 'ACTIVE'
),

campaign_experiment AS (
  SELECT
    ec.campaign_id,
    ae.experiment_id,
    ae.experiment_name,
    ae.strategy_id,
    ae.strategy_name,
    ae.start_date,
    ae.recommended_bid_max
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN active_experiments ae ON ec.experiment_id = ae.experiment_id
),

-- =============================================
-- LY Peak date range (for both Ads and SQP)
-- =============================================
next_holiday AS (
  SELECT holiday_name, holiday_date, pre_season_start
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
  WHERE category = 'gift_season' AND holiday_date >= CURRENT_DATE()
  ORDER BY holiday_date ASC LIMIT 1
),
ly_holiday AS (
  SELECT h.*
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
  JOIN next_holiday nh ON h.holiday_name = nh.holiday_name
  WHERE h.category = 'gift_season' AND h.holiday_date < nh.holiday_date
  ORDER BY h.holiday_date DESC LIMIT 1
),

-- =============================================
-- Campaign config: current bids from bulksheet snapshot
-- =============================================
campaign_config AS (
  SELECT
    campaign_id,
    LOWER(keyword_text) as keyword_text,
    keyword_id,
    bid as keyword_bid
  FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`
  WHERE entity_type = 'KEYWORD'
    AND snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`)
),

-- Product targeting config: AUTO targeting groups (close-match, substitutes, etc.) + ASIN targets
campaign_config_pt AS (
  SELECT
    campaign_id,
    product_targeting_id,
    LOWER(product_targeting_expression) as product_targeting_expression,
    pt_bid
  FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`
  WHERE entity_type = 'PRODUCT_TARGETING'
    AND snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`)
),

campaign_config_ag AS (
  SELECT campaign_id, ad_group_default_bid
  FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`
  WHERE entity_type = 'AD_GROUP'
    AND snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`)
),

-- SB keyword config: Sponsored Brands keyword bids
campaign_config_sb AS (
  SELECT
    campaign_id,
    keyword_id,
    LOWER(keyword_text) as keyword_text,
    bid as keyword_bid
  FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`
  WHERE entity_type = 'SB_KEYWORD'
    AND snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`)
),

-- =============================================
-- SECTION A: ACTIVE TERM DATA
-- Per campaign × asin × search_term
-- =============================================

-- Ads 8w: per campaign × asin × search_term (+ targeting/keyword_id)
ads_8w AS (
  SELECT
    ec.experiment_id,
    fa.campaign_id,
    ANY_VALUE(fa.ad_group_id HAVING MAX fa.date) as ad_group_id,
    fa.campaign_name,
    fa.campaign_type,
    'Unassigned' as portfolio_name,
    ce.strategy_id,
    ce.strategy_name,
    ce.experiment_name,
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    -- Target keyword (what you bid on) — fallback to config keyword_text for SBV
    COALESCE(fa.targeting, LOWER(kw_lookup.keyword_text)) as targeting,
    fa.keyword_id,

    SUM(fa.Ads_cost) as ads_spend_8w,
    SUM(fa.Ads_orders) as ads_orders_8w,
    SUM(fa.Ads_units) as ads_units_8w,
    SUM(fa.Ads_clicks) as ads_clicks_8w,
    SUM(fa.Ads_impressions) as ads_impressions_8w,
    SUM(fa.Ads_sales) as ads_sales_8w,
    COUNT(DISTINCT fa.date) as ads_days_8w,
    MIN(fa.date) as first_seen_8w,
    MAX(fa.date) as last_seen_8w,
    -- Recent 5d bleeding detection
    SUM(CASE WHEN fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 5 DAY) THEN fa.Ads_clicks ELSE 0 END) as ads_clicks_recent_5d

  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN campaign_experiment ce ON ec.campaign_id = ce.campaign_id AND ec.experiment_id = ce.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON ec.campaign_id = fa.campaign_id
    AND fa.date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 56 DAY)
                   AND DATE_SUB(CURRENT_DATE(), INTERVAL 4 DAY)


  -- Keyword text lookup for SBV campaigns where targeting is NULL
  LEFT JOIN (
    SELECT keyword_id, keyword_text,
           ROW_NUMBER() OVER(PARTITION BY keyword_id ORDER BY snapshot_date DESC) as rn
    FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`
    WHERE keyword_text IS NOT NULL AND keyword_id IS NOT NULL
  ) kw_lookup ON fa.keyword_id = kw_lookup.keyword_id AND kw_lookup.rn = 1
  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),

-- Ads 1w: recent 7 complete days (skip 3d attribution lag)
-- Today=March 22 → 1w = March 12–18
ads_1w AS (
  SELECT
    fa.campaign_id,
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    fa.targeting,
    SUM(fa.Ads_cost) as ads_spend_1w,
    SUM(fa.Ads_orders) as ads_orders_1w,
    SUM(fa.Ads_clicks) as ads_clicks_1w,
    SUM(fa.Ads_sales) as ads_sales_1w
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 10 DAY)
                     AND DATE_SUB(CURRENT_DATE(), INTERVAL 4 DAY)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2, 3, 4
),

-- Ads 4w: last 28 complete days (same attribution lag)
ads_4w AS (
  SELECT
    fa.campaign_id,
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    fa.targeting,
    SUM(fa.Ads_cost) as ads_spend_4w,
    SUM(fa.Ads_orders) as ads_orders_4w,
    SUM(fa.Ads_clicks) as ads_clicks_4w,
    SUM(fa.Ads_sales) as ads_sales_4w
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 31 DAY)
                     AND DATE_SUB(CURRENT_DATE(), INTERVAL 4 DAY)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2, 3, 4
),

-- Target keyword rollup: aggregate all search terms under same target
-- This is what you actually bid on in Amazon
target_rollup AS (
  SELECT
    campaign_id,
    targeting,
    keyword_id,
    asin,
    SUM(ads_spend_8w) as target_spend_8w,
    SUM(ads_orders_8w) as target_orders_8w,
    SUM(ads_clicks_8w) as target_clicks_8w,
    SUM(ads_impressions_8w) as target_impressions_8w,
    SUM(ads_sales_8w) as target_sales_8w,
    COUNT(DISTINCT search_term) as target_search_term_count,
    SUM(ads_clicks_recent_5d) as target_clicks_recent_5d
  FROM ads_8w
  GROUP BY 1, 2, 3, 4
),

-- Target rollup 1w: for weighted ROAS at target level
target_rollup_1w AS (
  SELECT
    campaign_id, targeting, asin,
    SUM(ads_spend_1w) as target_spend_1w,
    SUM(ads_orders_1w) as target_orders_1w,
    SUM(ads_sales_1w) as target_sales_1w
  FROM ads_1w
  GROUP BY 1, 2, 3
),

-- Target rollup 4w: for weighted ROAS at target level
target_rollup_4w AS (
  SELECT
    campaign_id, targeting, asin,
    SUM(ads_spend_4w) as target_spend_4w,
    SUM(ads_orders_4w) as target_orders_4w,
    SUM(ads_sales_4w) as target_sales_4w
  FROM ads_4w
  GROUP BY 1, 2, 3
),

-- Cross-campaign 8w: aggregate same keyword across ALL campaigns
-- (for reasoning: "does this keyword sell in OTHER campaigns?")
cross_campaign_8w AS (
  SELECT
    search_term,
    asin,
    SUM(ads_spend_8w) as xc_spend_8w,
    SUM(ads_orders_8w) as xc_orders_8w,
    SUM(ads_clicks_8w) as xc_clicks_8w,
    SUM(ads_impressions_8w) as xc_impressions_8w,
    SUM(ads_sales_8w) as xc_sales_8w,
    COUNT(DISTINCT campaign_id) as xc_campaign_count,
    COUNT(DISTINCT CASE WHEN ads_orders_8w > 0 THEN campaign_id END) as xc_selling_campaigns
  FROM ads_8w
  GROUP BY 1, 2
),

-- Ads lifetime: per term × ASIN (aggregated across all campaigns, all time)
ads_lifetime AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    SUM(fa.Ads_cost) as lt_spend,
    SUM(fa.Ads_orders) as lt_orders,
    SUM(fa.Ads_clicks) as lt_clicks,
    SUM(fa.Ads_sales) as lt_sales,
    COUNT(DISTINCT fa.date) as lt_days,
    MIN(fa.date) as lt_first_seen,
    MAX(fa.date) as lt_last_seen
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2
),

-- Ads LY Peak: per term × ASIN
ads_ly_peak AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    SUM(fa.Ads_cost) as ly_spend,
    SUM(fa.Ads_orders) as ly_orders,
    SUM(fa.Ads_units) as ly_units,
    SUM(fa.Ads_clicks) as ly_clicks,
    SUM(fa.Ads_impressions) as ly_impressions,
    SUM(fa.Ads_sales) as ly_sales
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  CROSS JOIN ly_holiday lyh
  WHERE fa.date >= lyh.pre_season_start AND fa.date <= lyh.holiday_date
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2
),

-- SQP 8w: Your ASIN + Amazon market measures
sqp_8w AS (
  SELECT
    LOWER(fsq.query_text) as search_term,
    fsq.ASIN as asin,
    -- Your ASIN measures
    SUM(fsq.impressions) as sqp_impressions_8w,
    SUM(fsq.clicks) as sqp_clicks_8w,
    SUM(fsq.cart_adds) as sqp_cart_adds_8w,
    SUM(fsq.conversions) as sqp_orders_8w,
    SUM(fsq.sales_amount) as sqp_sales_8w,
    AVG(fsq.show_rate_pct) as sqp_show_rate_8w,
    AVG(fsq.impression_share_pct) as sqp_impression_share_8w,
    AVG(fsq.estimated_organic_rank) as sqp_organic_rank_8w,
    -- Amazon market measures
    SUM(fsq.TOTAL_IMPRESSIONS) as sqp_amazon_impressions_8w,
    SUM(fsq.TOTAL_CLICKS) as sqp_amazon_clicks_8w,
    SUM(fsq.TOTAL_CART_ADDS) as sqp_amazon_cart_adds_8w,
    SUM(fsq.TOTAL_PURCHASES) as sqp_amazon_orders_8w,
    AVG(fsq.search_query_volume) as sqp_amazon_search_volume_8w,
    COUNT(DISTINCT fsq.week_end_date) as sqp_weeks_8w
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
  WHERE fsq.data_source = 'SQP' AND fsq.week_end_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 56 DAY)
  GROUP BY 1, 2
),

-- SQP LY Peak: Your ASIN + Amazon market measures
sqp_ly_peak AS (
  SELECT
    LOWER(fsq.query_text) as search_term,
    fsq.ASIN as asin,
    SUM(fsq.impressions) as sqp_ly_impressions,
    SUM(fsq.clicks) as sqp_ly_clicks,
    SUM(fsq.cart_adds) as sqp_ly_cart_adds,
    SUM(fsq.conversions) as sqp_ly_orders,
    SUM(fsq.sales_amount) as sqp_ly_sales,
    AVG(fsq.show_rate_pct) as sqp_ly_show_rate,
    AVG(fsq.impression_share_pct) as sqp_ly_impression_share,
    AVG(fsq.estimated_organic_rank) as sqp_ly_organic_rank,
    SUM(fsq.TOTAL_IMPRESSIONS) as sqp_ly_amazon_impressions,
    SUM(fsq.TOTAL_CLICKS) as sqp_ly_amazon_clicks,
    SUM(fsq.TOTAL_CART_ADDS) as sqp_ly_amazon_cart_adds,
    SUM(fsq.TOTAL_PURCHASES) as sqp_ly_amazon_orders,
    AVG(fsq.search_query_volume) as sqp_ly_amazon_search_volume
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
  CROSS JOIN ly_holiday lyh
  WHERE fsq.data_source = 'SQP'
    AND fsq.week_end_date >= lyh.pre_season_start AND fsq.week_end_date <= lyh.holiday_date
  GROUP BY 1, 2
),

-- Hero ASIN per search term (GLOBAL — best product across ALL families)
-- If "birthday gifts" converts best on Truth Or Dare (Family A), that's the hero
-- even if the current campaign advertises Lolli Box (Family B).
term_hero AS (
  SELECT
    search_term,
    asin as hero_asin,
    product_short_name as hero_product_name,
    parent_name as hero_parent_name,
    hero_score,
    sqp_cvr_pct as hero_sqp_cvr_pct,
    ads_cvr_pct as hero_ads_cvr_pct,
    confidence as hero_confidence
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY search_term ORDER BY hero_score DESC) as global_rank
    FROM `onyga-482313.OI.V_PARENT_HERO_ASIN`
    WHERE hero_score > 0
  )
  WHERE global_rank = 1
),

-- Search term segment/classification
term_classification AS (
  SELECT
    LOWER(search_term) as search_term,
    asin,
    experiment_segment,
    intent_segment,
    occasion,
    amazon_avg_weekly_orders,
    your_orders_share_pct,
    is_best_asin_for_term
  FROM `onyga-482313.OI.V_SEARCH_TERM_SEGMENT`
),

-- Check if term is already in an EXACT_BOOST experiment
exact_boost_terms AS (
  SELECT DISTINCT
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.DIM_EXPERIMENT` e ON ec.experiment_id = e.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec.campaign_id = fa.campaign_id
  WHERE e.strategy_id = 'EXACT_BOOST' AND e.status = 'ACTIVE'
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
),

-- =============================================
-- ACTIVE TERM ROWS: assemble all windows at campaign × asin × keyword grain
-- Now includes targeting (target keyword) and weighted ROAS
-- =============================================
active_term_data AS (
  SELECT
    'ACTIVE_TERM' as recommendation_type,

    -- Identity (grain)
    a8.campaign_id,
    a8.ad_group_id,
    a8.campaign_name,
    a8.campaign_type,
    a8.portfolio_name,
    a8.asin,
    ae.product_short_name,
    ae.parent_name,
    a8.search_term,
    a8.experiment_id,
    a8.experiment_name,
    a8.strategy_id,
    a8.strategy_name,
    -- Target keyword (what you bid on in Amazon)
    a8.targeting,
    a8.keyword_id,

    -- Unit economics
    ROUND(COALESCE(
      ae.margin_per_unit,
      SAFE_DIVIDE(a8.ads_sales_8w, NULLIF(a8.ads_orders_8w, 0)) - COALESCE(ae.total_cost_per_unit, 0)
    ), 2) as margin_per_unit,

    -- Per-campaign 8w ads metrics
    ROUND(a8.ads_spend_8w, 2) as ads_spend_8w,
    a8.ads_orders_8w,
    a8.ads_units_8w,
    a8.ads_clicks_8w,
    a8.ads_impressions_8w,
    ROUND(a8.ads_sales_8w, 2) as ads_sales_8w,
    a8.ads_days_8w,
    a8.first_seen_8w,
    a8.last_seen_8w,
    -- Derived per-campaign
    ROUND(SAFE_DIVIDE(a8.ads_spend_8w, NULLIF(a8.ads_clicks_8w, 0)), 2) as ads_cpc_8w,
    ROUND(SAFE_DIVIDE(a8.ads_orders_8w, NULLIF(a8.ads_clicks_8w, 0)) * 100, 2) as ads_cvr_pct_8w,
    ROUND(SAFE_DIVIDE(a8.ads_spend_8w, NULLIF(a8.ads_orders_8w, 0)), 2) as ads_cost_per_order_8w,
    ROUND(
      COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a8.ads_sales_8w, NULLIF(a8.ads_orders_8w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
        * a8.ads_orders_8w - a8.ads_spend_8w,
    2) as ads_net_profit_8w,
    ROUND(SAFE_DIVIDE(
      COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a8.ads_sales_8w, NULLIF(a8.ads_orders_8w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
        * a8.ads_orders_8w,
      NULLIF(a8.ads_spend_8w, 0)
    ), 2) as ads_net_roas_8w,

    -- 1w window Net ROAS (skip 3d attribution lag: last 7 complete days)
    ROUND(COALESCE(a1.ads_spend_1w, 0), 2) as ads_spend_1w,
    COALESCE(a1.ads_orders_1w, 0) as ads_orders_1w,
    COALESCE(a1.ads_clicks_1w, 0) as ads_clicks_1w,
    ROUND(SAFE_DIVIDE(
      COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a1.ads_sales_1w, NULLIF(a1.ads_orders_1w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
        * COALESCE(a1.ads_orders_1w, 0),
      NULLIF(COALESCE(a1.ads_spend_1w, 0), 0)
    ), 2) as ads_net_roas_1w,

    -- 4w window Net ROAS
    ROUND(COALESCE(a4.ads_spend_4w, 0), 2) as ads_spend_4w,
    COALESCE(a4.ads_orders_4w, 0) as ads_orders_4w,
    COALESCE(a4.ads_clicks_4w, 0) as ads_clicks_4w,
    ROUND(SAFE_DIVIDE(
      COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a4.ads_sales_4w, NULLIF(a4.ads_orders_4w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
        * COALESCE(a4.ads_orders_4w, 0),
      NULLIF(COALESCE(a4.ads_spend_4w, 0), 0)
    ), 2) as ads_net_roas_4w,

    -- Weighted Net ROAS = 1w×0.5 + 4w×0.3 + 8w×0.2
    -- Redistributes weights when a window has no spend
    ROUND(
      CASE
        WHEN COALESCE(a1.ads_spend_1w, 0) > 0 AND COALESCE(a4.ads_spend_4w, 0) > 0
        THEN
          SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a1.ads_sales_1w, NULLIF(a1.ads_orders_1w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
              * COALESCE(a1.ads_orders_1w, 0),
            NULLIF(COALESCE(a1.ads_spend_1w, 0), 0)
          ) * 0.5
          + SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a4.ads_sales_4w, NULLIF(a4.ads_orders_4w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
              * COALESCE(a4.ads_orders_4w, 0),
            NULLIF(COALESCE(a4.ads_spend_4w, 0), 0)
          ) * 0.3
          + SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a8.ads_sales_8w, NULLIF(a8.ads_orders_8w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
              * a8.ads_orders_8w,
            NULLIF(a8.ads_spend_8w, 0)
          ) * 0.2
        WHEN COALESCE(a1.ads_spend_1w, 0) = 0 AND COALESCE(a4.ads_spend_4w, 0) > 0
        THEN
          SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a4.ads_sales_4w, NULLIF(a4.ads_orders_4w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
              * COALESCE(a4.ads_orders_4w, 0),
            NULLIF(COALESCE(a4.ads_spend_4w, 0), 0)
          ) * 0.625
          + SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a8.ads_sales_8w, NULLIF(a8.ads_orders_8w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
              * a8.ads_orders_8w,
            NULLIF(a8.ads_spend_8w, 0)
          ) * 0.375
        ELSE
          SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a8.ads_sales_8w, NULLIF(a8.ads_orders_8w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
              * a8.ads_orders_8w,
            NULLIF(a8.ads_spend_8w, 0)
          )
      END
    , 2) as ads_weighted_net_roas,

    -- Recent 5d bleeding check
    a8.ads_clicks_recent_5d,

    -- Target keyword rollup (what you actually bid on)
    COALESCE(tr.target_spend_8w, a8.ads_spend_8w) as target_spend_8w,
    COALESCE(tr.target_orders_8w, a8.ads_orders_8w) as target_orders_8w,
    COALESCE(tr.target_clicks_8w, a8.ads_clicks_8w) as target_clicks_8w,
    COALESCE(tr.target_impressions_8w, a8.ads_impressions_8w) as target_impressions_8w,
    COALESCE(tr.target_search_term_count, 1) as target_search_term_count,
    COALESCE(tr.target_clicks_recent_5d, a8.ads_clicks_recent_5d) as target_clicks_recent_5d,
    ROUND(SAFE_DIVIDE(
      COALESCE(ae.margin_per_unit, 0) * COALESCE(tr.target_orders_8w, a8.ads_orders_8w),
      NULLIF(COALESCE(tr.target_spend_8w, a8.ads_spend_8w), 0)
    ), 2) as target_net_roas_8w,

    -- Target Weighted Net ROAS = 1w×0.5 + 4w×0.3 + 8w×0.2
    -- Same weighting as ads_weighted_net_roas but aggregated at target level
    ROUND(
      CASE
        WHEN COALESCE(tr1.target_spend_1w, 0) > 0 AND COALESCE(tr4.target_spend_4w, 0) > 0
        THEN
          SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, 0) * COALESCE(tr1.target_orders_1w, 0),
            NULLIF(COALESCE(tr1.target_spend_1w, 0), 0)
          ) * 0.5
          + SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, 0) * COALESCE(tr4.target_orders_4w, 0),
            NULLIF(COALESCE(tr4.target_spend_4w, 0), 0)
          ) * 0.3
          + SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, 0) * COALESCE(tr.target_orders_8w, a8.ads_orders_8w),
            NULLIF(COALESCE(tr.target_spend_8w, a8.ads_spend_8w), 0)
          ) * 0.2
        WHEN COALESCE(tr1.target_spend_1w, 0) = 0 AND COALESCE(tr4.target_spend_4w, 0) > 0
        THEN
          SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, 0) * COALESCE(tr4.target_orders_4w, 0),
            NULLIF(COALESCE(tr4.target_spend_4w, 0), 0)
          ) * 0.625
          + SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, 0) * COALESCE(tr.target_orders_8w, a8.ads_orders_8w),
            NULLIF(COALESCE(tr.target_spend_8w, a8.ads_spend_8w), 0)
          ) * 0.375
        ELSE
          SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, 0) * COALESCE(tr.target_orders_8w, a8.ads_orders_8w),
            NULLIF(COALESCE(tr.target_spend_8w, a8.ads_spend_8w), 0)
          )
      END
    , 2) as target_weighted_net_roas,

    -- Cross-campaign 8w context
    ROUND(COALESCE(xc.xc_spend_8w, a8.ads_spend_8w), 2) as xc_spend_8w,
    COALESCE(xc.xc_orders_8w, a8.ads_orders_8w) as xc_orders_8w,
    COALESCE(xc.xc_clicks_8w, a8.ads_clicks_8w) as xc_clicks_8w,
    COALESCE(xc.xc_campaign_count, 1) as xc_campaign_count,
    COALESCE(xc.xc_selling_campaigns, CASE WHEN a8.ads_orders_8w > 0 THEN 1 ELSE 0 END) as xc_selling_campaigns,
    -- This campaign's share
    ROUND(SAFE_DIVIDE(a8.ads_spend_8w, NULLIF(xc.xc_spend_8w, 0)) * 100, 1) as spend_share_pct,
    ROUND(SAFE_DIVIDE(a8.ads_orders_8w, NULLIF(xc.xc_orders_8w, 0)) * 100, 1) as orders_share_pct,

    -- Lifetime
    ROUND(COALESCE(lt.lt_spend, a8.ads_spend_8w), 2) as lt_spend,
    COALESCE(lt.lt_orders, a8.ads_orders_8w) as lt_orders,
    COALESCE(lt.lt_clicks, a8.ads_clicks_8w) as lt_clicks,
    COALESCE(lt.lt_days, a8.ads_days_8w) as lt_days,
    lt.lt_first_seen,
    lt.lt_last_seen,
    ROUND(SAFE_DIVIDE(
      COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a8.ads_sales_8w, NULLIF(a8.ads_orders_8w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
        * COALESCE(lt.lt_orders, a8.ads_orders_8w),
      NULLIF(COALESCE(lt.lt_spend, a8.ads_spend_8w), 0)
    ), 2) as lt_net_roas,

    -- LY Peak
    ROUND(COALESCE(lyp.ly_spend, 0), 2) as ly_spend,
    COALESCE(lyp.ly_orders, 0) as ly_orders,
    COALESCE(lyp.ly_clicks, 0) as ly_clicks,
    COALESCE(lyp.ly_impressions, 0) as ly_impressions,
    ROUND(SAFE_DIVIDE(COALESCE(lyp.ly_spend, 0), NULLIF(COALESCE(lyp.ly_clicks, 0), 0)), 2) as ly_cpc,
    ROUND(SAFE_DIVIDE(COALESCE(lyp.ly_orders, 0), NULLIF(COALESCE(lyp.ly_clicks, 0), 0)) * 100, 2) as ly_cvr_pct,
    ROUND(SAFE_DIVIDE(
      COALESCE(ae.margin_per_unit, 0) * COALESCE(lyp.ly_orders, 0),
      NULLIF(COALESCE(lyp.ly_spend, 0), 0)
    ), 2) as ly_net_roas,

    -- SQP 8w: Your ASIN
    COALESCE(sq8.sqp_impressions_8w, 0) as sqp_impressions_8w,
    COALESCE(sq8.sqp_clicks_8w, 0) as sqp_clicks_8w,
    COALESCE(sq8.sqp_cart_adds_8w, 0) as sqp_cart_adds_8w,
    COALESCE(sq8.sqp_orders_8w, 0) as sqp_orders_8w,
    ROUND(COALESCE(sq8.sqp_sales_8w, 0), 2) as sqp_sales_8w,
    GREATEST(0, COALESCE(sq8.sqp_orders_8w, 0) - a8.ads_orders_8w) as sqp_organic_units_8w,
    ROUND(COALESCE(sq8.sqp_show_rate_8w, 0), 2) as sqp_show_rate_8w,
    ROUND(COALESCE(sq8.sqp_impression_share_8w, 0), 2) as sqp_impression_share_8w,
    ROUND(COALESCE(sq8.sqp_organic_rank_8w, 0), 1) as sqp_organic_rank_8w,
    -- SQP 8w: Amazon market
    COALESCE(sq8.sqp_amazon_impressions_8w, 0) as sqp_amazon_impressions_8w,
    COALESCE(sq8.sqp_amazon_clicks_8w, 0) as sqp_amazon_clicks_8w,
    COALESCE(sq8.sqp_amazon_cart_adds_8w, 0) as sqp_amazon_cart_adds_8w,
    COALESCE(sq8.sqp_amazon_orders_8w, 0) as sqp_amazon_orders_8w,
    ROUND(COALESCE(sq8.sqp_amazon_search_volume_8w, 0), 0) as sqp_amazon_search_volume_8w,

    -- SQP LY Peak: Your ASIN
    COALESCE(sqlp.sqp_ly_impressions, 0) as sqp_ly_impressions,
    COALESCE(sqlp.sqp_ly_clicks, 0) as sqp_ly_clicks,
    COALESCE(sqlp.sqp_ly_cart_adds, 0) as sqp_ly_cart_adds,
    COALESCE(sqlp.sqp_ly_orders, 0) as sqp_ly_orders,
    ROUND(COALESCE(sqlp.sqp_ly_sales, 0), 2) as sqp_ly_sales,
    ROUND(COALESCE(sqlp.sqp_ly_show_rate, 0), 2) as sqp_ly_show_rate,
    ROUND(COALESCE(sqlp.sqp_ly_impression_share, 0), 2) as sqp_ly_impression_share,
    ROUND(COALESCE(sqlp.sqp_ly_organic_rank, 0), 1) as sqp_ly_organic_rank,
    -- SQP LY Peak: Amazon market
    COALESCE(sqlp.sqp_ly_amazon_impressions, 0) as sqp_ly_amazon_impressions,
    COALESCE(sqlp.sqp_ly_amazon_clicks, 0) as sqp_ly_amazon_clicks,
    COALESCE(sqlp.sqp_ly_amazon_cart_adds, 0) as sqp_ly_amazon_cart_adds,
    COALESCE(sqlp.sqp_ly_amazon_orders, 0) as sqp_ly_amazon_orders,
    ROUND(COALESCE(sqlp.sqp_ly_amazon_search_volume, 0), 0) as sqp_ly_amazon_search_volume,

    -- Hero ASIN
    th.hero_asin,
    th.hero_product_name,
    th.hero_score,
    th.hero_sqp_cvr_pct,
    th.hero_ads_cvr_pct,
    th.hero_confidence,
    COALESCE(a8.asin = th.hero_asin, FALSE) as is_hero_match,

    -- Segment / classification
    tc.experiment_segment,
    tc.intent_segment,
    tc.occasion,
    tc.amazon_avg_weekly_orders as market_weekly_orders,
    tc.your_orders_share_pct,
    COALESCE(tc.is_best_asin_for_term, FALSE) as is_best_asin_for_term,

    -- Already in EXACT_BOOST?
    ebt.search_term IS NOT NULL as already_in_exact_boost,

    -- Current bid from bulksheet config (SP keyword → SB keyword → product targeting → ad group default)
    ROUND(COALESCE(cc.keyword_bid, ccsb.keyword_bid, ccpt.pt_bid, ccag.ad_group_default_bid), 2) as current_bid

  FROM ads_8w a8
  JOIN asin_economics ae ON a8.asin = ae.asin
  LEFT JOIN ads_1w a1 ON a8.campaign_id = a1.campaign_id AND a8.search_term = a1.search_term AND a8.asin = a1.asin AND a8.targeting = a1.targeting
  LEFT JOIN ads_4w a4 ON a8.campaign_id = a4.campaign_id AND a8.search_term = a4.search_term AND a8.asin = a4.asin AND a8.targeting = a4.targeting
  LEFT JOIN target_rollup tr ON a8.campaign_id = tr.campaign_id AND a8.targeting = tr.targeting AND a8.keyword_id = tr.keyword_id AND a8.asin = tr.asin
  LEFT JOIN target_rollup_1w tr1 ON a8.campaign_id = tr1.campaign_id AND a8.targeting = tr1.targeting AND a8.asin = tr1.asin
  LEFT JOIN target_rollup_4w tr4 ON a8.campaign_id = tr4.campaign_id AND a8.targeting = tr4.targeting AND a8.asin = tr4.asin
  LEFT JOIN cross_campaign_8w xc ON a8.search_term = xc.search_term AND a8.asin = xc.asin
  LEFT JOIN ads_lifetime lt ON a8.search_term = lt.search_term AND a8.asin = lt.asin
  LEFT JOIN ads_ly_peak lyp ON a8.search_term = lyp.search_term AND a8.asin = lyp.asin
  LEFT JOIN sqp_8w sq8 ON a8.search_term = sq8.search_term AND a8.asin = sq8.asin
  LEFT JOIN sqp_ly_peak sqlp ON a8.search_term = sqlp.search_term AND a8.asin = sqlp.asin
  LEFT JOIN term_hero th ON a8.search_term = th.search_term
  LEFT JOIN term_classification tc ON a8.search_term = tc.search_term AND a8.asin = tc.asin
  LEFT JOIN exact_boost_terms ebt ON a8.search_term = ebt.search_term AND a8.asin = ebt.asin
  LEFT JOIN campaign_config cc ON a8.campaign_id = cc.campaign_id AND a8.keyword_id = cc.keyword_id
  LEFT JOIN campaign_config_sb ccsb ON a8.campaign_id = ccsb.campaign_id AND a8.keyword_id = ccsb.keyword_id
  LEFT JOIN campaign_config_pt ccpt ON a8.campaign_id = ccpt.campaign_id AND a8.keyword_id = ccpt.product_targeting_id
  LEFT JOIN campaign_config_ag ccag ON a8.campaign_id = ccag.campaign_id
),

-- =============================================
-- SECTION B: OPPORTUNITY TERMS
-- SQP terms with purchases NOT targeted by any active experiment
-- =============================================
all_experiment_targeted AS (
  SELECT DISTINCT
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN active_experiments ae ON ec.experiment_id = ae.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec.campaign_id = fa.campaign_id
  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
),

sqp_with_purchases AS (
  SELECT
    LOWER(fsq.query_text) as search_term,
    fsq.ASIN as asin,
    SUM(fsq.conversions) as sqp_purchases,
    SUM(fsq.clicks) as sqp_clicks,
    SUM(fsq.impressions) as sqp_impressions,
    SUM(fsq.sales_amount) as sqp_sales,
    COUNT(DISTINCT fsq.week_end_date) as sqp_weeks
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
  WHERE fsq.data_source = 'SQP'
    AND fsq.week_end_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 56 DAY)
    AND fsq.conversions > 0
  GROUP BY 1, 2
  HAVING SUM(fsq.conversions) >= 1
),

opportunity_data AS (
  SELECT
    'OPPORTUNITY' as recommendation_type,

    -- Identity (no campaign for opportunity rows)
    CAST(NULL AS STRING) as campaign_id,
    CAST(NULL AS STRING) as ad_group_id,
    CAST(NULL AS STRING) as campaign_name,
    CAST(NULL AS STRING) as campaign_type,
    'Unassigned' as portfolio_name,
    COALESCE(th.hero_asin, sp.asin) as asin,
    COALESCE(th.hero_product_name, ae.product_short_name) as product_short_name,
    ae.parent_name,
    sp.search_term,
    CAST(NULL AS STRING) as experiment_id,
    CAST(NULL AS STRING) as experiment_name,
    -- Suggest strategy based on segment
    CASE
      WHEN tc.experiment_segment = 'BRAND' THEN 'BRAND_DEFENSE'
      WHEN tc.intent_segment = 'COMPETITOR' THEN 'CATEGORY_CONQUEST'
      WHEN sp.sqp_purchases >= 3 AND sp.sqp_weeks >= 2 THEN 'EXACT_BOOST'
      WHEN sp.sqp_purchases >= 2 THEN 'EXACT_BOOST'
      ELSE 'HUNTER'
    END as strategy_id,
    CAST(NULL AS STRING) as strategy_name,
    -- Target keyword (N/A for opportunities)
    CAST(NULL AS STRING) as targeting,
    CAST(NULL AS STRING) as keyword_id,

    -- Unit economics
    ROUND(COALESCE(hero_ae.margin_per_unit, ae.margin_per_unit), 2) as margin_per_unit,

    -- Per-campaign 8w (all zeros for opportunity)
    0.0 as ads_spend_8w, 0 as ads_orders_8w, 0 as ads_units_8w, 0 as ads_clicks_8w,
    0 as ads_impressions_8w, 0.0 as ads_sales_8w, CAST(NULL AS INT64) as ads_days_8w,
    CAST(NULL AS DATE) as first_seen_8w, CAST(NULL AS DATE) as last_seen_8w,
    CAST(NULL AS FLOAT64) as ads_cpc_8w, CAST(NULL AS FLOAT64) as ads_cvr_pct_8w,
    CAST(NULL AS FLOAT64) as ads_cost_per_order_8w,
    0.0 as ads_net_profit_8w, CAST(NULL AS FLOAT64) as ads_net_roas_8w,
    -- 1w/4w windows (zeros for opportunity)
    0.0 as ads_spend_1w, 0 as ads_orders_1w, 0 as ads_clicks_1w, CAST(NULL AS FLOAT64) as ads_net_roas_1w,
    0.0 as ads_spend_4w, 0 as ads_orders_4w, 0 as ads_clicks_4w, CAST(NULL AS FLOAT64) as ads_net_roas_4w,
    CAST(NULL AS FLOAT64) as ads_weighted_net_roas,
    0 as ads_clicks_recent_5d,
    -- Target rollup (zeros for opportunity)
    0.0 as target_spend_8w, 0 as target_orders_8w, 0 as target_clicks_8w,
    0 as target_impressions_8w, 0 as target_search_term_count, 0 as target_clicks_recent_5d,
    CAST(NULL AS FLOAT64) as target_net_roas_8w,
    CAST(NULL AS FLOAT64) as target_weighted_net_roas,

    -- Cross-campaign (zeros)
    0.0 as xc_spend_8w, 0 as xc_orders_8w, 0 as xc_clicks_8w,
    0 as xc_campaign_count, 0 as xc_selling_campaigns,
    CAST(NULL AS FLOAT64) as spend_share_pct, CAST(NULL AS FLOAT64) as orders_share_pct,

    -- Lifetime (zeros)
    0.0 as lt_spend, 0 as lt_orders, 0 as lt_clicks, CAST(NULL AS INT64) as lt_days,
    CAST(NULL AS DATE) as lt_first_seen, CAST(NULL AS DATE) as lt_last_seen,
    CAST(NULL AS FLOAT64) as lt_net_roas,

    -- LY Peak (zeros)
    0.0 as ly_spend, 0 as ly_orders, 0 as ly_clicks, 0 as ly_impressions,
    CAST(NULL AS FLOAT64) as ly_cpc, CAST(NULL AS FLOAT64) as ly_cvr_pct,
    CAST(NULL AS FLOAT64) as ly_net_roas,

    -- SQP 8w (from sqp_with_purchases)
    sp.sqp_impressions as sqp_impressions_8w,
    sp.sqp_clicks as sqp_clicks_8w,
    0 as sqp_cart_adds_8w,
    sp.sqp_purchases as sqp_orders_8w,
    ROUND(sp.sqp_sales, 2) as sqp_sales_8w,
    sp.sqp_purchases as sqp_organic_units_8w,
    0.0 as sqp_show_rate_8w, 0.0 as sqp_impression_share_8w, 0.0 as sqp_organic_rank_8w,
    0 as sqp_amazon_impressions_8w, 0 as sqp_amazon_clicks_8w,
    0 as sqp_amazon_cart_adds_8w, 0 as sqp_amazon_orders_8w, 0.0 as sqp_amazon_search_volume_8w,

    -- SQP LY Peak (zeros for now — could enrich later)
    COALESCE(sqlp.sqp_ly_impressions, 0) as sqp_ly_impressions,
    COALESCE(sqlp.sqp_ly_clicks, 0) as sqp_ly_clicks,
    COALESCE(sqlp.sqp_ly_cart_adds, 0) as sqp_ly_cart_adds,
    COALESCE(sqlp.sqp_ly_orders, 0) as sqp_ly_orders,
    ROUND(COALESCE(sqlp.sqp_ly_sales, 0), 2) as sqp_ly_sales,
    ROUND(COALESCE(sqlp.sqp_ly_show_rate, 0), 2) as sqp_ly_show_rate,
    ROUND(COALESCE(sqlp.sqp_ly_impression_share, 0), 2) as sqp_ly_impression_share,
    ROUND(COALESCE(sqlp.sqp_ly_organic_rank, 0), 1) as sqp_ly_organic_rank,
    COALESCE(sqlp.sqp_ly_amazon_impressions, 0) as sqp_ly_amazon_impressions,
    COALESCE(sqlp.sqp_ly_amazon_clicks, 0) as sqp_ly_amazon_clicks,
    COALESCE(sqlp.sqp_ly_amazon_cart_adds, 0) as sqp_ly_amazon_cart_adds,
    COALESCE(sqlp.sqp_ly_amazon_orders, 0) as sqp_ly_amazon_orders,
    ROUND(COALESCE(sqlp.sqp_ly_amazon_search_volume, 0), 0) as sqp_ly_amazon_search_volume,

    -- Hero ASIN
    th.hero_asin,
    th.hero_product_name,
    th.hero_score,
    th.hero_sqp_cvr_pct,
    th.hero_ads_cvr_pct,
    th.hero_confidence,
    COALESCE(sp.asin = th.hero_asin, FALSE) as is_hero_match,

    -- Segment
    tc.experiment_segment,
    tc.intent_segment,
    tc.occasion,
    tc.amazon_avg_weekly_orders as market_weekly_orders,
    tc.your_orders_share_pct,
    COALESCE(tc.is_best_asin_for_term, FALSE) as is_best_asin_for_term,

    -- Not in any campaign, so no EXACT_BOOST check
    FALSE as already_in_exact_boost,

    -- No bid for opportunity rows
    CAST(NULL AS FLOAT64) as current_bid

  FROM sqp_with_purchases sp
  JOIN asin_economics ae ON sp.asin = ae.asin
  LEFT JOIN all_experiment_targeted aet
    ON sp.search_term = aet.search_term AND sp.asin = aet.asin
  LEFT JOIN term_classification tc
    ON sp.search_term = tc.search_term AND sp.asin = tc.asin
  LEFT JOIN term_hero th
    ON sp.search_term = th.search_term
  LEFT JOIN asin_economics hero_ae ON th.hero_asin = hero_ae.asin
  LEFT JOIN sqp_ly_peak sqlp ON sp.search_term = sqlp.search_term AND sp.asin = sqlp.asin
  WHERE aet.search_term IS NULL  -- Not targeted by any experiment
)

-- =============================================
-- Final: UNION active terms + opportunities
-- =============================================
SELECT * FROM active_term_data
UNION ALL
SELECT * FROM opportunity_data;
