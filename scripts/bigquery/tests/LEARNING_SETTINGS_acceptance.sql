-- =============================================================================================
-- LEARNING_SETTINGS acceptance — 2026-10-03, learning-contract piece 2, Task 2.
-- The LEARNING settings seeded by scripts/bigquery/migrations/2026-10-03_learning_settings.sql.
-- EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --nosync "$(grep -v '^[[:space:]]*--' FILE)"
--   bq wait JOB 60; then bq ls -j --parent_job_id=JOB and bq head the last child (the final SELECT).
-- Reads DE_COACH_THRESHOLDS and FACT_THRESHOLD_HISTORY (LEARNING rows only); writes only this
-- script's TEMP tables. No FACT_AMAZON_ADS.
-- Spec: docs/superpowers/specs/2026-10-01-learning-contract-design.md §4 (the scope), §14.
-- Plan: docs/superpowers/plans/2026-10-03-learning-piece2-ledger-grader.md Task 2 Step 2.
-- SOP:  architecture/LEARNING.md §3 "The settings", §10 "Task 2".
--
-- THE CHECKS (violation counts, 0 = PASS):
--   S1 every declared key is present exactly once under strategy_id = 'LEARNING', coach_mode =
--      'GUARDIAN', product_family IS NULL (the scope every reader reads), and no LEARNING row
--      sits under any other coach_mode or family (a row there is invisible to the readers)
--   S2 the history holds every declared key: its latest FACT_THRESHOLD_HISTORY event under that
--      scope exists, is not REMOVED and carries the live value (the migration's CALL of
--      SP_SNAPSHOT_THRESHOLDS, then the nightly pass, keep it so; the ledger cites history_id)
--   S3 a row the migration wrote and nobody has changed since (source = 'SEED', updated_by =
--      'learning-piece2') still holds its declared seed value and a description that names its
--      source ('Seeded 2026-10-03'); a row a proposal or Ori moved is outside S3 by its source
-- Emptiness terms: S1, S2 and S3 each count a declared key with no row under the scope as a
-- violation, so none of them passes on an empty table.
--
-- THE NEGATIVE CONTROLS. Each check is written once over labelled TEMP copies of its input: LIVE,
-- and doctored copies that add or change rows of whatever is live. A control row reads PASS when
-- its doctored copy FIRED (violations >= 1); its measured count is printed beside it.
--   NC_EMPTY        no LEARNING row at all                              -> S1, S2, S3
--   NC_S1_BLITZ     MIN_INVEST_MIN_ROWS under coach_mode = 'BLITZ'      -> S1 (the plan's control)
--   NC_S1_FAMILY    SETTLE_HORIZON_DAYS under product_family 'Lollibox' -> S1
--   NC_S1_DUP       a second SETTLE_HORIZON_DAYS row in scope           -> S1
--   NC_S2_UNSNAPPED the history without OWN_CVR_MIN_CLICKS              -> S2
--   NC_S2_REMOVED   a later REMOVED event for REGRESSION_MAX            -> S2
--   NC_S2_STALE     CLICK_BID_ELASTICITY moved to 1.1, the history not  -> S2
--   NC_S3_VALUE     BID_TO_CPC_RATIO_FALLBACK at 1.17 (the spec's unsourced figure) -> S3
--   NC_S3_NODESC    MATCH_BID_TOL with no description                   -> S3
--
-- TWIN of the migration kept in this file, which must change with it: the declared CTE (the
-- twelve keys and their seed values). The seed values are DECLARED CONSTANTS (Ori's rulings of
-- 2026-10-03), not measurements.
--
-- RUN LOG — the only place this file states a measurement; each entry is dated.
-- RUN 2026-10-03 17:04 UTC, BEFORE the migration (0 LEARNING rows): S1, S2, S3 LIVE 12 each, FAIL
--   — the emptiness terms; every control row read PASS (each copy was empty too).
-- RUN 2026-10-03 17:06 UTC, AFTER the migration (17:05:12 UTC; its CALL of SP_SNAPSHOT_THRESHOLDS
--   wrote 12 ADDED events at 17:05:15 UTC), run as written: 14 rows, every one PASS.
--   S1, S2, S3 LIVE 0. Controls, each FIRED: NC_EMPTY S1 12, S2 12, S3 12; NC_S1_BLITZ 2 (the key
--   missing from the scope + one LEARNING row outside it); NC_S1_FAMILY 2; NC_S1_DUP 1;
--   NC_S2_UNSNAPPED 1; NC_S2_REMOVED 1; NC_S2_STALE 1; NC_S3_VALUE 1; NC_S3_NODESC 1.
--   19.8 slot-seconds, 0.18 MB, 11 s.
-- =============================================================================================

CREATE TEMP TABLE declared AS
SELECT * FROM UNNEST([
  STRUCT('CLICK_BID_ELASTICITY' AS threshold_key, 1.0 AS seed_value),
  ('CPC_BID_EXPONENT', 1.0),
  ('BID_TO_CPC_RATIO_FALLBACK', 0.974),
  ('OWN_CVR_MIN_CLICKS', 30.0),
  ('SETTLE_HORIZON_DAYS', 14.0),
  ('MATCH_WINDOW_DAYS', 3.0),
  ('MATCH_BID_TOL', 0.005),
  ('MATCH_BUDGET_TOL', 0.01),
  ('MIN_INVEST_SIDE_ACCURACY', 0.80),
  ('MIN_INVEST_MIN_ROWS', 20.0),
  ('MIN_GRADED_WINDOWS', 3.0),
  ('REGRESSION_MAX', 0.10)
]);

CREATE TEMP TABLE live_th AS
SELECT * FROM `onyga-482313.OI.DE_COACH_THRESHOLDS` WHERE strategy_id = 'LEARNING';

CREATE TEMP TABLE live_hist AS
SELECT * FROM `onyga-482313.OI.FACT_THRESHOLD_HISTORY`
WHERE source_table = 'DE_COACH_THRESHOLDS' AND strategy_id = 'LEARNING';

-- ---- the threshold copies ----
CREATE TEMP TABLE th AS
SELECT c AS copy, t.*
FROM live_th t, UNNEST(['LIVE', 'NC_S2_UNSNAPPED', 'NC_S2_REMOVED']) AS c
UNION ALL
SELECT 'NC_S1_BLITZ', t.* REPLACE (IF(t.threshold_key = 'MIN_INVEST_MIN_ROWS', 'BLITZ', t.coach_mode) AS coach_mode)
FROM live_th t
UNION ALL
SELECT 'NC_S1_FAMILY', t.* REPLACE (IF(t.threshold_key = 'SETTLE_HORIZON_DAYS', 'Lollibox', t.product_family) AS product_family)
FROM live_th t
UNION ALL
SELECT 'NC_S1_DUP', t.* FROM live_th t
UNION ALL
SELECT 'NC_S1_DUP', t.* FROM live_th t
WHERE t.threshold_key = 'SETTLE_HORIZON_DAYS' AND t.coach_mode = 'GUARDIAN' AND t.product_family IS NULL
UNION ALL
SELECT 'NC_S2_STALE', t.* REPLACE (IF(t.threshold_key = 'CLICK_BID_ELASTICITY', 1.1, t.threshold_value) AS threshold_value)
FROM live_th t
UNION ALL
SELECT 'NC_S3_VALUE', t.* REPLACE (IF(t.threshold_key = 'BID_TO_CPC_RATIO_FALLBACK', 1.17, t.threshold_value) AS threshold_value)
FROM live_th t
UNION ALL
SELECT 'NC_S3_NODESC', t.* REPLACE (IF(t.threshold_key = 'MATCH_BID_TOL', CAST(NULL AS STRING), t.description) AS description)
FROM live_th t;
-- NC_EMPTY has no threshold row.

-- ---- the history copies ----
CREATE TEMP TABLE hist AS
SELECT c AS copy, h.*
FROM live_hist h,
     UNNEST(['LIVE', 'NC_EMPTY', 'NC_S1_BLITZ', 'NC_S1_FAMILY', 'NC_S1_DUP', 'NC_S2_REMOVED',
             'NC_S2_STALE', 'NC_S3_VALUE', 'NC_S3_NODESC']) AS c
UNION ALL
SELECT 'NC_S2_UNSNAPPED', h.* FROM live_hist h WHERE h.threshold_key <> 'OWN_CVR_MIN_CLICKS'
UNION ALL
SELECT 'NC_S2_REMOVED',
       h.* REPLACE (GENERATE_UUID() AS history_id,
                    TIMESTAMP_ADD(h.snapshot_at, INTERVAL 1 SECOND) AS snapshot_at,
                    'REMOVED' AS change_kind,
                    CAST(NULL AS STRING) AS row_fingerprint,
                    CAST(NULL AS FLOAT64) AS threshold_value)
FROM live_hist h
WHERE h.threshold_key = 'REGRESSION_MAX' AND h.coach_mode = 'GUARDIAN' AND h.product_family IS NULL
QUALIFY ROW_NUMBER() OVER (ORDER BY h.snapshot_at DESC, h.key_ordinal DESC) = 1;

WITH
copies AS (
  SELECT copy FROM UNNEST(['LIVE', 'NC_EMPTY', 'NC_S1_BLITZ', 'NC_S1_FAMILY', 'NC_S1_DUP',
                           'NC_S2_UNSNAPPED', 'NC_S2_REMOVED', 'NC_S2_STALE', 'NC_S3_VALUE',
                           'NC_S3_NODESC']) AS copy
),
scoped AS (   -- the scope every reader reads
  SELECT * FROM th
  WHERE strategy_id = 'LEARNING' AND coach_mode = 'GUARDIAN' AND product_family IS NULL
),
scoped_n AS (
  SELECT copy, threshold_key, COUNT(*) AS n_rows FROM scoped GROUP BY copy, threshold_key
),
latest AS (   -- each key's latest history event under the scope
  SELECT copy, threshold_key, change_kind, threshold_value
  FROM hist
  WHERE strategy_id = 'LEARNING' AND coach_mode = 'GUARDIAN' AND product_family IS NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY copy, threshold_key ORDER BY snapshot_at DESC, key_ordinal DESC) = 1
),
s1_keys AS (  -- a declared key missing from the scope, or there more than once
  SELECT c.copy, COUNTIF(IFNULL(s.n_rows, 0) <> 1) AS n
  FROM copies c CROSS JOIN declared d
  LEFT JOIN scoped_n s ON s.copy = c.copy AND s.threshold_key = d.threshold_key
  GROUP BY c.copy
),
s1_out AS (   -- a LEARNING row outside the scope
  SELECT c.copy, COUNT(t.copy) AS n
  FROM copies c
  LEFT JOIN th t
    ON t.copy = c.copy AND t.strategy_id = 'LEARNING'
   AND (t.coach_mode IS DISTINCT FROM 'GUARDIAN' OR t.product_family IS NOT NULL)
  GROUP BY c.copy
),
s2 AS (
  SELECT c.copy,
         COUNTIF(t.threshold_key IS NULL                      -- emptiness: no row to have a history
                 OR l.threshold_key IS NULL                   -- never snapshotted
                 OR l.change_kind = 'REMOVED'                 -- the history says it is gone
                 OR l.threshold_value IS DISTINCT FROM t.threshold_value) AS n  -- the history is stale
  FROM copies c CROSS JOIN declared d
  LEFT JOIN scoped t ON t.copy = c.copy AND t.threshold_key = d.threshold_key
  LEFT JOIN latest l ON l.copy = c.copy AND l.threshold_key = d.threshold_key
  GROUP BY c.copy
),
s3 AS (
  SELECT c.copy,
         COUNTIF(t.threshold_key IS NULL                      -- emptiness
                 OR (t.source = 'SEED' AND t.updated_by = 'learning-piece2'
                     AND (ABS(t.threshold_value - d.seed_value) > 1e-9
                          OR t.description IS NULL
                          OR STRPOS(t.description, 'Seeded 2026-10-03') = 0))) AS n
  FROM copies c CROSS JOIN declared d
  LEFT JOIN scoped t ON t.copy = c.copy AND t.threshold_key = d.threshold_key
  GROUP BY c.copy
),
f AS (
  SELECT k.copy, 'S1' AS chk, k.n + o.n AS n FROM s1_keys k JOIN s1_out o USING (copy)
  UNION ALL SELECT copy, 'S2', n FROM s2
  UNION ALL SELECT copy, 'S3', n FROM s3
),
expect AS (
  SELECT * FROM UNNEST([
    -- A KEY THE READERS CANNOT SEE RESOLVES NULL: the ledger prices nothing, or the grader grades on NULL.
    STRUCT('S1 every declared key once under LEARNING / GUARDIAN / NULL family; no LEARNING row elsewhere' AS check_name, 'S1' AS chk, 'LIVE' AS copy, FALSE AS must_fire),
    -- A SETTING THE HISTORY HAS NOT SEEN HAS NO history_id: the ledger cannot say which value priced a row.
    ('S2 the history holds every declared key, not REMOVED, at its live value', 'S2', 'LIVE', FALSE),
    -- A SEED ROW WEARING THE SEED'S LABEL WITH ANOTHER VALUE: the migration wrote the wrong number, or a hand edit hid behind it.
    ('S3 untouched seed rows hold their declared value and a description naming the source', 'S3', 'LIVE', FALSE),
    ('S1a NEGATIVE CONTROL S1 FIRES: no LEARNING row at all', 'S1', 'NC_EMPTY', TRUE),
    ('S1b NEGATIVE CONTROL S1 FIRES: MIN_INVEST_MIN_ROWS under coach_mode BLITZ', 'S1', 'NC_S1_BLITZ', TRUE),
    ('S1c NEGATIVE CONTROL S1 FIRES: SETTLE_HORIZON_DAYS under product_family Lollibox', 'S1', 'NC_S1_FAMILY', TRUE),
    ('S1d NEGATIVE CONTROL S1 FIRES: SETTLE_HORIZON_DAYS twice in scope', 'S1', 'NC_S1_DUP', TRUE),
    ('S2a NEGATIVE CONTROL S2 FIRES: no LEARNING row at all', 'S2', 'NC_EMPTY', TRUE),
    ('S2b NEGATIVE CONTROL S2 FIRES: the history without OWN_CVR_MIN_CLICKS', 'S2', 'NC_S2_UNSNAPPED', TRUE),
    ('S2c NEGATIVE CONTROL S2 FIRES: a later REMOVED event for REGRESSION_MAX', 'S2', 'NC_S2_REMOVED', TRUE),
    ('S2d NEGATIVE CONTROL S2 FIRES: CLICK_BID_ELASTICITY moved, the history not', 'S2', 'NC_S2_STALE', TRUE),
    ('S3a NEGATIVE CONTROL S3 FIRES: no LEARNING row at all', 'S3', 'NC_EMPTY', TRUE),
    ('S3b NEGATIVE CONTROL S3 FIRES: BID_TO_CPC_RATIO_FALLBACK seeded at 1.17', 'S3', 'NC_S3_VALUE', TRUE),
    ('S3c NEGATIVE CONTROL S3 FIRES: MATCH_BID_TOL with no description', 'S3', 'NC_S3_NODESC', TRUE)
  ])
)
SELECT e.check_name, e.copy, f.n AS violations,
       IF(IF(e.must_fire, f.n >= 1, f.n = 0), 'PASS', 'FAIL') AS result
FROM expect e
LEFT JOIN f ON f.chk = e.chk AND f.copy = e.copy
ORDER BY e.check_name;
