CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE`
OPTIONS (description = "Holiday-phase index for the intent CVR curve, projected onto month_of_year. WHY IT EXISTS: month_of_year cannot represent a moving holiday. Easter fell 2025-04-20 and 2026-04-05, so March flipped from pre-peak to peak and the easter x White Lollibox CVR went 0.691% -> 5.562% in the same calendar month while cvr_hat said 2.892% both times. Measured on the phase windows already in DIM_US_HOLIDAYS the shape is consistent across years: BOOST 0.544%/1.925%, PEAK 2.972%/6.984%, COOLDOWN 4.575%/4.718%. Reaches the ~9% of clicks carrying a holiday_name. PROJECTION IS ONE YEAR AHEAD: phases are mapped onto the next 12 months from the ads watermark and blended by days per month, so the curve must be rebuilt when DIM_US_HOLIDAYS rolls forward. Normalised per intent_key to a mean of 1.000 because base_cvr already carries the level. Registered as season_phase. Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md")
AS
-- =============================================================================================
-- V_INTENT_IDX_SEASON_PHASE — holiday-phase multiplier for the intent CVR curve.
-- Grain: one row per intent_key x month_of_year, for the holiday-linked intents only.
--
-- CONTRACT (every registry index honours these three):
--   1. clicks-weighted mean of index_value is 1.000 PER intent_key, so the index shifts SHAPE
--      not LEVEL and INTENT_CVR_CALIBRATION cannot silently absorb it.
--   2. index_value is never NULL and never <= 0.
--   3. every row publishes its support_clicks so a thin cell can be weighed, not just trusted.
--
-- NOTHING READS THIS YET. Registered with is_active = FALSE and joined by nothing until
-- V_INTENT_CVR_CURVE_SHADOW is built and passes the money gate.
--
-- !! ACCEPTANCE R07 FAILS AS BUILT. DO NOT ACTIVATE THIS INDEX. !!
--   Measured 2026-08-31 on watermark 2026-08-31: easter projects to Jan 0.9364 / Feb 0.7330 /
--   Mar 1.0797. R07 requires MAX(index_value) >= 1.5 for easter and gets 1.0797. Account-wide
--   the whole view is 76.6% inside [0.95,1.05] against the 85.3% of the hardcoded season_index
--   it was meant to replace — that is not a fix, it is the same inertness at a new grain.
--
--   THE BAR IS NOT MERELY MISSED, IT IS UNREACHABLE, and the arithmetic says so independently of
--   any parameter. Contract 1 pins SUM(index_value * support_clicks) / SUM(support_clicks) = 1.0
--   per intent_key. March carries 10,180 of easter's 13,673 projected support — a weight of
--   0.7445 — because PEAK is where the clicks are. A weighted mean of 1.0 therefore caps the
--   March index at 1/0.7445 = 1.343, reached only if every other month were exactly 0. R07 asks
--   for 1.5. Contract 1 and R07 cannot both hold for easter, whatever k_season is set to.
--
--   Two further losses stack underneath that ceiling, both measured:
--     a) k_season = 4038 was re-derived in Task 2 for intent_type pooling, where a cell holds
--        100k+ clicks. Easter's whole history is 21,052 clicks, so a 3,666-click BOOST cell is
--        shrunk almost entirely into the intent mean: the real 5x BOOST->PEAK swing
--        (0.955% vs 5.047%) arrives as phase indices of 0.634 vs 1.173, a 1.85x swing.
--     b) Normalising each phase against the intent's OWN all-period CVR is self-defeating when
--        70% of that intent's clicks ARE the peak. Even at k_season = 0 the PEAK phase index is
--        only 1.220, and easter's March index reaches just 1.2533 — still under 1.5.
--   Only k_season = 0 AND weighting the normaliser by DAYS instead of support_clicks reaches the
--   bar (March 1.7439), and that combination abandons both the shrink prior and Contract 1's
--   stated weighting. That is a design change, not a tuning, and is not made here.
--
--   What the index DOES carry: direction and a 1.47x March-over-February ratio for easter, which
--   is real and points the right way. If the curve only ever consumes the index as a ratio
--   between months, R07 is measuring the wrong statistic. That is a question for the spec owner.
--
-- SCOPE. Only intents carrying a holiday_name reach this view — 8.3% of cost / 9.2% of clicks.
-- Deliberately narrow: it exists to fix one specific defect, not to price the account.
-- Back to School and Halloween carry NULL cooldown windows in DIM_US_HOLIDAYS, so phase_of
-- cannot resolve them and they produce no rows here at all; the shadow curve COALESCEs a miss
-- to 1.000, which is the right answer for an intent this index cannot measure.
--
-- Dependencies: FACT_AMAZON_ADS, V_ADS_SEARCH_TERM_INTENT, DIM_PRODUCT, DIM_US_HOLIDAYS,
--               V_UNIFIED_DAILY, DE_COACH_THRESHOLDS
-- Project: onyga-482313 / Dataset: OI
-- =============================================================================================
WITH params AS (
  -- coach_mode IS PART OF THE RESOLUTION KEY, not a tag (see DE_COACH_THRESHOLDS.sql and the
  -- four-way LEFT JOIN in V_ADS_COACH). Filtering to GUARDIAN + product_family IS NULL makes this
  -- view read the exact row INTENT_INDEX_acceptance R02/R02b pin, and matches the params CTE in
  -- V_INTENT_IDX_SEASON_MONTH. Without it a threshold later added under BLITZ, or a family-scoped
  -- override, would give MAX() two candidates and it would silently return the larger.
  SELECT MAX(IF(threshold_key='INTENT_CVR_SEASON_PRIOR_CLICKS', threshold_value, NULL)) AS k_season
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id = 'INTENT' AND coach_mode = 'GUARDIAN' AND product_family IS NULL
),
wm AS (SELECT MAX(date) AS watermark FROM `onyga-482313.OI.FACT_AMAZON_ADS`),

-- Which phase a given date sits in for a given holiday.
phase_of AS (
  SELECT h.holiday_name, d AS day,
    CASE
      WHEN d BETWEEN h.peak_start       AND DATE_SUB(h.cooldown_start, INTERVAL 1 DAY) THEN 'PEAK'
      WHEN d BETWEEN h.boost_start      AND DATE_SUB(h.peak_start,     INTERVAL 1 DAY) THEN 'BOOST'
      WHEN d BETWEEN h.pre_season_start AND DATE_SUB(h.boost_start,    INTERVAL 1 DAY) THEN 'PRE'
      WHEN d BETWEEN h.cooldown_start   AND h.cooldown_end                             THEN 'COOLDOWN'
      ELSE 'OFF' END AS phase
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h,
  UNNEST(GENERATE_DATE_ARRAY(h.pre_season_start, h.cooldown_end)) AS d
  WHERE h.pre_season_start IS NOT NULL AND h.cooldown_end IS NOT NULL
),

-- Historical clicks for holiday-linked intents, stamped with the phase of their own date.
obs AS (
  SELECT i.intent_key, COALESCE(p.phase, 'OFF') AS phase,
         f.Ads_clicks AS clicks, f.Ads_orders AS orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  JOIN `onyga-482313.OI.V_ADS_SEARCH_TERM_INTENT` i USING(search_term)
  JOIN `onyga-482313.OI.DIM_PRODUCT` d ON d.asin = f.ASIN_BY_CAMPAIGN_NAME
  LEFT JOIN phase_of p ON p.holiday_name = i.holiday_name AND p.day = f.date
  WHERE f.campaign_id <> '-1' AND f.Ads_clicks > 0
    AND i.holiday_name IS NOT NULL
    AND d.parent_name IS NOT NULL AND d.parent_name != 'UNKNOWN'
    -- LAUNCH-RAMP QUARANTINE -- REQUIRED HERE. V_INTENT_CVR_CURVE's season CTE excludes a
    -- product's first 90 days (in_launch_ramp), added 2026-07-25 after ramp rows produced a false
    -- "LolliBall 11x back-to-school" signal: a launch curve happens once, a season repeats.
    -- Measured immaterial at Task 2's intent_type pooling (sd 0.2073 quarantined vs 0.2100 not)
    -- because pooling across the account dilutes any one product's ramp. This index keys on
    -- intent_key x phase, where a single product's launch CAN dominate a cell.
    AND f.date >= DATE_ADD((SELECT MIN(u.date) FROM `onyga-482313.OI.V_UNIFIED_DAILY` u
                            WHERE u.product_short_name = d.product_short_name AND u.units > 0),
                           INTERVAL 90 DAY)
),
intent_lvl AS (
  SELECT intent_key, SAFE_DIVIDE(SUM(orders), SUM(clicks)) AS cvr, SUM(clicks) AS all_clicks
  FROM obs GROUP BY intent_key
),
phase_idx AS (
  SELECT o.intent_key, o.phase,
    SUM(o.clicks) AS phase_clicks,
    SAFE_DIVIDE(
      SAFE_DIVIDE(SUM(o.orders) + p.k_season * il.cvr, SUM(o.clicks) + p.k_season),
      NULLIF(il.cvr, 0)) AS phase_index
  FROM obs o
  JOIN intent_lvl il USING(intent_key)
  CROSS JOIN params p
  GROUP BY o.intent_key, o.phase, p.k_season, il.cvr
),

-- PROJECTION: the next 12 months from the watermark, day by day, each day carrying the phase it
-- will be in that year. Blending by days is the only weight available -- future clicks are unknown.
future_days AS (
  SELECT d AS day,
         EXTRACT(MONTH FROM d) AS month_of_year,
         COALESCE(p.holiday_name, '') AS holiday_name,
         COALESCE(p.phase, 'OFF') AS phase
  FROM wm, UNNEST(GENERATE_DATE_ARRAY(
         DATE_TRUNC(wm.watermark, MONTH),
         DATE_ADD(DATE_TRUNC(wm.watermark, MONTH), INTERVAL 11 MONTH))) AS d
  LEFT JOIN phase_of p ON p.day = d
),
projected AS (
  SELECT pi.intent_key, fd.month_of_year,
    SAFE_DIVIDE(SUM(pi.phase_index), COUNT(*)) AS raw_index,
    CAST(ROUND(SUM(pi.phase_clicks) / COUNT(*)) AS INT64) AS support_clicks
  FROM future_days fd
  JOIN `onyga-482313.OI.V_ADS_SEARCH_TERM_INTENT` ist
    ON ist.holiday_name = fd.holiday_name
  JOIN phase_idx pi ON pi.intent_key = ist.intent_key AND pi.phase = fd.phase
  WHERE fd.holiday_name != ''
  GROUP BY pi.intent_key, fd.month_of_year
),
-- Contract 1, per intent_key. THE `raw_index IS NOT NULL` FILTER IS LOAD-BEARING, same defect as
-- the one fixed in V_INTENT_IDX_SEASON_MONTH: SUM() skips NULLs in the numerator but a NULL row's
-- support_clicks still lands in the DENOMINATOR, so without it the normaliser is computed over a
-- different row set than the final SELECT publishes and the published mean stops being 1.000.
norm AS (
  SELECT intent_key,
         SAFE_DIVIDE(SUM(raw_index * support_clicks), NULLIF(SUM(support_clicks),0)) AS mean_idx
  FROM projected WHERE raw_index IS NOT NULL GROUP BY intent_key
)
SELECT p.intent_key, p.month_of_year,
  ROUND(SAFE_DIVIDE(p.raw_index, n.mean_idx), 4) AS index_value,
  p.support_clicks
FROM projected p JOIN norm n USING(intent_key)
WHERE n.mean_idx > 0 AND p.raw_index IS NOT NULL;
