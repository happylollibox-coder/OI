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

  INSERT INTO `onyga-482313.OI.FACT_FORECAST_DEMAND`
  SELECT * FROM `onyga-482313.OI.V_FORECAST_DEMAND`;
END;
