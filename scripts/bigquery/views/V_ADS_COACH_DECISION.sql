-- =============================================
-- OI Database Project - V_ADS_COACH_DECISION View
-- =============================================
--
-- Purpose: ONE ROW PER SEARCH TERM.
--          Aggregated evidence across all campaigns + overall decision.
--          This is the "what should I do with this keyword?" view.
--
-- Grain: search_term (lowercase)
--
-- Columns:
--   4w metrics (aggregated across all campaigns)
--   LY Peak metrics (aggregated)
--   SQP (market demand)
--   Margin, net ROAS
--   Decision + full reasoning
--
-- Dependencies:
--   FACT_AMAZON_ADS, DIM_PRODUCT, DIM_COSTS_HISTORY,
--   DIM_US_HOLIDAYS, FACT_SEARCH_QUERY, DE_COACH_THRESHOLDS
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_COACH_DECISION`
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
-- LY Peak date range
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
-- Ads 4w: per term × ASIN (aggregated across campaigns)
-- =============================================
ads_4w_by_term AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    COUNT(DISTINCT fa.campaign_id) as campaign_count_4w,
    COUNT(DISTINCT fa.campaign_type) as campaign_type_count_4w,
    SUM(fa.Ads_cost) as ads_spend_4w,
    SUM(fa.Ads_orders) as ads_orders_4w,
    SUM(fa.Ads_units) as ads_units_4w,
    SUM(fa.Ads_clicks) as ads_clicks_4w,
    SUM(fa.Ads_impressions) as ads_impressions_4w,
    SUM(fa.Ads_sales) as ads_sales_4w,
    COUNT(DISTINCT fa.date) as ads_days_4w,
    -- How many campaigns actually sold?
    COUNT(DISTINCT CASE WHEN fa.Ads_orders > 0 THEN fa.campaign_id END) as selling_campaigns_4w
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2
),

-- =============================================
-- Ads 7d: check if term had ANY activity in last 7 days
-- If zero impressions in 7d → STOP/NEGATE action is likely unnecessary
-- =============================================
ads_7d_activity AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    SUM(fa.Ads_impressions) as ads_impressions_7d,
    SUM(fa.Ads_cost) as ads_spend_7d,
    SUM(fa.Ads_clicks) as ads_clicks_7d,
    MAX(fa.date) as last_ad_date
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2
),

-- Ads lifetime: per term × ASIN
ads_lifetime_by_term AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    SUM(fa.Ads_cost) as ads_spend_lifetime,
    SUM(fa.Ads_orders) as ads_orders_lifetime,
    SUM(fa.Ads_clicks) as ads_clicks_lifetime,
    SUM(fa.Ads_sales) as ads_sales_lifetime,
    COUNT(DISTINCT fa.date) as ads_days_lifetime,
    MIN(fa.date) as first_seen_ever,
    MAX(fa.date) as last_seen_ever
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2
),

-- Ads LY Peak: per term × ASIN
ads_ly_peak_by_term AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    SUM(fa.Ads_cost) as ads_spend_ly_peak,
    SUM(fa.Ads_orders) as ads_orders_ly_peak,
    SUM(fa.Ads_units) as ads_units_ly_peak,
    SUM(fa.Ads_clicks) as ads_clicks_ly_peak,
    SUM(fa.Ads_impressions) as ads_impressions_ly_peak,
    SUM(fa.Ads_sales) as ads_sales_ly_peak
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  CROSS JOIN ly_holiday lyh
  WHERE fa.date >= lyh.pre_season_start AND fa.date <= lyh.holiday_date
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.advertised_asins, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2
),

-- SQP 4w: Your ASIN + Amazon market measures
sqp_4w AS (
  SELECT
    LOWER(fsq.query_text) as search_term,
    fsq.ASIN as asin,
    -- Your ASIN measures
    SUM(fsq.impressions) as sqp_impressions_4w,
    SUM(fsq.clicks) as sqp_clicks_4w,
    SUM(fsq.cart_adds) as sqp_cart_adds_4w,
    SUM(fsq.conversions) as sqp_orders_4w,
    SUM(fsq.sales_amount) as sqp_sales_4w,
    AVG(fsq.show_rate_pct) as sqp_show_rate_4w,
    AVG(fsq.impression_share_pct) as sqp_impression_share_4w,
    AVG(fsq.estimated_organic_rank) as sqp_organic_rank_4w,
    -- Amazon market measures (TOTAL_ prefix in source → "amazon" in output)
    SUM(fsq.TOTAL_IMPRESSIONS) as sqp_amazon_impressions_4w,
    SUM(fsq.TOTAL_CLICKS) as sqp_amazon_clicks_4w,
    SUM(fsq.TOTAL_CART_ADDS) as sqp_amazon_cart_adds_4w,
    SUM(fsq.TOTAL_PURCHASES) as sqp_amazon_orders_4w,
    AVG(fsq.search_query_volume) as sqp_amazon_search_volume_4w
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
  WHERE fsq.data_source = 'SQP' AND fsq.week_end_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
  GROUP BY 1, 2
),

-- SQP LY Peak: Your ASIN + Amazon market measures
sqp_ly_peak AS (
  SELECT
    LOWER(fsq.query_text) as search_term,
    fsq.ASIN as asin,
    -- Your ASIN measures
    SUM(fsq.impressions) as sqp_impressions_ly_peak,
    SUM(fsq.clicks) as sqp_clicks_ly_peak,
    SUM(fsq.cart_adds) as sqp_cart_adds_ly_peak,
    SUM(fsq.conversions) as sqp_orders_ly_peak,
    SUM(fsq.sales_amount) as sqp_sales_ly_peak,
    AVG(fsq.show_rate_pct) as sqp_show_rate_ly_peak,
    AVG(fsq.impression_share_pct) as sqp_impression_share_ly_peak,
    AVG(fsq.estimated_organic_rank) as sqp_organic_rank_ly_peak,
    -- Amazon market measures
    SUM(fsq.TOTAL_IMPRESSIONS) as sqp_amazon_impressions_ly_peak,
    SUM(fsq.TOTAL_CLICKS) as sqp_amazon_clicks_ly_peak,
    SUM(fsq.TOTAL_CART_ADDS) as sqp_amazon_cart_adds_ly_peak,
    SUM(fsq.TOTAL_PURCHASES) as sqp_amazon_orders_ly_peak,
    AVG(fsq.search_query_volume) as sqp_amazon_search_volume_ly_peak
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
  CROSS JOIN ly_holiday lyh
  WHERE fsq.data_source = 'SQP'
    AND fsq.week_end_date >= lyh.pre_season_start AND fsq.week_end_date <= lyh.holiday_date
  GROUP BY 1, 2
),

-- =============================================
-- Assemble per term × ASIN (will pick best ASIN below)
-- =============================================
term_asin AS (
  SELECT
    a4.search_term,
    a4.asin,
    ae.product_short_name,
    ae.parent_name,
    -- Margin: use listing price if available, else actual selling price from ads
    ROUND(COALESCE(
      ae.margin_per_unit,
      SAFE_DIVIDE(a4.ads_sales_4w, NULLIF(a4.ads_orders_4w, 0)) - COALESCE(ae.total_cost_per_unit, 0)
    ), 2) as margin_per_unit,

    -- 4w metrics
    a4.campaign_count_4w,
    a4.campaign_type_count_4w,
    a4.selling_campaigns_4w,
    ROUND(a4.ads_spend_4w, 2) as ads_spend_4w,
    a4.ads_orders_4w,
    a4.ads_units_4w,
    a4.ads_clicks_4w,
    a4.ads_impressions_4w,
    ROUND(a4.ads_sales_4w, 2) as ads_sales_4w,
    a4.ads_days_4w,

    -- Derived 4w
    ROUND(SAFE_DIVIDE(a4.ads_spend_4w, NULLIF(a4.ads_clicks_4w, 0)), 2) as ads_cpc_4w,
    ROUND(SAFE_DIVIDE(a4.ads_orders_4w, NULLIF(a4.ads_clicks_4w, 0)) * 100, 2) as ads_cvr_pct_4w,
    ROUND(SAFE_DIVIDE(a4.ads_spend_4w, NULLIF(a4.ads_orders_4w, 0)), 2) as ads_cost_per_order_4w,
    -- Net profit: margin × orders - spend
    ROUND(
      COALESCE(
        ae.margin_per_unit,
        SAFE_DIVIDE(a4.ads_sales_4w, NULLIF(a4.ads_orders_4w, 0)) - COALESCE(ae.total_cost_per_unit, 0)
      ) * a4.ads_orders_4w - a4.ads_spend_4w,
    2) as ads_net_profit_4w,
    -- Net ROAS: margin × orders / spend
    ROUND(SAFE_DIVIDE(
      COALESCE(
        ae.margin_per_unit,
        SAFE_DIVIDE(a4.ads_sales_4w, NULLIF(a4.ads_orders_4w, 0)) - COALESCE(ae.total_cost_per_unit, 0)
      ) * a4.ads_orders_4w,
      NULLIF(a4.ads_spend_4w, 0)
    ), 2) as ads_net_roas_4w,

    -- Lifetime
    ROUND(COALESCE(al.ads_spend_lifetime, a4.ads_spend_4w), 2) as ads_spend_lifetime,
    COALESCE(al.ads_orders_lifetime, a4.ads_orders_4w) as ads_orders_lifetime,
    COALESCE(al.ads_clicks_lifetime, a4.ads_clicks_4w) as ads_clicks_lifetime,
    COALESCE(al.ads_days_lifetime, a4.ads_days_4w) as ads_days_lifetime,
    al.first_seen_ever,
    al.last_seen_ever,
    ROUND(SAFE_DIVIDE(
      COALESCE(
        ae.margin_per_unit,
        SAFE_DIVIDE(a4.ads_sales_4w, NULLIF(a4.ads_orders_4w, 0)) - COALESCE(ae.total_cost_per_unit, 0)
      ) * COALESCE(al.ads_orders_lifetime, a4.ads_orders_4w),
      NULLIF(COALESCE(al.ads_spend_lifetime, a4.ads_spend_4w), 0)
    ), 2) as ads_net_roas_lifetime,

    -- Ads LY Peak
    ROUND(COALESCE(alp.ads_spend_ly_peak, 0), 2) as ads_spend_ly_peak,
    COALESCE(alp.ads_orders_ly_peak, 0) as ads_orders_ly_peak,
    COALESCE(alp.ads_units_ly_peak, 0) as ads_units_ly_peak,
    COALESCE(alp.ads_clicks_ly_peak, 0) as ads_clicks_ly_peak,
    COALESCE(alp.ads_impressions_ly_peak, 0) as ads_impressions_ly_peak,
    ROUND(COALESCE(alp.ads_sales_ly_peak, 0), 2) as ads_sales_ly_peak,
    -- Ads LY Peak derived
    ROUND(SAFE_DIVIDE(COALESCE(alp.ads_spend_ly_peak, 0), NULLIF(COALESCE(alp.ads_clicks_ly_peak, 0), 0)), 2) as ads_cpc_ly_peak,
    ROUND(SAFE_DIVIDE(COALESCE(alp.ads_orders_ly_peak, 0), NULLIF(COALESCE(alp.ads_clicks_ly_peak, 0), 0)) * 100, 2) as ads_cvr_pct_ly_peak,
    ROUND(SAFE_DIVIDE(
      COALESCE(ae.margin_per_unit, SAFE_DIVIDE(alp.ads_sales_ly_peak, NULLIF(alp.ads_orders_ly_peak, 0)) - COALESCE(ae.total_cost_per_unit, 0))
        * COALESCE(alp.ads_orders_ly_peak, 0),
      NULLIF(COALESCE(alp.ads_spend_ly_peak, 0), 0)
    ), 2) as ads_net_roas_ly_peak,

    -- SQP 4w: Your ASIN
    COALESCE(sq4.sqp_impressions_4w, 0) as sqp_impressions_4w,
    COALESCE(sq4.sqp_clicks_4w, 0) as sqp_clicks_4w,
    COALESCE(sq4.sqp_cart_adds_4w, 0) as sqp_cart_adds_4w,
    COALESCE(sq4.sqp_orders_4w, 0) as sqp_orders_4w,
    ROUND(COALESCE(sq4.sqp_sales_4w, 0), 2) as sqp_sales_4w,
    GREATEST(0, COALESCE(sq4.sqp_orders_4w, 0) - a4.ads_orders_4w) as sqp_organic_units_4w,
    ROUND(COALESCE(sq4.sqp_show_rate_4w, 0), 2) as sqp_show_rate_4w,
    ROUND(COALESCE(sq4.sqp_impression_share_4w, 0), 2) as sqp_impression_share_4w,
    ROUND(COALESCE(sq4.sqp_organic_rank_4w, 0), 1) as sqp_organic_rank_4w,
    -- SQP 4w: Amazon market
    COALESCE(sq4.sqp_amazon_impressions_4w, 0) as sqp_amazon_impressions_4w,
    COALESCE(sq4.sqp_amazon_clicks_4w, 0) as sqp_amazon_clicks_4w,
    COALESCE(sq4.sqp_amazon_cart_adds_4w, 0) as sqp_amazon_cart_adds_4w,
    COALESCE(sq4.sqp_amazon_orders_4w, 0) as sqp_amazon_orders_4w,
    ROUND(COALESCE(sq4.sqp_amazon_search_volume_4w, 0), 0) as sqp_amazon_search_volume_4w,

    -- SQP LY Peak: Your ASIN
    COALESCE(sqlp.sqp_impressions_ly_peak, 0) as sqp_impressions_ly_peak,
    COALESCE(sqlp.sqp_clicks_ly_peak, 0) as sqp_clicks_ly_peak,
    COALESCE(sqlp.sqp_cart_adds_ly_peak, 0) as sqp_cart_adds_ly_peak,
    COALESCE(sqlp.sqp_orders_ly_peak, 0) as sqp_orders_ly_peak,
    ROUND(COALESCE(sqlp.sqp_sales_ly_peak, 0), 2) as sqp_sales_ly_peak,
    ROUND(COALESCE(sqlp.sqp_show_rate_ly_peak, 0), 2) as sqp_show_rate_ly_peak,
    ROUND(COALESCE(sqlp.sqp_impression_share_ly_peak, 0), 2) as sqp_impression_share_ly_peak,
    ROUND(COALESCE(sqlp.sqp_organic_rank_ly_peak, 0), 1) as sqp_organic_rank_ly_peak,
    -- SQP LY Peak: Amazon market
    COALESCE(sqlp.sqp_amazon_impressions_ly_peak, 0) as sqp_amazon_impressions_ly_peak,
    COALESCE(sqlp.sqp_amazon_clicks_ly_peak, 0) as sqp_amazon_clicks_ly_peak,
    COALESCE(sqlp.sqp_amazon_cart_adds_ly_peak, 0) as sqp_amazon_cart_adds_ly_peak,
    COALESCE(sqlp.sqp_amazon_orders_ly_peak, 0) as sqp_amazon_orders_ly_peak,
    ROUND(COALESCE(sqlp.sqp_amazon_search_volume_ly_peak, 0), 0) as sqp_amazon_search_volume_ly_peak,

    -- 7d activity (for stale-action detection)
    COALESCE(a7.ads_impressions_7d, 0) as ads_impressions_7d,
    ROUND(COALESCE(a7.ads_spend_7d, 0), 2) as ads_spend_7d,
    COALESCE(a7.ads_clicks_7d, 0) as ads_clicks_7d,
    a7.last_ad_date,

    -- Rank: pick best ASIN per term (most orders, then most spend)
    ROW_NUMBER() OVER (PARTITION BY a4.search_term ORDER BY a4.ads_orders_4w DESC, a4.ads_spend_4w DESC) as asin_rank

  FROM ads_4w_by_term a4
  LEFT JOIN asin_economics ae ON a4.asin = ae.asin
  LEFT JOIN ads_7d_activity a7 ON a4.search_term = a7.search_term AND a4.asin = a7.asin
  LEFT JOIN ads_lifetime_by_term al ON a4.search_term = al.search_term AND a4.asin = al.asin
  LEFT JOIN ads_ly_peak_by_term alp ON a4.search_term = alp.search_term AND a4.asin = alp.asin
  LEFT JOIN sqp_4w sq4 ON a4.search_term = sq4.search_term AND a4.asin = sq4.asin
  LEFT JOIN sqp_ly_peak sqlp ON a4.search_term = sqlp.search_term AND a4.asin = sqlp.asin
),

-- =============================================
-- Thresholds: resolve from DE_COACH_THRESHOLDS
-- Priority: GLOBAL defaults (strategy-specific applied at dashboard layer)
-- COALESCE ensures hardcoded fallback if table is empty
-- =============================================
coach_thresholds AS (
  SELECT
    COALESCE(MAX(IF(threshold_key='INSUFFICIENT_DATA_CLICKS', threshold_value, NULL)), 15) as insufficient_data_clicks,
    COALESCE(MAX(IF(threshold_key='WASTED_SPEND_THRESHOLD', threshold_value, NULL)), 15) as wasted_spend_threshold,
    COALESCE(MAX(IF(threshold_key='NEGATE_ROAS_THRESHOLD', threshold_value, NULL)), 0.5) as negate_roas_threshold,
    COALESCE(MAX(IF(threshold_key='NEGATE_SPEND_THRESHOLD', threshold_value, NULL)), 20) as negate_spend_threshold,
    COALESCE(MAX(IF(threshold_key='REDUCE_BID_ROAS', threshold_value, NULL)), 0.7) as reduce_bid_roas,
    COALESCE(MAX(IF(threshold_key='REDUCE_BID_SPEND', threshold_value, NULL)), 10) as reduce_bid_spend,
    COALESCE(MAX(IF(threshold_key='SCALE_UP_ROAS', threshold_value, NULL)), 2.0) as scale_up_roas,
    COALESCE(MAX(IF(threshold_key='SCALE_UP_SPEND_CAP', threshold_value, NULL)), 50) as scale_up_spend_cap,
    COALESCE(MAX(IF(threshold_key='PROFITABLE_ROAS', threshold_value, NULL)), 1.0) as profitable_roas,
    COALESCE(MAX(IF(threshold_key='HALO_ROAS', threshold_value, NULL)), 0.5) as halo_roas,
    COALESCE(MAX(IF(threshold_key='CONFIDENCE_DAYS_HIGH', threshold_value, NULL)), 14) as confidence_days_high,
    COALESCE(MAX(IF(threshold_key='CONFIDENCE_CLICKS_HIGH', threshold_value, NULL)), 50) as confidence_clicks_high,
    COALESCE(MAX(IF(threshold_key='CONFIDENCE_DAYS_MEDIUM', threshold_value, NULL)), 7) as confidence_days_medium,
    COALESCE(MAX(IF(threshold_key='CONFIDENCE_CLICKS_MEDIUM', threshold_value, NULL)), 20) as confidence_clicks_medium
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id = 'GLOBAL' AND product_family IS NULL
)

-- =============================================
-- Final: one row per search term (best ASIN)
-- =============================================
SELECT
  t.search_term,
  t.asin as best_asin,
  t.product_short_name,
  t.parent_name,
  t.margin_per_unit,

  -- 4w
  t.campaign_count_4w,
  t.campaign_type_count_4w,
  t.selling_campaigns_4w,
  t.ads_spend_4w,
  t.ads_orders_4w,
  t.ads_units_4w,
  t.ads_clicks_4w,
  t.ads_impressions_4w,
  t.ads_sales_4w,
  t.ads_days_4w,
  t.ads_cpc_4w,
  t.ads_cvr_pct_4w,
  t.ads_cost_per_order_4w,
  t.ads_net_profit_4w,
  t.ads_net_roas_4w,

  -- Lifetime
  t.ads_spend_lifetime,
  t.ads_orders_lifetime,
  t.ads_clicks_lifetime,
  t.ads_days_lifetime,
  t.first_seen_ever,
  t.last_seen_ever,
  t.ads_net_roas_lifetime,

  -- 7d activity
  t.ads_impressions_7d,
  t.ads_spend_7d,
  t.ads_clicks_7d,
  t.last_ad_date,
  COALESCE(t.ads_impressions_7d, 0) > 0 as ads_active_last_7d,

  -- Ads LY Peak
  t.ads_spend_ly_peak,
  t.ads_orders_ly_peak,
  t.ads_units_ly_peak,
  t.ads_clicks_ly_peak,
  t.ads_impressions_ly_peak,
  t.ads_sales_ly_peak,
  t.ads_cpc_ly_peak,
  t.ads_cvr_pct_ly_peak,
  t.ads_net_roas_ly_peak,

  -- SQP 4w: Your ASIN
  t.sqp_impressions_4w,
  t.sqp_clicks_4w,
  t.sqp_cart_adds_4w,
  t.sqp_orders_4w,
  t.sqp_sales_4w,
  t.sqp_organic_units_4w,
  t.sqp_show_rate_4w,
  t.sqp_impression_share_4w,
  t.sqp_organic_rank_4w,
  -- SQP 4w: Amazon market
  t.sqp_amazon_impressions_4w,
  t.sqp_amazon_clicks_4w,
  t.sqp_amazon_cart_adds_4w,
  t.sqp_amazon_orders_4w,
  t.sqp_amazon_search_volume_4w,

  -- SQP LY Peak: Your ASIN
  t.sqp_impressions_ly_peak,
  t.sqp_clicks_ly_peak,
  t.sqp_cart_adds_ly_peak,
  t.sqp_orders_ly_peak,
  t.sqp_sales_ly_peak,
  t.sqp_show_rate_ly_peak,
  t.sqp_impression_share_ly_peak,
  t.sqp_organic_rank_ly_peak,
  -- SQP LY Peak: Amazon market
  t.sqp_amazon_impressions_ly_peak,
  t.sqp_amazon_clicks_ly_peak,
  t.sqp_amazon_cart_adds_ly_peak,
  t.sqp_amazon_orders_ly_peak,
  t.sqp_amazon_search_volume_ly_peak,

  -- Signal (uses thresholds from DE_COACH_THRESHOLDS)
  CASE
    WHEN t.ads_clicks_4w < th.insufficient_data_clicks THEN 'INSUFFICIENT_DATA'
    WHEN t.ads_orders_4w = 0 AND t.sqp_organic_units_4w = 0 AND t.ads_spend_4w >= th.wasted_spend_threshold THEN 'WASTED_SPEND'
    WHEN t.ads_orders_4w = 0 AND t.sqp_organic_units_4w > 0 THEN 'ORGANIC_ONLY'
    WHEN t.ads_net_roas_4w >= th.scale_up_roas THEN 'STRONG'
    WHEN t.ads_net_roas_4w >= th.profitable_roas THEN 'PROFITABLE'
    WHEN t.ads_net_roas_4w >= th.halo_roas THEN 'MARGINAL'
    WHEN t.ads_net_roas_4w > 0 THEN 'UNPROFITABLE'
    WHEN t.ads_orders_4w > 0 THEN 'UNPROFITABLE'
    ELSE 'INSUFFICIENT_DATA'
  END as ads_signal,

  -- Decision (uses thresholds from DE_COACH_THRESHOLDS)
  CASE
    WHEN t.ads_orders_4w = 0 AND t.sqp_organic_units_4w = 0 AND t.ads_spend_4w >= th.wasted_spend_threshold
      THEN 'NEGATE_TERM'
    WHEN t.ads_net_roas_4w < th.negate_roas_threshold AND t.ads_spend_4w >= th.negate_spend_threshold AND t.ads_orders_lifetime <= 1
      THEN 'NEGATE_TERM'
    WHEN t.ads_net_roas_4w < th.reduce_bid_roas AND t.ads_spend_4w >= th.reduce_bid_spend AND t.ads_orders_4w > 0
      THEN 'REDUCE_BID'
    WHEN t.ads_net_roas_4w >= th.scale_up_roas AND t.ads_spend_4w < th.scale_up_spend_cap AND t.ads_orders_4w >= 2
      THEN 'INCREASE_BID'
    WHEN t.ads_net_roas_4w >= th.profitable_roas
      THEN 'KEEP'
    WHEN t.ads_net_roas_4w >= th.halo_roas AND t.sqp_organic_units_4w >= 2
      THEN 'KEEP'
    ELSE 'MONITOR'
  END as decision,

  -- Priority (uses thresholds from DE_COACH_THRESHOLDS)
  ROUND(CASE
    WHEN t.ads_orders_4w = 0 AND t.sqp_organic_units_4w = 0 AND t.ads_spend_4w >= th.wasted_spend_threshold
      THEN t.ads_spend_4w * 2.0
    WHEN t.ads_net_roas_4w < th.negate_roas_threshold AND t.ads_spend_4w >= th.negate_spend_threshold
      THEN t.ads_spend_4w * 1.5
    WHEN t.ads_net_roas_4w >= th.scale_up_roas AND t.ads_orders_4w >= 2
      THEN t.ads_orders_4w * 30.0
    WHEN t.ads_net_roas_4w < th.reduce_bid_roas AND t.ads_spend_4w >= th.reduce_bid_spend
      THEN t.ads_spend_4w * 1.0
    ELSE 0
  END, 0) as priority_score,

  -- Confidence (uses thresholds from DE_COACH_THRESHOLDS)
  CASE
    WHEN t.ads_days_4w >= th.confidence_days_high AND t.ads_clicks_4w >= th.confidence_clicks_high THEN 'HIGH'
    WHEN t.ads_days_4w >= th.confidence_days_medium AND t.ads_clicks_4w >= th.confidence_clicks_medium THEN 'MEDIUM'
    ELSE 'LOW'
  END as confidence,

  -- Reason (full transparency, uses thresholds from DE_COACH_THRESHOLDS)
  CASE
    WHEN t.ads_orders_4w = 0 AND t.sqp_organic_units_4w = 0 AND t.ads_spend_4w >= th.wasted_spend_threshold
      THEN CONCAT('Spent $', CAST(ROUND(t.ads_spend_4w, 0) AS STRING),
                   ' across ', CAST(t.campaign_count_4w AS STRING), ' campaigns over ',
                   CAST(t.ads_days_4w AS STRING), ' days with 0 orders. ',
                   'No organic demand (SQP = 0). CPC $', CAST(ROUND(t.ads_cpc_4w, 2) AS STRING), '. Negate everywhere.')
    WHEN t.ads_net_roas_4w < th.negate_roas_threshold AND t.ads_spend_4w >= th.negate_spend_threshold AND t.ads_orders_lifetime <= 1
      THEN CONCAT('Net ROAS ', CAST(ROUND(t.ads_net_roas_4w, 2) AS STRING),
                   ' on $', CAST(ROUND(t.ads_spend_4w, 0) AS STRING), ' spend. ',
                   'Only ', CAST(t.ads_orders_lifetime AS STRING), ' order(s) ever. Negate.')
    WHEN t.ads_net_roas_4w < th.reduce_bid_roas AND t.ads_spend_4w >= th.reduce_bid_spend AND t.ads_orders_4w > 0
      THEN CONCAT('Net ROAS ', CAST(ROUND(t.ads_net_roas_4w, 2) AS STRING),
                   ', losing $', CAST(ROUND(ABS(t.ads_net_profit_4w), 0) AS STRING),
                   '. ', CAST(t.ads_orders_4w AS STRING), ' orders at $',
                   CAST(ROUND(t.ads_cost_per_order_4w, 2) AS STRING), '/order vs $',
                   CAST(ROUND(t.margin_per_unit, 2) AS STRING), ' margin. Reduce bid ~30%.')
    WHEN t.ads_net_roas_4w >= th.scale_up_roas AND t.ads_spend_4w < th.scale_up_spend_cap AND t.ads_orders_4w >= 2
      THEN CONCAT('Strong ROAS ', CAST(ROUND(t.ads_net_roas_4w, 2) AS STRING),
                   ', ', CAST(t.ads_orders_4w AS STRING), ' orders on $',
                   CAST(ROUND(t.ads_spend_4w, 0) AS STRING), ' spend. ',
                   'Profit $', CAST(ROUND(t.ads_net_profit_4w, 0) AS STRING),
                   '. Scale up — increase bid.')
    WHEN t.ads_net_roas_4w >= th.profitable_roas
      THEN CONCAT('Profitable ROAS ', CAST(ROUND(t.ads_net_roas_4w, 2) AS STRING),
                   ', profit $', CAST(ROUND(t.ads_net_profit_4w, 0) AS STRING),
                   ' on $', CAST(ROUND(t.ads_spend_4w, 0) AS STRING), '. ',
                   CAST(t.ads_orders_4w AS STRING), ' orders. Keep.')
    WHEN t.ads_net_roas_4w >= th.halo_roas AND t.sqp_organic_units_4w >= 2
      THEN CONCAT('Ads marginal (ROAS ', CAST(ROUND(t.ads_net_roas_4w, 2) AS STRING),
                   ') but ', CAST(t.sqp_organic_units_4w AS STRING),
                   ' organic orders — halo effect justifies spend.')
    WHEN t.ads_clicks_4w < th.insufficient_data_clicks
      THEN CONCAT('Only ', CAST(t.ads_clicks_4w AS STRING), ' clicks (need ', CAST(CAST(th.insufficient_data_clicks AS INT64) AS STRING), '). Need more data.')
    ELSE CONCAT('$', CAST(ROUND(t.ads_spend_4w, 0) AS STRING), ' across ',
                CAST(t.campaign_count_4w AS STRING), ' campaigns. ',
                CAST(t.ads_orders_4w AS STRING), ' orders (ROAS ',
                CAST(COALESCE(ROUND(t.ads_net_roas_4w, 2), 0) AS STRING), '). ',
                CAST(t.selling_campaigns_4w AS STRING), '/', CAST(t.campaign_count_4w AS STRING), ' campaigns selling. Monitoring.')
  END as reason

FROM term_asin t
CROSS JOIN coach_thresholds th
WHERE t.asin_rank = 1;
