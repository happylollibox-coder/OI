-- V_MONTHLY_STORAGE_COST
-- Monthly inventory storage cost per ASIN from FBA + AWD
-- Uses FACT_INVENTORY_SNAPSHOT × calculated cubic feet from package dimensions × seasonal rate
-- Cubic feet calculated from package_length/width/height (inches) / 1728
-- FBA: $0.87/cu ft (Jan-Sep), $2.40/cu ft (Oct-Dec)
-- AWD: $0.51/cu ft/month (all year)
-- Storage cost is attributed to the month the inventory was stored (Option A)
CREATE OR REPLACE VIEW `onyga-482313.OI.V_MONTHLY_STORAGE_COST` AS
WITH monthly_avg AS (
  SELECT
    DATE_TRUNC(Date, MONTH) AS storage_month,
    s.ASIN,
    s.source_type,
    AVG(s.quantity_balance) AS avg_units,
    -- Calculate cubic feet from package dimensions (inches → cu ft)
    -- DIM_PRODUCT.package_cubic_feet is unreliable; compute from L×W×H directly
    CASE
      WHEN p.package_length_value IS NOT NULL
       AND p.package_width_value IS NOT NULL
       AND p.package_height_value IS NOT NULL
      THEN p.package_length_value * p.package_width_value * p.package_height_value / 1728.0
      ELSE NULL
    END AS unit_cubic_feet,
    p.product_type
  FROM `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT` s
  JOIN `onyga-482313.OI.DIM_PRODUCT` p ON s.ASIN = p.asin
  WHERE s.source_type IN ('FBA', 'AWD')
    AND s.quantity_balance > 0
  GROUP BY DATE_TRUNC(Date, MONTH), s.ASIN, s.source_type,
           p.package_length_value, p.package_width_value, p.package_height_value, p.product_type
)
SELECT
  storage_month,
  ASIN AS asin,
  product_type,
  source_type,
  ROUND(avg_units, 0) AS avg_units,
  ROUND(unit_cubic_feet, 4) AS package_cubic_feet,
  ROUND(avg_units * unit_cubic_feet, 2) AS total_cubic_feet,
  -- Seasonal rate
  CASE
    WHEN source_type = 'AWD' THEN 0.51
    WHEN EXTRACT(MONTH FROM storage_month) BETWEEN 10 AND 12 THEN 2.40
    ELSE 0.87
  END AS rate_per_cu_ft,
  -- Storage cost
  ROUND(
    avg_units * COALESCE(unit_cubic_feet, 0) *
    CASE
      WHEN source_type = 'AWD' THEN 0.51
      WHEN EXTRACT(MONTH FROM storage_month) BETWEEN 10 AND 12 THEN 2.40
      ELSE 0.87
    END,
  2) AS storage_cost
FROM monthly_avg;
