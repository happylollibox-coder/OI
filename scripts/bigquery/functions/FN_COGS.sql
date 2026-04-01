-- =============================================
-- OI Database Project - FN_COGS (Cost of Goods Sold)
-- =============================================
--
-- Purpose: Single source of truth for COGS formula (units × cost per unit)
-- Used by: Cube schema (Trends, Ads), refresh_data.py, views
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE FUNCTION `onyga-482313.OI.FN_COGS`(units FLOAT64, cost_per_unit FLOAT64)
RETURNS FLOAT64
AS (
  COALESCE(units, 0) * COALESCE(cost_per_unit, 0)
);
