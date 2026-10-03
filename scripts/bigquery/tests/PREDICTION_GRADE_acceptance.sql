-- =============================================================================================
-- PREDICTION_GRADE acceptance — 2026-10-03, learning-contract piece 2, Task 5: the grader
-- (SP_GRADE_PREDICTIONS v27.173; v27.174 and V9 since the Task 5 follow-up, 2026-10-04), its grades
-- (FACT_PREDICTION_GRADE) and its report card
-- (T_PREDICTION_SCORECARD), checked against independent recomputes. EVERY ASSERTED ROW MUST READ
-- PASS; the V2g row is a REPORT. Run it right after a grader run (V1 reads the house watermark now).
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --nosync "$(grep -v '^[[:space:]]*--' FILE)"
--   bq wait JOB 60; then bq ls -j --parent_job_id=JOB and bq head the last child (the final SELECT).
-- Reads FACT_PREDICTION_GRADE, T_PREDICTION_SCORECARD, V_PREDICTION_LEDGER, FACT_AMAZON_ADS (the
-- graded horizons), DIM_KEYWORD, DIM_CAMPAIGN, DE_COACH_THRESHOLDS, V_PPC_CHANGE_LOG_LANDED (V9);
-- writes only this script's TEMP tables. Piece-2 Task 7's contract suite (PREDICTION_CONTRACT_acceptance.sql) is the spec §11 suite;
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
--   V9 the applied scenario and both change-id lists equal an independent recompute from
--      V_PPC_CHANGE_LOG_LANDED (not LOGGED_ONLY) on the prediction's own clock: only changes applied
--      at or after built_at; the keyword's own and its campaign's state / budget changes read until
--      the Los Angeles midnight that ends horizon_to (an SB keyword's own: one day later); a change
--      matches a component only before the midnight that starts horizon_from + MATCH_WINDOW_DAYS
--      (never past horizon_to); ACT / DO_NOTHING / OTHER_ACTION as architecture/LEARNING.md §4;
--      +1 when empty
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
-- V9's controls act on two picks (v9_pick: the first plan key in key order, every predictor's rows of
-- it, that applied as DO_NOTHING on an SP keyword with no change read, and that the injected change
-- cannot reach through any other graded night of the keyword; DAY5 also needs no real change on the
-- keyword or its campaign from built_at to horizon_from + 8). Each injects one change into its own copy
-- of the change record. A PC_ copy must read 0, an NC_ copy must fire:
--   PC_V9_PREBUILD  the bid the row already had (current_bid), set one hour before built_at; the row
--                   keeps its DO_NOTHING label                                   -> V9 reads 0
--   NC_V9_PREBUILD  the same change, the row labelled OTHER_ACTION for it (the v27.173 reading)
--                                                                                -> V9 fires
--   PC_V9_DAY5      the row's horizon stretched to 7 days (horizon_to = horizon_from + 6), a bid 0.37
--                   above current_bid set at noon Los Angeles on day 5; the row labelled
--                   OTHER_ACTION with that change in other_change_ids            -> V9 reads 0
--   NC_V9_DAY5      the same stretch and change, the row left DO_NOTHING (the v27.173 reading, which
--                   read Los Angeles dates as_of .. as_of + 3 only)              -> V9 fires
-- A pick that finds no row leaves its copy equal to LIVE, so its NC reads 0 and FAILS (loud).
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
-- RUNS 2026-10-03 21:29-21:34 UTC (Task 5 follow-up; SP_GRADE_PREDICTIONS v27.174 deployed 21:29:52
--   UTC, V9 added), each as written (33 rows):
--   * before the re-grade, the v27.173 grades current (t5f_acc_pre_1791063005, 195.3 slot-seconds):
--     V1..V8 and every V1..V8 control as before; V9 LIVE FAIL 368 = 92 plan rows per plan x 2 plans x
--     2 scenarios (64 labelled OTHER_ACTION only for changes made before built_at, 28 OTHER_ACTION rows
--     whose id lists held 31 such changes); V9a 1, V9c 372, V9e 372; PC_V9_PREBUILD and PC_V9_DAY5 368
--     each (LIVE's 368, nothing added).
--   * after CALL SP_GRADE_PREDICTIONS(DATE '2026-08-23', reason) appended the v27.174 re-grade
--     (t5f_acc_post_1791063180, 201.8 slot-seconds, 192,112,052 bytes): every asserted row PASS.
--     LIVE V1..V9 0 (V1's gradable population 8,944); V2g REPORT 0. Controls, each FIRED: NC_EMPTY V1
--     8944, V2..V9 1 each; NC_V1_MISSING 1; NC_V2_REAL 1; NC_V3_FROZEN 1; NC_V4_LABEL 1; NC_V5_SIDE 1;
--     NC_V6_APPLIED 1; NC_V7_FALSE_UNGRADABLE 1; NC_V7_MISSED_ARCHIVE 24; NC_V8_CURVE 1; NC_V8_ACC 1;
--     NC_V9_PREBUILD 4; NC_V9_DAY5 4 (one plan key x 2 plans x 2 scenarios). PC_V9_PREBUILD 0,
--     PC_V9_DAY5 0. Picks: PREBUILD 2026-08-23 keyword 108301382467865 (change at 04:34:19 UTC on
--     08-24, built_at 05:34:19 UTC); DAY5 2026-08-25 keyword 236377827196202 (noon Los Angeles on
--     08-30, horizon 08-26 .. 09-01 on the copy).
--   * on the procedure-copy fixtures (architecture/LEARNING.md §10 "Task 5 follow-up"): v27.174's
--     grades every asserted row PASS (t5fx_acc_new_1791062874, 85.0 slot-seconds); v27.173's grades
--     of the same inputs V9 LIVE FAIL 388 (t5fx_acc_old_1791062874): the 368 above and the 20 rows
--     of the five fixtures the two rules label differently.
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

-- V9's settings and its two picks (one plan key each, every predictor's rows of it): a DO_NOTHING SP row
-- with no change read, on which a change can be injected without reaching any other graded row of the
-- keyword (PREBUILD: one hour before built_at; DAY5: noon Los Angeles on day 5 of the row's horizon
-- stretched to 7 days, which must also hold no real change on the keyword or its campaign)
CREATE TEMP TABLE st AS
SELECT MAX(IF(threshold_key = 'MATCH_WINDOW_DAYS', CAST(threshold_value AS INT64), NULL)) AS match_days,
       MAX(IF(threshold_key = 'MATCH_BID_TOL', threshold_value, NULL))                    AS bid_tol,
       MAX(IF(threshold_key = 'MATCH_BUDGET_TOL', threshold_value, NULL))                 AS budget_tol
FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
WHERE strategy_id = 'LEARNING' AND coach_mode = 'GUARDIAN' AND product_family IS NULL
  AND threshold_key IN ('MATCH_WINDOW_DAYS', 'MATCH_BID_TOL', 'MATCH_BUDGET_TOL');

CREATE TEMP TABLE chg_real AS
SELECT change_id, action, keyword_id, campaign_id, new_bid, new_budget, applied_at
FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_LANDED`
WHERE landed_evidence <> 'LOGGED_ONLY'
  AND applied_at >= (SELECT MIN(built_at) FROM cur)
  AND applied_at <  TIMESTAMP(DATE_ADD((SELECT MAX(horizon_to) FROM cur), INTERVAL 9 DAY), 'America/Los_Angeles');

CREATE TEMP TABLE v9_pick AS
WITH cand AS (
  SELECT c.predictor, c.as_of, c.campaign_id, c.keyword_id, c.built_at, c.horizon_from, c.current_bid,
         what,
         IF(what = 'PREBUILD', TIMESTAMP_SUB(c.built_at, INTERVAL 1 HOUR),
            TIMESTAMP(DATETIME(DATE_ADD(c.horizon_from, INTERVAL 4 DAY), TIME '12:00:00'), 'America/Los_Angeles')) AS ts
  FROM cur c CROSS JOIN UNNEST(['PREBUILD', 'DAY5']) AS what
  WHERE c.scenario = 'DO_NOTHING' AND c.applied_scenario = 'DO_NOTHING' AND c.channel = 'SP'
    AND c.grade <> 'UNGRADABLE' AND c.predictor <> 'FIXTURE'
    AND ARRAY_LENGTH(c.matched_change_ids) = 0 AND ARRAY_LENGTH(c.other_change_ids) = 0
),
ok AS (
  SELECT x.* FROM cand x
  WHERE NOT EXISTS (SELECT 1 FROM cur o
                    WHERE o.keyword_id = x.keyword_id AND o.as_of <> x.as_of
                      AND x.ts >= o.built_at AND x.ts < TIMESTAMP(DATE_ADD(o.horizon_to, INTERVAL 2 DAY), 'America/Los_Angeles'))
    AND (x.what = 'PREBUILD' OR NOT EXISTS (
          SELECT 1 FROM chg_real r
          WHERE (r.keyword_id = x.keyword_id OR (r.keyword_id IS NULL AND r.campaign_id = x.campaign_id))
            AND r.applied_at >= x.built_at
            AND r.applied_at < TIMESTAMP(DATE_ADD(x.horizon_from, INTERVAL 8 DAY), 'America/Los_Angeles')))
)
SELECT what, as_of, campaign_id, keyword_id, ts, current_bid
FROM ok
QUALIFY ROW_NUMBER() OVER (PARTITION BY what ORDER BY as_of, keyword_id, predictor) = 1;

CREATE TEMP TABLE cur_f AS
SELECT c.*,
       EXISTS (SELECT 1 FROM pick p WHERE p.what = 'ANY' AND p.predictor = c.predictor AND p.as_of = c.as_of
               AND p.campaign_id = c.campaign_id AND p.keyword_id = c.keyword_id AND p.scenario = c.scenario) AS f_any,
       EXISTS (SELECT 1 FROM pick p WHERE p.what = 'INCONCL' AND p.predictor = c.predictor AND p.as_of = c.as_of
               AND p.campaign_id = c.campaign_id AND p.keyword_id = c.keyword_id AND p.scenario = c.scenario) AS f_inc,
       EXISTS (SELECT 1 FROM v9_pick p WHERE p.what = 'PREBUILD' AND p.as_of = c.as_of
               AND p.campaign_id = c.campaign_id AND p.keyword_id = c.keyword_id) AS f_pre,
       EXISTS (SELECT 1 FROM v9_pick p WHERE p.what = 'DAY5' AND p.as_of = c.as_of
               AND p.campaign_id = c.campaign_id AND p.keyword_id = c.keyword_id) AS f_d5
FROM cur c;

CREATE TEMP TABLE g AS
SELECT 'LIVE' AS copy, c.* EXCEPT (f_any, f_inc, f_pre, f_d5) FROM cur_f c
UNION ALL SELECT 'NC_V1_MISSING', c.* EXCEPT (f_any, f_inc, f_pre, f_d5) FROM cur_f c WHERE NOT c.f_any
UNION ALL SELECT 'NC_V2_REAL', c.* EXCEPT (f_any, f_inc, f_pre, f_d5) REPLACE (IF(c.f_any, c.real_spend + 1.0, c.real_spend) AS real_spend) FROM cur_f c
UNION ALL SELECT 'NC_V3_FROZEN', c.* EXCEPT (f_any, f_inc, f_pre, f_d5) REPLACE (IF(c.f_any, c.pred_net + 0.01, c.pred_net) AS pred_net) FROM cur_f c
UNION ALL SELECT 'NC_V4_LABEL', c.* EXCEPT (f_any, f_inc, f_pre, f_d5) REPLACE (IF(c.f_inc, 'RIGHT', c.grade) AS grade) FROM cur_f c
UNION ALL SELECT 'NC_V5_SIDE', c.* EXCEPT (f_any, f_inc, f_pre, f_d5) REPLACE (IF(c.f_any, 1 - c.real_side, c.real_side) AS real_side) FROM cur_f c
UNION ALL SELECT 'NC_V6_APPLIED', c.* EXCEPT (f_any, f_inc, f_pre, f_d5) REPLACE (IF(c.f_any, NOT c.is_applied, c.is_applied) AS is_applied) FROM cur_f c
UNION ALL SELECT 'NC_V7_FALSE_UNGRADABLE', c.* EXCEPT (f_any, f_inc, f_pre, f_d5) REPLACE (
            IF(c.f_any, 'UNGRADABLE', c.grade) AS grade, IF(c.f_any, 'KEYWORD_ARCHIVED', c.ungradable_reason) AS ungradable_reason) FROM cur_f c
UNION ALL SELECT 'NC_V7_MISSED_ARCHIVE', c.* EXCEPT (f_any, f_inc, f_pre, f_d5) FROM cur_f c
UNION ALL SELECT 'NC_V8_CURVE', c.* EXCEPT (f_any, f_inc, f_pre, f_d5) FROM cur_f c
UNION ALL SELECT 'NC_V8_ACC', c.* EXCEPT (f_any, f_inc, f_pre, f_d5) FROM cur_f c
-- V9: PC_ copies must read 0, NC_ copies must fire; the change each injects is in chg (below)
UNION ALL SELECT 'PC_V9_PREBUILD', c.* EXCEPT (f_any, f_inc, f_pre, f_d5) FROM cur_f c
UNION ALL SELECT 'NC_V9_PREBUILD', c.* EXCEPT (f_any, f_inc, f_pre, f_d5) REPLACE (
            IF(c.f_pre, 'OTHER_ACTION', c.applied_scenario) AS applied_scenario, IF(c.f_pre, FALSE, c.is_applied) AS is_applied,
            IF(c.f_pre, ['acc|V9|NC_V9_PREBUILD'], c.other_change_ids) AS other_change_ids) FROM cur_f c
UNION ALL SELECT 'PC_V9_DAY5', c.* EXCEPT (f_any, f_inc, f_pre, f_d5) REPLACE (
            IF(c.f_d5, DATE_ADD(c.horizon_from, INTERVAL 6 DAY), c.horizon_to) AS horizon_to,
            IF(c.f_d5, 'OTHER_ACTION', c.applied_scenario) AS applied_scenario, IF(c.f_d5, FALSE, c.is_applied) AS is_applied,
            IF(c.f_d5, ['acc|V9|PC_V9_DAY5'], c.other_change_ids) AS other_change_ids) FROM cur_f c
UNION ALL SELECT 'NC_V9_DAY5', c.* EXCEPT (f_any, f_inc, f_pre, f_d5) REPLACE (
            IF(c.f_d5, DATE_ADD(c.horizon_from, INTERVAL 6 DAY), c.horizon_to) AS horizon_to) FROM cur_f c;
-- NC_EMPTY has no grade row.

CREATE TEMP TABLE copies AS
SELECT copy FROM UNNEST(['LIVE', 'NC_EMPTY', 'NC_V1_MISSING', 'NC_V2_REAL', 'NC_V3_FROZEN', 'NC_V4_LABEL',
                         'NC_V5_SIDE', 'NC_V6_APPLIED', 'NC_V7_FALSE_UNGRADABLE', 'NC_V7_MISSED_ARCHIVE',
                         'NC_V8_CURVE', 'NC_V8_ACC', 'PC_V9_PREBUILD', 'NC_V9_PREBUILD', 'PC_V9_DAY5',
                         'NC_V9_DAY5']) AS copy;

-- V9's change record: every landed change that can bear on a graded row, for every copy, plus the one
-- change each V9 copy injects (PREBUILD: the bid the row already had, an hour before built_at; DAY5: a
-- bid 0.37 above it, at noon Los Angeles on day 5)
CREATE TEMP TABLE chg AS
SELECT CAST(NULL AS STRING) AS only_copy, r.* FROM chg_real r
UNION ALL
SELECT copy, 'acc|V9|' || copy, 'REDUCE_BID', p.keyword_id, p.campaign_id,
       IF(p.what = 'PREBUILD', p.current_bid, p.current_bid + 0.37), CAST(NULL AS FLOAT64), p.ts
FROM v9_pick p
JOIN UNNEST(['PC_V9_PREBUILD', 'NC_V9_PREBUILD', 'PC_V9_DAY5', 'NC_V9_DAY5']) AS copy
  ON ENDS_WITH(copy, p.what);

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
v9_prow AS (   -- one row per plan row of each copy, the columns the applied scenario is decided on
  SELECT copy, predictor, variant, as_of, campaign_id, keyword_id,
         MAX(channel) AS channel, MAX(built_at) AS built_at, MAX(horizon_from) AS horizon_from, MAX(horizon_to) AS horizon_to,
         MAX(IF(scenario = 'ACT', move, NULL)) AS move, MAX(current_bid) AS current_bid, MAX(planned_bid) AS planned_bid,
         MAX(campaign_current_budget) AS ccb, MAX(campaign_planned_budget) AS cpb
  FROM g GROUP BY 1, 2, 3, 4, 5, 6
),
v9_comp AS (
  SELECT p.*,
         COALESCE(ABS(p.planned_bid - p.current_bid) >= st.bid_tol, FALSE) AS has_bid,
         COALESCE(p.move = 'PAUSE', FALSE)                                  AS has_state,
         COALESCE(ABS(p.cpb - p.ccb) >= st.budget_tol, FALSE)              AS has_budget,
         LEAST(TIMESTAMP(DATE_ADD(p.horizon_from, INTERVAL st.match_days DAY), 'America/Los_Angeles'),
               TIMESTAMP(DATE_ADD(p.horizon_to, INTERVAL 1 DAY), 'America/Los_Angeles')) AS match_end,
         st.bid_tol, st.budget_tol
  FROM v9_prow p CROSS JOIN st
),
v9_hit AS (    -- the changes read: from built_at to the end of horizon_to (an SB keyword's own: one day more)
  SELECT c.copy, c.predictor, c.variant, c.as_of, c.campaign_id, c.keyword_id, x.change_id,
         CASE WHEN x.applied_at >= c.match_end THEN NULL
              WHEN c.has_bid AND x.new_bid IS NOT NULL AND ABS(x.new_bid - c.planned_bid) <= c.bid_tol + 1e-9 THEN 'BID'
              WHEN c.has_state AND x.action IN ('KEYWORD_PAUSE', 'STOP_TARGET') THEN 'STATE' END AS matched
  FROM v9_comp c
  JOIN chg x
    ON x.keyword_id = c.keyword_id AND (x.only_copy IS NULL OR x.only_copy = c.copy)
   AND x.applied_at >= c.built_at
   AND x.applied_at < TIMESTAMP(DATE_ADD(c.horizon_to, INTERVAL IF(c.channel = 'SB', 2, 1) DAY), 'America/Los_Angeles')
  UNION ALL
  SELECT c.copy, c.predictor, c.variant, c.as_of, c.campaign_id, c.keyword_id, x.change_id,
         CASE WHEN x.applied_at >= c.match_end THEN NULL
              WHEN c.has_budget AND x.action LIKE '%BUDGET%' AND x.new_budget IS NOT NULL
                   AND ABS(x.new_budget - c.cpb) <= c.budget_tol + 1e-9 THEN 'BUDGET' END
  FROM v9_comp c
  JOIN chg x
    ON x.campaign_id = c.campaign_id AND x.keyword_id IS NULL AND (x.only_copy IS NULL OR x.only_copy = c.copy)
   AND (x.action LIKE '%BUDGET%' OR STARTS_WITH(x.action, 'CAMPAIGN_'))
   AND x.applied_at >= c.built_at
   AND x.applied_at < TIMESTAMP(DATE_ADD(c.horizon_to, INTERVAL 1 DAY), 'America/Los_Angeles')
),
v9_exp AS (    -- the applied scenario and the two id lists the rule gives
  SELECT c.copy, c.predictor, c.variant, c.as_of, c.campaign_id, c.keyword_id,
         CASE WHEN (c.has_bid OR c.has_state OR c.has_budget)
                   AND (NOT c.has_bid OR COALESCE(LOGICAL_OR(h.matched = 'BID'), FALSE))
                   AND (NOT c.has_state OR COALESCE(LOGICAL_OR(h.matched = 'STATE'), FALSE))
                   AND (NOT c.has_budget OR COALESCE(LOGICAL_OR(h.matched = 'BUDGET'), FALSE))
                   AND COUNTIF(h.change_id IS NOT NULL AND h.matched IS NULL) = 0 THEN 'ACT'
              WHEN COUNT(h.change_id) = 0 THEN 'DO_NOTHING'
              ELSE 'OTHER_ACTION' END AS exp_applied,
         COALESCE(STRING_AGG(IF(h.matched IS NOT NULL, h.change_id, NULL), ',' ORDER BY h.change_id), '') AS exp_matched,
         COALESCE(STRING_AGG(IF(h.change_id IS NOT NULL AND h.matched IS NULL, h.change_id, NULL), ',' ORDER BY h.change_id), '') AS exp_other
  FROM v9_comp c
  LEFT JOIN v9_hit h
    ON h.copy = c.copy AND h.predictor = c.predictor AND h.variant = c.variant AND h.as_of = c.as_of
   AND h.campaign_id = c.campaign_id AND h.keyword_id = c.keyword_id
  GROUP BY c.copy, c.predictor, c.variant, c.as_of, c.campaign_id, c.keyword_id,
           c.has_bid, c.has_state, c.has_budget
),
v9_rows AS (   -- every grade row carries the applied scenario and the change ids its plan row's rule gives
  SELECT g.copy,
         COUNTIF(e.copy IS NULL OR g.applied_scenario IS DISTINCT FROM e.exp_applied
                 OR ARRAY_TO_STRING(g.matched_change_ids, ',') IS DISTINCT FROM e.exp_matched
                 OR ARRAY_TO_STRING(g.other_change_ids, ',') IS DISTINCT FROM e.exp_other) AS n
  FROM g
  LEFT JOIN v9_exp e
    ON e.copy = g.copy AND e.predictor = g.predictor AND e.variant = g.variant AND e.as_of = g.as_of
   AND e.campaign_id = g.campaign_id AND e.keyword_id = g.keyword_id
  GROUP BY g.copy
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
  UNION ALL SELECT p.copy, 'V9', COALESCE(v.n, 0) + IF(p.n = 0, 1, 0) FROM pop p LEFT JOIN v9_rows v ON v.copy = p.copy
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
    ('V8c NC fires: one ACCURACY mae_net_share + 0.01', 'V8', 'NC_V8_ACC', TRUE),
    ('V9 the applied scenario and change ids follow from the changes made after built_at, to the end of the horizon', 'V9', 'LIVE', FALSE),
    ('V9a NC fires: no grade row', 'V9', 'NC_EMPTY', TRUE),
    ('V9b PC reads 0: a change made before built_at, to the bid the row already had, leaves the row DO_NOTHING', 'V9', 'PC_V9_PREBUILD', FALSE),
    ('V9c NC fires: that row labelled OTHER_ACTION for that pre-build change', 'V9', 'NC_V9_PREBUILD', TRUE),
    ('V9d PC reads 0: a change on day 5 of a 7-day horizon makes the row OTHER_ACTION', 'V9', 'PC_V9_DAY5', FALSE),
    ('V9e NC fires: that row left DO_NOTHING after a change on day 5 of its 7-day horizon', 'V9', 'NC_V9_DAY5', TRUE)
  ])
)
SELECT e.check_name, e.copy, f.n AS violations,
       IF(IF(e.must_fire, f.n >= 1, f.n = 0), 'PASS', 'FAIL') AS result
FROM expect e LEFT JOIN f ON f.chk = e.chk AND f.copy = e.copy
UNION ALL
SELECT 'V2g REPORT gross profit restated since grading (frozen grades keep their copy; not asserted)', 'LIVE', f.n, 'REPORT'
FROM f WHERE f.chk = 'V2g' AND f.copy = 'LIVE'
ORDER BY check_name;
