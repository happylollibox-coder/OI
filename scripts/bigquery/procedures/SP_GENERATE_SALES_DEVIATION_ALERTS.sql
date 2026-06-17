-- =============================================
-- SP_GENERATE_SALES_DEVIATION_ALERTS
-- =============================================
-- Purpose: Weekly check — compares actual sales against the frozen forecast
--          snapshot saved at plan approval time.
--
-- Logic:
--   1. Find the latest APPROVED plan's snapshot in DE_FORECAST_SNAPSHOT
--   2. For completed months: compare actual vs forecast (cumulative)
--   3. For current month IF it's a peak month (peak_days > 0):
--      pro-rate the forecast by days elapsed and compare to actual so far
--   4. Combine completed + pro-rated peak month into cumulative deviation
--   5. If |deviation| > 20%: WARNING, > 40%: CRITICAL
--
-- Peak months (Oct-Dec) get weekly sensitivity because the SP runs every
-- Monday and includes pro-rated current-month data during peaks.
-- Off-peak months are only compared once completed (monthly granularity).
--
-- Runs: Weekly via SP_ORCHESTRATE_DAILY_REFRESH (Monday guard)
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_GENERATE_SALES_DEVIATION_ALERTS`()
OPTIONS (
  description = "Weekly alert generator: compares actual sales vs frozen approved forecast snapshot. Pro-rates current month during peak seasons for weekly sensitivity."
)
BEGIN
  DECLARE today DATE DEFAULT CURRENT_DATE();
  DECLARE current_month INT64 DEFAULT EXTRACT(MONTH FROM today);
  DECLARE current_year INT64 DEFAULT EXTRACT(YEAR FROM today);
  DECLARE days_into_month INT64 DEFAULT EXTRACT(DAY FROM today);
  DECLARE days_in_current_month INT64 DEFAULT EXTRACT(DAY FROM LAST_DAY(today));
  DECLARE month_fraction FLOAT64 DEFAULT SAFE_DIVIDE(days_into_month, days_in_current_month);
  DECLARE deviation_threshold FLOAT64 DEFAULT 0.20;
  DECLARE critical_threshold FLOAT64 DEFAULT 0.40;
  DECLARE alert_count INT64 DEFAULT 0;
  DECLARE active_plan_id STRING;

  -- ─── Step 1: Find the latest APPROVED plan with a forecast snapshot ───
  SET active_plan_id = (
    SELECT s.plan_id
    FROM `onyga-482313.OI.DE_FORECAST_SNAPSHOT` s
    JOIN `onyga-482313.OI.DE_PLAN_STRATEGY` p ON p.plan_id = s.plan_id AND p.status = 'APPROVED'
    ORDER BY s.approved_at DESC
    LIMIT 1
  );

  IF active_plan_id IS NULL THEN
    -- No approved plan → there is no valid basis for any deviation alert.
    -- Auto-resolve any still-open ones instead of stranding them (previously this
    -- early-returned, leaving stale OPEN alerts that never refreshed).
    UPDATE `onyga-482313.OI.DE_ALERTS`
    SET status = 'AUTO_RESOLVED',
        resolved_at = CURRENT_TIMESTAMP(),
        resolved_by = 'system',
        updated_at = CURRENT_TIMESTAMP(),
        notes = CONCAT('Auto-resolved on ', CAST(today AS STRING), ': no approved plan to evaluate against')
    WHERE status = 'OPEN' AND alert_type = 'SALES_DEVIATION';
    SELECT 'SP_GENERATE_SALES_DEVIATION_ALERTS: No approved plan — resolved any stranded SALES_DEVIATION alerts.' AS log_message;
    RETURN;
  END IF;

  -- ─── Step 2: Build candidate alerts ───
  CREATE TEMP TABLE tmp_candidates AS
  WITH latest_snapshots AS (
    SELECT s.*
    FROM (
      SELECT *,
             ROW_NUMBER() OVER(PARTITION BY plan_id, product, forecast_year, forecast_month ORDER BY approved_at DESC) as row_num
      FROM `onyga-482313.OI.DE_FORECAST_SNAPSHOT`
      WHERE plan_id = active_plan_id
    ) s
    WHERE s.row_num = 1
  )
  SELECT
    GENERATE_UUID() AS id,
    'SALES_DEVIATION' AS alert_type,
    comp.asin AS product_asin,
    comp.product AS product_name,
    CASE
      WHEN ABS(comp.cum_deviation_pct) >= critical_threshold THEN 'CRITICAL'
      ELSE 'WARNING'
    END AS severity,
    CASE
      WHEN comp.cum_deviation_pct > 0 THEN CONCAT(comp.product, ' — Selling ', CAST(ROUND(comp.cum_deviation_pct * 100) AS STRING), '% ABOVE plan')
      ELSE CONCAT(comp.product, ' — Selling ', CAST(ROUND(ABS(comp.cum_deviation_pct) * 100) AS STRING), '% BELOW plan')
    END AS title,
    CONCAT(
      'Forecast (approved): ', CAST(ROUND(comp.cum_forecast) AS STRING), ' units. ',
      'Actual sold: ', CAST(comp.cum_actual AS STRING), ' units. ',
      'Period: ', comp.month_range,
      CASE WHEN comp.includes_prorated THEN CONCAT(' (incl. ', CAST(days_into_month AS STRING), '/', CAST(days_in_current_month AS STRING), ' days of current peak month)') ELSE '' END,
      '. ',
      CASE
        WHEN comp.cum_deviation_pct > 0 THEN CONCAT('Over-selling by ~', CAST(ROUND(comp.cum_actual - comp.cum_forecast) AS STRING), ' units. Consider increasing plan and ordering more inventory.')
        ELSE CONCAT('Under-selling by ~', CAST(ROUND(comp.cum_forecast - comp.cum_actual) AS STRING), ' units. Consider reducing future orders to avoid over-stock.')
      END
    ) AS description,
    CASE
      WHEN comp.cum_deviation_pct > 0 THEN CAST(ROUND(comp.cum_actual - comp.cum_forecast) AS INT64)
      ELSE 0
    END AS suggested_qty,
    COALESCE(pf.fba_doc, 0) AS fba_doc,
    COALESCE(pf.system_doc, 0) AS system_doc,
    active_plan_id AS related_plan_id,
    'LINK_PLAN_STRATEGY' AS action_type,
    JSON_OBJECT(
      'asin', comp.asin,
      'plan_id', active_plan_id,
      'deviation_pct', comp.cum_deviation_pct,
      'recommended_adjustment', CASE WHEN comp.cum_deviation_pct > 0 THEN CAST(ROUND(comp.cum_actual - comp.cum_forecast) AS INT64) ELSE 0 END
    ) AS action_payload
  FROM (
    SELECT
      product,
      asin,
      SUM(adj_forecast) AS cum_forecast,
      SUM(adj_actual) AS cum_actual,
      SAFE_DIVIDE(
        SUM(adj_actual) - SUM(adj_forecast),
        SUM(adj_forecast)
      ) AS cum_deviation_pct,
      CONCAT(
        FORMAT('%d/%02d', MIN(forecast_year), MIN(forecast_month)),
        ' → ',
        FORMAT('%d/%02d', MAX(forecast_year), MAX(forecast_month))
      ) AS month_range,
      LOGICAL_OR(is_prorated) AS includes_prorated
    FROM (
      -- ── Part A: Completed months (full comparison) ──
      SELECT
        s.product,
        s.asin,
        s.forecast_year,
        s.forecast_month,
        CAST(s.forecast_units AS FLOAT64) AS adj_forecast,
        CAST(COALESCE(SUM(u.units), 0) AS FLOAT64) AS adj_actual,
        FALSE AS is_prorated
      FROM latest_snapshots s
      LEFT JOIN `onyga-482313.OI.V_UNIFIED_DAILY` u
        ON u.asin = s.asin
        AND EXTRACT(YEAR FROM u.date) = s.forecast_year
        AND EXTRACT(MONTH FROM u.date) = s.forecast_month
        AND u.date > DATE(s.approved_at)
      WHERE s.forecast_year = current_year
        AND s.forecast_month < current_month
      GROUP BY 1, 2, 3, 4, 5

      UNION ALL

      -- ── Part B: Current month pro-rated (PEAK ONLY) ──
      SELECT
        s.product,
        s.asin,
        s.forecast_year,
        s.forecast_month,
        ROUND(s.forecast_units * SAFE_DIVIDE(
          DATE_DIFF(today, GREATEST(DATE_SUB(DATE_TRUNC(today, MONTH), INTERVAL 1 DAY), DATE(s.approved_at)), DAY),
          DATE_DIFF(LAST_DAY(today), GREATEST(DATE_SUB(DATE_TRUNC(today, MONTH), INTERVAL 1 DAY), DATE(s.approved_at)), DAY)
        )) AS adj_forecast,
        CAST(COALESCE(SUM(u.units), 0) AS FLOAT64) AS adj_actual,
        TRUE AS is_prorated
      FROM latest_snapshots s
      LEFT JOIN `onyga-482313.OI.V_UNIFIED_DAILY` u
        ON u.asin = s.asin
        AND EXTRACT(YEAR FROM u.date) = s.forecast_year
        AND EXTRACT(MONTH FROM u.date) = s.forecast_month
        AND u.date > DATE(s.approved_at)
      WHERE s.forecast_year = current_year
        AND s.forecast_month = current_month
        AND COALESCE(s.peak_days, 0) > 0  -- ← Only pro-rate peak months
      GROUP BY 1, 2, 3, 4, 5
    ) combined
    GROUP BY product, asin
    HAVING SUM(adj_forecast) > 0
  ) comp
  LEFT JOIN `onyga-482313.OI.V_PLAN_FORECAST` pf ON pf.product = comp.product
  WHERE ABS(comp.cum_deviation_pct) >= deviation_threshold
    AND (COALESCE(pf.total_stock, 0) > 0 OR COALESCE(pf.ytd_sold, 0) > 0);

  -- ─── Step 3: MERGE into DE_ALERTS (Self-Healing) ───
  MERGE `onyga-482313.OI.DE_ALERTS` t
  USING tmp_candidates s
  ON t.alert_type = s.alert_type AND t.product_asin = s.product_asin AND t.status IN ('OPEN', 'SNOOZED')
  WHEN MATCHED THEN
    UPDATE SET
      t.severity = s.severity,
      t.title = s.title,
      t.description = s.description,
      t.suggested_qty = s.suggested_qty,
      t.fba_doc = s.fba_doc,
      t.system_doc = s.system_doc,
      t.action_type = s.action_type,
      t.action_payload = s.action_payload,
      t.related_plan_id = s.related_plan_id,
      t.updated_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN
    INSERT (id, alert_type, product_asin, product_name, severity, title, description,
            suggested_qty, fba_doc, system_doc, status, created_at, fire_day, 
            action_type, action_payload, related_plan_id, updated_at)
    VALUES (s.id, s.alert_type, s.product_asin, s.product_name, s.severity, s.title, s.description,
            s.suggested_qty, s.fba_doc, s.system_doc, 'OPEN', CURRENT_TIMESTAMP(), CAST(today AS STRING),
            s.action_type, s.action_payload, s.related_plan_id, CURRENT_TIMESTAMP());

  -- ─── Step 4: Auto-Resolve stale deviation alerts ───
  UPDATE `onyga-482313.OI.DE_ALERTS` t
  SET
    status = 'AUTO_RESOLVED',
    resolved_at = CURRENT_TIMESTAMP(),
    resolved_by = 'system',
    updated_at = CURRENT_TIMESTAMP(),
    notes = CONCAT('Auto-resolved on ', CAST(today AS STRING), ': deviation fell below threshold')
  WHERE status = 'OPEN'
    AND alert_type = 'SALES_DEVIATION'
    AND NOT EXISTS (
      SELECT 1 FROM tmp_candidates s 
      WHERE s.alert_type = t.alert_type AND s.product_asin = t.product_asin
    );

  SET alert_count = (SELECT COUNT(*) FROM tmp_candidates);

  SELECT FORMAT(
    'SP_GENERATE_SALES_DEVIATION_ALERTS: Created/Updated %d alerts (plan: %s, threshold: %.0f%%, peak_prorate: %s, month_fraction: %.2f)',
    alert_count, active_plan_id, deviation_threshold * 100,
    CASE WHEN current_month IN (10, 11, 12) THEN 'ON' ELSE 'OFF' END,
    month_fraction
  ) AS log_message;

  DROP TABLE IF EXISTS tmp_candidates;

END;
