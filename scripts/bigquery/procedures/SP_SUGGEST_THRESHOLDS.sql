-- =============================================
-- OI Database Project - SP_SUGGEST_THRESHOLDS Stored Procedure
-- =============================================
--
-- Purpose: Analyzes experiment outcomes and ads performance data
--          to suggest new threshold values for DE_COACH_THRESHOLDS.
--          Writes suggested_value + suggestion_reason per threshold.
--          User must approve suggestions via the Flask API.
--
-- Method: Run periodically (weekly) or on-demand
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SUGGEST_THRESHOLDS`()
BEGIN

DECLARE v_run_at DATETIME DEFAULT CURRENT_DATETIME();

-- =============================================
-- 1. Analyze "false negative" negations:
--    Keywords negated that later became profitable
--    → Suggests WASTED_SPEND_THRESHOLD is too low
-- =============================================
MERGE INTO `onyga-482313.OI.DE_COACH_THRESHOLDS` AS target
USING (
  SELECT
    'WASTED_SPEND_THRESHOLD' as threshold_key,
    'GLOBAL' as strategy_id,
    CAST(NULL AS STRING) as product_family,
    -- Suggest: 90th percentile of spend on terms that had 0 orders in first 4w but later converted
    ROUND(APPROX_QUANTILES(late_converters.first_4w_spend, 100)[OFFSET(90)], 0) as suggested_value,
    CONCAT('Based on ', COUNT(*), ' keywords that had 0 orders initially but converted later. ',
           '90th percentile of their early spend was $',
           ROUND(APPROX_QUANTILES(late_converters.first_4w_spend, 100)[OFFSET(90)], 0)) as suggestion_reason
  FROM (
    SELECT
      term_data.search_term,
      SUM(CASE WHEN term_data.date < DATE_ADD(fd.first_date, INTERVAL 28 DAY) THEN term_data.cost ELSE 0 END) as first_4w_spend,
      SUM(CASE WHEN term_data.date < DATE_ADD(fd.first_date, INTERVAL 28 DAY) THEN term_data.orders ELSE 0 END) as first_4w_orders,
      SUM(term_data.orders) as total_orders
    FROM (
      SELECT LOWER(fa.search_term) as search_term, fa.date, fa.cost, fa.orders
      FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
      WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
        AND fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
    ) term_data
    JOIN (
      SELECT LOWER(search_term) as search_term, MIN(date) as first_date
      FROM `onyga-482313.OI.FACT_AMAZON_ADS`
      WHERE search_term IS NOT NULL AND search_term != ''
        AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
      GROUP BY 1
    ) fd ON term_data.search_term = fd.search_term
    GROUP BY 1
  ) late_converters
  WHERE late_converters.first_4w_orders = 0  -- no orders in first 4 weeks
    AND late_converters.total_orders >= 2     -- but converted eventually
  HAVING COUNT(*) >= 5                        -- need enough data points
) AS source
ON target.threshold_key = source.threshold_key
  AND target.strategy_id = source.strategy_id
  AND COALESCE(target.product_family, '') = COALESCE(source.product_family, '')
WHEN MATCHED AND (
  target.suggested_value IS NULL
  OR ABS(target.suggested_value - source.suggested_value) > 1
) THEN
  UPDATE SET
    target.suggested_value = source.suggested_value,
    target.suggested_at = v_run_at,
    target.suggestion_reason = source.suggestion_reason;


-- =============================================
-- 2. Analyze profitable keywords to tune SCALE_UP_ROAS:
--    Find the median Net ROAS of keywords that stayed profitable
--    → Suggests what "strong" really means for your products
-- =============================================
MERGE INTO `onyga-482313.OI.DE_COACH_THRESHOLDS` AS target
USING (
  SELECT
    'SCALE_UP_ROAS' as threshold_key,
    'GLOBAL' as strategy_id,
    CAST(NULL AS STRING) as product_family,
    ROUND(APPROX_QUANTILES(strong_terms.net_roas, 100)[OFFSET(75)], 2) as suggested_value,
    CONCAT('75th percentile Net ROAS of ', COUNT(*), ' profitable keywords = ',
           ROUND(APPROX_QUANTILES(strong_terms.net_roas, 100)[OFFSET(75)], 2),
           '. Keywords above this are genuinely strong.') as suggestion_reason
  FROM (
    SELECT
      LOWER(fa.search_term) as search_term,
      SAFE_DIVIDE(
        SUM(p.listing_price_amount - COALESCE(ch.TOTAL_COST_PER_UNIT, 0)) * SUM(fa.orders),
        NULLIF(SUM(fa.cost), 0)
      ) as net_roas
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
    LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) = p.asin
    LEFT JOIN (
      SELECT asin, TOTAL_COST_PER_UNIT,
        ROW_NUMBER() OVER (PARTITION BY asin ORDER BY end_date DESC) as rn
      FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
    ) ch ON p.asin = ch.asin AND ch.rn = 1
    WHERE fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
      AND fa.search_term IS NOT NULL AND fa.search_term != ''
      AND fa.orders > 0
    GROUP BY 1
    HAVING SUM(fa.cost) >= 5  -- minimum spend to be meaningful
  ) strong_terms
  WHERE strong_terms.net_roas > 0
  HAVING COUNT(*) >= 10  -- need enough profitable terms
) AS source
ON target.threshold_key = source.threshold_key
  AND target.strategy_id = source.strategy_id
  AND COALESCE(target.product_family, '') = COALESCE(source.product_family, '')
WHEN MATCHED AND (
  target.suggested_value IS NULL
  OR ABS(target.suggested_value - source.suggested_value) > 0.3
) THEN
  UPDATE SET
    target.suggested_value = source.suggested_value,
    target.suggested_at = v_run_at,
    target.suggestion_reason = source.suggestion_reason;


-- =============================================
-- 3. Analyze loss patterns to tune NEGATE_ROAS_THRESHOLD:
--    Find ROAS below which keywords never recover
--    → Suggests the "give up" point
-- =============================================
MERGE INTO `onyga-482313.OI.DE_COACH_THRESHOLDS` AS target
USING (
  SELECT
    'NEGATE_ROAS_THRESHOLD' as threshold_key,
    'GLOBAL' as strategy_id,
    CAST(NULL AS STRING) as product_family,
    ROUND(APPROX_QUANTILES(losers.net_roas, 100)[OFFSET(25)], 2) as suggested_value,
    CONCAT('25th percentile Net ROAS of ', COUNT(*), ' keywords that never recovered = ',
           ROUND(APPROX_QUANTILES(losers.net_roas, 100)[OFFSET(25)], 2),
           '. Below this, keywords almost never become profitable.') as suggestion_reason
  FROM (
    SELECT
      LOWER(fa.search_term) as search_term,
      SAFE_DIVIDE(
        SUM(p.listing_price_amount - COALESCE(ch.TOTAL_COST_PER_UNIT, 0)) * SUM(fa.orders),
        NULLIF(SUM(fa.cost), 0)
      ) as net_roas,
      COUNT(DISTINCT fa.date) as days_running,
      SUM(fa.cost) as total_spend
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
    LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) = p.asin
    LEFT JOIN (
      SELECT asin, TOTAL_COST_PER_UNIT,
        ROW_NUMBER() OVER (PARTITION BY asin ORDER BY end_date DESC) as rn
      FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
    ) ch ON p.asin = ch.asin AND ch.rn = 1
    WHERE fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
      AND fa.search_term IS NOT NULL AND fa.search_term != ''
    GROUP BY 1
    HAVING SUM(fa.cost) >= 20 AND COUNT(DISTINCT fa.date) >= 14  -- mature keywords only
  ) losers
  WHERE losers.net_roas < 1.0 AND losers.net_roas > 0  -- unprofitable but had orders
  HAVING COUNT(*) >= 10
) AS source
ON target.threshold_key = source.threshold_key
  AND target.strategy_id = source.strategy_id
  AND COALESCE(target.product_family, '') = COALESCE(source.product_family, '')
WHEN MATCHED AND (
  target.suggested_value IS NULL
  OR ABS(target.suggested_value - source.suggested_value) > 0.1
) THEN
  UPDATE SET
    target.suggested_value = source.suggested_value,
    target.suggested_at = v_run_at,
    target.suggestion_reason = source.suggestion_reason;

END;
