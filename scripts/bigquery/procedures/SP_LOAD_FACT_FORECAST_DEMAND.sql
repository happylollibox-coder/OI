-- =============================================
-- OI Database Project - SP_LOAD_FACT_FORECAST_DEMAND
-- =============================================
--
-- Purpose: Materialize V_FORECAST_DEMAND into a physical table to resolve query planner limits.
--          V_PLAN_FORECAST references this demand forecast 7 times. If it's a view,
--          the BigQuery planner inline-expands it exponentially and fails with "Resources exceeded".
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_FACT_FORECAST_DEMAND`()
BEGIN
  -- Truncate and reload
  TRUNCATE TABLE `onyga-482313.OI.FACT_FORECAST_DEMAND`;

  -- Explicit column list (NOT SELECT *) so a new column in V_FORECAST_DEMAND
  -- errors loudly here instead of silently drifting the row shape. The view
  -- currently emits a trailing is_stable column that this FACT table does not carry.
  INSERT INTO `onyga-482313.OI.FACT_FORECAST_DEMAND` (
    product,
    family,
    forecast_year,
    forecast_month,
    family_forecast_units,
    product_share,
    forecast_units,
    is_new_product,
    is_draft,
    sqrt_lift,
    peak_days,
    offseason_days,
    peak_holidays,
    forecast_phase,
    model_product
  )
  SELECT
    product,
    family,
    forecast_year,
    forecast_month,
    family_forecast_units,
    product_share,
    forecast_units,
    is_new_product,
    is_draft,
    sqrt_lift,
    peak_days,
    offseason_days,
    peak_holidays,
    forecast_phase,
    model_product
  FROM `onyga-482313.OI.V_FORECAST_DEMAND`;
END;
