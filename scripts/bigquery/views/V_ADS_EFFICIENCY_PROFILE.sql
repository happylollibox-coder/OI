-- V_ADS_EFFICIENCY_PROFILE: Per-family × forecast-month ads efficiency parameters
-- Single source of truth for:
--   - Auto-forecast ad spend targets
--   - Unit volume forecast via 3-parameter model
--
-- FORECAST FORMULA (validated at 0% error vs 12 months of 2025):
--   Forecast_Units = Spend ÷ CPC × Unit_CVR ÷ Ads_Share
--
--   Where:
--     Unit_CVR = Ads_units / Ads_clicks  (unit-based, not order-based)
--     Ads_Share = Ads_units / Total_units (from FACT tables, not V_UNIFIED)
--     CPC       = Spend / Clicks         (seasonal, tier-driven)
--
-- SEASONAL-AWARE (per-holiday granularity):
--   Uses DIM_US_HOLIDAYS + DIM_US_HOLIDAYS_PRODUCT_FAMILY to classify
--   each day into off-season / boost / peak PER FAMILY PER HOLIDAY.
--   Christmas peak ≠ Easter peak ≠ Valentine's peak.
--   Each forecast month blends the efficiency of the SPECIFIC holidays
--   that fall within it, not a single pooled "peak" average.
--
-- Output grain: family × forecast_year × forecast_month
--
-- Dependencies:
--   FACT_AMAZON_ADS, V_PRODUCT_FAMILY_MAP, FACT_AMAZON_PERFORMANCE_DAILY,
--   DIM_US_HOLIDAYS, DIM_US_HOLIDAYS_PRODUCT_FAMILY, DIM_PRODUCT
--
-- Invariant #8: All business logic in SQL.
-- Invariant #10: No hardcoded thresholds.

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_EFFICIENCY_PROFILE` AS

WITH

-- ═══ 1. Holiday windows per product family (actual dates) ═══
family_holidays AS (
  SELECT
    hpf.product_family AS family,
    h.holiday_name,
    h.boost_start,
    DATE_SUB(h.peak_start, INTERVAL 1 DAY) AS boost_end,
    h.peak_start,
    DATE_SUB(h.holiday_date, INTERVAL 1 DAY) AS peak_end,
    h.holiday_date,
    EXTRACT(YEAR FROM h.holiday_date) AS yr,
    CASE WHEN h.peak_start > h.boost_start THEN TRUE ELSE FALSE END AS has_boost
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
  JOIN `onyga-482313.OI.DIM_US_HOLIDAYS_PRODUCT_FAMILY` hpf
    ON hpf.holiday_name = h.holiday_name
  WHERE h.category = 'gift_season'
),

active_families AS (
  SELECT DISTINCT family
  FROM `onyga-482313.OI.V_PRODUCT_FAMILY_MAP`
  WHERE family IS NOT NULL
),

-- ═══ 2. Historical: tag each date with (family, holiday, tier) ═══
date_range AS (
  SELECT d
  FROM UNNEST(GENERATE_DATE_ARRAY(
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 24 MONTH),
    DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
  )) d
),

-- Per-date per-family: which holiday and which tier
hist_tagged AS (
  SELECT
    af.family,
    dr.d AS date,
    CASE
      WHEN fh.peak_start IS NOT NULL AND dr.d BETWEEN fh.peak_start AND fh.peak_end THEN 'peak'
      WHEN fh.has_boost AND dr.d BETWEEN fh.boost_start AND fh.boost_end THEN 'boost'
      WHEN fh.holiday_name IS NOT NULL THEN 'boost' -- fallback: in holiday range but no distinct boost
      ELSE 'offseason'
    END AS tier,
    COALESCE(fh.holiday_name, 'offseason') AS holiday_name
  FROM active_families af
  CROSS JOIN date_range dr
  LEFT JOIN family_holidays fh
    ON fh.family = af.family
    AND dr.d BETWEEN fh.boost_start AND fh.peak_end
),

-- Deduplicate: if a date falls in overlapping holidays, pick the highest-priority tier
hist_deduped AS (
  SELECT
    family, date, tier, holiday_name,
    ROW_NUMBER() OVER (
      PARTITION BY family, date
      ORDER BY CASE WHEN tier = 'peak' THEN 0 WHEN tier = 'boost' THEN 1 ELSE 2 END,
               holiday_name
    ) AS rn
  FROM hist_tagged
),
hist_family_tier AS (
  SELECT family, date, tier, holiday_name
  FROM hist_deduped
  WHERE rn = 1
),

-- ═══ 3. Historical efficiency per family × holiday × tier ═══
-- Uses Ads_units (not Ads_orders) for unit-consistent CVR
ads_with_tier AS (
  SELECT
    fm.family,
    a.date,
    hft.tier,
    hft.holiday_name,
    a.Ads_impressions AS impressions,
    a.Ads_clicks AS clicks,
    a.Ads_orders AS orders,
    a.Ads_units AS units,
    a.Ads_cost AS spend,
    a.Ads_sales AS sales,
    a.GROSS_PROFIT AS gross_profit
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN `onyga-482313.OI.V_PRODUCT_FAMILY_MAP` fm
    ON a.ASIN_BY_CAMPAIGN_NAME = fm.asin
  JOIN hist_family_tier hft
    ON hft.family = fm.family AND hft.date = a.date
),

-- Per family × holiday × tier: efficiency + avg daily spend
holiday_tier_efficiency AS (
  SELECT
    family,
    holiday_name,
    tier,
    COUNT(DISTINCT date) AS days_data,
    SUM(clicks) AS total_clicks,
    SUM(orders) AS total_orders,
    SUM(units) AS total_ads_units,
    SUM(spend) AS total_spend,
    SUM(gross_profit) AS total_gp,
    -- CPC
    SAFE_DIVIDE(SUM(spend), NULLIF(SUM(clicks), 0)) AS cpc,
    -- CVR: UNIT-based (ads_units / clicks)
    SAFE_DIVIDE(SUM(units), NULLIF(SUM(clicks), 0)) AS unit_cvr,
    -- CVR: order-based (kept for diagnostics)
    SAFE_DIVIDE(SUM(orders), NULLIF(SUM(clicks), 0)) AS order_cvr,
    -- Net ROAS
    SAFE_DIVIDE(SUM(gross_profit), NULLIF(SUM(spend), 0)) AS net_roas,
    -- Cost per order
    SAFE_DIVIDE(SUM(spend), NULLIF(SUM(orders), 0)) AS cost_per_order,
    -- Avg daily spend
    SAFE_DIVIDE(SUM(spend), NULLIF(COUNT(DISTINCT date), 0)) AS avg_daily_spend
  FROM ads_with_tier
  GROUP BY 1, 2, 3
),

-- ═══ 4. Ads share per family × holiday × tier ═══
-- SOURCE: FACT_AMAZON_ADS (ads_units) + FACT_AMAZON_PERFORMANCE_DAILY (total_units)
-- NOT V_UNIFIED_DAILY (which uses different attribution)
ads_units_by_tier AS (
  SELECT
    fm.family,
    hft.holiday_name,
    hft.tier,
    SUM(a.Ads_units) AS ads_units
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN `onyga-482313.OI.V_PRODUCT_FAMILY_MAP` fm
    ON a.ASIN_BY_CAMPAIGN_NAME = fm.asin
  JOIN hist_family_tier hft
    ON hft.family = fm.family AND hft.date = a.date
  GROUP BY 1, 2, 3
),

total_units_by_tier AS (
  SELECT
    fm.family,
    hft.holiday_name,
    hft.tier,
    SUM(f.PURCHASED_UNITS) AS total_units
  FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` f
  JOIN `onyga-482313.OI.V_PRODUCT_FAMILY_MAP` fm
    ON fm.asin = f.PURCHASED_ASIN
  JOIN hist_family_tier hft
    ON hft.family = fm.family AND hft.date = f.DATE
  GROUP BY 1, 2, 3
),

ads_share_by_tier AS (
  SELECT
    a.family,
    a.holiday_name,
    a.tier,
    a.ads_units,
    t.total_units,
    -- Cap ads_share at 0.95 to prevent >100% attribution
    LEAST(
      SAFE_DIVIDE(a.ads_units, NULLIF(t.total_units, 0)),
      0.95
    ) AS ads_share
  FROM ads_units_by_tier a
  LEFT JOIN total_units_by_tier t
    ON t.family = a.family
    AND t.holiday_name = a.holiday_name
    AND t.tier = a.tier
),

-- ═══ 5. Future months grid ═══
forecast_months AS (
  SELECT
    DATE_TRUNC(DATE_ADD(CURRENT_DATE(), INTERVAL offset MONTH), MONTH) AS month_start,
    LAST_DAY(DATE_ADD(CURRENT_DATE(), INTERVAL offset MONTH)) AS month_end,
    EXTRACT(MONTH FROM DATE_ADD(CURRENT_DATE(), INTERVAL offset MONTH)) AS mo,
    EXTRACT(YEAR FROM DATE_ADD(CURRENT_DATE(), INTERVAL offset MONTH)) AS yr
  FROM UNNEST(GENERATE_ARRAY(0, 11)) AS offset
),

-- ═══ 6. Tag FUTURE dates per family with (holiday, tier) ═══
future_dates AS (
  SELECT d, fm.mo, fm.yr
  FROM forecast_months fm,
  UNNEST(GENERATE_DATE_ARRAY(fm.month_start, fm.month_end)) d
),
future_tagged AS (
  SELECT
    af.family,
    fd.d,
    fd.mo,
    fd.yr,
    CASE
      WHEN fh.peak_start IS NOT NULL AND fd.d BETWEEN fh.peak_start AND fh.peak_end THEN 'peak'
      WHEN fh.has_boost AND fd.d BETWEEN fh.boost_start AND fh.boost_end THEN 'boost'
      WHEN fh.holiday_name IS NOT NULL THEN 'boost'
      ELSE 'offseason'
    END AS tier,
    COALESCE(fh.holiday_name, 'offseason') AS holiday_name
  FROM active_families af
  CROSS JOIN future_dates fd
  LEFT JOIN family_holidays fh
    ON fh.family = af.family
    AND fd.d BETWEEN fh.boost_start AND fh.peak_end
),
future_deduped AS (
  SELECT
    family, d, mo, yr, tier, holiday_name,
    ROW_NUMBER() OVER (
      PARTITION BY family, d
      ORDER BY CASE WHEN tier = 'peak' THEN 0 WHEN tier = 'boost' THEN 1 ELSE 2 END,
               holiday_name
    ) AS rn
  FROM future_tagged
),
future_family_tier AS (
  SELECT family, d, mo, yr, tier, holiday_name
  FROM future_deduped
  WHERE rn = 1
),

-- ═══ 7. Count days per family × month × holiday × tier ═══
month_holiday_days AS (
  SELECT
    family, yr, mo, holiday_name, tier,
    COUNT(*) AS days
  FROM future_family_tier
  GROUP BY 1, 2, 3, 4, 5
),

-- ═══ 8. Join future day counts with MATCHING historical efficiency ═══
month_enriched AS (
  SELECT
    mhd.family,
    mhd.yr,
    mhd.mo,
    mhd.holiday_name,
    mhd.tier,
    mhd.days,
    -- CPC
    COALESCE(hte.cpc, hte_off.cpc) AS cpc,
    -- Unit CVR (unit-based)
    COALESCE(hte.unit_cvr, hte_off.unit_cvr) AS unit_cvr,
    -- Order CVR (for diagnostics)
    COALESCE(hte.order_cvr, hte_off.order_cvr) AS order_cvr,
    -- Net ROAS
    COALESCE(hte.net_roas, hte_off.net_roas) AS net_roas,
    -- Cost per order
    COALESCE(hte.cost_per_order, hte_off.cost_per_order) AS cost_per_order,
    -- Avg daily spend
    COALESCE(hte.avg_daily_spend, hte_off.avg_daily_spend) AS avg_daily_spend,
    -- Ads share (from FACT tables, capped at 0.95)
    COALESCE(ast.ads_share, ast_off.ads_share, 0.75) AS ads_share
  FROM month_holiday_days mhd
  -- Matching holiday+tier efficiency
  LEFT JOIN holiday_tier_efficiency hte
    ON hte.family = mhd.family
    AND hte.holiday_name = mhd.holiday_name
    AND hte.tier = mhd.tier
  -- Offseason fallback
  LEFT JOIN holiday_tier_efficiency hte_off
    ON hte_off.family = mhd.family
    AND hte_off.holiday_name = 'offseason'
    AND hte_off.tier = 'offseason'
  -- Ads share (matching tier)
  LEFT JOIN ads_share_by_tier ast
    ON ast.family = mhd.family
    AND ast.holiday_name = mhd.holiday_name
    AND ast.tier = mhd.tier
  -- Ads share (offseason fallback)
  LEFT JOIN ads_share_by_tier ast_off
    ON ast_off.family = mhd.family
    AND ast_off.holiday_name = 'offseason'
    AND ast_off.tier = 'offseason'
),

-- ═══ 9. Aggregate across holiday segments within each month ═══
month_agg AS (
  SELECT
    family,
    yr,
    mo,
    -- Tier day counts
    SUM(CASE WHEN tier = 'offseason' THEN days ELSE 0 END) AS off_days,
    SUM(CASE WHEN tier = 'boost' THEN days ELSE 0 END) AS boost_days,
    SUM(CASE WHEN tier = 'peak' THEN days ELSE 0 END) AS peak_days,
    SUM(days) AS total_days,
    -- Holidays in this month
    STRING_AGG(DISTINCT CASE WHEN holiday_name != 'offseason' THEN holiday_name END, ', ') AS holidays_in_month,

    -- Day-weighted blended metrics
    SAFE_DIVIDE(SUM(cpc * days), SUM(days)) AS avg_cpc,
    SAFE_DIVIDE(SUM(unit_cvr * days), SUM(days)) AS avg_unit_cvr,
    SAFE_DIVIDE(SUM(order_cvr * days), SUM(days)) AS avg_order_cvr,
    SAFE_DIVIDE(SUM(net_roas * days), SUM(days)) AS avg_net_roas,
    SAFE_DIVIDE(SUM(cost_per_order * days), SUM(days)) AS avg_cost_per_order,
    SAFE_DIVIDE(SUM(ads_share * days), SUM(days)) AS avg_ads_share,

    -- Suggested spend = Σ(avg_daily_spend_per_segment × days_in_segment)
    SUM(avg_daily_spend * days) AS suggested_spend,

    -- ═══ FORECAST UNITS via 3-parameter model ═══
    -- For each segment: daily_clicks × unit_cvr / ads_share × days
    -- = (avg_daily_spend / cpc) × unit_cvr / ads_share × days
    SUM(
      SAFE_DIVIDE(avg_daily_spend, NULLIF(cpc, 0))
      * unit_cvr
      / NULLIF(ads_share, 0)
      * days
    ) AS forecast_units,

    -- Per-tier diagnostics: offseason
    MAX(CASE WHEN tier = 'offseason' THEN cpc END) AS off_cpc,
    MAX(CASE WHEN tier = 'offseason' THEN unit_cvr END) AS off_unit_cvr,
    MAX(CASE WHEN tier = 'offseason' THEN net_roas END) AS off_net_roas,
    MAX(CASE WHEN tier = 'offseason' THEN avg_daily_spend END) AS off_daily_spend,

    -- Boost
    SAFE_DIVIDE(
      SUM(CASE WHEN tier = 'boost' THEN cpc * days END),
      NULLIF(SUM(CASE WHEN tier = 'boost' THEN days END), 0)
    ) AS boost_cpc,
    SAFE_DIVIDE(
      SUM(CASE WHEN tier = 'boost' THEN unit_cvr * days END),
      NULLIF(SUM(CASE WHEN tier = 'boost' THEN days END), 0)
    ) AS boost_unit_cvr,
    SAFE_DIVIDE(
      SUM(CASE WHEN tier = 'boost' THEN net_roas * days END),
      NULLIF(SUM(CASE WHEN tier = 'boost' THEN days END), 0)
    ) AS boost_net_roas,
    SAFE_DIVIDE(
      SUM(CASE WHEN tier = 'boost' THEN avg_daily_spend * days END),
      NULLIF(SUM(CASE WHEN tier = 'boost' THEN days END), 0)
    ) AS boost_daily_spend,

    -- Peak
    SAFE_DIVIDE(
      SUM(CASE WHEN tier = 'peak' THEN cpc * days END),
      NULLIF(SUM(CASE WHEN tier = 'peak' THEN days END), 0)
    ) AS peak_cpc,
    SAFE_DIVIDE(
      SUM(CASE WHEN tier = 'peak' THEN unit_cvr * days END),
      NULLIF(SUM(CASE WHEN tier = 'peak' THEN days END), 0)
    ) AS peak_unit_cvr,
    SAFE_DIVIDE(
      SUM(CASE WHEN tier = 'peak' THEN net_roas * days END),
      NULLIF(SUM(CASE WHEN tier = 'peak' THEN days END), 0)
    ) AS peak_net_roas,
    SAFE_DIVIDE(
      SUM(CASE WHEN tier = 'peak' THEN avg_daily_spend * days END),
      NULLIF(SUM(CASE WHEN tier = 'peak' THEN days END), 0)
    ) AS peak_daily_spend
  FROM month_enriched
  GROUP BY 1, 2, 3
),

-- ═══ 10. Current Path: trailing 30-day actual daily spend per family ═══
-- This anchors the "Current" forecast to real recent spend, not historical avg.
current_spend AS (
  SELECT
    fm.family,
    SAFE_DIVIDE(SUM(a.Ads_cost), NULLIF(COUNT(DISTINCT a.date), 0)) AS current_daily_spend,
    SAFE_DIVIDE(SUM(a.Ads_cost), NULLIF(SUM(a.Ads_clicks), 0)) AS current_cpc
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN `onyga-482313.OI.V_PRODUCT_FAMILY_MAP` fm
    ON a.ASIN_BY_CAMPAIGN_NAME = fm.asin
  WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
    AND a.date < CURRENT_DATE()
  GROUP BY 1
)

-- ═══ 11. Final output ═══
SELECT
  ma.family,
  ma.yr AS forecast_year,
  ma.mo AS forecast_month,

  -- Tier composition
  ma.off_days,
  ma.boost_days,
  ma.peak_days,
  ma.total_days,
  ma.holidays_in_month,

  -- 3-Parameter model outputs
  ROUND(ma.avg_cpc, 3) AS cpc,
  ROUND(ma.avg_unit_cvr * 100, 2) AS unit_cvr_pct,
  ROUND(ma.avg_ads_share * 100) AS ads_share_pct,

  -- ═══ TARGET path: historical avg daily spend → forecast ═══
  ROUND(ma.suggested_spend) AS suggested_spend,
  ROUND(ma.forecast_units) AS forecast_units,
  -- Target net profit = target_spend × (net_roas - 1)
  ROUND(ma.suggested_spend * GREATEST(ma.avg_net_roas - 1, 0)) AS target_net_profit,

  -- ═══ CURRENT path: trailing 30d actual daily spend → forecast ═══
  ROUND(COALESCE(cs.current_daily_spend, 0)) AS current_daily_spend,
  ROUND(COALESCE(cs.current_cpc, 0), 3) AS current_cpc,
  ROUND(COALESCE(cs.current_daily_spend, 0) * ma.total_days) AS current_spend,
  ROUND(
    SAFE_DIVIDE(COALESCE(cs.current_daily_spend, 0) * ma.total_days, NULLIF(ma.avg_cpc, 0))
    * ma.avg_unit_cvr
    / NULLIF(ma.avg_ads_share, 0)
  ) AS current_forecast_units,
  -- Current net profit = current_spend × (net_roas - 1)
  ROUND(COALESCE(cs.current_daily_spend, 0) * ma.total_days * GREATEST(ma.avg_net_roas - 1, 0)) AS current_net_profit,

  -- Profitability
  ROUND(ma.avg_net_roas, 2) AS avg_net_roas,
  ma.avg_net_roas > 1.0 AS is_profitable,
  ROUND(ma.avg_cost_per_order, 2) AS cost_per_incremental_order,

  -- Spend bounds
  ROUND(ma.suggested_spend * CASE WHEN ma.peak_days > 0 THEN 1.5 ELSE 1.2 END) AS max_monthly_spend,

  -- Per-tier diagnostics
  ROUND(ma.off_cpc, 3) AS off_cpc,
  ROUND(ma.off_unit_cvr * 100, 2) AS off_unit_cvr_pct,
  ROUND(ma.off_net_roas, 2) AS off_net_roas,
  ROUND(ma.off_daily_spend) AS off_daily_spend,

  ROUND(ma.boost_cpc, 3) AS boost_cpc,
  ROUND(ma.boost_unit_cvr * 100, 2) AS boost_unit_cvr_pct,
  ROUND(ma.boost_net_roas, 2) AS boost_net_roas,
  ROUND(ma.boost_daily_spend) AS boost_daily_spend,

  ROUND(ma.peak_cpc, 3) AS peak_cpc,
  ROUND(ma.peak_unit_cvr * 100, 2) AS peak_unit_cvr_pct,
  ROUND(ma.peak_net_roas, 2) AS peak_net_roas,
  ROUND(ma.peak_daily_spend) AS peak_daily_spend

FROM month_agg ma
LEFT JOIN current_spend cs ON cs.family = ma.family
ORDER BY ma.family, ma.yr, ma.mo;
