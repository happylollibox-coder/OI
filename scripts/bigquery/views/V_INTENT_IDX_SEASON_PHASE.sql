CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE`
OPTIONS (description = "Holiday-phase index for the intent CVR curve, projected onto month_of_year. month_of_year cannot represent a moving holiday: Easter moved 15 days between 2025 and 2026 and March flipped from 0.691% to 5.562% CVR while cvr_hat said 2.892% both times. Measured on DIM_US_HOLIDAYS phase windows the BOOST->PEAK swing is ~5x in both years. PROJECTION IS ONE YEAR AHEAD from the ads watermark, blended by days per month, so every published number moves when the watermark rolls and changes wholesale once the horizon passes Easter 2027 -- the curve must be rebuilt when DIM_US_HOLIDAYS rolls forward. Days outside every window take the intent's own OFF phase index, so a month is a true day-weighted blend rather than an extrapolation from a handful of in-window days, and support_clicks is the MONTH's evidence (each day carries its phase's clicks divided by that phase's projected day count), so a thin month reports thin support and is pinned neutral by INTENT_IDX_MIN_SUPPORT downstream. READ THE SHAPE AS A RATIO, NOT A MAXIMUM: Contract 1 normalises to a clicks-weighted mean of 1.000 and 70.5% of easter clicks are PEAK, so the PEAK PHASE index is capped at 1/0.705 = 1.418, and the March MONTH index is capped tighter at 1.214 by March holding 82.4% of projected support. Acceptance R07 therefore tests peak-to-trough RATIO, not MAX. As of ads watermark 2026-08-31, easter runs Jan 0.6877 / Feb 0.3081 / Mar 1.1308 / off-season 0.8047, a 3.67x ratio. Uses its own grain-specific prior INTENT_PHASE_PRIOR_CLICKS (123, the median of 99 intent_key x phase cells), NOT the season prior 4038, which belongs to a 33x larger grain. NO ROWS IS NOT A BUG for back-to-school or halloween (DIM_US_HOLIDAYS carries NULL cooldown dates so phase_of resolves no window and intent_scope drops them -- they DO reach obs) nor for the mothers-day keys, prime-day and cyber-monday (zero orders ever, dropped by the intent_lvl HAVING); the shadow curve COALESCEs a miss to 1.000. NOTHING READS THIS YET: registered in DE_INTENT_INDEX_REGISTRY with is_active=FALSE until V_INTENT_CVR_CURVE_SHADOW passes the scorecard and money gate. Acceptance: scripts/bigquery/tests/INTENT_INDEX_acceptance.sql.")
AS
-- =============================================================================================
-- V_INTENT_IDX_SEASON_PHASE — holiday-phase multiplier for the intent CVR curve.
-- Grain: one row per intent_key x month_of_year, for the holiday-linked intents only.
--
-- WHY IT EXISTS. month_of_year cannot represent a moving holiday. Easter fell 2025-04-20 and
-- 2026-04-05, so March flipped from pre-peak to peak: easter x White Lollibox ran 0.691% CVR in
-- March 2025 and 5.562% in March 2026 while cvr_hat said 2.892% both times. Re-keyed on the phase
-- windows DIM_US_HOLIDAYS already carries, the shape is consistent across both years —
-- BOOST 0.544%/1.925%, PEAK 2.972%/6.984%, COOLDOWN 4.575%/4.718%.
--
-- CONTRACT (every registry index honours these three):
--   1. clicks-weighted mean of index_value is 1.000 PER intent_key, so the index shifts SHAPE
--      not LEVEL and INTENT_CVR_CALIBRATION cannot silently absorb it.
--   2. index_value is never NULL and never <= 0.
--   3. every row publishes its support_clicks so a thin cell can be weighed, not just trusted.
--      support_clicks is THE MONTH'S OWN EVIDENCE, not the phase's — see the projection below.
--
-- NOTHING READS THIS YET. Registered with is_active = FALSE and joined by nothing until
-- V_INTENT_CVR_CURVE_SHADOW is built and passes the money gate.
--
-- SCOPE. Only intents carrying a holiday_name reach this view — 8.3% of cost / 9.2% of clicks.
-- Deliberately narrow: it exists to fix one specific defect, not to price the account.
--
-- HOW TO READ THE SHAPE — AS A RATIO, NOT AS A MAXIMUM. Contract 1 normalises against a
-- clicks-weighted mean, and for a holiday intent that mean is itself peak-dominated. TWO DIFFERENT
-- CEILINGS FOLLOW, and they bound two different objects — this is not a contradiction:
--   * A PHASE's index is capped by that phase's share of the intent's clicks. Easter runs 70.5%
--     of its clicks in PEAK (14,841 of 21,052 at this view's scope), so the PEAK PHASE index
--     cannot exceed 1/0.705 = 1.418.
--   * A MONTH's published index is capped by that month's share of projected support, which is
--     tighter still once one month absorbs a whole phase: March holds 82.4% of
--     easter's projected support, capping the March MONTH index at 1.214.
-- So the season reads as "off-season is 0.3" rather than "peak is 5x". That is correct: base_cvr
-- already carries the peak-weighted level, and this index's only job is the departure from it.
-- The first cut of acceptance R07 asked for MAX(index_value) >= 1.5 and was therefore testing the
-- normaliser rather than the signal; it is a PEAK-TO-TROUGH RATIO test instead. Spec section 4.5.
--
-- WHY SOME HOLIDAY INTENTS PRODUCE NO ROWS AT ALL — absence here is not a bug:
--   * back-to-school and halloween: DIM_US_HOLIDAYS carries NULL cooldown_start / cooldown_end for
--     both, so phase_of resolves no window for them. THEY DO REACH obs — the LEFT JOIN misses and
--     COALESCE admits their clicks under phase 'OFF' with a perfectly valid intent_lvl.cvr
--     (halloween: 50 clicks, 1 order). They are dropped one stage later, at intent_scope, which
--     keeps only intents whose holiday phase_of can actually resolve. An intent with no window has
--     no phase structure to project, and publishing 12 identical rows would be noise, not a shape.
--   * all five mothers-day keys, prime-day, cyber-monday: zero orders across their entire history,
--     so intent_lvl.cvr is 0 and the HAVING drops them. An intent that has never converted has no
--     shape to measure.
-- The shadow curve COALESCEs a missing cell to 1.000, which is the right answer in every case.
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

-- Which phase a given date sits in for a given holiday. Exactly one row per holiday_name x day:
-- one occurrence's four windows tile [pre_season_start, cooldown_end] contiguously, and two
-- occurrences of the same holiday are a year apart so their windows cannot overlap (verified: 0
-- duplicate holiday_name x day pairs over 1,564). THE `ELSE 'OFF'` BRANCH IS UNREACHABLE for the
-- same reason — the four windows exhaust the generated range. It is kept only because a CASE
-- needs a terminal ELSE. 'OFF' as a real phase is minted in obs and intent_days below, not here;
-- reading this ELSE as the origin of OFF is the wrong mental model.
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
-- A click outside every window of its own holiday is stamped 'OFF' — that is where the OFF phase
-- index comes from, and the projection below leans on it for out-of-season months.
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
    -- LAUNCH-RAMP QUARANTINE. V_INTENT_CVR_CURVE's season CTE excludes a product's first 90 days
    -- (in_launch_ramp), added 2026-07-25 after ramp rows produced a false "LolliBall 11x
    -- back-to-school" signal: a launch curve happens once, a season repeats. MEASURED IMMATERIAL
    -- AT THIS GRAIN TOO: it drops 2 rows of the published grid (5 and 2 support clicks) and moves
    -- the largest surviving row by 0.0268, with zero effect on easter. Kept: correct and cheap.
    AND f.date >= DATE_ADD((SELECT MIN(u.date) FROM `onyga-482313.OI.V_UNIFIED_DAILY` u
                            WHERE u.product_short_name = d.product_short_name AND u.units > 0),
                           INTERVAL 90 DAY)
),

-- The intent's own all-period rate: what a phase is measured against.
-- HAVING cvr > 0 drops intents that have never converted, and it is load-bearing rather than
-- tidy: without it NULLIF would null every phase_index for such an intent, the LEFT JOIN in
-- day_val could not then tell "this phase was never observed" (fall back to 1.000) from "this
-- intent has no rate at all" (drop it), and the zero-order intents would be resurrected at 1.000.
intent_lvl AS (
  SELECT intent_key, SAFE_DIVIDE(SUM(orders), SUM(clicks)) AS cvr
  FROM obs GROUP BY intent_key
  HAVING cvr > 0
),

-- Beta-binomial shrink toward the intent's own rate, expressed as a ratio to it.
phase_idx AS (
  SELECT o.intent_key, o.phase,
    SUM(o.clicks) AS phase_clicks,
    SAFE_DIVIDE(
      SAFE_DIVIDE(SUM(o.orders) + p.k_phase * il.cvr, SUM(o.clicks) + p.k_phase),
      il.cvr) AS phase_index
  FROM obs o
  JOIN intent_lvl il USING(intent_key)
  CROSS JOIN params p
  GROUP BY o.intent_key, o.phase, p.k_phase, il.cvr
),

-- ---------------------------------------------------------------------------------------------
-- PROJECTION: the next 12 months from the ads watermark, day by day, each day carrying the phase
-- that intent will be in on that date. Blending by days is the only weight available — future
-- clicks are unknown.
--
-- EVERY DAY OF THE GRID IS KEPT, INCLUDING DAYS INSIDE NO WINDOW. An earlier cut filtered to
-- window days only, and that was a real defect: Easter 2027's pre_season_start is 2027-01-24, so
-- only 8 of January's 31 days sit in any window, and January was published at the PRE index as if
-- the whole month were pre-season — a deep haircut on three out-of-season weeks decided by 8 days.
-- Worse, it was INCONSISTENT: a month with zero window days produced no row and COALESCEd to
-- 1.000 downstream, while a month with one window day inherited that phase outright. The same
-- out-of-season period got two contradictory answers depending on an arbitrary boundary.
-- Uncovered days now take the intent's own OFF index, which phase_idx already computes from real
-- out-of-season clicks, so January is a genuine 8/31 blend.
-- ---------------------------------------------------------------------------------------------

-- LAST_DAY IS LOAD-BEARING. DATE_ADD(..., INTERVAL 11 MONTH) alone lands on the FIRST of the
-- twelfth month, so that month would blend a single day. Still exactly 12 distinct
-- month_of_year values, so no month is counted twice.
cal AS (
  SELECT d AS day FROM wm, UNNEST(GENERATE_DATE_ARRAY(
    DATE_TRUNC(wm.watermark, MONTH),
    LAST_DAY(DATE_ADD(DATE_TRUNC(wm.watermark, MONTH), INTERVAL 11 MONTH)))) AS d
),

-- SELECT DISTINCT, NOT A JOIN THROUGH V_ADS_SEARCH_TERM_INTENT AT SEARCH-TERM GRAIN. The earlier
-- cut fanned the 365-day grid across 41,401 search-term rows to perform what is a 26-row lookup,
-- and its day-average was only correct because intent_key -> holiday_name happens to be 1:1
-- today. Nothing enforces that; a second holiday on one intent_key would have skewed the average
-- silently by weighting days by search-term count. DISTINCT makes the invariant visible.
-- Restricted to holidays phase_of can actually resolve, which is what excludes back-to-school and
-- halloween (NULL cooldown dates) rather than anything in obs.
intent_scope AS (
  SELECT DISTINCT i.intent_key, i.holiday_name
  FROM `onyga-482313.OI.V_ADS_SEARCH_TERM_INTENT` i
  JOIN (SELECT DISTINCT holiday_name FROM phase_of) h USING(holiday_name)
  WHERE i.holiday_name IS NOT NULL
),

-- One row per intent_key x day. Days inside that intent's own holiday window carry its phase;
-- every other day is OFF for that intent.
intent_days AS (
  SELECT s.intent_key, c.day, EXTRACT(MONTH FROM c.day) AS month_of_year,
         COALESCE(p.phase, 'OFF') AS phase
  FROM intent_scope s
  CROSS JOIN cal c
  LEFT JOIN phase_of p ON p.holiday_name = s.holiday_name AND p.day = c.day
),

-- How many days of the projection each intent spends in each phase. This is the denominator that
-- turns a phase's total historical clicks into a PER-DAY rate.
phase_days AS (
  SELECT intent_key, phase, COUNT(*) AS n_days FROM intent_days GROUP BY 1,2
),

-- Each projected day carries (a) the index of its phase and (b) its share of that phase's
-- evidence. SUPPORT IS PER-DAY, WHICH IS THE POINT: an earlier cut day-averaged whole-phase
-- totals, so a month touched by a single window day inherited the entire phase's support and
-- sailed past INTENT_IDX_MIN_SUPPORT = 100 downstream — exactly what let a thin month reach
-- production instead of being pinned neutral. Summed per month, this form makes a thin month
-- report thin support, and conserves the intent's total clicks across the 12 months.
day_val AS (
  SELECT idd.intent_key, idd.month_of_year,
    -- pi.intent_key IS NULL means this phase was never observed for this intent -> neutral 1.000.
    -- A phase_index that is present but NULL (k_phase unresolved) must stay NULL and poison the
    -- month, so that a missing threshold empties the view rather than publishing a fake 1.000.
    IF(pi.intent_key IS NULL, 1.0, pi.phase_index) AS idx_v,
    COALESCE(SAFE_DIVIDE(pi.phase_clicks, pd.n_days), 0) AS day_support
  FROM intent_days idd
  LEFT JOIN phase_idx  pi ON pi.intent_key = idd.intent_key AND pi.phase = idd.phase
  LEFT JOIN phase_days pd ON pd.intent_key = idd.intent_key AND pd.phase = idd.phase
),
projected AS (
  SELECT intent_key, month_of_year,
    IF(LOGICAL_OR(idx_v IS NULL), NULL, AVG(idx_v)) AS raw_index,
    CAST(ROUND(SUM(day_support)) AS INT64) AS support_clicks
  FROM day_val GROUP BY 1,2
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
