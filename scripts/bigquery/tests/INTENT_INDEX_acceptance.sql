-- =============================================================================================
-- INTENT INDEX REGISTRY acceptance. Every check returns a VIOLATION COUNT; PASS is 0.
-- Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md
-- =============================================================================================

-- R01 THE REGISTRY EXISTS AND HAS A UNIQUE KEY. A duplicate index_name would apply the same
--     multiplier twice and square it.
--     NOTE: the registry is EMPTY until Task 2 seeds season_month, so a green R01 today has
--     validated nothing beyond the table existing — an empty table cannot hold a duplicate. It
--     starts enforcing once there are rows. Do not read today's 0 as evidence the key holds.
WITH r01 AS (
  SELECT COUNTIF(n > 1) AS v
  FROM (SELECT index_name, COUNT(*) AS n
        FROM `onyga-482313.OI.DE_INTENT_INDEX_REGISTRY` GROUP BY 1)
),
-- R02 EVERY THRESHOLD THE CURVE READS IS PRESENT, UNDER THE MODE IT WILL BE READ AT. A missing
--     row makes the multiplier NULL and silently blanks cvr_hat for the whole catalog.
--     coach_mode IS PART OF THE KEY, not a tag: thresholds resolve strategy_id+coach_mode ->
--     GLOBAL+coach_mode -> strategy_id+GUARDIAN -> GLOBAL+GUARDIAN -> hardcoded fallback (see the
--     header of DE_COACH_THRESHOLDS.sql and the four-way LEFT JOIN in V_ADS_COACH). A row landing
--     under BLITZ or COOLDOWN is invisible to a GUARDIAN read, which falls through to a GLOBAL
--     default instead — the curve then prices against a number nobody chose for it, and without
--     this filter the check would still report a clean 0. All five seeded rows are GUARDIAN.
--     COUNT(DISTINCT threshold_key) rather than COUNT(*): product_family is also part of the
--     grain, so a family-scoped override for one of these keys would push a row count past 5 and
--     let one extra row cancel out one missing row.
r02 AS (
  SELECT 5 - COUNT(DISTINCT threshold_key) AS v
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id = 'INTENT' AND coach_mode = 'GUARDIAN' AND threshold_key IN (
    'INTENT_CVR_BASE_PRIOR_CLICKS','INTENT_CVR_SEASON_PRIOR_CLICKS',
    'INTENT_CVR_CALIBRATION','INTENT_IDX_MIN_SUPPORT','INTENT_IDX_MIN_SCORED_CLICKS')
),
-- R02b THE VALUES ARE THE ONES THIS MIGRATION LANDED, not merely present. R02 proves the keys
--      exist and asserts none of the numbers. If the base-prior UPDATE were reverted, or a stale
--      copy of the migration were partially re-run, all five keys would still be there and R02
--      would stay green while the curve priced every intent off the old prior — which is one of
--      the three defects this work exists to fix, so it would fail silently in exactly the place
--      it was supposed to be fixed. Asserts the two values the migration deliberately sets:
--      the base prior it RAISES 200 -> 400, and the calibration constant. The other three are
--      seeded-and-never-yet-tuned, and Task 2 re-derives the season prior, so pinning those here
--      would only create a check that has to be edited every time a number is legitimately tuned.
r02b AS (
  SELECT COUNTIF(
           (threshold_key = 'INTENT_CVR_BASE_PRIOR_CLICKS' AND threshold_value != 400.0)
        OR (threshold_key = 'INTENT_CVR_CALIBRATION'       AND threshold_value != 1.151)
         ) AS v
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id = 'INTENT' AND coach_mode = 'GUARDIAN'
    AND threshold_key IN ('INTENT_CVR_BASE_PRIOR_CLICKS','INTENT_CVR_CALIBRATION')
),
-- R03 EVERY INDEX IS NORMALISED TO A CLICKS-WEIGHTED MEAN OF 1.000. An un-normalised index
--     silently shifts the whole catalog's level and INTENT_CVR_CALIBRATION absorbs it, which
--     hides the change from the scorecard. Tolerance 0.02.
r03 AS (
  SELECT COUNTIF(ABS(m - 1.0) > 0.02) AS v FROM (
    SELECT SAFE_DIVIDE(SUM(index_value * support_clicks), NULLIF(SUM(support_clicks),0)) AS m
    FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_MONTH`)
),
-- R03b THE INDEX GRID IS COMPLETE, AND R03/R04/R05 ARE NOT BEING GREEN OVER AN EMPTY VIEW.
--      Verified by negative control: with the view filtered to zero rows, R03, R04 and R05 all
--      return 0 — an empty set has no mean to be off by 0.02, no NULL to find, and 0 flat values
--      is not > 0 * 0.80. So all three would stay silent on total failure. That is reachable: the
--      params CTE resolves k_season from a single DE_COACH_THRESHOLDS row, and if that row is
--      deleted or moved to another coach_mode, k_season is NULL, every raw_index is NULL, the
--      final WHERE drops every row and the curve loses its whole seasonal layer while acceptance
--      reports a clean pass. Same shape as the R01 note above: a check over an empty table has
--      validated nothing. Also fails if any intent_type is missing a month, because the shadow
--      curve LEFT JOINs this grid and COALESCEs a miss to 1.000 — a silently neutral month.
--      THE EXPECTED TYPE COUNT IS SOURCED FROM DE_INTENT_THEMES, NOT FROM THE VIEW. The first
--      version compared COUNT(*) against COUNT(DISTINCT intent_type) * 12 read off the view
--      itself, which cannot detect a whole intent_type disappearing: t.cvr is one value per TYPE,
--      not per month, so a genuinely-zero all-month CVR nulls raw_index for all 12 of that type's
--      rows at once and the final WHERE drops the entire type — both sides of that comparison then
--      shrink together and it stays green while half the grid is gone. Counting the types that
--      V_ADS_SEARCH_TERM_INTENT can actually resolve (active themes carrying an ads regex) gives
--      an anchor the view cannot move.
r03b AS (
  SELECT CAST(COUNT(*) = 0
           OR COUNT(*) != (SELECT COUNT(DISTINCT intent_type)
                           FROM `onyga-482313.OI.DE_INTENT_THEMES`
                           WHERE is_active AND match_ads_regex IS NOT NULL
                             AND intent_type IS NOT NULL) * 12 AS INT64) AS v
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_MONTH`
),
-- R04 NO INDEX IS NULL OR NON-POSITIVE. A NULL multiplies cvr_hat to NULL; a zero or negative
--     value makes a bid of zero or a negative price.
r04 AS (
  SELECT COUNTIF(index_value IS NULL OR index_value <= 0) AS v
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_MONTH`
),
-- R05 THE INDEX IS ACTUALLY DOING SOMETHING. The defect this replaces had 85.3% of values inside
--     [0.95,1.05]. If the replacement is just as flat it has not been fixed.
--     THRESHOLD IS 0.30, NOT 0.80. Over a 24-row grid, 0.80 fires only at 20/24 (83%) — that is
--     essentially the original 85.3% defect restored exactly, so a regression to 40-50% flat,
--     serious by any standard, would sit here green. 0.30 fires at 8/24 (33%): far enough above
--     today's measured 4.2% (1/24) that ordinary drift in the underlying clicks will not trip it,
--     and small enough a fraction of 85.3% that it actually guards the property it names.
r05 AS (
  SELECT CAST(COUNTIF(index_value BETWEEN 0.95 AND 1.05) > COUNT(*) * 0.30 AS INT64) AS v
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_MONTH`
),
-- R06 PHASE INDEX IS NORMALISED PER INTENT. base_cvr already carries the intent's own level, so
--     an index whose intent-level mean is not 1.0 would double-count that level.
--     PER intent_key, not once overall: this view is keyed on intent_key and the shadow curve
--     joins it on intent_key, so a per-intent level error is exactly what would leak through.
--     THE `COUNT(*) = 0` TERM IS LOAD-BEARING AND GUARDS R07/R08 TOO. Verified by negative
--     control: with the view filtered to zero rows the plain COUNTIF form returns 0 — an empty
--     set has no mean to be off by 0.05 — and R08's duplicate check returns 0 for the same
--     reason. Total failure is reachable: k_season resolves from a single DE_COACH_THRESHOLDS
--     row, and if it is deleted or moved to another coach_mode every phase_index is NULL, the
--     normaliser is NULL and the final WHERE drops the whole view. `m IS NULL` is in the same
--     spirit — a row set whose support_clicks sum to 0 yields a NULL mean, which ABS() > 0.05
--     would also wave through.
r06 AS (
  SELECT COUNTIF(m IS NULL OR ABS(m - 1.0) > 0.05) + CAST(COUNT(*) = 0 AS INT64) AS v FROM (
    SELECT intent_key, SAFE_DIVIDE(SUM(index_value * support_clicks), NULLIF(SUM(support_clicks),0)) AS m
    FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE` GROUP BY intent_key)
),
-- R07 THE PHASE INDEX ACTUALLY PEAKS. Easter measured on phase windows runs BOOST 0.54%/1.93%
--     against PEAK 2.97%/6.98% in 2025/2026 -- roughly 5x. If the projected index for the
--     easter intent never exceeds 1.5 the projection has flattened the signal it exists to carry.
--     COALESCE(...,0) IS LOAD-BEARING. Without it, an easter row set that is empty (or all NULL)
--     makes MAX() NULL, `NULL < 1.5` NULL, and v NULL — which is not the 0 this file defines as
--     PASS but reads like one at a glance. With it, the total-disappearance case scores 1 and
--     fails loudly, which is the correct verdict: no easter row means no moving-holiday fix.
r07 AS (
  SELECT CAST(COALESCE(MAX(index_value), 0) < 1.5 AS INT64) AS v
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE` WHERE intent_key = 'easter'
),
-- R08 ONE ROW PER intent_key x month_of_year. A duplicate multiplies the index twice.
--     Real risk here, not theory: the projection fans out over V_ADS_SEARCH_TERM_INTENT and over
--     overlapping holiday windows, and both fan-outs have to collapse in the GROUP BY.
--     Vacuously green over an empty view; R06's COUNT(*) = 0 term is what covers that case.
r08 AS (
  SELECT COUNTIF(n > 1) AS v FROM (
    SELECT intent_key, month_of_year, COUNT(*) AS n
    FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE` GROUP BY 1,2)
)
SELECT 'R01 registry key unique' AS check_name, v FROM r01
UNION ALL SELECT 'R02 thresholds present', v FROM r02
UNION ALL SELECT 'R02b threshold values correct', v FROM r02b
UNION ALL SELECT 'R03 season_month index normalised to mean 1.000', v FROM r03
UNION ALL SELECT 'R03b season_month grid complete and non-empty', v FROM r03b
UNION ALL SELECT 'R04 season_month index never null or non-positive', v FROM r04
UNION ALL SELECT 'R05 season_month index is not flat', v FROM r05
UNION ALL SELECT 'R06 season_phase index normalised per intent_key', v FROM r06
UNION ALL SELECT 'R07 season_phase index peaks for easter', v FROM r07
UNION ALL SELECT 'R08 season_phase one row per intent_key x month', v FROM r08
ORDER BY check_name;
