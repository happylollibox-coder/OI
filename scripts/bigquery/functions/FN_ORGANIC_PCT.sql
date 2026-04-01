-- =============================================
-- OI Database Project - FN_ORGANIC_PCT (Organic %)
-- =============================================
--
-- Purpose: Single source of truth for Organic % = organic_units ÷ total_orders × 100
-- Used by: Cube schema (Trends, Summary)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE FUNCTION `onyga-482313.OI.FN_ORGANIC_PCT`(organic_units FLOAT64, total_orders FLOAT64)
RETURNS FLOAT64
AS (
  SAFE_DIVIDE(GREATEST(COALESCE(organic_units, 0), 0) * 100.0, NULLIF(COALESCE(total_orders, 0), 0))
);
