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
)
SELECT 'R01 registry key unique' AS check_name, v FROM r01
UNION ALL SELECT 'R02 thresholds present', v FROM r02
UNION ALL SELECT 'R02b threshold values correct', v FROM r02b
ORDER BY check_name;
