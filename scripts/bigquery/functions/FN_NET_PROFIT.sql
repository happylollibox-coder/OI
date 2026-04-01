-- =============================================
-- OI Database Project - FN_NET_PROFIT
-- =============================================
--
-- Purpose: Single source of truth for Net Profit = Sales − Ad Cost − COGS
-- Used by: Cube schema (Trends, Summary)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE FUNCTION `onyga-482313.OI.FN_NET_PROFIT`(sales FLOAT64, ad_cost FLOAT64, cogs FLOAT64)
RETURNS FLOAT64
AS (
  COALESCE(sales, 0) - COALESCE(ad_cost, 0) - COALESCE(cogs, 0)
);
