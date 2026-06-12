-- =============================================
-- V_ASIN_OOS_DAYS
-- Days each ASIN spent out of sellable (FBA) stock in the recent windows.
-- Feeds the coacher clear-case gate: a 0-order ads window that overlaps OOS
-- days is shelf data, not demand data (owner case 2026-06-12).
-- Grain: one row per ASIN.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_ASIN_OOS_DAYS` AS
WITH fba AS (
  SELECT ASIN AS asin, Date AS d, SUM(quantity_balance) AS sellable
  FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`
  WHERE source_type = 'FBA'
    AND Date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 28 DAY)
  GROUP BY asin, d
)
SELECT
  asin,
  COUNTIF(sellable <= 0) AS oos_days_28d,
  COUNTIF(sellable <= 0 AND d >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)) AS oos_days_7d,
  COUNT(*) AS observed_days_28d,
  MAX(IF(sellable > 0, d, NULL)) AS last_in_stock_date
FROM fba
GROUP BY asin;
