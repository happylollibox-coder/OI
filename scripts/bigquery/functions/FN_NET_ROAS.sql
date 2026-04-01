-- =============================================
-- OI Database Project - FN_NET_ROAS (Net ROAS)
-- =============================================
--
-- Purpose: Single source of truth for Net ROAS = (Sales − COGS) ÷ Ad Spend
-- Used by: Cube schema (Trends, Summary), views
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE FUNCTION `onyga-482313.OI.FN_NET_ROAS`(sales FLOAT64, cogs FLOAT64, ad_cost FLOAT64)
RETURNS FLOAT64
AS (
  SAFE_DIVIDE(COALESCE(sales, 0) - COALESCE(cogs, 0), NULLIF(COALESCE(ad_cost, 0), 0))
);
