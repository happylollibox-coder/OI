CREATE OR REPLACE VIEW `onyga-482313.OI.V_LAUNCH_RAMP` AS
-- Donor launch-growth curve by PRODUCT AGE, de-seasonalized against the house
-- calendar (V_HOUSE_SEASONALITY) so it is pure growth with Christmas stripped out.
-- Normalized to age 1 = 1.000, forced monotonic (running max), and held flat after
-- PLATEAU_AGE = 6 to drop the noisy de-seasonalized tail. One row per
-- (donor_product, launch_age_month). Consumed by V_FORECAST_DEMAND (Phase 1 & 2):
-- a new product inherits its chosen donor's ramp shape by its own age.
WITH const AS (SELECT 6 AS plateau_age),
donor_first AS (
  SELECT product_short_name AS donor, MIN(date) AS first_sale
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE units > 0 AND product_short_name IS NOT NULL
  GROUP BY 1
),
donor_age_month AS (
  SELECT
    d.donor,
    DATE_DIFF(DATE_TRUNC(u.date, MONTH), DATE_TRUNC(d.first_sale, MONTH), MONTH) + 1 AS age_month,
    EXTRACT(MONTH FROM u.date) AS cal_month,
    SUM(u.units) AS units,
    COUNT(DISTINCT u.date) AS days
  FROM `onyga-482313.OI.T_UNIFIED_DAILY` u
  JOIN donor_first d ON u.product_short_name = d.donor
  WHERE u.units > 0
  GROUP BY 1, 2, 3
),
-- De-seasonalize: daily rate / house index for that calendar month.
-- Ignore thin (<10-day) partial launch/tail months.
deseason AS (
  SELECT dam.donor, dam.age_month,
    SAFE_DIVIDE(SAFE_DIVIDE(dam.units, dam.days), NULLIF(hs.house_season_index, 0)) AS growth_raw
  FROM donor_age_month dam
  JOIN `onyga-482313.OI.V_HOUSE_SEASONALITY` hs ON hs.calendar_month = dam.cal_month
  WHERE dam.days >= 10
),
base AS (
  SELECT donor, growth_raw AS base_growth FROM deseason WHERE age_month = 1
),
norm AS (
  SELECT ds.donor, ds.age_month,
    SAFE_DIVIDE(ds.growth_raw, NULLIF(b.base_growth, 0)) AS ramp_norm
  FROM deseason ds JOIN base b ON b.donor = ds.donor
),
cummax AS (
  SELECT donor, age_month,
    MAX(ramp_norm) OVER (PARTITION BY donor ORDER BY age_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ramp_mono
  FROM norm
),
plateau_val AS (
  SELECT donor,
    MAX(IF(age_month = (SELECT plateau_age FROM const), ramp_mono, NULL)) AS plateau_ramp
  FROM cummax GROUP BY 1
)
SELECT
  c.donor AS donor_product,
  c.age_month AS launch_age_month,
  ROUND(
    CASE WHEN c.age_month >= (SELECT plateau_age FROM const)
         THEN COALESCE(pv.plateau_ramp, c.ramp_mono)
         ELSE c.ramp_mono END, 4) AS ramp_factor
FROM cummax c
LEFT JOIN plateau_val pv ON pv.donor = c.donor
ORDER BY c.donor, c.age_month;
