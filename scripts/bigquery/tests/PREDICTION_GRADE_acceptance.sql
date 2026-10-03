-- =============================================================================================
-- PREDICTION_GRADE acceptance — 2026-10-03, learning-contract piece 2, Task 5: the grader
-- (SP_GRADE_PREDICTIONS v27.173), its grades (FACT_PREDICTION_GRADE) and its report card
-- (T_PREDICTION_SCORECARD), checked against independent recomputes. EVERY ASSERTED ROW MUST READ
-- PASS; the V2g row is a REPORT. Run it right after a grader run (V1 reads the house watermark now).
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --nosync "$(grep -v '^[[:space:]]*--' FILE)"
--   bq wait JOB 60; then bq ls -j --parent_job_id=JOB and bq head the last child (the final SELECT).
-- Reads FACT_PREDICTION_GRADE, T_PREDICTION_SCORECARD, V_PREDICTION_LEDGER, FACT_AMAZON_ADS (the
-- graded horizons), DIM_KEYWORD, DIM_CAMPAIGN, DE_COACH_THRESHOLDS; writes only this script's TEMP
-- tables. Piece-2 Task 7's contract suite (PREDICTION_CONTRACT_acceptance.sql) is the spec §11 suite;
-- this file is the grader's own.
-- Spec: docs/superpowers/specs/2026-10-01-learning-contract-design.md §7, §11.
-- Plan: docs/superpowers/plans/2026-10-03-learning-piece2-ledger-grader.md Task 5.
-- SOP:  architecture/LEARNING.md §4, §5, §10 "Task 5" (the procedure-copy proofs: idempotence,
--       the re-grade band, the lowered-bar labels, the card's schema).
--
-- THE CHECKS (violation counts, 0 = PASS), over the current grade of every prediction (highest
-- regrade_seq):
--   V1 every ledger row gradable on the house watermark (horizon_to + SETTLE_HORIZON_DAYS <=
--      LEAST(MAX(FACT_AMAZON_ADS.date), FN_ADS_ANCHOR_CAP())) has exactly one current grade, and no
--      current grade lacks a gradable ledger row; +1 when nothing is gradable (emptiness)
--   V2 realised clicks, orders and spend equal FACT_AMAZON_ADS over horizon_from .. horizon_to (no
--      row = 0; spend to the cent), and real_net = real_gp - real_spend; +1 when no grade exists.
--      V2g REPORTS the rows whose gross profit FACT has restated since grading: the grade keeps the
--      copy it was graded on (spec §7, "Idempotent"), so the count is not a failure
--   V3 the frozen copy equals the ledger row: the five predicted numbers (1e-6), pred_side,
--      built_at, the horizon, rule_version, response_model_version, act_is_noop; +1 when empty
--   V4 the label and the click bucket follow from the row and the line stored on it
--      (UNGRADABLE; else INCONCLUSIVE at 0 clicks, below min_clicks_at_grade or with none; else
--      RIGHT / WRONG by side_correct); +1 when empty
--   V5 real_side is the judge's test (orders >= min_orders AND COALESCE(gp / spend, -1) >=
--      family_bar); side_correct = (pred_side = real_side); err_net and abs_err_net; +1 when empty
--   V6 is_applied = (scenario = applied_scenario); a plan row has two rows, agreeing on the applied
--      scenario, the outcome and the label, at most one applied; +1 when empty
--   V7 UNGRADABLE exactly where DIM_KEYWORD or DIM_CAMPAIGN holds an archived version (any case) in
--      force at some moment of the horizon (an independent recompute); +1 when empty
--   V8 the report card reads back from the grades: every SINCE_START CURVE row (predictor x family
--      x state x bucket) and ACCURACY APPLIED row (predictor x family, 'ALL' included) equals a
--      recompute from the grade rows (floats within 1e-6); +1 when the card has no such row
--
-- THE NEGATIVE CONTROLS. Each check runs once over labelled TEMP copies: LIVE and doctored copies of
-- the grade rows (and, for V8, of the card). A control row reads PASS when its copy FIRED; its
-- count is printed beside it. The doctored row is the first of its kind in key order.
--   NC_EMPTY               no grade row, no card row                 -> V1 .. V8
--   NC_V1_MISSING          one grade row removed                     -> V1
--   NC_V2_REAL             one real_spend + 1.00                     -> V2
--   NC_V3_FROZEN           one frozen pred_net + 0.01                -> V3
--   NC_V4_LABEL            one INCONCLUSIVE row with clicks -> RIGHT  -> V4
--   NC_V5_SIDE             one real_side flipped                     -> V5
--   NC_V6_APPLIED          one is_applied flipped                    -> V6
--   NC_V7_FALSE_UNGRADABLE one row labelled UNGRADABLE, no archive   -> V7
--   NC_V7_MISSED_ARCHIVE   an archived version of one graded keyword injected from its first horizon
--                          day on (the archive record copy only)    -> V7
--   NC_V8_CURVE            one card CURVE bucket_spend + 1           -> V8
--   NC_V8_ACC              one card ACCURACY mae_net_share + 0.01    -> V8
--
-- RUN LOG — each entry dated.
-- RUN 2026-10-03 20:51:49 UTC (Task 5; SP_GRADE_PREDICTIONS v27.173 deployed 20:41:50 UTC, first
--   CALL 20:42:19 UTC graded the six August nights, second CALL 20:43:46 UTC inserted 0), run as
--   written, job t5_acc_1791060707: 27 rows, every asserted row PASS. LIVE V1..V8 0 over 8,944 grade
--   rows (4,472 plan rows x 2 scenarios; V1's gradable population 8,944); V2g REPORT 0. Controls,
--   each FIRED: NC_EMPTY V1 8944, V2..V8 1 each; NC_V1_MISSING V1 1; NC_V2_REAL V2 1; NC_V3_FROZEN
--   V3 1; NC_V4_LABEL V4 1; NC_V5_SIDE V5 1; NC_V6_APPLIED V6 1; NC_V7_FALSE_UNGRADABLE V7 1;
--   NC_V7_MISSED_ARCHIVE V7 24 (the injected version runs from the keyword's first horizon day on,
--   so it reaches all six nights x 2 plans x 2 scenarios); NC_V8_CURVE V8 1; NC_V8_ACC V8 1.
--   139.8 slot-seconds, 159,024,712 bytes, 49 s. Every label on this run is INCONCLUSIVE (no line
--   at the 0.80 bar), so V4's RIGHT / WRONG arms were exercised on a copy with the bar at 0.30
--   (architecture/LEARNING.md §10 "Task 5": V1..V7 0 there, 1,428 RIGHT and 2,078 WRONG rows).
-- =============================================================================================

CREATE TEMP TABLE cur AS
SELECT * FROM `onyga-482313.OI.FACT_PREDICTION_GRADE`
QUALIFY ROW_NUMBER() OVER (PARTITION BY predictor, variant, as_of, campaign_id, keyword_id, scenario
                           ORDER BY regrade_seq DESC) = 1;

CREATE TEMP TABLE led AS SELECT * FROM `onyga-482313.OI.V_PREDICTION_LEDGER`;

CREATE TEMP TABLE wm AS
SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d,
       (SELECT CAST(threshold_value AS INT64) FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
        WHERE strategy_id = 'LEARNING' AND coach_mode = 'GUARDIAN' AND product_family IS NULL
          AND threshold_key = 'SETTLE_HORIZON_DAYS') AS settle
FROM `onyga-482313.OI.FACT_AMAZON_ADS`;

-- the rows each control doctors: the first in key order of its kind
CREATE TEMP TABLE pick AS
SELECT 'ANY' AS what, predictor, variant, as_of, campaign_id, keyword_id, scenario FROM cur
QUALIFY ROW_NUMBER() OVER (ORDER BY as_of, predictor, campaign_id, keyword_id, scenario) = 1
UNION ALL
SELECT 'INCONCL', predictor, variant, as_of, campaign_id, keyword_id, scenario FROM cur
WHERE grade = 'INCONCLUSIVE' AND real_clicks > 0
QUALIFY ROW_NUMBER() OVER (ORDER BY as_of DESC, predictor, campaign_id, keyword_id, scenario) = 1
UNION ALL
SELECT 'GRADED_KW', predictor, variant, as_of, campaign_id, keyword_id, scenario FROM cur
WHERE grade <> 'UNGRADABLE' AND scenario = 'DO_NOTHING'
QUALIFY ROW_NUMBER() OVER (ORDER BY as_of, predictor DESC, campaign_id DESC, keyword_id DESC) = 1;

CREATE TEMP TABLE cur_f AS
SELECT c.*,
       EXISTS (SELECT 1 FROM pick p WHERE p.what = 'ANY' AND p.predictor = c.predictor AND p.as_of = c.as_of
               AND p.campaign_id = c.campaign_id AND p.keyword_id = c.keyword_id AND p.scenario = c.scenario) AS f_any,
       EXISTS (SELECT 1 FROM pick p WHERE p.what = 'INCONCL' AND p.predictor = c.predictor AND p.as_of = c.as_of
               AND p.campaign_id = c.campaign_id AND p.keyword_id = c.keyword_id AND p.scenario = c.scenario) AS f_inc
FROM cur c;

CREATE TEMP TABLE g AS
SELECT 'LIVE' AS copy, c.* EXCEPT (f_any, f_inc) FROM cur_f c
UNION ALL SELECT 'NC_V1_MISSING', c.* EXCEPT (f_any, f_inc) FROM cur_f c WHERE NOT c.f_any
UNION ALL SELECT 'NC_V2_REAL', c.* EXCEPT (f_any, f_inc) REPLACE (IF(c.f_any, c.real_spend + 1.0, c.real_spend) AS real_spend) FROM cur_f c
UNION ALL SELECT 'NC_V3_FROZEN', c.* EXCEPT (f_any, f_inc) REPLACE (IF(c.f_any, c.pred_net + 0.01, c.pred_net) AS pred_net) FROM cur_f c
UNION ALL SELECT 'NC_V4_LABEL', c.* EXCEPT (f_any, f_inc) REPLACE (IF(c.f_inc, 'RIGHT', c.grade) AS grade) FROM cur_f c
UNION ALL SELECT 'NC_V5_SIDE', c.* EXCEPT (f_any, f_inc) REPLACE (IF(c.f_any, 1 - c.real_side, c.real_side) AS real_side) FROM cur_f c
UNION ALL SELECT 'NC_V6_APPLIED', c.* EXCEPT (f_any, f_inc) REPLACE (IF(c.f_any, NOT c.is_applied, c.is_applied) AS is_applied) FROM cur_f c
UNION ALL SELECT 'NC_V7_FALSE_UNGRADABLE', c.* EXCEPT (f_any, f_inc) REPLACE (
            IF(c.f_any, 'UNGRADABLE', c.grade) AS grade, IF(c.f_any, 'KEYWORD_ARCHIVED', c.ungradable_reason) AS ungradable_reason) FROM cur_f c
UNION ALL SELECT 'NC_V7_MISSED_ARCHIVE', c.* EXCEPT (f_any, f_inc) FROM cur_f c
UNION ALL SELECT 'NC_V8_CURVE', c.* EXCEPT (f_any, f_inc) FROM cur_f c
UNION ALL SELECT 'NC_V8_ACC', c.* EXCEPT (f_any, f_inc) FROM cur_f c;
-- NC_EMPTY has no grade row.

CREATE TEMP TABLE copies AS
SELECT copy FROM UNNEST(['LIVE', 'NC_EMPTY', 'NC_V1_MISSING', 'NC_V2_REAL', 'NC_V3_FROZEN', 'NC_V4_LABEL',
                         'NC_V5_SIDE', 'NC_V6_APPLIED', 'NC_V7_FALSE_UNGRADABLE', 'NC_V7_MISSED_ARCHIVE',
                         'NC_V8_CURVE', 'NC_V8_ACC']) AS copy;

-- V2's independent outcome: FACT_AMAZON_ADS over each graded row's horizon
CREATE TEMP TABLE real AS
WITH k AS (SELECT DISTINCT campaign_id, keyword_id, horizon_from, horizon_to FROM cur)
SELECT k.*, SUM(f.Ads_clicks) AS clk, SUM(f.Ads_cost) AS sp, SUM(f.Ads_orders) AS ord, SUM(f.GROSS_PROFIT) AS gp
FROM k JOIN `onyga-482313.OI.FACT_AMAZON_ADS` f
  ON f.campaign_id = k.campaign_id AND f.keyword_id = k.keyword_id AND f.date BETWEEN k.horizon_from AND k.horizon_to
GROUP BY 1, 2, 3, 4;

-- V7's independent archive record, plus one injected archived version (NC_V7_MISSED_ARCHIVE)
CREATE TEMP TABLE arch_src AS
SELECT 'REAL' AS src, keyword_id, CAST(NULL AS STRING) AS campaign_id, effective_from, effective_to
FROM `onyga-482313.OI.DIM_KEYWORD` WHERE LOWER(state) = 'archived'
UNION ALL
SELECT 'REAL', CAST(NULL AS STRING), campaign_id, effective_from, effective_to
FROM `onyga-482313.OI.DIM_CAMPAIGN` WHERE LOWER(state) = 'archived'
UNION ALL
SELECT 'INJECTED', c.keyword_id, CAST(NULL AS STRING),
       DATETIME(TIMESTAMP(c.horizon_from, 'America/Los_Angeles'), 'UTC'), CAST(NULL AS DATETIME)
FROM cur c JOIN pick p ON p.what = 'GRADED_KW' AND p.predictor = c.predictor AND p.as_of = c.as_of
                      AND p.campaign_id = c.campaign_id AND p.keyword_id = c.keyword_id AND p.scenario = c.scenario;

CREATE TEMP TABLE arch AS
WITH k AS (SELECT DISTINCT campaign_id, keyword_id, horizon_from, horizon_to FROM cur),
hit AS (
  SELECT x.copy, k.campaign_id, k.keyword_id, k.horizon_from, k.horizon_to
  FROM copies x CROSS JOIN k
  JOIN arch_src a ON a.keyword_id = k.keyword_id
  WHERE (a.src = 'REAL' OR x.copy = 'NC_V7_MISSED_ARCHIVE')
    AND TIMESTAMP(a.effective_from, 'UTC') < TIMESTAMP(DATE_ADD(k.horizon_to, INTERVAL 1 DAY), 'America/Los_Angeles')
    AND (a.effective_to IS NULL OR TIMESTAMP(a.effective_to, 'UTC') > TIMESTAMP(k.horizon_from, 'America/Los_Angeles'))
  UNION ALL
  SELECT x.copy, k.campaign_id, k.keyword_id, k.horizon_from, k.horizon_to
  FROM copies x CROSS JOIN k
  JOIN arch_src a ON a.campaign_id = k.campaign_id
  WHERE a.src = 'REAL'
    AND TIMESTAMP(a.effective_from, 'UTC') < TIMESTAMP(DATE_ADD(k.horizon_to, INTERVAL 1 DAY), 'America/Los_Angeles')
    AND (a.effective_to IS NULL OR TIMESTAMP(a.effective_to, 'UTC') > TIMESTAMP(k.horizon_from, 'America/Los_Angeles'))
)
SELECT DISTINCT copy, campaign_id, keyword_id, horizon_from, horizon_to, TRUE AS archived FROM hit;

-- V8's card copies: the report card's SINCE_START CURVE and ACCURACY APPLIED rows, for every copy;
-- doctored on NC_V8_CURVE (one bucket_spend + 1) and NC_V8_ACC (one mae_net_share + 0.01); none on NC_EMPTY
CREATE TEMP TABLE card AS
SELECT * FROM `onyga-482313.OI.T_PREDICTION_SCORECARD`
WHERE level = 'SINCE_START' AND (row_type = 'CURVE' OR (row_type = 'ACCURACY' AND scenario = 'APPLIED'));

CREATE TEMP TABLE card_pick AS
SELECT row_type, predictor, family, calendar_state, bucket FROM card
QUALIFY ROW_NUMBER() OVER (PARTITION BY row_type ORDER BY predictor, family, calendar_state, bucket) = 1;

CREATE TEMP TABLE card_c AS
SELECT x.copy,
       c.* REPLACE (
         IF(x.copy = 'NC_V8_CURVE' AND p.row_type = 'CURVE', c.bucket_spend + 1, c.bucket_spend) AS bucket_spend,
         IF(x.copy = 'NC_V8_ACC' AND p.row_type = 'ACCURACY', c.mae_net_share + 0.01, c.mae_net_share) AS mae_net_share)
FROM copies x
CROSS JOIN card c
LEFT JOIN card_pick p
  ON p.row_type = c.row_type AND p.predictor = c.predictor AND p.family = c.family
 AND p.calendar_state = c.calendar_state AND p.bucket IS NOT DISTINCT FROM c.bucket
WHERE x.copy <> 'NC_EMPTY';

CREATE TEMP FUNCTION fd(a FLOAT64, b FLOAT64) AS (   -- two FLOAT64 differ beyond 1e-6, or only one is NULL
  (a IS NULL) <> (b IS NULL) OR COALESCE(ABS(a - b) > 1e-6, FALSE)
);

WITH
gradable AS (
  SELECT l.* FROM led l CROSS JOIN wm
  WHERE DATE_ADD(l.horizon_to, INTERVAL wm.settle DAY) <= wm.d
),
gn AS (SELECT COUNT(*) AS n FROM gradable),
gk AS (SELECT x.copy, l.* FROM copies x CROSS JOIN gradable l),
v1_rows AS (   -- every gradable ledger row has one current grade; every current grade has a gradable ledger row
  SELECT COALESCE(l.copy, c.copy) AS copy,
         COUNTIF(l.predictor IS NULL OR c.predictor IS NULL) AS n
  FROM gk l
  FULL OUTER JOIN g c
    ON c.copy = l.copy AND c.predictor = l.predictor AND c.variant = l.variant AND c.as_of = l.as_of
   AND c.campaign_id = l.campaign_id AND c.keyword_id = l.keyword_id AND c.scenario = l.scenario
  GROUP BY 1
),
v2_rows AS (   -- the realised clicks, orders and spend reproduce from FACT_AMAZON_ADS (no row = 0), to the cent;
               -- gross profit restates (V2g counts the drift, unasserted)
  SELECT c.copy,
         COUNTIF(c.real_clicks <> COALESCE(r.clk, 0) OR c.real_orders <> COALESCE(r.ord, 0)
                 OR ABS(c.real_spend - COALESCE(r.sp, 0)) > 0.005
                 OR ABS(c.real_net - (c.real_gp - c.real_spend)) > 0.005) AS n,
         COUNTIF(ABS(c.real_gp - COALESCE(r.gp, 0)) > 0.005) AS n_gp_drift
  FROM g c
  LEFT JOIN real r ON r.campaign_id = c.campaign_id AND r.keyword_id = c.keyword_id
                  AND r.horizon_from = c.horizon_from AND r.horizon_to = c.horizon_to
  GROUP BY c.copy
),
v3_rows AS (   -- the frozen copy equals the ledger row (five numbers within 1e-6, pred_side, built_at, versions)
  SELECT c.copy,
         COUNTIF(l.predictor IS NULL
                 OR ABS(c.pred_clicks - l.pred_clicks) > 1e-6 OR ABS(c.pred_spend - l.pred_spend) > 1e-6
                 OR ABS(c.pred_orders - l.pred_orders) > 1e-6 OR ABS(c.pred_gp - l.pred_gp) > 1e-6
                 OR ABS(c.pred_net - l.pred_net) > 1e-6
                 OR c.pred_side IS DISTINCT FROM l.pred_side OR c.built_at IS DISTINCT FROM l.built_at
                 OR c.horizon_from IS DISTINCT FROM l.horizon_from OR c.horizon_to IS DISTINCT FROM l.horizon_to
                 OR c.rule_version IS DISTINCT FROM l.rule_version
                 OR c.response_model_version IS DISTINCT FROM l.response_model_version
                 OR c.act_is_noop IS DISTINCT FROM l.act_is_noop) AS n
  FROM g c
  LEFT JOIN led l
    ON l.predictor = c.predictor AND l.variant = c.variant AND l.as_of = c.as_of
   AND l.campaign_id = c.campaign_id AND l.keyword_id = c.keyword_id AND l.scenario = c.scenario
  GROUP BY c.copy
),
v4_rows AS (   -- the label follows from the row's own fields and the line it stores
  SELECT copy,
         COUNTIF(grade IS DISTINCT FROM CASE
                   WHEN ungradable_reason IS NOT NULL THEN 'UNGRADABLE'
                   WHEN real_clicks = 0 OR min_clicks_at_grade IS NULL OR real_clicks < min_clicks_at_grade THEN 'INCONCLUSIVE'
                   WHEN side_correct THEN 'RIGHT' ELSE 'WRONG' END
                 OR click_bucket IS DISTINCT FROM CASE
                   WHEN real_clicks = 0 THEN '0' WHEN real_clicks <= 5 THEN '1-5' WHEN real_clicks <= 10 THEN '6-10'
                   WHEN real_clicks <= 20 THEN '11-20' WHEN real_clicks <= 40 THEN '21-40'
                   WHEN real_clicks <= 80 THEN '41-80' ELSE '81+' END) AS n
  FROM g GROUP BY copy
),
v5_rows AS (   -- the realised side is the judge's test; side_correct and the error follow
  SELECT copy,
         COUNTIF(real_side IS DISTINCT FROM IF(real_orders >= min_orders
                   AND COALESCE(SAFE_DIVIDE(real_gp, real_spend), -1) >= family_bar, 1, 0)
                 OR side_correct IS DISTINCT FROM (pred_side = real_side)
                 OR ABS(err_net - (pred_net - real_net)) > 1e-6 OR ABS(abs_err_net - ABS(pred_net - real_net)) > 1e-6) AS n
  FROM g GROUP BY copy
),
v6a AS (
  SELECT copy, COUNTIF(is_applied IS DISTINCT FROM (scenario = applied_scenario)) AS n FROM g GROUP BY copy
),
v6b AS (
  SELECT copy, COUNT(*) AS n FROM (
    SELECT copy, predictor, as_of, campaign_id, keyword_id
    FROM g GROUP BY 1, 2, 3, 4, 5
    HAVING COUNT(DISTINCT applied_scenario) > 1 OR COUNT(DISTINCT grade) > 1
        OR COUNT(DISTINCT real_clicks) > 1 OR MAX(real_spend) - MIN(real_spend) > 1e-9
        OR COUNTIF(is_applied) > 1 OR COUNT(*) <> 2)
  GROUP BY copy
),
v6_rows AS (   -- is_applied marks exactly the applied scenario; a plan row has two rows agreeing on outcome and label
  SELECT x.copy, COALESCE(a.n, 0) + COALESCE(b.n, 0) AS n
  FROM copies x LEFT JOIN v6a a ON a.copy = x.copy LEFT JOIN v6b b ON b.copy = x.copy
),
v7_rows AS (   -- UNGRADABLE exactly where the keyword or campaign was archived within the horizon
  SELECT c.copy,
         COUNTIF((c.grade = 'UNGRADABLE') IS DISTINCT FROM COALESCE(a.archived, FALSE)) AS n
  FROM g c
  LEFT JOIN arch a ON a.copy = c.copy AND a.campaign_id = c.campaign_id AND a.keyword_id = c.keyword_id
                  AND a.horizon_from = c.horizon_from AND a.horizon_to = c.horizon_to
  GROUP BY c.copy
),
rc AS (        -- V8's recompute from each grade copy: SINCE_START CURVE per predictor x family x state x
               -- bucket, and ACCURACY APPLIED per predictor x family (the 'ALL' rollup included)
  SELECT g.copy, 'CURVE' AS row_type, g.predictor, g.family, g.calendar_state, b.bucket,
         COUNTIF(g.click_bucket = b.bucket) AS bucket_rows,
         SUM(IF(g.click_bucket = b.bucket, g.real_spend, 0)) AS bucket_spend,
         SAFE_DIVIDE(SUM(IF(g.click_bucket = b.bucket AND g.side_correct, g.real_spend, 0)),
                     SUM(IF(g.click_bucket = b.bucket, g.real_spend, 0))) AS bucket_accuracy,
         IF(b.fl = 0, NULL, COUNTIF(g.real_clicks >= b.fl)) AS cum_rows,
         IF(b.fl = 0, NULL, SAFE_DIVIDE(SUM(IF(g.real_clicks >= b.fl AND g.side_correct, g.real_spend, 0)),
                                        SUM(IF(g.real_clicks >= b.fl, g.real_spend, 0)))) AS cum_accuracy,
         CAST(NULL AS FLOAT64) AS mae_net_share, CAST(NULL AS FLOAT64) AS bias_share,
         CAST(NULL AS FLOAT64) AS side_accuracy, CAST(NULL AS INT64) AS n_rows
  FROM g, UNNEST([STRUCT('0' AS bucket, 0 AS fl), ('1-5', 1), ('6-10', 6), ('11-20', 11), ('21-40', 21),
                  ('41-80', 41), ('81+', 81)]) AS b
  WHERE g.scenario = 'DO_NOTHING' AND g.grade <> 'UNGRADABLE' AND g.predictor <> 'FIXTURE'
  GROUP BY g.copy, g.predictor, g.family, g.calendar_state, b.bucket, b.fl
  UNION ALL
  SELECT g.copy, 'ACCURACY', g.predictor, x.f, x.s, CAST(NULL AS STRING), NULL, NULL, NULL, NULL, NULL,
         SAFE_DIVIDE(SUM(g.abs_err_net), SUM(g.real_spend)), SAFE_DIVIDE(SUM(g.err_net), SUM(g.real_spend)),
         SAFE_DIVIDE(SUM(IF(g.side_correct, g.real_spend, 0)), SUM(g.real_spend)), COUNT(*)
  FROM g, UNNEST([STRUCT(g.family AS f, g.calendar_state AS s), STRUCT('ALL' AS f, 'ALL' AS s)]) AS x
  WHERE g.is_applied AND g.grade <> 'UNGRADABLE' AND g.predictor <> 'FIXTURE'
  GROUP BY g.copy, g.predictor, x.f, x.s
),
v8_rows AS (   -- every recomputed row has its card row, equal (floats within 1e-6)
  SELECT r.copy,
         COUNTIF(c.predictor IS NULL
                 OR c.bucket_rows IS DISTINCT FROM r.bucket_rows OR fd(c.bucket_spend, r.bucket_spend)
                 OR fd(c.bucket_accuracy, r.bucket_accuracy) OR c.cum_rows IS DISTINCT FROM r.cum_rows
                 OR fd(c.cum_accuracy, r.cum_accuracy) OR fd(c.mae_net_share, r.mae_net_share)
                 OR fd(c.bias_share, r.bias_share) OR fd(c.side_accuracy, r.side_accuracy)
                 OR (r.row_type = 'ACCURACY' AND c.n_rows IS DISTINCT FROM r.n_rows)) AS n
  FROM rc r
  LEFT JOIN card_c c
    ON c.copy = r.copy AND c.row_type = r.row_type AND c.predictor = r.predictor AND c.family = r.family
   AND c.calendar_state = r.calendar_state AND c.bucket IS NOT DISTINCT FROM r.bucket
  GROUP BY r.copy
),
card_n AS (SELECT copy, COUNT(*) AS n FROM card_c GROUP BY copy),
pop AS (SELECT x.copy, COUNT(g.copy) AS n FROM copies x LEFT JOIN g ON g.copy = x.copy GROUP BY x.copy),
f AS (
  SELECT x.copy, 'V1' AS chk, COALESCE(v1.n, 0) + IF((SELECT n FROM gn) = 0, 1, 0) AS n
  FROM copies x LEFT JOIN v1_rows v1 ON v1.copy = x.copy
  UNION ALL SELECT p.copy, 'V2', COALESCE(v.n, 0) + IF(p.n = 0, 1, 0) FROM pop p LEFT JOIN v2_rows v ON v.copy = p.copy
  UNION ALL SELECT p.copy, 'V3', COALESCE(v.n, 0) + IF(p.n = 0, 1, 0) FROM pop p LEFT JOIN v3_rows v ON v.copy = p.copy
  UNION ALL SELECT p.copy, 'V4', COALESCE(v.n, 0) + IF(p.n = 0, 1, 0) FROM pop p LEFT JOIN v4_rows v ON v.copy = p.copy
  UNION ALL SELECT p.copy, 'V5', COALESCE(v.n, 0) + IF(p.n = 0, 1, 0) FROM pop p LEFT JOIN v5_rows v ON v.copy = p.copy
  UNION ALL SELECT p.copy, 'V6', COALESCE(v.n, 0) + IF(p.n = 0, 1, 0) FROM pop p LEFT JOIN v6_rows v ON v.copy = p.copy
  UNION ALL SELECT p.copy, 'V7', COALESCE(v.n, 0) + IF(p.n = 0, 1, 0) FROM pop p LEFT JOIN v7_rows v ON v.copy = p.copy
  UNION ALL SELECT p.copy, 'V2g', COALESCE(v.n_gp_drift, 0) FROM pop p LEFT JOIN v2_rows v ON v.copy = p.copy
  UNION ALL SELECT x.copy, 'V8', COALESCE(v.n, 0) + IF(COALESCE(k.n, 0) = 0, 1, 0)
            FROM copies x LEFT JOIN v8_rows v ON v.copy = x.copy LEFT JOIN card_n k ON k.copy = x.copy
),
expect AS (
  SELECT * FROM UNNEST([
    STRUCT('V1 every gradable ledger row has exactly one current grade, and no grade lacks one' AS check_name, 'V1' AS chk, 'LIVE' AS copy, FALSE AS must_fire),
    ('V2 realised clicks, orders and spend reproduce from FACT_AMAZON_ADS (net = gp - spend)', 'V2', 'LIVE', FALSE),
    ('V3 the frozen copy equals the ledger row', 'V3', 'LIVE', FALSE),
    ('V4 the label and bucket follow from the row and its stored line', 'V4', 'LIVE', FALSE),
    ('V5 the realised side is the judge test; side_correct and errors follow', 'V5', 'LIVE', FALSE),
    ('V6 is_applied marks the applied scenario; both rows of a plan row agree', 'V6', 'LIVE', FALSE),
    ('V7 UNGRADABLE exactly where archived within the horizon', 'V7', 'LIVE', FALSE),
    ('V1a NC fires: no grade row', 'V1', 'NC_EMPTY', TRUE),
    ('V1b NC fires: one grade row missing', 'V1', 'NC_V1_MISSING', TRUE),
    ('V2a NC fires: no grade row', 'V2', 'NC_EMPTY', TRUE),
    ('V2b NC fires: one real_spend + 1.00', 'V2', 'NC_V2_REAL', TRUE),
    ('V3a NC fires: no grade row', 'V3', 'NC_EMPTY', TRUE),
    ('V3b NC fires: one frozen pred_net + 0.01', 'V3', 'NC_V3_FROZEN', TRUE),
    ('V4a NC fires: no grade row', 'V4', 'NC_EMPTY', TRUE),
    ('V4b NC fires: one INCONCLUSIVE row with clicks relabelled RIGHT', 'V4', 'NC_V4_LABEL', TRUE),
    ('V5a NC fires: no grade row', 'V5', 'NC_EMPTY', TRUE),
    ('V5b NC fires: one real_side flipped', 'V5', 'NC_V5_SIDE', TRUE),
    ('V6a NC fires: no grade row', 'V6', 'NC_EMPTY', TRUE),
    ('V6b NC fires: one is_applied flipped', 'V6', 'NC_V6_APPLIED', TRUE),
    ('V7a NC fires: no grade row', 'V7', 'NC_EMPTY', TRUE),
    ('V7b NC fires: a row labelled UNGRADABLE with no archive', 'V7', 'NC_V7_FALSE_UNGRADABLE', TRUE),
    ('V7c NC fires: an archived version injected in one graded horizon', 'V7', 'NC_V7_MISSED_ARCHIVE', TRUE),
    ('V8 the report card reads back from the grades (SINCE_START CURVE and ACCURACY APPLIED)', 'V8', 'LIVE', FALSE),
    ('V8a NC fires: no card row', 'V8', 'NC_EMPTY', TRUE),
    ('V8b NC fires: one CURVE bucket_spend + 1', 'V8', 'NC_V8_CURVE', TRUE),
    ('V8c NC fires: one ACCURACY mae_net_share + 0.01', 'V8', 'NC_V8_ACC', TRUE)
  ])
)
SELECT e.check_name, e.copy, f.n AS violations,
       IF(IF(e.must_fire, f.n >= 1, f.n = 0), 'PASS', 'FAIL') AS result
FROM expect e LEFT JOIN f ON f.chk = e.chk AND f.copy = e.copy
UNION ALL
SELECT 'V2g REPORT gross profit restated since grading (frozen grades keep their copy; not asserted)', 'LIVE', f.n, 'REPORT'
FROM f WHERE f.chk = 'V2g' AND f.copy = 'LIVE'
ORDER BY check_name;
