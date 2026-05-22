-- ════════════════════════════════════════════════════════════════════
-- V_FORECAST_ROAS: 3-Tier Seasonal Net ROAS Forecast by Family × Month
--
-- Uses DIM_US_HOLIDAYS joined with DIM_US_HOLIDAYS_PRODUCT_FAMILY
-- to determine which peaks are active per product family.
--
-- Tier classification (per family):
--   boost:     boost_start → peak_start - 1  (only for family's active holidays)
--   peak:      peak_start  → holiday_date - 1 (only for family's active holidays)
--   offseason: everything else
--
-- Monthly forecast:
--   monthly_roas = (off_roas × off_days + boost_roas × boost_days
--                   + peak_roas × peak_days) / total_days
--
-- ROAS is family-level. Simulation derives ad = gross_profit / forecast_roas
-- Excludes first 60 days of each family's history.
-- ════════════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW `onyga-482313.OI.V_FORECAST_ROAS` AS

WITH

-- ── 1. First sale date per family (60-day launch exclusion) ──
family_first_sale AS (
  SELECT family, MIN(date) AS first_sale_date
  FROM `onyga-482313.OI.T_UNIFIED_DAILY`
  WHERE family IS NOT NULL AND units > 0
  GROUP BY 1
),

-- ── 2. Holiday windows per product family ───────────────────
-- Only holidays mapped in DIM_US_HOLIDAYS_PRODUCT_FAMILY are active
family_holidays AS (
  SELECT
    hpf.product_family AS family,
    h.holiday_name,
    h.boost_start,
    DATE_SUB(h.peak_start, INTERVAL 1 DAY) AS boost_end,
    h.peak_start,
    DATE_SUB(h.holiday_date, INTERVAL 1 DAY) AS peak_end,
    EXTRACT(YEAR FROM h.holiday_date) AS yr,
    CASE WHEN h.peak_start > h.boost_start THEN TRUE ELSE FALSE END AS has_boost
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
  JOIN `onyga-482313.OI.DIM_US_HOLIDAYS_PRODUCT_FAMILY` hpf
    ON hpf.holiday_name = h.holiday_name
  WHERE h.category = 'gift_season'
),

-- ── 3. Classify historical dates PER FAMILY ─────────────────
-- Each family only sees its own relevant holidays
hist_dates AS (
  SELECT d FROM UNNEST(GENERATE_DATE_ARRAY(
    DATE_SUB(CURRENT_DATE(), INTERVAL 18 MONTH),
    DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
  )) d
),
-- Per family × date → tier
hist_family_tier AS (
  SELECT ffs.family, hd.d,
    CASE
      WHEN MAX(CASE WHEN hd.d BETWEEN fh.peak_start AND fh.peak_end THEN 1 ELSE 0 END) = 1 THEN 'peak'
      WHEN MAX(CASE WHEN fh.has_boost AND hd.d BETWEEN fh.boost_start AND fh.boost_end THEN 1 ELSE 0 END) = 1 THEN 'boost'
      ELSE 'offseason'
    END AS tier
  FROM family_first_sale ffs
  CROSS JOIN hist_dates hd
  LEFT JOIN family_holidays fh ON fh.family = ffs.family
    AND hd.d BETWEEN fh.boost_start AND fh.peak_end
  GROUP BY ffs.family, hd.d
),

-- ── 4. Join actuals with per-family tier ────────────────────
hist_with_tier AS (
  SELECT d.family, d.date, d.sales, d.cogs, d.ad_cost,
    hft.tier
  FROM `onyga-482313.OI.T_UNIFIED_DAILY` d
  JOIN family_first_sale ffs ON ffs.family = d.family
  JOIN hist_family_tier hft ON hft.family = d.family AND hft.d = d.date
  WHERE d.family IS NOT NULL
    AND d.date >= DATE_ADD(ffs.first_sale_date, INTERVAL 60 DAY)
),

-- ── 5a. OFF-SEASON ROAS per family ─────────────────────────
offseason_roas AS (
  SELECT family,
    (SUM(sales) - SUM(cogs)) / NULLIF(SUM(ad_cost), 0) AS roas,
    COUNT(DISTINCT date) AS days_data
  FROM hist_with_tier
  WHERE tier = 'offseason'
    AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
  GROUP BY 1
  HAVING SUM(ad_cost) > 0 AND COUNT(DISTINCT date) >= 7
),

-- ── 5b. BOOST ROAS per family ──────────────────────────────
boost_roas AS (
  SELECT family,
    (SUM(sales) - SUM(cogs)) / NULLIF(SUM(ad_cost), 0) AS roas,
    COUNT(DISTINCT date) AS days_data
  FROM hist_with_tier
  WHERE tier = 'boost'
  GROUP BY 1
  HAVING SUM(ad_cost) > 0 AND COUNT(DISTINCT date) >= 7
),

-- ── 5c. PEAK ROAS per family ──────────────────────────────
peak_roas AS (
  SELECT family,
    (SUM(sales) - SUM(cogs)) / NULLIF(SUM(ad_cost), 0) AS roas,
    COUNT(DISTINCT date) AS days_data
  FROM hist_with_tier
  WHERE tier = 'peak'
  GROUP BY 1
  HAVING SUM(ad_cost) > 0 AND COUNT(DISTINCT date) >= 7
),

-- ── 6. Forecast months grid ────────────────────────────────
forecast_months AS (
  SELECT
    EXTRACT(MONTH FROM DATE_ADD(CURRENT_DATE(), INTERVAL offset MONTH)) AS mo,
    EXTRACT(YEAR FROM DATE_ADD(CURRENT_DATE(), INTERVAL offset MONTH)) AS yr,
    DATE_TRUNC(DATE_ADD(CURRENT_DATE(), INTERVAL offset MONTH), MONTH) AS month_start,
    LAST_DAY(DATE_ADD(CURRENT_DATE(), INTERVAL offset MONTH)) AS month_end
  FROM UNNEST(GENERATE_ARRAY(0, 10)) AS offset
),

-- ── 7. Classify future dates PER FAMILY ─────────────────────
future_dates AS (
  SELECT d, fm.mo, fm.yr
  FROM forecast_months fm,
  UNNEST(GENERATE_DATE_ARRAY(fm.month_start, fm.month_end)) d
),
future_family_tier AS (
  SELECT af.family, fd.d, fd.mo, fd.yr,
    CASE
      WHEN MAX(CASE WHEN fd.d BETWEEN fh.peak_start AND fh.peak_end THEN 1 ELSE 0 END) = 1 THEN 'peak'
      WHEN MAX(CASE WHEN fh.has_boost AND fd.d BETWEEN fh.boost_start AND fh.boost_end THEN 1 ELSE 0 END) = 1 THEN 'boost'
      ELSE 'offseason'
    END AS tier
  FROM future_dates fd
  CROSS JOIN (SELECT DISTINCT family FROM offseason_roas) af
  LEFT JOIN family_holidays fh ON fh.family = af.family
    AND fd.d BETWEEN fh.boost_start AND fh.peak_end
  GROUP BY af.family, fd.d, fd.mo, fd.yr
),

-- ── 8. Count days per family × month per tier ───────────────
month_tier_days AS (
  SELECT family, yr, mo,
    COUNTIF(tier = 'offseason') AS off_days,
    COUNTIF(tier = 'boost') AS boost_days,
    COUNTIF(tier = 'peak') AS peak_days,
    COUNT(*) AS total_days
  FROM future_family_tier
  GROUP BY 1, 2, 3
),

-- ── 9. Blend: weighted ROAS per family × month ─────────────
blended AS (
  SELECT
    mtd.yr AS forecast_year,
    mtd.mo AS forecast_month,
    mtd.family,
    mtd.off_days,
    mtd.boost_days,
    mtd.peak_days,
    mtd.total_days,
    osr.roas AS off_roas,
    COALESCE(br.roas, osr.roas) AS boost_roas,
    COALESCE(pr.roas, osr.roas) AS peak_roas,
    -- Day-weighted blend
    SAFE_DIVIDE(
      osr.roas * mtd.off_days
      + COALESCE(br.roas, osr.roas) * mtd.boost_days
      + COALESCE(pr.roas, osr.roas) * mtd.peak_days,
      mtd.total_days
    ) AS blended_roas
  FROM month_tier_days mtd
  JOIN offseason_roas osr ON osr.family = mtd.family
  LEFT JOIN boost_roas br ON br.family = mtd.family
  LEFT JOIN peak_roas pr ON pr.family = mtd.family
)

-- ── 10. Output ─────────────────────────────────────────────
SELECT
  b.forecast_year,
  b.forecast_month,
  b.family,
  -- Tier ROAS for diagnostics
  ROUND(b.off_roas, 4) AS event_mapped_roas,
  ROUND(b.boost_roas, 4) AS raw_yoy_lift,
  ROUND(b.peak_roas, 4) AS clamped_yoy_lift,
  -- Day breakdown packed: off.boost_peak
  ROUND(b.off_days + b.boost_days * 0.001 + b.peak_days * 0.000001, 6) AS sqrt_lift,
  -- THE KEY OUTPUT: blended monthly Net ROAS
  ROUND(b.blended_roas, 4) AS forecast_roas,
  0 AS forecast_units_base,
  0.0 AS mapped_rev,
  0.0 AS mapped_ad
FROM blended b
WHERE b.blended_roas IS NOT NULL
ORDER BY b.family, b.forecast_year, b.forecast_month;
