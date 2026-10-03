-- =============================================================================================
-- PREDICTION_CONTRACT acceptance — 2026-10-03, learning-contract piece 2. Started by Task 4 with
-- the ledger's checks L1-L4 (V_PREDICTION_LEDGER); Task 7 completes it with the spec §11 checks
-- 1-5 and 8 (the grader, the labels, the fixtures, the health checks, the parity with
-- FN_PLAN_SCORECARD). EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --nosync "$(grep -v '^[[:space:]]*--' FILE)"
--   bq wait JOB 60; then bq ls -j --parent_job_id=JOB and bq head the last child (the final SELECT).
-- Reads V_PREDICTION_LEDGER (twice) and FACT_PLAN_NEXT_WEEK's keys; writes only this script's TEMP
-- tables. No FACT_AMAZON_ADS.
-- Spec: docs/superpowers/specs/2026-10-01-learning-contract-design.md §5, §6, §11, §14.
-- Plan: docs/superpowers/plans/2026-10-03-learning-piece2-ledger-grader.md Task 4 Step 5 (L1-L4).
-- SOP:  architecture/LEARNING.md §1-§3, §10 "Task 4".
--
-- THE CHECKS (violation counts, 0 = PASS):
--   L1a every FACT_PLAN_NEXT_WEEK row (as_of, plan, campaign_id, keyword_id) has exactly one
--       DO_NOTHING and one ACT ledger row, and no ledger row lacks a plan row; +1 when the plan
--       table holds no row (emptiness)
--   L1b the five predicted numbers are non-NULL on every row; +1 when the ledger is empty
--   L1c basis_clicks is non-NULL and >= 0 on every row; +1 when the ledger is empty
--   L1d every row has a rule_version; +1 when the ledger is empty
--   L2  ANCHORING: on every plan row with act_is_noop and no budget cut (campaign_planned_budget
--       not below campaign_current_budget), ACT equals DO_NOTHING to the cent on all five numbers
--       (|ACT - DO_NOTHING| < 0.005; a NULL difference counts); +1 when that population holds no
--       row with window clicks (emptiness: every such row would otherwise pass on zeros)
--   L3  the brief's two worked examples (10-03, plan B) reproduce; a missing example row counts
--   L4  the view is deterministic: two reads, keyed FULL OUTER JOIN on (as_of, predictor,
--       campaign_id, keyword_id, scenario), every column equal (floats within 1e-6, house rule on
--       float parity); a key on one side only counts; +1 when the first read is empty
--
-- L3's expected values. Example 1, keyword 305171316086021 (LolliME SP, REPRICE 0.75 -> 0.71):
-- clicks, spend and orders are the brief's (DO_NOTHING 84 / 75.71 / 4.455; ACT 79.5 / 67.85 /
-- 4.22). Gross profit, net and the seat are the stored night's, which is not the write the brief
-- read: the brief read the 13:04:57 UTC write (w_gp_corrected 56.8067, seat 72.0843 over the
-- horizon; time travel, job t4_tt_ex_1791057063), and the night stored now is the 16:34:13 UTC
-- rewrite (w_gp_corrected 55.1582, seat 71.403) — FACT_AMAZON_ADS restated GROSS_PROFIT at 16:08
-- UTC in between (spec §14.2 E6). The view's own body run on the 13:04:57 write gives the brief's
-- DO_NOTHING 56.81 / -18.90 and ACT 53.78 / -14.07 (architecture/LEARNING.md §10 "Task 4").
-- Example 2, keyword 439648864838275 (Fresh SB, PARK 1.15 -> 0.25): ACT 19.6 clicks / $4.63, the
-- seat $0 (the brief's), DO_NOTHING 90 / $97.96. Both nights are frozen (v27.170), so these values
-- do not move.
--
-- THE NEGATIVE CONTROLS. Each check is written once over labelled TEMP copies of the ledger: LIVE,
-- and doctored copies of it. A control row reads PASS when its doctored copy FIRED (violations >=
-- 1); its measured count is printed beside it. The doctored row is the first eligible row in key
-- order (as_of, predictor, campaign_id, keyword_id, scenario).
--   NC_EMPTY           no ledger row (and an empty second read)          -> L1a-L1d, L2, L3, L4
--   NC_L1_ONE_SCENARIO one ACT row removed                               -> L1a
--   NC_L1_NULL_NUMBER  one row's pred_gp NULL                            -> L1b
--   NC_L1_NEG_BASIS    one row's basis_clicks -1                         -> L1c
--   NC_L1_NO_RULE      one row's rule_version NULL                       -> L1d
--   NC_L2_R_09         one L2 row with window clicks: its ACT priced at r = 0.9 (clicks, orders,
--                      gross profit x 0.9, spend x 0.81, net recomputed) -> L2 (the plan's control)
--   NC_L3_SPEND_R1     example 1's ACT spend at r^1 (window spend x r)   -> L3
--   NC_L3_SEAT         example 2's ACT spend at the seat ($0)            -> L3
--   NC_L4_DRIFT        the second read: one row's pred_net + 0.01 and another row missing -> L4
--
-- RUN LOG — each entry dated. (Besides it, only L3's paragraph above quotes measured values: the
-- ones L3 holds, each with its source.)
-- RUN 2026-10-03 19:49 UTC (Task 4, V_PREDICTION_LEDGER v27.172 deployed 19:49:05 UTC), run as
--   written, job t4_acc_1791056985: 22 rows, every one PASS. LIVE L1a, L1b, L1c, L1d, L2, L3, L4 0
--   over 17,588 ledger rows (8,794 plan rows); L2's population 1,142 ACT rows, 96 with window clicks
--   (job t4_meas_1791057281). Controls, each FIRED: NC_EMPTY L1a 8794, L1b 1, L1c 1, L1d 1, L2 1,
--   L3 16, L4 1; NC_L1_ONE_SCENARIO L1a 1; NC_L1_NULL_NUMBER L1b 1; NC_L1_NEG_BASIS L1c 1;
--   NC_L1_NO_RULE L1d 1; NC_L2_R_09 L2 1; NC_L3_SPEND_R1 L3 1; NC_L3_SEAT L3 1; NC_L4_DRIFT L4 2.
--   235.9 slot-seconds, 108,751,862 bytes, 22 s.
-- =============================================================================================

CREATE TEMP TABLE live AS
SELECT * FROM `onyga-482313.OI.V_PREDICTION_LEDGER`;

-- the second read (L4): a separate statement with different text, so no cached result can answer it
CREATE TEMP TABLE live2 AS
SELECT l.* FROM `onyga-482313.OI.V_PREDICTION_LEDGER` l WHERE l.scenario IN ('DO_NOTHING', 'ACT');

CREATE TEMP TABLE plan_keys AS
SELECT as_of, CONCAT('PLAN_', plan) AS predictor, campaign_id, keyword_id
FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`;

-- ---- the rows each control doctors (first eligible in key order) ----
CREATE TEMP TABLE pick AS
SELECT 'ANY' AS what, as_of, predictor, campaign_id, keyword_id
FROM live WHERE scenario = 'ACT'
QUALIFY ROW_NUMBER() OVER (ORDER BY as_of, predictor, campaign_id, keyword_id) = 1
UNION ALL
SELECT 'L2', a.as_of, a.predictor, a.campaign_id, a.keyword_id
FROM live a
WHERE a.scenario = 'ACT' AND a.act_is_noop AND a.basis_clicks > 0
  AND NOT COALESCE(a.campaign_planned_budget < a.campaign_current_budget, FALSE)
QUALIFY ROW_NUMBER() OVER (ORDER BY a.as_of, a.predictor, a.campaign_id, a.keyword_id) = 1
UNION ALL
SELECT 'L4_MISSING', as_of, predictor, campaign_id, keyword_id
FROM live WHERE scenario = 'DO_NOTHING'
QUALIFY ROW_NUMBER() OVER (ORDER BY as_of DESC, predictor DESC, campaign_id DESC, keyword_id DESC) = 1;

CREATE TEMP TABLE live_f AS
SELECT l.*,
       (p1.what IS NOT NULL AND l.scenario = 'ACT') AS f_any,
       (p2.what IS NOT NULL AND l.scenario = 'ACT') AS f_l2,
       (l.scenario = 'ACT' AND l.as_of = DATE '2026-10-03' AND l.predictor = 'PLAN_B'
        AND l.keyword_id = '305171316086021') AS f_ex1,
       (l.scenario = 'ACT' AND l.as_of = DATE '2026-10-03' AND l.predictor = 'PLAN_B'
        AND l.keyword_id = '439648864838275') AS f_ex2
FROM live l
LEFT JOIN pick p1 ON p1.what = 'ANY' AND p1.as_of = l.as_of AND p1.predictor = l.predictor
                 AND p1.campaign_id = l.campaign_id AND p1.keyword_id = l.keyword_id
LEFT JOIN pick p2 ON p2.what = 'L2' AND p2.as_of = l.as_of AND p2.predictor = l.predictor
                 AND p2.campaign_id = l.campaign_id AND p2.keyword_id = l.keyword_id;

-- ---- the ledger copies ----
CREATE TEMP TABLE lg AS
SELECT c AS copy, l.* EXCEPT (f_any, f_l2, f_ex1, f_ex2)
FROM live_f l, UNNEST(['LIVE', 'NC_L4_DRIFT']) AS c
UNION ALL
SELECT 'NC_L1_ONE_SCENARIO', l.* EXCEPT (f_any, f_l2, f_ex1, f_ex2) FROM live_f l
WHERE NOT l.f_any
UNION ALL
SELECT 'NC_L1_NULL_NUMBER',
       l.* EXCEPT (f_any, f_l2, f_ex1, f_ex2) REPLACE (IF(l.f_any, CAST(NULL AS FLOAT64), l.pred_gp) AS pred_gp)
FROM live_f l
UNION ALL
SELECT 'NC_L1_NEG_BASIS',
       l.* EXCEPT (f_any, f_l2, f_ex1, f_ex2) REPLACE (IF(l.f_any, -1, l.basis_clicks) AS basis_clicks)
FROM live_f l
UNION ALL
SELECT 'NC_L1_NO_RULE',
       l.* EXCEPT (f_any, f_l2, f_ex1, f_ex2) REPLACE (IF(l.f_any, CAST(NULL AS STRING), l.rule_version) AS rule_version)
FROM live_f l
UNION ALL
SELECT 'NC_L2_R_09',
       l.* EXCEPT (f_any, f_l2, f_ex1, f_ex2) REPLACE (
         IF(l.f_l2, l.basis_clicks * 0.9, l.pred_clicks) AS pred_clicks,
         IF(l.f_l2, l.basis_spend * 0.81, l.pred_spend) AS pred_spend,
         IF(l.f_l2, l.pred_orders * 0.9, l.pred_orders) AS pred_orders,
         IF(l.f_l2, l.pred_gp * 0.9, l.pred_gp) AS pred_gp,
         IF(l.f_l2, l.pred_gp * 0.9 - l.basis_spend * 0.81, l.pred_net) AS pred_net,
         IF(l.f_l2, 0.9, l.act_bid_ratio) AS act_bid_ratio)
FROM live_f l
UNION ALL
SELECT 'NC_L3_SPEND_R1',
       l.* EXCEPT (f_any, f_l2, f_ex1, f_ex2) REPLACE (IF(l.f_ex1, l.basis_spend * l.act_bid_ratio, l.pred_spend) AS pred_spend)
FROM live_f l
UNION ALL
SELECT 'NC_L3_SEAT',
       l.* EXCEPT (f_any, f_l2, f_ex1, f_ex2) REPLACE (IF(l.f_ex2, l.alloc_spend, l.pred_spend) AS pred_spend)
FROM live_f l;
-- NC_EMPTY has no ledger row.

-- ---- the second read's copies (L4) ----
CREATE TEMP TABLE lg2 AS
SELECT 'LIVE' AS copy, l.* FROM live2 l
UNION ALL
SELECT 'NC_L4_DRIFT',
       l.* REPLACE (IF(p1.what IS NOT NULL AND l.scenario = 'ACT', l.pred_net + 0.01, l.pred_net) AS pred_net)
FROM live2 l
LEFT JOIN pick p1 ON p1.what = 'ANY' AND p1.as_of = l.as_of AND p1.predictor = l.predictor
                 AND p1.campaign_id = l.campaign_id AND p1.keyword_id = l.keyword_id
LEFT JOIN pick p3 ON p3.what = 'L4_MISSING' AND p3.as_of = l.as_of AND p3.predictor = l.predictor
                 AND p3.campaign_id = l.campaign_id AND p3.keyword_id = l.keyword_id
WHERE NOT (p3.what IS NOT NULL AND l.scenario = 'DO_NOTHING');

CREATE TEMP FUNCTION fd(a FLOAT64, b FLOAT64) AS (   -- two FLOAT64 differ beyond 1e-6, or only one is NULL
  (a IS NULL) <> (b IS NULL) OR COALESCE(ABS(a - b) > 1e-6, FALSE)
);

CREATE TEMP TABLE copies AS
SELECT copy FROM UNNEST(['LIVE', 'NC_EMPTY', 'NC_L1_ONE_SCENARIO', 'NC_L1_NULL_NUMBER', 'NC_L1_NEG_BASIS',
                         'NC_L1_NO_RULE', 'NC_L2_R_09', 'NC_L3_SPEND_R1', 'NC_L3_SEAT', 'NC_L4_DRIFT']) AS copy;

WITH
plan_n AS (SELECT COUNT(*) AS n FROM plan_keys),
cnt AS (
  SELECT copy, as_of, predictor, campaign_id, keyword_id,
         COUNTIF(scenario = 'DO_NOTHING') AS n_dn, COUNTIF(scenario = 'ACT') AS n_act
  FROM lg GROUP BY copy, as_of, predictor, campaign_id, keyword_id
),
pk AS (SELECT c.copy, k.* FROM copies c CROSS JOIN plan_keys k),
l1a_rows AS (
  SELECT COALESCE(p.copy, x.copy) AS copy,
         (p.copy IS NULL OR x.copy IS NULL OR x.n_dn <> 1 OR x.n_act <> 1) AS bad
  FROM pk p
  FULL OUTER JOIN cnt x
    ON x.copy = p.copy AND x.as_of = p.as_of AND x.predictor = p.predictor
   AND x.campaign_id = p.campaign_id AND x.keyword_id = p.keyword_id
),
l1a AS (
  SELECT c.copy, COUNTIF(COALESCE(r.bad, FALSE)) + IF((SELECT n FROM plan_n) = 0, 1, 0) AS n
  FROM copies c LEFT JOIN l1a_rows r ON r.copy = c.copy
  GROUP BY c.copy
),
per_copy AS (
  SELECT c.copy,
         COUNT(l.copy) AS n_rows,
         COUNTIF(l.copy IS NOT NULL AND (l.pred_clicks IS NULL OR l.pred_spend IS NULL OR l.pred_orders IS NULL
                                         OR l.pred_gp IS NULL OR l.pred_net IS NULL)) AS n_null_number,
         COUNTIF(l.copy IS NOT NULL AND (l.basis_clicks IS NULL OR l.basis_clicks < 0)) AS n_bad_basis,
         COUNTIF(l.copy IS NOT NULL AND l.rule_version IS NULL) AS n_no_rule
  FROM copies c LEFT JOIN lg l ON l.copy = c.copy
  GROUP BY c.copy
),
l2_pairs AS (
  SELECT a.copy, a.basis_clicks,
         COALESCE(ABS(a.pred_clicks - d.pred_clicks) >= 0.005, TRUE)
         OR COALESCE(ABS(a.pred_spend  - d.pred_spend)  >= 0.005, TRUE)
         OR COALESCE(ABS(a.pred_orders - d.pred_orders) >= 0.005, TRUE)
         OR COALESCE(ABS(a.pred_gp     - d.pred_gp)     >= 0.005, TRUE)
         OR COALESCE(ABS(a.pred_net    - d.pred_net)    >= 0.005, TRUE) AS differs
  FROM lg a
  JOIN lg d ON d.copy = a.copy AND d.as_of = a.as_of AND d.predictor = a.predictor
           AND d.campaign_id = a.campaign_id AND d.keyword_id = a.keyword_id AND d.scenario = 'DO_NOTHING'
  WHERE a.scenario = 'ACT' AND a.act_is_noop
    AND NOT COALESCE(a.campaign_planned_budget < a.campaign_current_budget, FALSE)
),
l2 AS (
  SELECT c.copy, COUNTIF(p.differs) + IF(COUNTIF(p.basis_clicks > 0) = 0, 1, 0) AS n
  FROM copies c LEFT JOIN l2_pairs p ON p.copy = c.copy
  GROUP BY c.copy
),
ex AS (       -- the worked examples: (keyword, scenario, metric, expected, tolerance)
  SELECT * FROM UNNEST([
    STRUCT('305171316086021' AS keyword_id, 'DO_NOTHING' AS scenario, 'clicks' AS metric, 84.0 AS expected, 0.0 AS tol),
    ('305171316086021', 'DO_NOTHING', 'spend',  75.71,  0.005),
    ('305171316086021', 'DO_NOTHING', 'orders', 4.455,  0.0005),
    ('305171316086021', 'DO_NOTHING', 'gp',     55.16,  0.005),
    ('305171316086021', 'DO_NOTHING', 'net',    -20.55, 0.005),
    ('305171316086021', 'ACT',        'clicks', 79.5,   0.05),
    ('305171316086021', 'ACT',        'spend',  67.85,  0.005),
    ('305171316086021', 'ACT',        'orders', 4.22,   0.005),
    ('305171316086021', 'ACT',        'gp',     52.22,  0.005),
    ('305171316086021', 'ACT',        'net',    -15.63, 0.005),
    ('305171316086021', 'ACT',        'alloc',  71.40,  0.005),
    ('439648864838275', 'DO_NOTHING', 'clicks', 90.0,   0.0),
    ('439648864838275', 'DO_NOTHING', 'spend',  97.96,  0.005),
    ('439648864838275', 'ACT',        'clicks', 19.6,   0.05),
    ('439648864838275', 'ACT',        'spend',  4.63,   0.005),
    ('439648864838275', 'ACT',        'alloc',  0.0,    0.005)
  ])
),
l3_got AS (
  SELECT l.copy, l.keyword_id, l.scenario, m.metric, m.got
  FROM lg l,
       UNNEST([STRUCT('clicks' AS metric, l.pred_clicks AS got), ('spend', l.pred_spend),
               ('orders', l.pred_orders), ('gp', l.pred_gp), ('net', l.pred_net),
               ('alloc', l.alloc_spend)]) AS m
  WHERE l.as_of = DATE '2026-10-03' AND l.predictor = 'PLAN_B'
    AND l.keyword_id IN ('305171316086021', '439648864838275')
),
l3 AS (
  SELECT c.copy, COUNTIF(v.got IS NULL OR ABS(v.got - e.expected) > e.tol + 1e-9) AS n
  FROM copies c
  CROSS JOIN ex e
  LEFT JOIN l3_got v ON v.copy = c.copy AND v.keyword_id = e.keyword_id
                    AND v.scenario = e.scenario AND v.metric = e.metric
  GROUP BY c.copy
),
r1 AS (SELECT * FROM lg WHERE copy IN ('LIVE', 'NC_L4_DRIFT')),
r1_n AS (SELECT copy, COUNT(*) AS n FROM r1 GROUP BY copy),
l4_rows AS (
  SELECT COALESCE(a.copy, b.copy) AS copy,
         a.copy IS NULL OR b.copy IS NULL
         OR a.variant IS DISTINCT FROM b.variant OR a.built_at IS DISTINCT FROM b.built_at
         OR a.builder_version IS DISTINCT FROM b.builder_version
         OR a.horizon_from IS DISTINCT FROM b.horizon_from OR a.horizon_to IS DISTINCT FROM b.horizon_to
         OR a.window_days IS DISTINCT FROM b.window_days OR a.family IS DISTINCT FROM b.family
         OR a.channel IS DISTINCT FROM b.channel OR a.calendar_state IS DISTINCT FROM b.calendar_state
         OR a.is_live_plan IS DISTINCT FROM b.is_live_plan OR a.holdout IS DISTINCT FROM b.holdout
         OR a.min_orders IS DISTINCT FROM b.min_orders OR a.move IS DISTINCT FROM b.move
         OR a.act_is_noop IS DISTINCT FROM b.act_is_noop OR a.pred_side IS DISTINCT FROM b.pred_side
         OR a.basis_clicks IS DISTINCT FROM b.basis_clicks OR a.act_basis IS DISTINCT FROM b.act_basis
         OR a.rule_version IS DISTINCT FROM b.rule_version
         OR a.response_model_version IS DISTINCT FROM b.response_model_version
         OR fd(a.family_bar, b.family_bar) OR fd(a.current_bid, b.current_bid)
         OR fd(a.planned_bid, b.planned_bid)
         OR fd(a.campaign_current_budget, b.campaign_current_budget)
         OR fd(a.campaign_planned_budget, b.campaign_planned_budget)
         OR fd(a.alloc_spend, b.alloc_spend) OR fd(a.basis_spend, b.basis_spend)
         OR fd(a.settle_factor_eff, b.settle_factor_eff)
         OR fd(a.pred_clicks, b.pred_clicks) OR fd(a.pred_spend, b.pred_spend)
         OR fd(a.pred_orders, b.pred_orders) OR fd(a.pred_gp, b.pred_gp) OR fd(a.pred_net, b.pred_net)
         OR fd(a.act_bid_ratio, b.act_bid_ratio) OR fd(a.act_budget_factor, b.act_budget_factor) AS differs
  FROM r1 a
  FULL OUTER JOIN lg2 b
    ON b.copy = a.copy AND b.as_of = a.as_of AND b.predictor = a.predictor
   AND b.campaign_id = a.campaign_id AND b.keyword_id = a.keyword_id AND b.scenario = a.scenario
),
l4_n AS (SELECT copy, COUNTIF(differs) AS n FROM l4_rows GROUP BY copy),
l4 AS (
  SELECT c.copy, COALESCE(d.n, 0) + IF(COALESCE(r.n, 0) = 0, 1, 0) AS n
  FROM copies c
  LEFT JOIN l4_n d ON d.copy = c.copy
  LEFT JOIN r1_n r ON r.copy = c.copy
),
f AS (
  SELECT copy, 'L1a' AS chk, n FROM l1a
  UNION ALL SELECT copy, 'L1b', n_null_number + IF(n_rows = 0, 1, 0) FROM per_copy
  UNION ALL SELECT copy, 'L1c', n_bad_basis   + IF(n_rows = 0, 1, 0) FROM per_copy
  UNION ALL SELECT copy, 'L1d', n_no_rule     + IF(n_rows = 0, 1, 0) FROM per_copy
  UNION ALL SELECT copy, 'L2', n FROM l2
  UNION ALL SELECT copy, 'L3', n FROM l3
  UNION ALL SELECT copy, 'L4', n FROM l4
),
expect AS (
  SELECT * FROM UNNEST([
    -- A PLAN ROW WITH ONE SCENARIO CANNOT BE GRADED AGAINST THE OTHER: the lift is a difference of two rows.
    STRUCT('L1a every plan row has one DO_NOTHING and one ACT row, and no ledger row lacks a plan row' AS check_name, 'L1a' AS chk, 'LIVE' AS copy, FALSE AS must_fire),
    -- A NULL PREDICTION GRADES AS NOTHING: the grader's errors and the report card's sums skip it in silence.
    ('L1b the five predicted numbers are non-NULL', 'L1b', 'LIVE', FALSE),
    ('L1c basis_clicks is non-NULL and >= 0', 'L1c', 'LIVE', FALSE),
    -- A PREDICTION THAT CANNOT NAME ITS RULE CANNOT BE BLAMED ON ONE: prediction_regression names the rule that moved.
    ('L1d every row has a rule_version', 'L1d', 'LIVE', FALSE),
    -- A MODEL THAT MOVES ROWS THE PLAN DOES NOT MOVE INVENTS LIFT (spec §14 E3).
    ('L2 ACT equals DO_NOTHING to the cent on every no-op row of an uncut campaign', 'L2', 'LIVE', FALSE),
    ('L3 the two worked examples of the brief reproduce (10-03, plan B)', 'L3', 'LIVE', FALSE),
    -- A LEDGER THAT READS DIFFERENTLY TWICE CANNOT BE FROZEN INTO A GRADE.
    ('L4 two reads of the view are equal row for row (floats within 1e-6)', 'L4', 'LIVE', FALSE),
    ('L1a1 NEGATIVE CONTROL L1a FIRES: no ledger row', 'L1a', 'NC_EMPTY', TRUE),
    ('L1a2 NEGATIVE CONTROL L1a FIRES: one ACT row removed', 'L1a', 'NC_L1_ONE_SCENARIO', TRUE),
    ('L1b1 NEGATIVE CONTROL L1b FIRES: no ledger row', 'L1b', 'NC_EMPTY', TRUE),
    ('L1b2 NEGATIVE CONTROL L1b FIRES: one pred_gp NULL', 'L1b', 'NC_L1_NULL_NUMBER', TRUE),
    ('L1c1 NEGATIVE CONTROL L1c FIRES: no ledger row', 'L1c', 'NC_EMPTY', TRUE),
    ('L1c2 NEGATIVE CONTROL L1c FIRES: one basis_clicks -1', 'L1c', 'NC_L1_NEG_BASIS', TRUE),
    ('L1d1 NEGATIVE CONTROL L1d FIRES: no ledger row', 'L1d', 'NC_EMPTY', TRUE),
    ('L1d2 NEGATIVE CONTROL L1d FIRES: one rule_version NULL', 'L1d', 'NC_L1_NO_RULE', TRUE),
    ('L2a NEGATIVE CONTROL L2 FIRES: no ledger row', 'L2', 'NC_EMPTY', TRUE),
    ('L2b NEGATIVE CONTROL L2 FIRES: one no-op row priced at r = 0.9', 'L2', 'NC_L2_R_09', TRUE),
    ('L3a NEGATIVE CONTROL L3 FIRES: no ledger row', 'L3', 'NC_EMPTY', TRUE),
    ('L3b NEGATIVE CONTROL L3 FIRES: example 1 ACT spend at r^1', 'L3', 'NC_L3_SPEND_R1', TRUE),
    ('L3c NEGATIVE CONTROL L3 FIRES: example 2 ACT spend at the seat', 'L3', 'NC_L3_SEAT', TRUE),
    ('L4a NEGATIVE CONTROL L4 FIRES: both reads empty', 'L4', 'NC_EMPTY', TRUE),
    ('L4b NEGATIVE CONTROL L4 FIRES: the second read drifted and lost a row', 'L4', 'NC_L4_DRIFT', TRUE)
  ])
)
SELECT e.check_name, e.copy, f.n AS violations,
       IF(IF(e.must_fire, f.n >= 1, f.n = 0), 'PASS', 'FAIL') AS result
FROM expect e
LEFT JOIN f ON f.chk = e.chk AND f.copy = e.copy
ORDER BY e.check_name;
