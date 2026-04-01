-- =============================================
-- OI Database Project - V_EXPERIMENT_VARIATION_COMPARISON View
-- =============================================
--
-- Purpose: Split experiment performance into periods defined by
--          changes logged in DIM_EXPERIMENT_CHANGE_LOG.
--          Compare: spend, orders, ROAS, organic lift across periods.
--
-- How it works:
--   1. Each change_date in the changelog creates a new "period"
--   2. Period 0 = experiment start to first change
--   3. Period 1 = first change to second change, etc.
--   4. FACT_EXPERIMENT_DAILY rows are assigned to periods
--   5. Metrics are aggregated per period for side-by-side comparison
--
-- Dependencies:
--   DIM_EXPERIMENT, DIM_EXPERIMENT_CHANGE_LOG, FACT_EXPERIMENT_DAILY,
--   DIM_PRODUCT, DIM_COSTS_HISTORY
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_EXPERIMENT_VARIATION_COMPARISON`
AS
WITH
-- All experiments that have at least one change logged
experiments_with_changes AS (
  SELECT DISTINCT cl.experiment_id
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CHANGE_LOG` cl
),

-- Build period boundaries per experiment:
-- period 0 starts at experiment start_date
-- each subsequent period starts at a change_date
period_boundaries AS (
  SELECT
    e.experiment_id,
    e.experiment_name,
    e.strategy_id,
    e.start_date,
    COALESCE(e.end_date, CURRENT_DATE()) as effective_end_date,
    0 as period_num,
    'INITIAL' as period_label,
    e.start_date as period_start,
    DATE_SUB(
      COALESCE(
        (SELECT MIN(cl.change_date) FROM `onyga-482313.OI.DIM_EXPERIMENT_CHANGE_LOG` cl
         WHERE cl.experiment_id = e.experiment_id AND cl.change_date > e.start_date),
        COALESCE(e.end_date, DATE '9999-12-31')
      ),
      INTERVAL 1 DAY
    ) as period_end,
    CAST(NULL AS STRING) as change_type,
    CAST(NULL AS STRING) as field_changed,
    CAST(NULL AS STRING) as old_value,
    CAST(NULL AS STRING) as new_value,
    CAST(NULL AS STRING) as change_reason
  FROM `onyga-482313.OI.DIM_EXPERIMENT` e
  WHERE e.experiment_id IN (SELECT experiment_id FROM experiments_with_changes)

  UNION ALL

  SELECT
    e.experiment_id,
    e.experiment_name,
    e.strategy_id,
    e.start_date,
    COALESCE(e.end_date, CURRENT_DATE()) as effective_end_date,
    changes.period_num,
    changes.period_label,
    changes.change_date as period_start,
    DATE_SUB(
      COALESCE(changes.next_change_date, COALESCE(e.end_date, DATE '9999-12-31')),
      INTERVAL 1 DAY
    ) as period_end,
    changes.change_type,
    changes.field_changed,
    changes.old_value,
    changes.new_value,
    changes.reason as change_reason
  FROM `onyga-482313.OI.DIM_EXPERIMENT` e
  JOIN (
    SELECT
      cl.experiment_id,
      cl.change_date,
      cl.change_type,
      cl.field_changed,
      cl.old_value,
      cl.new_value,
      cl.reason,
      ROW_NUMBER() OVER (PARTITION BY cl.experiment_id ORDER BY cl.change_date, cl.change_id) as period_num,
      CONCAT(cl.change_type, ': ', COALESCE(cl.field_changed, ''), ' ', COALESCE(cl.old_value, '?'), ' → ', COALESCE(cl.new_value, '?')) as period_label,
      LEAD(cl.change_date) OVER (PARTITION BY cl.experiment_id ORDER BY cl.change_date, cl.change_id) as next_change_date
    FROM `onyga-482313.OI.DIM_EXPERIMENT_CHANGE_LOG` cl
  ) changes ON e.experiment_id = changes.experiment_id
),

-- Unit economics per ASIN
asin_economics AS (
  SELECT
    p.asin,
    p.product_short_name,
    p.listing_price_amount - COALESCE(ch.TOTAL_COST_PER_UNIT, 0) as margin_per_unit
  FROM `onyga-482313.OI.DIM_PRODUCT` p
  LEFT JOIN (
    SELECT asin, TOTAL_COST_PER_UNIT,
      ROW_NUMBER() OVER (PARTITION BY asin ORDER BY end_date DESC) as rn
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  ) ch ON p.asin = ch.asin AND ch.rn = 1
),

-- Assign each daily snapshot to a period and aggregate
period_metrics AS (
  SELECT
    pb.experiment_id,
    pb.experiment_name,
    pb.strategy_id,
    pb.period_num,
    pb.period_label,
    pb.period_start,
    LEAST(pb.period_end, pb.effective_end_date) as period_end,
    pb.change_type,
    pb.field_changed,
    pb.old_value,
    pb.new_value,
    pb.change_reason,
    fd.asin,
    ue.product_short_name,
    ue.margin_per_unit,

    COUNT(*) as days_in_period,

    -- Ad spend & orders (experiment campaigns only)
    ROUND(SUM(fd.ads_exp_cost), 2) as period_ad_spend,
    SUM(fd.ads_exp_orders) as period_ad_orders,
    SUM(fd.ads_exp_units) as period_ad_units,
    ROUND(SUM(fd.ads_exp_sales), 2) as period_ad_sales,

    -- Organic
    SUM(fd.performance_organic_units) as period_organic_units,
    ROUND(SUM(fd.performance_organic_sales), 2) as period_organic_sales,

    -- Total ASIN
    SUM(fd.performance_total_orders) as period_total_orders,
    ROUND(SUM(fd.performance_total_sales), 2) as period_total_sales,
    SUM(fd.performance_sessions) as period_sessions,

    -- Averages per day
    ROUND(AVG(fd.ads_exp_cost), 2) as avg_daily_spend,
    ROUND(AVG(CAST(fd.ads_exp_orders AS FLOAT64)), 2) as avg_daily_ad_orders,
    ROUND(AVG(CAST(fd.performance_organic_units AS FLOAT64)), 2) as avg_daily_organic_units,
    ROUND(AVG(CAST(fd.performance_total_orders AS FLOAT64)), 2) as avg_daily_total_orders,

    -- Net ROAS
    ROUND(SAFE_DIVIDE(
      SUM(fd.ads_exp_units) * ue.margin_per_unit,
      NULLIF(SUM(fd.ads_exp_cost), 0)
    ), 2) as period_ads_net_roas,

    -- Traditional ROAS
    ROUND(SAFE_DIVIDE(
      SUM(fd.ads_exp_sales),
      NULLIF(SUM(fd.ads_exp_cost), 0)
    ), 2) as period_traditional_roas,

    -- CPC
    ROUND(SAFE_DIVIDE(
      SUM(fd.ads_exp_cost),
      NULLIF(SUM(CAST(fd.ads_exp_orders AS FLOAT64)) / NULLIF(
        SAFE_DIVIDE(SUM(CAST(fd.ads_exp_orders AS FLOAT64)), SUM(CAST(fd.ads_exp_units AS FLOAT64))),
        0
      ), 0)
    ), 2) as period_cost_per_order,

    -- Seasonal organic lift (avg across period)
    ROUND(AVG(fd.performance_seasonal_organic_lift_vs_baseline), 4) as avg_seasonal_organic_lift

  FROM period_boundaries pb
  JOIN `onyga-482313.OI.FACT_EXPERIMENT_DAILY` fd
    ON pb.experiment_id = fd.experiment_id
    AND fd.snapshot_date >= pb.period_start
    AND fd.snapshot_date <= LEAST(pb.period_end, pb.effective_end_date)
  LEFT JOIN asin_economics ue ON fd.asin = ue.asin
  GROUP BY
    pb.experiment_id, pb.experiment_name, pb.strategy_id,
    pb.period_num, pb.period_label, pb.period_start, pb.period_end,
    pb.effective_end_date,
    pb.change_type, pb.field_changed, pb.old_value, pb.new_value, pb.change_reason,
    fd.asin, ue.product_short_name, ue.margin_per_unit
)

SELECT
  experiment_id,
  experiment_name,
  strategy_id,
  asin,
  product_short_name,

  period_num,
  period_label,
  period_start,
  period_end,
  days_in_period,

  -- What changed to create this period
  change_type,
  field_changed,
  old_value,
  new_value,
  change_reason,

  -- Period totals
  period_ad_spend,
  period_ad_orders,
  period_ad_units,
  period_ad_sales,
  period_organic_units,
  period_organic_sales,
  period_total_orders,
  period_total_sales,
  period_sessions,

  -- Per-day averages (for fair comparison across different-length periods)
  avg_daily_spend,
  avg_daily_ad_orders,
  avg_daily_organic_units,
  avg_daily_total_orders,

  -- Efficiency
  period_ads_net_roas,
  period_traditional_roas,
  margin_per_unit,

  -- Organic impact
  avg_seasonal_organic_lift,

  -- Period-over-period comparison (vs previous period)
  LAG(avg_daily_spend) OVER (PARTITION BY experiment_id, asin ORDER BY period_num) as prev_period_avg_daily_spend,
  LAG(avg_daily_ad_orders) OVER (PARTITION BY experiment_id, asin ORDER BY period_num) as prev_period_avg_daily_ad_orders,
  LAG(avg_daily_organic_units) OVER (PARTITION BY experiment_id, asin ORDER BY period_num) as prev_period_avg_daily_organic_units,
  LAG(period_ads_net_roas) OVER (PARTITION BY experiment_id, asin ORDER BY period_num) as prev_period_ads_net_roas,
  LAG(period_traditional_roas) OVER (PARTITION BY experiment_id, asin ORDER BY period_num) as prev_period_traditional_roas,

  -- Delta vs previous period
  ROUND(avg_daily_spend - COALESCE(LAG(avg_daily_spend) OVER (PARTITION BY experiment_id, asin ORDER BY period_num), 0), 2) as spend_delta_vs_prev,
  ROUND(avg_daily_ad_orders - COALESCE(LAG(avg_daily_ad_orders) OVER (PARTITION BY experiment_id, asin ORDER BY period_num), 0), 2) as ad_orders_delta_vs_prev,
  ROUND(avg_daily_organic_units - COALESCE(LAG(avg_daily_organic_units) OVER (PARTITION BY experiment_id, asin ORDER BY period_num), 0), 2) as organic_units_delta_vs_prev

FROM period_metrics
ORDER BY experiment_id, asin, period_num;
