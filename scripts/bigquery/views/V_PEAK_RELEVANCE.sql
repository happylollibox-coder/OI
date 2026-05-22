-- V_PEAK_RELEVANCE: Automated peak relevance check per family per holiday
-- Compares peak-period performance vs 4-week baseline before peak
-- Flags holidays that do NOT lift performance for a given family
-- Used by Coach to decide which peaks to boost
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PEAK_RELEVANCE` AS

WITH holidays AS (
  SELECT
    holiday_name,
    holiday_date,
    category,
    pre_season_start,
    boost_start,
    peak_start
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
  WHERE category = 'gift_season'
    AND holiday_date < CURRENT_DATE()  -- only evaluate past holidays with actual data
),

-- For each holiday, define peak period and a 4-week baseline before it
holiday_periods AS (
  SELECT
    holiday_name,
    holiday_date,
    pre_season_start,
    boost_start,
    peak_start,
    -- Peak period: pre_season_start → holiday_date - 1
    pre_season_start AS peak_period_start,
    DATE_SUB(holiday_date, INTERVAL 1 DAY) AS peak_period_end,
    -- Baseline: 4 weeks ending the day before pre_season_start
    DATE_SUB(pre_season_start, INTERVAL 28 DAY) AS baseline_start,
    DATE_SUB(pre_season_start, INTERVAL 1 DAY) AS baseline_end
  FROM holidays
),

-- Family data availability: only include ACTIVE families (in DIM_PRODUCT) with 12+ months of history
family_data_range AS (
  SELECT
    family,
    MIN(date) AS first_date,
    MAX(date) AS last_date,
    DATE_DIFF(MAX(date), MIN(date), MONTH) AS months_of_data
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE family IS NOT NULL AND family != ''
    -- Only active families: must exist in DIM_PRODUCT
    AND LOWER(family) IN (
      SELECT DISTINCT LOWER(parent_name)
      FROM `onyga-482313.OI.DIM_PRODUCT`
      WHERE parent_name IS NOT NULL AND parent_name != 'UNKNOWN'
    )
  GROUP BY family
  HAVING DATE_DIFF(MAX(date), MIN(date), MONTH) >= 12
),

-- Aggregate daily data per family per period (peak vs baseline)
peak_agg AS (
  SELECT
    hp.holiday_name,
    hp.holiday_date,
    d.family,
    'PEAK' AS period,
    COUNT(DISTINCT d.date) AS days,
    SUM(d.orders) AS total_orders,
    SUM(d.units) AS total_units,
    SUM(d.sales) AS total_sales,
    SUM(d.ad_cost) AS total_ad_cost,
    SUM(d.cogs) AS total_cogs,
    SUM(d.gross_margin) AS total_gross_margin,
    SAFE_DIVIDE(SUM(d.orders), COUNT(DISTINCT d.date)) AS avg_daily_orders,
    SAFE_DIVIDE(SUM(d.units), COUNT(DISTINCT d.date)) AS avg_daily_units,
    SAFE_DIVIDE(SUM(d.sales), COUNT(DISTINCT d.date)) AS avg_daily_sales,
    SAFE_DIVIDE(SUM(d.sales) - SUM(d.ad_cost) - SUM(d.cogs), NULLIF(SUM(d.ad_cost), 0)) AS net_roas
  FROM holiday_periods hp
  JOIN `onyga-482313.OI.T_UNIFIED_DAILY` d
    ON d.date BETWEEN hp.peak_period_start AND hp.peak_period_end
  JOIN family_data_range fr ON d.family = fr.family
    AND hp.peak_period_start >= fr.first_date  -- family must have data for this period
  WHERE d.family IS NOT NULL AND d.family != ''
  GROUP BY hp.holiday_name, hp.holiday_date, d.family
),

baseline_agg AS (
  SELECT
    hp.holiday_name,
    hp.holiday_date,
    d.family,
    'BASELINE' AS period,
    COUNT(DISTINCT d.date) AS days,
    SUM(d.orders) AS total_orders,
    SUM(d.units) AS total_units,
    SUM(d.sales) AS total_sales,
    SUM(d.ad_cost) AS total_ad_cost,
    SUM(d.cogs) AS total_cogs,
    SUM(d.gross_margin) AS total_gross_margin,
    SAFE_DIVIDE(SUM(d.orders), COUNT(DISTINCT d.date)) AS avg_daily_orders,
    SAFE_DIVIDE(SUM(d.units), COUNT(DISTINCT d.date)) AS avg_daily_units,
    SAFE_DIVIDE(SUM(d.sales), COUNT(DISTINCT d.date)) AS avg_daily_sales,
    SAFE_DIVIDE(SUM(d.sales) - SUM(d.ad_cost) - SUM(d.cogs), NULLIF(SUM(d.ad_cost), 0)) AS net_roas
  FROM holiday_periods hp
  JOIN `onyga-482313.OI.T_UNIFIED_DAILY` d
    ON d.date BETWEEN hp.baseline_start AND hp.baseline_end
  JOIN family_data_range fr ON d.family = fr.family
    AND hp.baseline_start >= fr.first_date
  WHERE d.family IS NOT NULL AND d.family != ''
  GROUP BY hp.holiday_name, hp.holiday_date, d.family
),

-- Join peak and baseline, compute deltas
comparison AS (
  SELECT
    COALESCE(p.holiday_name, b.holiday_name) AS holiday_name,
    COALESCE(p.holiday_date, b.holiday_date) AS holiday_date,
    COALESCE(p.family, b.family) AS family,
    -- Baseline metrics
    b.days AS baseline_days,
    b.total_orders AS baseline_orders,
    b.total_units AS baseline_units,
    b.total_sales AS baseline_sales,
    b.total_ad_cost AS baseline_ad_cost,
    b.avg_daily_orders AS baseline_avg_daily_orders,
    b.avg_daily_units AS baseline_avg_daily_units,
    b.avg_daily_sales AS baseline_avg_daily_sales,
    b.net_roas AS baseline_net_roas,
    -- Peak metrics
    p.days AS peak_days,
    p.total_orders AS peak_orders,
    p.total_units AS peak_units,
    p.total_sales AS peak_sales,
    p.total_ad_cost AS peak_ad_cost,
    p.avg_daily_orders AS peak_avg_daily_orders,
    p.avg_daily_units AS peak_avg_daily_units,
    p.avg_daily_sales AS peak_avg_daily_sales,
    p.net_roas AS peak_net_roas,
    -- Deltas (% change in avg daily metrics — normalizes for different period lengths)
    SAFE_DIVIDE(p.avg_daily_orders - b.avg_daily_orders, NULLIF(b.avg_daily_orders, 0)) AS orders_change_pct,
    SAFE_DIVIDE(p.avg_daily_units - b.avg_daily_units, NULLIF(b.avg_daily_units, 0)) AS units_change_pct,
    SAFE_DIVIDE(p.avg_daily_sales - b.avg_daily_sales, NULLIF(b.avg_daily_sales, 0)) AS sales_change_pct,
    p.net_roas - COALESCE(b.net_roas, 0) AS net_roas_delta
  FROM peak_agg p
  FULL OUTER JOIN baseline_agg b
    ON p.holiday_name = b.holiday_name
    AND p.holiday_date = b.holiday_date
    AND p.family = b.family
)

SELECT
  holiday_name,
  holiday_date,
  family,
  -- Baseline
  baseline_days,
  baseline_orders,
  baseline_units,
  ROUND(baseline_sales, 2) AS baseline_sales,
  ROUND(baseline_ad_cost, 2) AS baseline_ad_cost,
  ROUND(baseline_avg_daily_orders, 1) AS baseline_avg_daily_orders,
  ROUND(baseline_avg_daily_units, 1) AS baseline_avg_daily_units,
  ROUND(baseline_net_roas, 2) AS baseline_net_roas,
  -- Peak
  peak_days,
  peak_orders,
  peak_units,
  ROUND(peak_sales, 2) AS peak_sales,
  ROUND(peak_ad_cost, 2) AS peak_ad_cost,
  ROUND(peak_avg_daily_orders, 1) AS peak_avg_daily_orders,
  ROUND(peak_avg_daily_units, 1) AS peak_avg_daily_units,
  ROUND(peak_net_roas, 2) AS peak_net_roas,
  -- Deltas
  ROUND(orders_change_pct * 100, 1) AS orders_change_pct,
  ROUND(units_change_pct * 100, 1) AS units_change_pct,
  ROUND(sales_change_pct * 100, 1) AS sales_change_pct,
  ROUND(net_roas_delta, 2) AS net_roas_delta,
  -- Peak relevance flag
  -- A holiday is a relevant peak for a family if EITHER:
  --   1. Avg daily orders increased ≥ 10% during peak, OR
  --   2. Net ROAS improved ≥ 0.2 during peak
  -- Otherwise it's flagged as NOT a peak for this family
  CASE
    WHEN COALESCE(orders_change_pct, 0) >= 0.10 OR COALESCE(net_roas_delta, 0) >= 0.2
    THEN TRUE
    ELSE FALSE
  END AS is_relevant_peak,
  -- Confidence: how reliable is this assessment?
  CASE
    WHEN baseline_days >= 21 AND peak_days >= 14 THEN 'HIGH'
    WHEN baseline_days >= 14 AND peak_days >= 7 THEN 'MEDIUM'
    ELSE 'LOW'
  END AS confidence,
  -- Coach action recommendation
  CASE
    WHEN COALESCE(orders_change_pct, 0) >= 0.50 AND COALESCE(net_roas_delta, 0) > 0
    THEN 'AGGRESSIVE_BOOST'   -- strong peak + profitable → scale hard
    WHEN COALESCE(orders_change_pct, 0) >= 0.10 AND COALESCE(net_roas_delta, 0) >= -0.1
    THEN 'MODERATE_BOOST'     -- orders up, ROAS stable → boost carefully
    WHEN COALESCE(orders_change_pct, 0) >= 0.10 AND COALESCE(net_roas_delta, 0) < -0.1
    THEN 'CAUTIOUS_BOOST'     -- orders up but ROAS drops → boost with bid caps
    WHEN COALESCE(orders_change_pct, 0) < -0.20
    THEN 'REDUCE'             -- orders DROP during "peak" → pull back spend
    ELSE 'HOLD'               -- no meaningful change → keep normal strategy
  END AS coach_recommendation,
  -- Human-readable reason
  CASE
    WHEN COALESCE(orders_change_pct, 0) >= 0.50 AND COALESCE(net_roas_delta, 0) > 0
    THEN CONCAT('Orders +', CAST(ROUND(orders_change_pct * 100) AS STRING), '% with improving ROAS — scale aggressively')
    WHEN COALESCE(orders_change_pct, 0) >= 0.10 AND COALESCE(net_roas_delta, 0) >= -0.1
    THEN CONCAT('Orders +', CAST(ROUND(orders_change_pct * 100) AS STRING), '% with stable ROAS — boost moderately')
    WHEN COALESCE(orders_change_pct, 0) >= 0.10 AND COALESCE(net_roas_delta, 0) < -0.1
    THEN CONCAT('Orders +', CAST(ROUND(orders_change_pct * 100) AS STRING), '% but ROAS drops ', CAST(ROUND(net_roas_delta, 2) AS STRING), ' — boost with bid caps')
    WHEN COALESCE(orders_change_pct, 0) < -0.20
    THEN CONCAT('Orders ', CAST(ROUND(orders_change_pct * 100) AS STRING), '% during peak — NOT a peak for this family, reduce spend')
    ELSE CONCAT('No significant lift (orders ', CAST(ROUND(COALESCE(orders_change_pct, 0) * 100) AS STRING), '%) — hold normal strategy')
  END AS reason

FROM comparison
ORDER BY holiday_date DESC, family
