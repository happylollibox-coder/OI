-- =============================================================================================
-- INTENT INDEX REGISTRY acceptance. Every check returns a VIOLATION COUNT; PASS is 0.
-- Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md
-- =============================================================================================

-- R01 THE REGISTRY EXISTS AND HAS A UNIQUE KEY. A duplicate index_name would apply the same
--     multiplier twice and square it.
WITH r01 AS (
  SELECT COUNTIF(n > 1) AS v
  FROM (SELECT index_name, COUNT(*) AS n
        FROM `onyga-482313.OI.DE_INTENT_INDEX_REGISTRY` GROUP BY 1)
),
-- R02 EVERY THRESHOLD THE CURVE READS IS PRESENT. A missing row makes the multiplier NULL and
--     silently blanks cvr_hat for the whole catalog. COUNT(DISTINCT threshold_key), not COUNT(*):
--     this table really does carry duplicate rows for one key (GLOBAL holds three copies of
--     SCALE_UP_ROAS and five others), so a plain row count lets one duplicate cancel out one
--     missing row and report a clean 0 while the curve is reading a NULL.
r02 AS (
  SELECT 5 - COUNT(DISTINCT threshold_key) AS v
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id = 'INTENT' AND threshold_key IN (
    'INTENT_CVR_BASE_PRIOR_CLICKS','INTENT_CVR_SEASON_PRIOR_CLICKS',
    'INTENT_CVR_CALIBRATION','INTENT_IDX_MIN_SUPPORT','INTENT_IDX_MIN_SCORED_CLICKS')
)
SELECT 'R01 registry key unique' AS check_name, v FROM r01
UNION ALL SELECT 'R02 thresholds present', v FROM r02
ORDER BY check_name;
