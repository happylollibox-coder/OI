CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE`
OPTIONS (description = "Holiday-phase index for the intent CVR curve, projected onto month_of_year. WHY IT EXISTS: month_of_year cannot represent a moving holiday. Easter fell 2025-04-20 and 2026-04-05, so March flipped from pre-peak to peak and the easter x White Lollibox CVR went 0.691% -> 5.562% in the same calendar month while cvr_hat said 2.892% both times. Measured on the phase windows already in DIM_US_HOLIDAYS the shape is consistent across years: BOOST 0.544%/1.925%, PEAK 2.972%/6.984%, COOLDOWN 4.575%/4.718%. Reaches the ~9% of clicks carrying a holiday_name. PROJECTION IS ONE YEAR AHEAD: phases are mapped onto the next 12 months from the ads watermark and blended by days per month, so the curve must be rebuilt when DIM_US_HOLIDAYS rolls forward. Normalised per intent_key to a mean of 1.000 because base_cvr already carries the level, which means the season reads as off-season 0.33 against peak 1.23 rather than as a peak above 1.5: 70.9% of easter clicks are PEAK, so a mean of 1.000 caps PEAK at 1/0.709 = 1.41. Acceptance R07 tests the peak-to-trough RATIO for that reason. Uses INTENT_PHASE_PRIOR_CLICKS (123, this grain's median cell), NOT the season prior 4038, which belongs to a 33x larger grain and flattens this one. NO ROWS IS NOT A BUG for back-to-school or halloween (DIM_US_HOLIDAYS carries NULL cooldown dates, so no phase window resolves) nor for the mothers-day keys, prime-day and cyber-monday (zero orders ever, so there is no shape to measure). Registered as season_phase. Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md")
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
-- HOW THE SIGNAL READS, AND WHY IT IS NOT A NUMBER ABOVE 1.5. Contract 1 normalises against a
-- clicks-weighted mean, and for a holiday intent that mean is itself peak-dominated: 70.9% of
-- easter's clicks fall in PEAK. A mean of 1.000 therefore caps PEAK's index at 1/0.709 = 1.41,
-- reachable only if every other phase were exactly 0. The index expresses the season as
-- "off-season is 0.3" rather than "peak is 5x", and that is correct -- base_cvr already carries
-- the peak-weighted level, so this index's only job is how far each month departs from it.
-- The first cut of acceptance R07 asked for MAX(index_value) >= 1.5 and so was testing the
-- normaliser rather than the signal; it is a PEAK-TO-TROUGH RATIO test instead. See spec section
-- 4.5, AMENDMENT 2026-08-31.
--
-- WHY SOME HOLIDAY INTENTS PRODUCE NO ROWS AT ALL -- absence here is not a bug:
--   * back-to-school and halloween: DIM_US_HOLIDAYS carries NULL cooldown_start / cooldown_end
--     for both, so phase_of cannot resolve a window and they never reach obs.
--   * all five mothers-day keys, prime-day, cyber-monday: zero orders in their entire history, so
--     intent_lvl.cvr is 0, NULLIF nulls every phase_index and the norm filter drops them. An
--     intent that has never converted has no shape to measure.
-- The shadow curve COALESCEs a missing cell to 1.000, which is the right answer in both cases.
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
  -- INTENT_PHASE_PRIOR_CLICKS, NOT INTENT_CVR_SEASON_PRIOR_CLICKS. A prior belongs to a GRAIN.
  -- The season prior (4038) was derived for intent_type x month, median cell 7,163. This grain is
  -- intent_key x phase: 99 cells, p25 13, median 123, max 15,465 -- 33x smaller. Borrowing 4038
  -- swamped every cell and published an index 76.6% flat inside [0.95,1.05], the same inertness
  -- as the hardcoded season_index the project exists to replace. See migration
  -- 2026-08-31_intent_phase_prior.sql for why the MEDIAN is used here and the p25 rule is not.
  SELECT MAX(IF(threshold_key='INTENT_PHASE_PRIOR_CLICKS', threshold_value, NULL)) AS k_phase
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
      SAFE_DIVIDE(SUM(o.orders) + p.k_phase * il.cvr, SUM(o.clicks) + p.k_phase),
      NULLIF(il.cvr, 0)) AS phase_index
  FROM obs o
  JOIN intent_lvl il USING(intent_key)
  CROSS JOIN params p
  GROUP BY o.intent_key, o.phase, p.k_phase, il.cvr
),

-- PROJECTION: the next 12 months from the watermark, day by day, each day carrying the phase it
-- will be in that year. Blending by days is the only weight available -- future clicks are unknown.
future_days AS (
  SELECT d AS day,
         EXTRACT(MONTH FROM d) AS month_of_year,
         COALESCE(p.holiday_name, '') AS holiday_name,
         COALESCE(p.phase, 'OFF') AS phase
  -- LAST_DAY IS LOAD-BEARING. DATE_ADD(..., INTERVAL 11 MONTH) alone lands on the FIRST of the
  -- twelfth month, so that month would blend a single day instead of a full one and any holiday
  -- phase falling there would be read off one date. Still exactly 12 distinct month_of_year
  -- values, so no month is counted twice.
  FROM wm, UNNEST(GENERATE_DATE_ARRAY(
         DATE_TRUNC(wm.watermark, MONTH),
         LAST_DAY(DATE_ADD(DATE_TRUNC(wm.watermark, MONTH), INTERVAL 11 MONTH)))) AS d
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
