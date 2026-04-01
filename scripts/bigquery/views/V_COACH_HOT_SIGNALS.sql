-- =============================================
-- OI Database Project - V_COACH_HOT_SIGNALS
-- =============================================
--
-- Purpose: 3-day rapid-reaction ads alerts
-- Catches strong signals (good or bad) before the 8-week coach
-- No SQP data — purely ads-based
--
-- Signal types:
--   URGENT_STOP   — bleeding money, 0 orders (overrides 8w coach)
--   HOT_WINNER    — strong short-term performance
--   RAPID_DECLINE — was profitable (8w), suddenly tanked (3d)
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_COACH_HOT_SIGNALS`
AS
WITH
-- =============================================
-- Unit economics per ASIN
-- =============================================
asin_unit_economics AS (
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

-- =============================================
-- 3-day ads aggregation per search term
-- =============================================
ads_3d AS (
  SELECT
    ec.experiment_id,
    ae.experiment_name,
    ae.strategy_id,
    ae.strategy_name,
    ec.campaign_id,
    fa.campaign_name,
    COALESCE(fa.campaign_type, 'SP') as campaign_type,
    fa.ad_group_id,
    fa.advertised_asins as asin,
    LOWER(fa.search_term) as search_term,
    SUM(fa.Ads_cost) as spend_3d,
    SUM(fa.Ads_orders) as orders_3d,
    SUM(fa.Ads_units) as units_3d,
    SUM(fa.Ads_clicks) as clicks_3d,
    SUM(fa.Ads_impressions) as impressions_3d,
    COUNT(DISTINCT fa.date) as days_with_data
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN (
    SELECT experiment_id, experiment_name, strategy_id, strategy_name
    FROM (
      SELECT e.experiment_id, e.experiment_name, e.strategy_id, st.strategy_name
      FROM `onyga-482313.OI.DIM_EXPERIMENT` e
      LEFT JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st ON e.strategy_id = st.strategy_id
      WHERE e.status = 'ACTIVE'
    )
  ) ae ON ec.experiment_id = ae.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON ec.campaign_id = fa.campaign_id
    AND fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY)
  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
    AND fa.advertised_asins IS NOT NULL
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
),

-- =============================================
-- 8-week coach action for context / RAPID_DECLINE comparison
-- =============================================
coach_8w AS (
  SELECT search_term, campaign_id, coach_8w_action, coach_8w_roas, coach_8w_signal
  FROM (
    SELECT
      search_term,
      campaign_id,
      action as coach_8w_action,
      weighted_total_net_roas as coach_8w_roas,
      ads_signal as coach_8w_signal,
      ROW_NUMBER() OVER (PARTITION BY search_term, campaign_id ORDER BY COALESCE(weighted_total_net_roas, 0) DESC) as rn
    FROM `onyga-482313.OI.T_EXPERIMENT_TERM_RECOMMENDATIONS`
    WHERE recommendation_type = 'ACTIVE_TERM'
  )
  WHERE rn = 1
),

-- =============================================
-- SQP 4-week context (volume + organic rank)
-- =============================================
sqp_4w AS (
  SELECT
    LOWER(fsq.query_text) as search_term,
    fsq.ASIN as asin,
    ROUND(AVG(fsq.search_query_volume), 0) as sqp_search_volume_4w,
    ROUND(AVG(fsq.estimated_organic_rank), 1) as sqp_organic_rank
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
  WHERE fsq.data_source = 'SQP'
    AND fsq.week_end_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
  GROUP BY 1, 2
)

-- =============================================
-- FINAL OUTPUT: Hot Signals
-- =============================================
SELECT
  -- Signal classification
  CASE
    -- URGENT_STOP: spending money, zero orders
    -- EXACT campaigns: 20+ clicks (higher bar, more targeted)
    -- Non-EXACT campaigns: 10+ clicks
    WHEN a.orders_3d = 0
      AND a.spend_3d >= 15
      AND (
        (a.strategy_id = 'EXACT_BOOST' AND a.clicks_3d >= 20)
        OR (a.strategy_id != 'EXACT_BOOST' AND a.clicks_3d >= 10)
      )
      THEN 'URGENT_STOP'

    -- HOT_WINNER: 3+ orders with strong ROAS
    WHEN a.orders_3d >= 3
      AND SAFE_DIVIDE(a.orders_3d * ue.margin_per_unit, NULLIF(a.spend_3d, 0)) >= 2.0
      THEN 'HOT_WINNER'

    -- RAPID_DECLINE: 8w coach says profitable, but 3d shows zero orders
    WHEN c.coach_8w_action IN ('KEEP', 'INCREASE_BID')
      AND a.spend_3d >= 10
      AND a.orders_3d = 0
      AND a.clicks_3d >= 10
      THEN 'RAPID_DECLINE'

    ELSE NULL
  END as hot_signal,

  -- Human-readable reason
  CASE
    WHEN a.orders_3d = 0
      AND a.spend_3d >= 15
      AND (
        (a.strategy_id = 'EXACT_BOOST' AND a.clicks_3d >= 20)
        OR (a.strategy_id != 'EXACT_BOOST' AND a.clicks_3d >= 10)
      )
      THEN CONCAT(
        '🔴 $', CAST(ROUND(a.spend_3d, 0) AS STRING),
        ' spent, ', CAST(a.clicks_3d AS STRING), ' clicks, 0 orders in 3 days.',
        CASE WHEN c.coach_8w_action IS NOT NULL
          THEN CONCAT(' Overrides 8w: ', c.coach_8w_action)
          ELSE '' END
      )

    WHEN a.orders_3d >= 3
      AND SAFE_DIVIDE(a.orders_3d * ue.margin_per_unit, NULLIF(a.spend_3d, 0)) >= 2.0
      THEN CONCAT(
        '🟢 ', CAST(a.orders_3d AS STRING), ' orders in 3d (',
        CAST(ROUND(SAFE_DIVIDE(a.orders_3d, NULLIF(a.clicks_3d, 0)) * 100, 1) AS STRING), '% CVR). ',
        'ROAS ', CAST(ROUND(SAFE_DIVIDE(a.orders_3d * ue.margin_per_unit, NULLIF(a.spend_3d, 0)), 1) AS STRING), 'x.'
      )

    WHEN c.coach_8w_action IN ('KEEP', 'INCREASE_BID')
      AND a.spend_3d >= 10
      AND a.orders_3d = 0
      AND a.clicks_3d >= 10
      THEN CONCAT(
        '🟡 8w coach says ', c.coach_8w_action, ' (ROAS ',
        CAST(ROUND(COALESCE(c.coach_8w_roas, 0), 1) AS STRING), 'x), but $',
        CAST(ROUND(a.spend_3d, 0) AS STRING), ' / ', CAST(a.clicks_3d AS STRING),
        ' clicks / 0 orders in last 3 days.'
      )

    ELSE NULL
  END as hot_signal_reason,

  -- Dimension columns
  a.search_term,
  a.asin,
  ue.product_short_name,
  ue.parent_name,
  a.experiment_id,
  a.experiment_name,
  a.strategy_id,
  a.strategy_name,
  a.campaign_id,
  a.campaign_name,
  a.campaign_type,
  a.ad_group_id,

  -- 3-day metrics
  ROUND(a.spend_3d, 2) as spend_3d,
  a.orders_3d,
  a.clicks_3d,
  a.impressions_3d,
  ROUND(SAFE_DIVIDE(a.spend_3d, NULLIF(a.clicks_3d, 0)), 2) as cpc_3d,
  ROUND(SAFE_DIVIDE(a.orders_3d, NULLIF(a.clicks_3d, 0)) * 100, 1) as cvr_3d,
  ROUND(SAFE_DIVIDE(a.orders_3d * ue.margin_per_unit, NULLIF(a.spend_3d, 0)), 2) as ads_roas_3d,
  ROUND(a.orders_3d * ue.margin_per_unit - a.spend_3d, 2) as net_profit_3d,
  ROUND(ue.margin_per_unit, 2) as margin_per_unit,

  -- 8-week coach context
  c.coach_8w_action,
  ROUND(COALESCE(c.coach_8w_roas, 0), 2) as coach_8w_roas,
  c.coach_8w_signal,

  -- Priority score: higher = more urgent
  -- URGENT_STOP: spend × 10 (most critical)
  -- RAPID_DECLINE: spend × 5
  -- HOT_WINNER: orders × margin (opportunity cost)
  ROUND(CASE
    WHEN a.orders_3d = 0
      AND a.spend_3d >= 15
      AND (
        (a.strategy_id = 'EXACT_BOOST' AND a.clicks_3d >= 20)
        OR (a.strategy_id != 'EXACT_BOOST' AND a.clicks_3d >= 10)
      )
      THEN a.spend_3d * 10
    WHEN c.coach_8w_action IN ('KEEP', 'INCREASE_BID')
      AND a.spend_3d >= 10
      AND a.orders_3d = 0
      AND a.clicks_3d >= 10
      THEN a.spend_3d * 5
    WHEN a.orders_3d >= 3
      AND SAFE_DIVIDE(a.orders_3d * ue.margin_per_unit, NULLIF(a.spend_3d, 0)) >= 2.0
      THEN a.orders_3d * ue.margin_per_unit
    ELSE 0
  END, 2) as priority_score,

  -- SQP 4-week context
  COALESCE(sqp.sqp_search_volume_4w, 0) as sqp_search_volume_4w,
  sqp.sqp_organic_rank,

  a.days_with_data

FROM ads_3d a
LEFT JOIN asin_unit_economics ue ON a.asin = ue.asin
LEFT JOIN coach_8w c ON a.search_term = c.search_term AND a.campaign_id = c.campaign_id
LEFT JOIN sqp_4w sqp ON a.search_term = sqp.search_term AND a.asin = sqp.asin

-- Only output rows with a signal
WHERE
  -- URGENT_STOP
  (a.orders_3d = 0
    AND a.spend_3d >= 15
    AND (
      (a.strategy_id = 'EXACT_BOOST' AND a.clicks_3d >= 20)
      OR (a.strategy_id != 'EXACT_BOOST' AND a.clicks_3d >= 10)
    ))
  -- HOT_WINNER
  OR (a.orders_3d >= 3
    AND SAFE_DIVIDE(a.orders_3d * ue.margin_per_unit, NULLIF(a.spend_3d, 0)) >= 2.0)
  -- RAPID_DECLINE
  OR (c.coach_8w_action IN ('KEEP', 'INCREASE_BID')
    AND a.spend_3d >= 10
    AND a.orders_3d = 0
    AND a.clicks_3d >= 10)
;
