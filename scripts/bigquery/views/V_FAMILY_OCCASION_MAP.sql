-- =============================================
-- OI Database Project - V_FAMILY_OCCASION_MAP View
-- =============================================
--
-- Purpose: Auto-detect which occasions each product family participates in,
--          by measuring historical peak lift (orders during BOOST/PEAK vs OFF_SEASON).
--          Used by V_ADS_COACH to resolve coach_mode per family per day.
--
-- Logic:
--   1. For each family × occasion, compare avg daily orders during
--      BOOST/PEAK vs pure OFF_SEASON
--   2. Calculate lift_ratio = peak_daily / off_season_daily
--   3. Any occasion with lift ≥ 1.3 is considered "relevant" for that family
--   4. If manual override exists in DE_FAMILY_OCCASION_OVERRIDE, use that
--
-- Output: one row per family × occasion (only relevant ones)
--   parent_name, occasion, lift_ratio, peak_daily_orders, off_daily_orders, is_override
--
-- Dependencies: FACT_AMAZON_ADS, DIM_PRODUCT, DIM_TIME, DE_FAMILY_OCCASION_OVERRIDE
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_FAMILY_OCCASION_MAP`
AS
WITH

-- Off-season baseline: avg daily orders when ALL occasions are OFF_SEASON
off_season_baseline AS (
  SELECT
    p.parent_name,
    SAFE_DIVIDE(SUM(fa.Ads_orders), COUNT(DISTINCT fa.date)) as off_season_daily_orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  JOIN `onyga-482313.OI.DIM_PRODUCT` p
    ON COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) = p.asin
  JOIN `onyga-482313.OI.DIM_TIME` t ON fa.date = t.full_date
  WHERE fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
    AND p.parent_name IS NOT NULL AND p.parent_name != 'UNKNOWN'
    AND t.occasion_easter_phase = 'OFF_SEASON'
    AND t.occasion_christmas_phase = 'OFF_SEASON'
    AND t.occasion_back_to_school_phase = 'OFF_SEASON'
    AND t.occasion_valentines_phase = 'OFF_SEASON'
  GROUP BY 1
),

-- Peak orders per family × occasion (only BOOST/PEAK days)
peak_orders AS (
  SELECT
    p.parent_name,
    CASE
      WHEN t.occasion_easter_phase IN ('BOOST', 'PEAK') THEN 'EASTER'
      WHEN t.occasion_christmas_phase IN ('BOOST', 'PEAK') THEN 'CHRISTMAS'
      WHEN t.occasion_back_to_school_phase IN ('BOOST', 'PEAK') THEN 'BACK_TO_SCHOOL'
      WHEN t.occasion_valentines_phase IN ('BOOST', 'PEAK') THEN 'VALENTINES'
    END as occasion,
    SAFE_DIVIDE(SUM(fa.Ads_orders), COUNT(DISTINCT fa.date)) as peak_daily_orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  JOIN `onyga-482313.OI.DIM_PRODUCT` p
    ON COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) = p.asin
  JOIN `onyga-482313.OI.DIM_TIME` t ON fa.date = t.full_date
  WHERE fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
    AND p.parent_name IS NOT NULL AND p.parent_name != 'UNKNOWN'
    AND (t.occasion_easter_phase IN ('BOOST', 'PEAK')
      OR t.occasion_christmas_phase IN ('BOOST', 'PEAK')
      OR t.occasion_back_to_school_phase IN ('BOOST', 'PEAK')
      OR t.occasion_valentines_phase IN ('BOOST', 'PEAK'))
  GROUP BY 1, 2
),

-- Calculate lift + rank
family_lift AS (
  SELECT
    pk.parent_name,
    pk.occasion,
    ROUND(pk.peak_daily_orders, 2) as peak_daily_orders,
    ROUND(bl.off_season_daily_orders, 2) as off_season_daily_orders,
    ROUND(SAFE_DIVIDE(pk.peak_daily_orders, NULLIF(bl.off_season_daily_orders, 0)), 2) as lift_ratio,
    ROW_NUMBER() OVER (
      PARTITION BY pk.parent_name
      ORDER BY SAFE_DIVIDE(pk.peak_daily_orders, NULLIF(bl.off_season_daily_orders, 0)) DESC
    ) as rank_by_lift
  FROM peak_orders pk
  JOIN off_season_baseline bl ON pk.parent_name = bl.parent_name
  WHERE pk.occasion IS NOT NULL
),

-- Manual overrides (can disable an auto-detected occasion or force one)
overrides AS (
  SELECT parent_name, primary_occasion, is_active
  FROM `onyga-482313.OI.DE_FAMILY_OCCASION_OVERRIDE`
)

-- Final: all occasions with lift ≥ 1.3 OR manual override forcing it
SELECT
  fl.parent_name,
  fl.occasion,
  fl.lift_ratio,
  fl.peak_daily_orders,
  fl.off_season_daily_orders,
  fl.rank_by_lift,
  fl.rank_by_lift = 1 as is_primary,
  COALESCE(ov.is_active IS NOT NULL, FALSE) as is_override
FROM family_lift fl
LEFT JOIN overrides ov ON fl.parent_name = ov.parent_name AND fl.occasion = ov.primary_occasion
WHERE fl.lift_ratio >= 1.3  -- meaningful peak lift
   OR (ov.primary_occasion IS NOT NULL AND ov.is_active = TRUE);
