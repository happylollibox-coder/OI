-- =============================================================================================
-- PREDICTION_CONTRACT acceptance — the learning contract's suite (spec §11), 2026-10-03/04,
-- learning-contract piece 2. Started by Task 4 with the ledger's checks L1-L4 (V_PREDICTION_LEDGER);
-- completed by Task 7 with the spec §11 checks 2-5 and 8 (C2-C8), the frozen check F and the parity
-- check P (ruling D5). Checks 6-7 arrive with piece 6. EVERY ASSERTED ROW MUST READ PASS; the P2n row
-- is a REPORT.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --nosync "$(grep -v '^[[:space:]]*--' FILE)"
--   bq wait JOB 60; then bq ls -j --parent_job_id=JOB and bq head the last child (the final SELECT).
-- Run it after a grader run (C2 reads the house watermark now, with no night of grace).
-- Reads V_PREDICTION_LEDGER (twice), FACT_PLAN_NEXT_WEEK's keys, FACT_PREDICTION_GRADE,
-- T_PREDICTION_SCORECARD (its row count, fixture rows and scored_at), V_ENGINE_HEALTH (the three
-- learning rows), FN_PLAN_SCORECARD at today's two clocks, FACT_AMAZON_ADS (the watermark, and the
-- nights both graders grade), DE_COACH_THRESHOLDS (SETTLE_HORIZON_DAYS); writes only this script's
-- TEMP tables. It never runs the grader: checks 3 and 5 need grader runs, and those are proved by
-- scripts/bigquery/tests/check_prediction_contract_controls.py on procedure copies (below), which
-- runs this file's own C statement (c_out) on the copies' grades.
-- Spec: docs/superpowers/specs/2026-10-01-learning-contract-design.md §5, §6, §7, §11, §14.
-- Plan: docs/superpowers/plans/2026-10-03-learning-piece2-ledger-grader.md Task 4 Step 5 (L1-L4),
--       Task 7 (C2-C8, F, P, the controls harness).
-- SOP:  architecture/LEARNING.md §1-§4, §10 "Task 4", §10 "Task 7".
--
-- THE CHECKS (violation counts, 0 = PASS):
--   L1a every FACT_PLAN_NEXT_WEEK row (as_of, plan, campaign_id, keyword_id) has exactly one
--       DO_NOTHING and one ACT ledger row, and no ledger row lacks a plan row; +1 when the plan
--       table holds no row (emptiness)                                      [spec §11 check 1]
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
--   The C statement (c_out) reads labelled inputs only — cg (grade rows), cl (ledger rows), cf
--   (FN_PLAN_SCORECARD rows), ch (board rows), cc (the card's row count, fixture rows, scored_at),
--   each tagged with a variant v, and cm (copy -> the variant of each input) — plus wmx (the house
--   watermark and SETTLE_HORIZON_DAYS) and FACT_AMAZON_ADS (P2's restatement test). A prediction's
--   current grade is its row(s) with the highest regrade_seq.
--   C2  [check 2] every ledger row gradable on the house watermark (horizon_to +
--       SETTLE_HORIZON_DAYS <= LEAST(MAX(FACT_AMAZON_ADS.date), FN_ADS_ANCHOR_CAP())) has exactly
--       one current grade row, and no prediction with a grade lacks a gradable ledger row (a grade
--       made early, or a prediction gone from the ledger); +1 when nothing is gradable
--   C3  [check 3, the record] what the grade table's own record proves about every grader run that
--       wrote it: one row per prediction per regrade_seq (a second run that graded a graded
--       prediction again leaves two), regrade_seq from 0 without a gap, a regrade_reason on every
--       re-grade and on no first grade, each re-grade graded after the grade it replaces, and every
--       re-grade run re-graded its whole band — a run's re-grade rows start on the night band_from
--       (their earliest as_of), and every prediction graded before that run, of a night >= band_from
--       and still in the ledger, has a row in it; +1 when the table is empty. The forward property
--       (a second run inserts 0; a regrade_from run re-grades exactly the NAMED band) is run by the
--       harness on procedure copies (C3i, C3n there).
--   C4a [check 4] every current grade carries exactly one of RIGHT, WRONG, INCONCLUSIVE,
--       UNGRADABLE, so the four counts add up to the graded rows; +1 when no grade exists
--   C4b [check 4] the line splits the labels: no INCONCLUSIVE row with a click at or above its
--       min_clicks_at_grade, no RIGHT or WRONG row with no click, below its line or with no line.
--       NO EMPTINESS TERM: at the 0.80 bar no family has a line (architecture/LEARNING.md §9), so on
--       the live record the RIGHT / WRONG arm has no row; the harness's fixture copy (a line at 6
--       clicks) exercises both arms on the grader's own output.
--   C5  [check 5] every current grade under predictor 'FIXTURE' reads the label its keyword names
--       (keyword_id FIXTURE_RIGHT..., FIXTURE_WRONG..., FIXTURE_INCONCLUSIVE...), and FIXTURE_RIGHT,
--       FIXTURE_WRONG and FIXTURE_INCONCLUSIVE are graded on both scenarios (+1 per one missing).
--       Asserted on fixture copies only: on the real record C5z holds instead.
--   C5z the fixtures are written to copies only: the grade table holds no FIXTURE row and the
--       report card none (FACT_PREDICTION_GRADE is append-only, so a fabricated row there could
--       never be removed). The fixtures themselves — graded by the grader's own text, read RIGHT,
--       WRONG and INCONCLUSIVE, and absent from every aggregate of the card — are the harness's.
--   C8a [check 8] prediction_grades_fresh, prediction_regression and response_model_unverified are
--       each on V_ENGINE_HEALTH once (+1 per name not there exactly once)
--   C8b [check 8] prediction_grades_fresh is GREEN with measured 0 (1 when not, or missing)
--   C8c [check 8] "after a run": the report card holds rows and a scored_at, so the grader has run
--       and rebuilt it (1 when not)
--   F   FROZEN: every grade row, re-grades included, still equals the ledger row it was graded from
--       — the five predicted numbers (1e-6), pred_side, built_at, the horizon, rule_version,
--       response_model_version, builder_version, act_is_noop, move, the grain, the plan's ask and
--       basis; a grade whose ledger row is gone counts; +1 when no grade exists
--   P1  PARITY (D5), allocation: on the nights both grade (a FAMILY_WEEK graded_night of
--       FN_PLAN_SCORECARD at CURRENT_DATE('America/New_York'), CURRENT_DATE('America/Los_Angeles')
--       that the grade table grades), FN's FAMILY_WEEK allocated_a / allocated_b per family x night
--       and its GRADE allocated_dollars per plan x family x calendar_state (when every FN night of
--       that group is one both grade) equal the grade table computed the FN way — SUM(alloc_spend)
--       over the current DO_NOTHING grades of the plan predictors — within a cent; a family x plan
--       missing on the grade side counts; +1 when no night both grade
--   P2  PARITY (D5), realised: on the family-nights both grade ON ONE CLOCK — the grade rows'
--       horizon is FN's window (horizon_from = as_of, horizon_to = as_of + window_days - 1) — and
--       not restated since grading (FACT_AMAZON_ADS now equals real_spend and real_net over the
--       horizon on every keyword, within 0.005), FN's FAMILY_WEEK realized_net (the live plan),
--       net_at_realized_a / _b and its GRADE realized_net, net_at_realized_returns and
--       allocated_unrealized_dollars equal the grade table's (SUM real_net; SUM alloc_spend x
--       real_net / real_spend, 0 where nothing was spent; SUM alloc_spend where nothing was spent),
--       within a cent. The ledger starts a horizon on the first full Los Angeles day after built_at
--       (D2), and every night stored up to 2026-10-03 was written after Los Angeles midnight of its
--       as_of, so on those nights the two windows differ by a day and P2 has nothing to compare:
--       FN keeps its own clock until piece 6 (spec §7, architecture/LEARNING.md §4). NO EMPTINESS
--       TERM; P2n REPORTS the family-nights compared. A grade is frozen and FN reads FACT_AMAZON_ADS
--       live, so a restatement after grading is left out of P2 rather than read as a disagreement.
--       PC_P2_FN_CLOCK (below) and the harness's FNCLK copy exercise it.
--
-- THE NEGATIVE CONTROLS. Each check is written once over labelled TEMP copies: LIVE, and doctored
-- copies of it. A control row reads PASS when its doctored copy FIRED (violations >= 1); its measured
-- count is printed beside it. The doctored row is the first eligible row in key order (as_of,
-- predictor, campaign_id, keyword_id, scenario for the ledger; predictor, variant, as_of,
-- campaign_id, keyword_id, scenario for the grades). A pick that finds no row leaves its copy equal
-- to LIVE, so its control reads 0 and FAILS (loud).
--   NC_EMPTY           no ledger row (and an empty second read)          -> L1a-L1d, L2, L3, L4
--                      no grade, ledger, FN, board or card row           -> C2, C3, C4a, C8a-C8c, F, P1
--   NC_L1_ONE_SCENARIO one ACT row removed                               -> L1a
--   NC_L1_NULL_NUMBER  one row's pred_gp NULL                            -> L1b
--   NC_L1_NEG_BASIS    one row's basis_clicks -1                         -> L1c
--   NC_L1_NO_RULE      one row's rule_version NULL                       -> L1d
--   NC_L2_R_09         one L2 row with window clicks: its ACT priced at r = 0.9 (clicks, orders,
--                      gross profit x 0.9, spend x 0.81, net recomputed) -> L2 (the plan's control)
--   NC_L3_SPEND_R1     example 1's ACT spend at r^1 (window spend x r)   -> L3
--   NC_L3_SEAT         example 2's ACT spend at the seat ($0)            -> L3
--   NC_L4_DRIFT        the second read: one row's pred_net + 0.01 and another row missing -> L4
--   NC_C2_UNGRADED     K1 (the first current grade) removed, every regrade_seq   -> C2
--   NC_C2_TWO_CURRENT  K1's current row written twice                    -> C2
--   NC_C2_EARLY        a grade on KE, the first ledger row not yet gradable -> C2
--   NC_C3_SECOND_GRADE K1 graded again: a second regrade_seq 0 row, an hour later -> C3
--   NC_C3_NO_REASON    KR's current re-grade (the first with regrade_seq >= 1) without its reason -> C3
--   NC_C3_BAND_HOLE    KR's current re-grade removed: left out of its run's band -> C3
--   NC_C4_NO_LABEL     K1's current label NULL                           -> C4a
--   NC_C4_INCONCLUSIVE_AT_LINE  K4 (the first current INCONCLUSIVE grade with a click) given a
--                      line at its own clicks                            -> C4b
--   NC_C4_RIGHT_NO_LINE         K4 relabelled RIGHT with no line         -> C4b
--   PC_C5_FIXTURES     three fixtures (RIGHT, WRONG, INCONCLUSIVE x both scenarios) added with the
--                      labels their keywords name: C5 reads 0            -> C5 0; C5z fires
--   NC_C5_SWAPPED      the same with the RIGHT and WRONG labels swapped  -> C5
--   NC_C5Z_CARD        one fixture row on the report card                -> C5z
--   NC_C8_MISSING      prediction_regression gone from the board         -> C8a
--   NC_C8_RED          prediction_grades_fresh RED, measured 1           -> C8b
--   NC_C8_NO_RUN       an empty report card                              -> C8c
--   NC_F_MOVED         the plan's control: K1's LEDGER row with pred_net + 0.01 -> F
--   NC_F_LOST          K1's ledger row gone                              -> F
--   NC_P1_ALLOC        KP (the first current DO_NOTHING plan grade on a night both grade):
--                      alloc_spend + 0.02                                -> P1
--   PC_P2_FN_CLOCK     the grade rows of the nights both grade re-read on FN's window (horizon
--                      as_of .. as_of + window_days - 1, realised numbers from FACT_AMAZON_ADS by
--                      the grader's join): P1 0, P2 0 and P2n >= 1 — what a night written before
--                      its Los Angeles midnight will look like
--   NC_P2_FN_DOCTORED  that copy against FN's first FAMILY_WEEK row of a night both grade with
--                      net_at_realized_a + 0.02                          -> P2
-- THE HARNESS, scripts/bigquery/tests/check_prediction_contract_controls.py (--submit / --collect):
-- the grader's own text (SP_GRADE_PREDICTIONS.sql, comment lines stripped, only the procedure,
-- grade, card, ledger and FACT_AMAZON_ADS names swapped for OI._tmp_t7c_* scratch objects, dropped
-- at the end; the deployed body checked equal to the file's first) CALLed on copies, one CALL per
-- copy, and this file's own fd, wmx, fnr and c_out statements cut out and run on each copy's
-- grades. A first run on the grades without the latest night inserts exactly that night (C3f) and a
-- second run inserts 0 (C3i; control NC_NOGUARD: the grader without its graded-once guard inserts
-- rows and C3 fires); the live record re-run inserts 0 (BASE, C3i); a regrade_from run re-grades
-- exactly the named band (C3n; controls: a run row lost, a prediction outside the band re-graded);
-- 34 fixtures under predictor 'FIXTURE', with a line at 6 clicks under the live bar, read RIGHT,
-- WRONG and INCONCLUSIVE (C5, C4a, C4b both arms; controls: a label flipped, a line under an
-- INCONCLUSIVE, a fixture missing) and leave the report card equal to BASE's (C5x; controls: the same
-- fixtures under PLAN_B, an empty card); the grader on FN's clock (the night both grade, horizon
-- as_of .. as_of + window_days - 1) agrees with FN_PLAN_SCORECARD (P1 0, P2 0, P2n >= 1; control: FN
-- doctored). Its header lists every copy; architecture/LEARNING.md §10 "Task 7" records the run.
--
-- RUN LOG — each entry dated. (Besides it, only L3's paragraph below quotes measured values: the
-- ones L3 holds, each with its source.)
-- RUN 2026-10-03 19:49 UTC (Task 4, V_PREDICTION_LEDGER v27.172 deployed 19:49:05 UTC), run as
--   written, job t4_acc_1791056985: 22 rows, every one PASS. LIVE L1a, L1b, L1c, L1d, L2, L3, L4 0
--   over 17,588 ledger rows (8,794 plan rows); L2's population 1,142 ACT rows, 96 with window clicks
--   (job t4_meas_1791057281). Controls, each FIRED: NC_EMPTY L1a 8794, L1b 1, L1c 1, L1d 1, L2 1,
--   L3 16, L4 1; NC_L1_ONE_SCENARIO L1a 1; NC_L1_NULL_NUMBER L1b 1; NC_L1_NEG_BASIS L1c 1;
--   NC_L1_NO_RULE L1d 1; NC_L2_R_09 L2 1; NC_L3_SPEND_R1 L3 1; NC_L3_SEAT L3 1; NC_L4_DRIFT L4 2.
--   235.9 slot-seconds, 108,751,862 bytes, 22 s.
-- RUN 2026-10-04 01:02 UTC (Task 7; the file as committed, comment-stripped text SHA-256 prefix
--   8250b70f3bd5; SP_GRADE_PREDICTIONS v27.175, V_ENGINE_HEALTH v27.176), run as written, job
--   t7_acc2_1791075763: 64 rows, 63 PASS and P2n REPORT 0. LIVE L1a-L4, C2, C3, C4a, C4b, C5z,
--   C8a, C8b, C8c, F, P1, P2 0 over 17,588 ledger rows and 17,888 grade rows (the six August
--   nights, regrade_seq 0 and 1); the nights both grade: 2026-08-28 (FN at New York 10-03 / Los
--   Angeles 10-03), P1 over its 4 FAMILY_WEEK and 8 GRADE rows; P2 compares none (P2n 0).
--   Controls, each read: NC_EMPTY C2 1, C3 1, C4a 1, C8a 3, C8b 1, F 1, P1 1; NC_C2_UNGRADED C2 1;
--   NC_C2_TWO_CURRENT C2 1; NC_C2_EARLY C2 1; NC_C3_SECOND_GRADE C3 2; NC_C3_NO_REASON C3 1;
--   NC_C3_BAND_HOLE C3 1; NC_C4_NO_LABEL C4a 1; NC_C4_INCONCLUSIVE_AT_LINE C4b 1;
--   NC_C4_RIGHT_NO_LINE C4b 1; PC_C5_FIXTURES C5 0 and C5z 6; NC_C5_SWAPPED C5 4; NC_C5Z_CARD C5z 1;
--   NC_C8_MISSING C8a 1; NC_C8_RED C8b 1; NC_C8_NO_RUN C8c 1; NC_F_MOVED F 2; NC_F_LOST F 2;
--   NC_P1_ALLOC P1 2; PC_P2_FN_CLOCK P1 0, P2 0, P2n 4; NC_P2_FN_DOCTORED P2 1; the L controls as
--   in Task 4's run. 872.7 slot-seconds, 553,986,247 bytes, 74 s, 24 statements. (The same text at
--   00:33 UTC, job t7_acc1_1791073978: the same 64 readings, 778.3 slot-seconds.)
--   The harness the same night (job bqjob_r68f8c321bb6f68ea_000001a104611486_1, 00:47-01:01 UTC):
--   exit 0, every asserted reading held — architecture/LEARNING.md §10 "Task 7" lists them.
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

CREATE TEMP TABLE l_out AS
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
)
SELECT copy, chk, n FROM f;

-- =============================================================================================
-- TASK 7 — the spec §11 checks 2-5 and 8, the frozen check F, the parity check P
-- =============================================================================================
CREATE TEMP FUNCTION gkey(p STRING, v STRING, d DATE, c STRING, k STRING, s STRING) AS (
  CONCAT(p, '|', v, '|', CAST(d AS STRING), '|', c, '|', k, '|', s)
);

CREATE TEMP TABLE grd AS
SELECT * FROM `onyga-482313.OI.FACT_PREDICTION_GRADE`;

-- the house watermark (V_PLAN_WINDOW_JUDGMENT's wm, the grader's) and the settle horizon the grader reads
CREATE TEMP TABLE wmx AS
SELECT
  (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) FROM `onyga-482313.OI.FACT_AMAZON_ADS`) AS wm,
  (SELECT CAST(MAX(threshold_value) AS INT64) FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
   WHERE strategy_id = 'LEARNING' AND coach_mode = 'GUARDIAN' AND product_family IS NULL
     AND threshold_key = 'SETTLE_HORIZON_DAYS') AS settle_days;

-- the piece-0 scorecard at today's two clocks (V_PLAN_SCORECARD's), the rows the parity reads
CREATE TEMP TABLE fnr AS
SELECT row_type, plan, family, calendar_state, graded_night, live_plan, graded_windows,
       allocated_dollars, realized_net, net_at_realized_returns, allocated_unrealized_dollars,
       allocated_a, net_at_realized_a, allocated_b, net_at_realized_b
FROM `onyga-482313.OI.FN_PLAN_SCORECARD`(CURRENT_DATE('America/New_York'), CURRENT_DATE('America/Los_Angeles'))
WHERE row_type IN ('GRADE', 'FAMILY_WEEK');

CREATE TEMP TABLE hbr AS
SELECT check_name, status, measured
FROM `onyga-482313.OI.V_ENGINE_HEALTH`
WHERE check_name IN ('prediction_grades_fresh', 'prediction_regression', 'response_model_unverified');

CREATE TEMP TABLE cardr AS
SELECT COUNT(*) AS n_rows, COUNTIF(predictor = 'FIXTURE') AS n_fixture, MAX(scored_at) AS scored_at
FROM `onyga-482313.OI.T_PREDICTION_SCORECARD`;

-- every grade row with its key; is_cur marks the current grade (the highest regrade_seq)
CREATE TEMP TABLE gk AS
SELECT g.*, gkey(g.predictor, g.variant, g.as_of, g.campaign_id, g.keyword_id, g.scenario) AS kk,
       g.regrade_seq = MAX(g.regrade_seq) OVER (PARTITION BY g.predictor, g.variant, g.as_of, g.campaign_id,
                                                             g.keyword_id, g.scenario) AS is_cur
FROM grd g;

-- ---- the rows each control doctors (first eligible in key order) ----
CREATE TEMP TABLE cpick AS
SELECT
  (SELECT kk FROM gk WHERE is_cur
   ORDER BY predictor, variant, as_of, campaign_id, keyword_id, scenario LIMIT 1) AS k1,
  (SELECT kk FROM gk WHERE is_cur AND regrade_seq >= 1
   ORDER BY predictor, variant, as_of, campaign_id, keyword_id, scenario LIMIT 1) AS kr,
  (SELECT kk FROM gk WHERE is_cur AND grade = 'INCONCLUSIVE' AND real_clicks >= 1
   ORDER BY predictor, variant, as_of, campaign_id, keyword_id, scenario LIMIT 1) AS k4,
  (SELECT kk FROM gk WHERE is_cur AND scenario = 'DO_NOTHING' AND STARTS_WITH(predictor, 'PLAN_')
     AND as_of IN (SELECT graded_night FROM fnr WHERE row_type = 'FAMILY_WEEK')
   ORDER BY predictor, variant, as_of, campaign_id, keyword_id, scenario LIMIT 1) AS kp,
  (SELECT AS STRUCT l.predictor, l.variant, l.as_of, l.campaign_id, l.keyword_id, l.scenario,
                    l.horizon_from, l.horizon_to
   FROM live l CROSS JOIN wmx
   WHERE NOT COALESCE(DATE_ADD(l.horizon_to, INTERVAL wmx.settle_days DAY) <= wmx.wm, FALSE)
   ORDER BY l.as_of, l.predictor, l.campaign_id, l.keyword_id, l.scenario LIMIT 1) AS ke,
  (SELECT AS STRUCT family, graded_night FROM fnr
   WHERE row_type = 'FAMILY_WEEK' AND graded_night IN (SELECT as_of FROM grd)
   ORDER BY graded_night, family LIMIT 1) AS fw;

-- ---- the grade copies (cg), by variant ----
CREATE TEMP TABLE cg AS
WITH p AS (SELECT * FROM cpick),
cur1 AS (SELECT gk.* FROM gk, p WHERE gk.kk = p.k1 AND gk.is_cur LIMIT 1),
fx AS (     -- PC_C5: three fixtures per scenario, labelled as their keywords name them
  SELECT c.* EXCEPT (kk, is_cur) REPLACE (
           'FIXTURE' AS predictor, 'F' AS variant, DATE '2026-08-20' AS as_of, 'FIXTURE_CAMPAIGN' AS campaign_id,
           x.kw AS keyword_id, s AS scenario, 0 AS regrade_seq, x.lbl AS grade, CAST(NULL AS STRING) AS regrade_reason)
  FROM cur1 c,
       UNNEST([STRUCT('FIXTURE_RIGHT' AS kw, 'RIGHT' AS lbl), ('FIXTURE_WRONG', 'WRONG'),
               ('FIXTURE_INCONCLUSIVE', 'INCONCLUSIVE')]) AS x,
       UNNEST(['DO_NOTHING', 'ACT']) AS s
),
both0 AS (  -- the nights both grade
  SELECT DISTINCT graded_night AS as_of FROM fnr
  WHERE row_type = 'FAMILY_WEEK' AND graded_night IN (SELECT as_of FROM grd)
),
rr AS (     -- PC_P2_FN_CLOCK: each graded keyword of those nights on FN's window, the grader's join
  SELECT k.as_of, k.campaign_id, k.keyword_id,
         SUM(f.Ads_clicks) AS clk, SUM(f.Ads_cost) AS sp, SUM(f.Ads_orders) AS ord, SUM(f.GROSS_PROFIT) AS gp
  FROM (SELECT DISTINCT g.as_of, g.campaign_id, g.keyword_id, g.window_days FROM grd g JOIN both0 USING (as_of)) k
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` f
    ON f.campaign_id = k.campaign_id AND f.keyword_id = k.keyword_id
   AND f.date BETWEEN k.as_of AND DATE_ADD(k.as_of, INTERVAL k.window_days - 1 DAY)
  GROUP BY k.as_of, k.campaign_id, k.keyword_id
)
SELECT 'LIVE' AS v, gk.* EXCEPT (kk, is_cur) FROM gk
UNION ALL
SELECT 'C2_UNGRADED', gk.* EXCEPT (kk, is_cur) FROM gk, p WHERE NOT COALESCE(gk.kk = p.k1, FALSE)
UNION ALL
SELECT 'C2_TWO_CURRENT', gk.* EXCEPT (kk, is_cur) FROM gk
UNION ALL
SELECT 'C2_TWO_CURRENT', c.* EXCEPT (kk, is_cur) FROM cur1 c
UNION ALL
SELECT 'C2_EARLY', gk.* EXCEPT (kk, is_cur) FROM gk
UNION ALL
SELECT 'C2_EARLY', c.* EXCEPT (kk, is_cur) REPLACE (
         p.ke.predictor AS predictor, p.ke.variant AS variant, p.ke.as_of AS as_of, p.ke.campaign_id AS campaign_id,
         p.ke.keyword_id AS keyword_id, p.ke.scenario AS scenario, p.ke.horizon_from AS horizon_from,
         p.ke.horizon_to AS horizon_to, 0 AS regrade_seq, CAST(NULL AS STRING) AS regrade_reason)
FROM cur1 c, p WHERE p.ke.keyword_id IS NOT NULL
UNION ALL
SELECT 'C3_SECOND_GRADE', gk.* EXCEPT (kk, is_cur) FROM gk
UNION ALL
SELECT 'C3_SECOND_GRADE', gk.* EXCEPT (kk, is_cur) REPLACE (TIMESTAMP_ADD(gk.graded_at, INTERVAL 1 HOUR) AS graded_at)
FROM gk, p WHERE gk.kk = p.k1 AND gk.regrade_seq = 0
UNION ALL
SELECT 'C3_NO_REASON', gk.* EXCEPT (kk, is_cur) REPLACE (
         IF(COALESCE(gk.kk = p.kr AND gk.is_cur, FALSE), CAST(NULL AS STRING), gk.regrade_reason) AS regrade_reason)
FROM gk, p
UNION ALL
SELECT 'C3_BAND_HOLE', gk.* EXCEPT (kk, is_cur) FROM gk, p WHERE NOT COALESCE(gk.kk = p.kr AND gk.is_cur, FALSE)
UNION ALL
SELECT 'C4_NO_LABEL', gk.* EXCEPT (kk, is_cur) REPLACE (
         IF(COALESCE(gk.kk = p.k1 AND gk.is_cur, FALSE), CAST(NULL AS STRING), gk.grade) AS grade)
FROM gk, p
UNION ALL
SELECT 'C4_INCONCLUSIVE_AT_LINE', gk.* EXCEPT (kk, is_cur) REPLACE (
         IF(COALESCE(gk.kk = p.k4 AND gk.is_cur, FALSE), gk.real_clicks, gk.min_clicks_at_grade) AS min_clicks_at_grade)
FROM gk, p
UNION ALL
SELECT 'C4_RIGHT_NO_LINE', gk.* EXCEPT (kk, is_cur) REPLACE (
         IF(COALESCE(gk.kk = p.k4 AND gk.is_cur, FALSE), 'RIGHT', gk.grade) AS grade)
FROM gk, p
UNION ALL
SELECT 'C5_PC', gk.* EXCEPT (kk, is_cur) FROM gk
UNION ALL
SELECT 'C5_PC', x.* FROM fx x
UNION ALL
SELECT 'C5_SWAPPED', gk.* EXCEPT (kk, is_cur) FROM gk
UNION ALL
SELECT 'C5_SWAPPED', x.* REPLACE (
         CASE x.grade WHEN 'RIGHT' THEN 'WRONG' WHEN 'WRONG' THEN 'RIGHT' ELSE x.grade END AS grade)
FROM fx x
UNION ALL
SELECT 'P1_ALLOC', gk.* EXCEPT (kk, is_cur) REPLACE (
         IF(COALESCE(gk.kk = p.kp AND gk.is_cur, FALSE), gk.alloc_spend + 0.02, gk.alloc_spend) AS alloc_spend)
FROM gk, p
UNION ALL
SELECT 'P2_FN_CLOCK', gk.* EXCEPT (kk, is_cur) REPLACE (
         IF(b.as_of IS NULL, gk.horizon_from, gk.as_of)                                          AS horizon_from,
         IF(b.as_of IS NULL, gk.horizon_to, DATE_ADD(gk.as_of, INTERVAL gk.window_days - 1 DAY)) AS horizon_to,
         IF(b.as_of IS NULL, gk.real_clicks, COALESCE(r.clk, 0))                                 AS real_clicks,
         IF(b.as_of IS NULL, gk.real_spend, COALESCE(r.sp, 0.0))                                 AS real_spend,
         IF(b.as_of IS NULL, gk.real_orders, COALESCE(r.ord, 0))                                 AS real_orders,
         IF(b.as_of IS NULL, gk.real_gp, COALESCE(r.gp, 0.0))                                    AS real_gp,
         IF(b.as_of IS NULL, gk.real_net, COALESCE(r.gp, 0.0) - COALESCE(r.sp, 0.0))             AS real_net)
FROM gk
LEFT JOIN both0 b ON b.as_of = gk.as_of
LEFT JOIN rr r ON r.as_of = gk.as_of AND r.campaign_id = gk.campaign_id AND r.keyword_id = gk.keyword_id;
-- variant EMPTY has no row.

-- ---- the ledger copies (cl) ----
CREATE TEMP TABLE cl AS
SELECT 'LIVE' AS v, l.* FROM live l
UNION ALL
SELECT 'F_MOVED', l.* REPLACE (
         IF(COALESCE(gkey(l.predictor, l.variant, l.as_of, l.campaign_id, l.keyword_id, l.scenario) = p.k1, FALSE),
            l.pred_net + 0.01, l.pred_net) AS pred_net)
FROM live l, cpick p
UNION ALL
SELECT 'F_LOST', l.* FROM live l, cpick p
WHERE NOT COALESCE(gkey(l.predictor, l.variant, l.as_of, l.campaign_id, l.keyword_id, l.scenario) = p.k1, FALSE);

-- ---- the scorecard copies (cf) ----
CREATE TEMP TABLE cf AS
SELECT 'LIVE' AS v, f.* FROM fnr f
UNION ALL
SELECT 'P2_DOCTORED', f.* REPLACE (
         IF(COALESCE(f.row_type = 'FAMILY_WEEK' AND f.family = p.fw.family AND f.graded_night = p.fw.graded_night, FALSE),
            f.net_at_realized_a + 0.02, f.net_at_realized_a) AS net_at_realized_a)
FROM fnr f, cpick p;

-- ---- the board copies (ch) and the card copies (cc) ----
CREATE TEMP TABLE ch AS
SELECT 'LIVE' AS v, h.* FROM hbr h
UNION ALL
SELECT 'C8_MISSING', h.* FROM hbr h WHERE h.check_name <> 'prediction_regression'
UNION ALL
SELECT 'C8_RED', h.* REPLACE (IF(h.check_name = 'prediction_grades_fresh', 'RED', h.status) AS status,
                              IF(h.check_name = 'prediction_grades_fresh', 1.0, h.measured) AS measured)
FROM hbr h;

CREATE TEMP TABLE cc AS
SELECT 'LIVE' AS v, c.* FROM cardr c
UNION ALL
SELECT 'EMPTY', 0, 0, CAST(NULL AS TIMESTAMP)
UNION ALL
SELECT 'C5Z_CARD', c.* REPLACE (c.n_fixture + 1 AS n_fixture) FROM cardr c;

-- ---- the copies: which variant of each input a copy reads ----
CREATE TEMP TABLE cm AS
SELECT * FROM UNNEST([
  STRUCT('LIVE' AS copy, 'LIVE' AS gv, 'LIVE' AS lv, 'LIVE' AS fv, 'LIVE' AS hv, 'LIVE' AS cv),
  ('NC_EMPTY',                   'EMPTY',                   'EMPTY',   'EMPTY',       'EMPTY',      'EMPTY'),
  ('NC_C2_UNGRADED',             'C2_UNGRADED',             'LIVE',    'LIVE',        'LIVE',       'LIVE'),
  ('NC_C2_TWO_CURRENT',          'C2_TWO_CURRENT',          'LIVE',    'LIVE',        'LIVE',       'LIVE'),
  ('NC_C2_EARLY',                'C2_EARLY',                'LIVE',    'LIVE',        'LIVE',       'LIVE'),
  ('NC_C3_SECOND_GRADE',         'C3_SECOND_GRADE',         'LIVE',    'LIVE',        'LIVE',       'LIVE'),
  ('NC_C3_NO_REASON',            'C3_NO_REASON',            'LIVE',    'LIVE',        'LIVE',       'LIVE'),
  ('NC_C3_BAND_HOLE',            'C3_BAND_HOLE',            'LIVE',    'LIVE',        'LIVE',       'LIVE'),
  ('NC_C4_NO_LABEL',             'C4_NO_LABEL',             'LIVE',    'LIVE',        'LIVE',       'LIVE'),
  ('NC_C4_INCONCLUSIVE_AT_LINE', 'C4_INCONCLUSIVE_AT_LINE', 'LIVE',    'LIVE',        'LIVE',       'LIVE'),
  ('NC_C4_RIGHT_NO_LINE',        'C4_RIGHT_NO_LINE',        'LIVE',    'LIVE',        'LIVE',       'LIVE'),
  ('PC_C5_FIXTURES',             'C5_PC',                   'LIVE',    'LIVE',        'LIVE',       'LIVE'),
  ('NC_C5_SWAPPED',              'C5_SWAPPED',              'LIVE',    'LIVE',        'LIVE',       'LIVE'),
  ('NC_C5Z_CARD',                'LIVE',                    'LIVE',    'LIVE',        'LIVE',       'C5Z_CARD'),
  ('NC_C8_MISSING',              'LIVE',                    'LIVE',    'LIVE',        'C8_MISSING', 'LIVE'),
  ('NC_C8_RED',                  'LIVE',                    'LIVE',    'LIVE',        'C8_RED',     'LIVE'),
  ('NC_C8_NO_RUN',               'LIVE',                    'LIVE',    'LIVE',        'LIVE',       'EMPTY'),
  ('NC_F_MOVED',                 'LIVE',                    'F_MOVED', 'LIVE',        'LIVE',       'LIVE'),
  ('NC_F_LOST',                  'LIVE',                    'F_LOST',  'LIVE',        'LIVE',       'LIVE'),
  ('NC_P1_ALLOC',                'P1_ALLOC',                'LIVE',    'LIVE',        'LIVE',       'LIVE'),
  ('PC_P2_FN_CLOCK',             'P2_FN_CLOCK',             'LIVE',    'LIVE',        'LIVE',       'LIVE'),
  ('NC_P2_FN_DOCTORED',          'P2_FN_CLOCK',             'LIVE',    'P2_DOCTORED', 'LIVE',       'LIVE')
]);

-- ---- THE C STATEMENT: reads cm, cg, cl, cf, ch, cc, wmx and FACT_AMAZON_ADS only (the harness runs
-- ---- this text on its copies; architecture/LEARNING.md §10 "Task 7") ----
CREATE OR REPLACE TEMP TABLE c_out AS
WITH
g_all AS (SELECT m.copy, g.* EXCEPT (v) FROM cm m JOIN cg g ON g.v = m.gv),
g_cur AS (
  SELECT * FROM g_all
  WHERE TRUE
  QUALIFY regrade_seq = MAX(regrade_seq) OVER (PARTITION BY copy, predictor, variant, as_of, campaign_id,
                                                            keyword_id, scenario)
),
l_all AS (SELECT m.copy, l.* EXCEPT (v) FROM cm m JOIN cl l ON l.v = m.lv),
f_all AS (SELECT m.copy, f.* EXCEPT (v) FROM cm m JOIN cf f ON f.v = m.fv),
h_all AS (SELECT m.copy, h.* EXCEPT (v) FROM cm m JOIN ch h ON h.v = m.hv),
c_meta AS (SELECT m.copy, c.n_rows, c.n_fixture, c.scored_at FROM cm m LEFT JOIN cc c ON c.v = m.cv),
n_g AS (SELECT m.copy, COUNT(g.copy) AS n FROM cm m LEFT JOIN g_all g ON g.copy = m.copy GROUP BY m.copy),
n_cur AS (SELECT m.copy, COUNT(g.copy) AS n FROM cm m LEFT JOIN g_cur g ON g.copy = m.copy GROUP BY m.copy),
-- C2: gradable ledger rows against current grades
gradable AS (
  SELECT l.copy, l.predictor, l.variant, l.as_of, l.campaign_id, l.keyword_id, l.scenario
  FROM l_all l CROSS JOIN wmx
  WHERE DATE_ADD(l.horizon_to, INTERVAL wmx.settle_days DAY) <= wmx.wm
),
n_gradable AS (SELECT m.copy, COUNT(a.copy) AS n FROM cm m LEFT JOIN gradable a ON a.copy = m.copy GROUP BY m.copy),
cur_n AS (
  SELECT copy, predictor, variant, as_of, campaign_id, keyword_id, scenario, COUNT(*) AS n_current
  FROM g_cur
  GROUP BY copy, predictor, variant, as_of, campaign_id, keyword_id, scenario
),
c2_bad AS (
  SELECT COALESCE(a.copy, b.copy) AS copy, COUNT(*) AS n
  FROM gradable a
  FULL OUTER JOIN cur_n b
    ON b.copy = a.copy AND b.predictor = a.predictor AND b.variant = a.variant AND b.as_of = a.as_of
   AND b.campaign_id = a.campaign_id AND b.keyword_id = a.keyword_id AND b.scenario = a.scenario
  WHERE a.copy IS NULL OR b.copy IS NULL OR b.n_current <> 1
  GROUP BY 1
),
-- C3: the record of every grader run
c3_key AS (
  SELECT copy, COUNTIF(n_rows <> n_seq OR mn <> 0 OR mx <> n_seq - 1) AS n
  FROM (
    SELECT copy, COUNT(*) AS n_rows, COUNT(DISTINCT regrade_seq) AS n_seq, MIN(regrade_seq) AS mn, MAX(regrade_seq) AS mx
    FROM g_all
    GROUP BY copy, predictor, variant, as_of, campaign_id, keyword_id, scenario
  )
  GROUP BY copy
),
c3_row AS (
  SELECT copy,
         COUNTIF((regrade_seq = 0) = (COALESCE(TRIM(regrade_reason), '') <> '')) AS n_reason,
         COUNTIF(regrade_seq > 0 AND NOT COALESCE(graded_at > prev_at, FALSE))   AS n_order
  FROM (
    SELECT g.*, LAG(g.graded_at) OVER (PARTITION BY g.copy, g.predictor, g.variant, g.as_of, g.campaign_id,
                                                    g.keyword_id, g.scenario
                                       ORDER BY g.regrade_seq, g.graded_at) AS prev_at
    FROM g_all g
  )
  GROUP BY copy
),
c3_batch AS (       -- every re-grade run: its graded_at and the first night of its band
  SELECT copy, graded_at, MIN(as_of) AS band_from
  FROM g_all
  WHERE regrade_seq > 0
  GROUP BY copy, graded_at
),
c3_need AS (        -- every prediction graded before that run, of a night in its band, still in the ledger
  SELECT DISTINCT b.copy, b.graded_at, g.predictor, g.variant, g.as_of, g.campaign_id, g.keyword_id, g.scenario
  FROM c3_batch b
  JOIN g_all g ON g.copy = b.copy AND g.graded_at < b.graded_at AND g.as_of >= b.band_from
  JOIN l_all l
    ON l.copy = g.copy AND l.predictor = g.predictor AND l.variant = g.variant AND l.as_of = g.as_of
   AND l.campaign_id = g.campaign_id AND l.keyword_id = g.keyword_id AND l.scenario = g.scenario
),
c3_hole AS (
  SELECT nd.copy, COUNT(*) AS n
  FROM c3_need nd
  LEFT JOIN g_all g
    ON g.copy = nd.copy AND g.graded_at = nd.graded_at AND g.predictor = nd.predictor AND g.variant = nd.variant
   AND g.as_of = nd.as_of AND g.campaign_id = nd.campaign_id AND g.keyword_id = nd.keyword_id
   AND g.scenario = nd.scenario
  WHERE g.copy IS NULL
  GROUP BY nd.copy
),
-- C4: the labels
c4 AS (
  SELECT copy,
         COUNTIF(grade IS NULL OR grade NOT IN ('RIGHT', 'WRONG', 'INCONCLUSIVE', 'UNGRADABLE')) AS n_label,
         COUNTIF((grade = 'INCONCLUSIVE' AND real_clicks > 0 AND min_clicks_at_grade IS NOT NULL
                  AND real_clicks >= min_clicks_at_grade)
                 OR (grade IN ('RIGHT', 'WRONG') AND (COALESCE(real_clicks, 0) = 0 OR min_clicks_at_grade IS NULL
                                                     OR real_clicks < min_clicks_at_grade)))   AS n_line
  FROM g_cur
  GROUP BY copy
),
-- C5: the fixtures
c5_fx AS (
  SELECT copy, keyword_id, scenario, grade,
         REGEXP_EXTRACT(keyword_id, r'^FIXTURE_(RIGHT|WRONG|INCONCLUSIVE)') AS expected
  FROM g_cur
  WHERE predictor = 'FIXTURE'
),
c5_bad AS (
  SELECT copy, COUNTIF(expected IS NULL OR grade IS DISTINCT FROM expected) AS n
  FROM c5_fx
  GROUP BY copy
),
c5_miss AS (
  SELECT m.copy, COUNTIF(x.copy IS NULL) AS n
  FROM cm m
  CROSS JOIN UNNEST(['FIXTURE_RIGHT', 'FIXTURE_WRONG', 'FIXTURE_INCONCLUSIVE']) AS kw
  CROSS JOIN UNNEST(['DO_NOTHING', 'ACT']) AS sc
  LEFT JOIN (SELECT DISTINCT copy, keyword_id, scenario FROM c5_fx) x
    ON x.copy = m.copy AND x.keyword_id = kw AND x.scenario = sc
  GROUP BY m.copy
),
c5z AS (
  SELECT m.copy, COALESCE(gx.n, 0) + COALESCE(c.n_fixture, 0) AS n
  FROM cm m
  LEFT JOIN (SELECT copy, COUNT(*) AS n FROM g_all WHERE predictor = 'FIXTURE' GROUP BY copy) gx ON gx.copy = m.copy
  LEFT JOIN c_meta c ON c.copy = m.copy
),
-- C8: the board
h_n AS (
  SELECT copy, check_name, COUNT(*) AS n, MAX(status) AS status, MAX(measured) AS measured
  FROM h_all
  GROUP BY copy, check_name
),
c8a AS (
  SELECT m.copy, COUNTIF(COALESCE(h.n, 0) <> 1) AS n
  FROM cm m
  CROSS JOIN UNNEST(['prediction_grades_fresh', 'prediction_regression', 'response_model_unverified']) AS nm
  LEFT JOIN h_n h ON h.copy = m.copy AND h.check_name = nm
  GROUP BY m.copy
),
c8b AS (
  SELECT m.copy, IF(COALESCE(h.n = 1 AND h.status = 'GREEN' AND h.measured = 0, FALSE), 0, 1) AS n
  FROM cm m
  LEFT JOIN h_n h ON h.copy = m.copy AND h.check_name = 'prediction_grades_fresh'
),
-- F: every grade row against the ledger row it was graded from
f_bad AS (
  SELECT g.copy, COUNT(*) AS n
  FROM g_all g
  LEFT JOIN l_all l
    ON l.copy = g.copy AND l.predictor = g.predictor AND l.variant = g.variant AND l.as_of = g.as_of
   AND l.campaign_id = g.campaign_id AND l.keyword_id = g.keyword_id AND l.scenario = g.scenario
  WHERE l.copy IS NULL
     OR fd(g.pred_clicks, l.pred_clicks) OR fd(g.pred_spend, l.pred_spend) OR fd(g.pred_orders, l.pred_orders)
     OR fd(g.pred_gp, l.pred_gp) OR fd(g.pred_net, l.pred_net)
     OR g.pred_side IS DISTINCT FROM l.pred_side OR g.built_at IS DISTINCT FROM l.built_at
     OR g.horizon_from IS DISTINCT FROM l.horizon_from OR g.horizon_to IS DISTINCT FROM l.horizon_to
     OR g.rule_version IS DISTINCT FROM l.rule_version
     OR g.response_model_version IS DISTINCT FROM l.response_model_version
     OR g.builder_version IS DISTINCT FROM l.builder_version OR g.act_is_noop IS DISTINCT FROM l.act_is_noop
     OR g.move IS DISTINCT FROM l.move OR g.family IS DISTINCT FROM l.family
     OR g.channel IS DISTINCT FROM l.channel OR g.calendar_state IS DISTINCT FROM l.calendar_state
     OR g.window_days IS DISTINCT FROM l.window_days OR g.is_live_plan IS DISTINCT FROM l.is_live_plan
     OR g.holdout IS DISTINCT FROM l.holdout OR g.min_orders IS DISTINCT FROM l.min_orders
     OR g.basis_clicks IS DISTINCT FROM l.basis_clicks
     OR fd(g.family_bar, l.family_bar) OR fd(g.current_bid, l.current_bid) OR fd(g.planned_bid, l.planned_bid)
     OR fd(g.campaign_current_budget, l.campaign_current_budget)
     OR fd(g.campaign_planned_budget, l.campaign_planned_budget)
     OR fd(g.basis_spend, l.basis_spend) OR fd(g.alloc_spend, l.alloc_spend)
  GROUP BY g.copy
),
-- P: the grade table computed the FN way, per plan x family x night (current DO_NOTHING plan grades)
gp_n AS (
  SELECT copy, variant AS plan, family, as_of,
         SUM(alloc_spend)                                             AS alloc,
         SUM(real_net)                                                AS net,
         SUM(alloc_spend * IF(real_spend > 0, real_net / real_spend, 0)) AS nar,
         SUM(IF(real_spend = 0, alloc_spend, 0))                      AS unreal,
         SUM(IF(is_live_plan, real_net, 0))                           AS live_net,
         LOGICAL_AND(horizon_from = as_of
                     AND horizon_to = DATE_ADD(as_of, INTERVAL window_days - 1 DAY)) AS fn_clock
  FROM g_cur
  WHERE scenario = 'DO_NOTHING' AND STARTS_WITH(predictor, 'PLAN_')
  GROUP BY copy, variant, family, as_of
),
both_n AS (         -- the nights both grade: FN's FAMILY_WEEK graded nights the grade table grades
  SELECT DISTINCT f.copy, f.graded_night AS as_of
  FROM f_all f
  JOIN (SELECT DISTINCT copy, as_of FROM gp_n) g ON g.copy = f.copy AND g.as_of = f.graded_night
  WHERE f.row_type = 'FAMILY_WEEK'
),
n_both AS (SELECT m.copy, COUNT(b.copy) AS n FROM cm m LEFT JOIN both_n b ON b.copy = m.copy GROUP BY m.copy),
p2_keys AS (        -- the keywords P2 may compare: graded on FN's window, on a night both grade
  SELECT DISTINCT g.copy, g.predictor, g.as_of, g.family, g.campaign_id, g.keyword_id, g.horizon_from,
                  g.horizon_to, g.real_spend, g.real_net
  FROM g_cur g
  JOIN both_n b ON b.copy = g.copy AND b.as_of = g.as_of
  WHERE g.scenario = 'DO_NOTHING' AND STARTS_WITH(g.predictor, 'PLAN_')
    AND g.horizon_from = g.as_of AND g.horizon_to = DATE_ADD(g.as_of, INTERVAL g.window_days - 1 DAY)
),
p2_fact AS (        -- what FACT_AMAZON_ADS reads for them now
  SELECT k.copy, k.predictor, k.as_of, k.family, k.campaign_id, k.keyword_id,
         MAX(k.real_spend) AS real_spend, MAX(k.real_net) AS real_net,
         COALESCE(SUM(f.Ads_cost), 0)                                  AS sp_now,
         COALESCE(SUM(f.GROSS_PROFIT), 0) - COALESCE(SUM(f.Ads_cost), 0) AS net_now
  FROM p2_keys k
  LEFT JOIN `onyga-482313.OI.FACT_AMAZON_ADS` f
    ON f.campaign_id = k.campaign_id AND f.keyword_id = k.keyword_id
   AND f.date BETWEEN k.horizon_from AND k.horizon_to
  GROUP BY k.copy, k.predictor, k.as_of, k.family, k.campaign_id, k.keyword_id, k.horizon_from, k.horizon_to
),
p2_restated AS (    -- family-nights with a keyword FACT_AMAZON_ADS has restated since grading
  SELECT DISTINCT copy, as_of, family
  FROM p2_fact
  WHERE ABS(sp_now - real_spend) >= 0.005 OR ABS(net_now - real_net) >= 0.005
),
p2_night AS (       -- the family-nights P2 compares
  SELECT g.copy, g.as_of, g.family
  FROM gp_n g
  JOIN both_n b ON b.copy = g.copy AND b.as_of = g.as_of
  LEFT JOIN p2_restated r ON r.copy = g.copy AND r.as_of = g.as_of AND r.family = g.family
  GROUP BY g.copy, g.as_of, g.family
  HAVING LOGICAL_AND(g.fn_clock) AND LOGICAL_AND(r.copy IS NULL)
),
p_fw AS (           -- FN's FAMILY_WEEK rows of the nights both grade
  SELECT f.copy,
         COUNTIF(a.copy IS NULL OR b.copy IS NULL
                 OR ABS(COALESCE(f.allocated_a, 0) - COALESCE(a.alloc, 0)) > 0.01
                 OR ABS(COALESCE(f.allocated_b, 0) - COALESCE(b.alloc, 0)) > 0.01) AS n1,
         COUNTIF(pn.copy IS NOT NULL
                 AND (a.copy IS NULL OR b.copy IS NULL
                      OR ABS(COALESCE(f.realized_net, 0) - (COALESCE(a.live_net, 0) + COALESCE(b.live_net, 0))) > 0.01
                      OR ABS(COALESCE(f.net_at_realized_a, 0) - COALESCE(a.nar, 0)) > 0.01
                      OR ABS(COALESCE(f.net_at_realized_b, 0) - COALESCE(b.nar, 0)) > 0.01)) AS n2
  FROM f_all f
  JOIN both_n bo ON bo.copy = f.copy AND bo.as_of = f.graded_night
  LEFT JOIN gp_n a ON a.copy = f.copy AND a.as_of = f.graded_night AND a.family = f.family AND a.plan = 'A'
  LEFT JOIN gp_n b ON b.copy = f.copy AND b.as_of = f.graded_night AND b.family = f.family AND b.plan = 'B'
  LEFT JOIN p2_night pn ON pn.copy = f.copy AND pn.as_of = f.graded_night AND pn.family = f.family
  WHERE f.row_type = 'FAMILY_WEEK'
  GROUP BY f.copy
),
fw_n AS (SELECT DISTINCT copy, family, calendar_state, graded_night AS as_of FROM f_all WHERE row_type = 'FAMILY_WEEK'),
p_gr0 AS (          -- FN's GRADE rows, pooled over FN's graded nights of the family x state
  SELECT f.copy, f.plan, f.family, f.calendar_state,
         MAX(f.allocated_dollars) AS fn_alloc, MAX(f.realized_net) AS fn_net,
         MAX(f.net_at_realized_returns) AS fn_nar, MAX(f.allocated_unrealized_dollars) AS fn_unreal,
         LOGICAL_AND(bo.copy IS NOT NULL) AS all_both, LOGICAL_AND(pn.copy IS NOT NULL) AS all_p2,
         COUNTIF(g.copy IS NULL) AS n_missing,
         SUM(g.alloc) AS g_alloc, SUM(g.net) AS g_net, SUM(g.nar) AS g_nar, SUM(g.unreal) AS g_unreal
  FROM f_all f
  JOIN fw_n w ON w.copy = f.copy AND w.family = f.family AND w.calendar_state = f.calendar_state
  LEFT JOIN both_n bo ON bo.copy = w.copy AND bo.as_of = w.as_of
  LEFT JOIN p2_night pn ON pn.copy = w.copy AND pn.as_of = w.as_of AND pn.family = w.family
  LEFT JOIN gp_n g ON g.copy = w.copy AND g.as_of = w.as_of AND g.family = w.family AND g.plan = f.plan
  WHERE f.row_type = 'GRADE'
  GROUP BY f.copy, f.plan, f.family, f.calendar_state
),
p_gr AS (
  SELECT copy,
         COUNTIF(all_both AND (n_missing > 0 OR ABS(COALESCE(fn_alloc, 0) - COALESCE(g_alloc, 0)) > 0.01)) AS n1,
         COUNTIF(all_p2 AND (n_missing > 0
                             OR ABS(COALESCE(fn_net, 0) - COALESCE(g_net, 0)) > 0.01
                             OR ABS(COALESCE(fn_nar, 0) - COALESCE(g_nar, 0)) > 0.01
                             OR ABS(COALESCE(fn_unreal, 0) - COALESCE(g_unreal, 0)) > 0.01)) AS n2
  FROM p_gr0
  GROUP BY copy
),
n_p2 AS (SELECT m.copy, COUNT(pn.copy) AS n FROM cm m LEFT JOIN p2_night pn ON pn.copy = m.copy GROUP BY m.copy),
c_all AS (
  SELECT m.copy, 'C2' AS chk, COALESCE(x.n, 0) + IF(ng.n = 0, 1, 0) AS n
  FROM cm m JOIN n_gradable ng ON ng.copy = m.copy LEFT JOIN c2_bad x ON x.copy = m.copy
  UNION ALL
  SELECT m.copy, 'C3', COALESCE(k.n, 0) + COALESCE(r.n_reason, 0) + COALESCE(r.n_order, 0) + COALESCE(h.n, 0)
                       + IF(g.n = 0, 1, 0)
  FROM cm m JOIN n_g g ON g.copy = m.copy
  LEFT JOIN c3_key k ON k.copy = m.copy LEFT JOIN c3_row r ON r.copy = m.copy LEFT JOIN c3_hole h ON h.copy = m.copy
  UNION ALL
  SELECT m.copy, 'C4a', COALESCE(c.n_label, 0) + IF(nc.n = 0, 1, 0)
  FROM cm m JOIN n_cur nc ON nc.copy = m.copy LEFT JOIN c4 c ON c.copy = m.copy
  UNION ALL
  SELECT m.copy, 'C4b', COALESCE(c.n_line, 0) FROM cm m LEFT JOIN c4 c ON c.copy = m.copy
  UNION ALL
  SELECT m.copy, 'C5', COALESCE(b.n, 0) + COALESCE(s.n, 0)
  FROM cm m LEFT JOIN c5_bad b ON b.copy = m.copy LEFT JOIN c5_miss s ON s.copy = m.copy
  UNION ALL
  SELECT copy, 'C5z', n FROM c5z
  UNION ALL
  SELECT copy, 'C8a', n FROM c8a
  UNION ALL
  SELECT copy, 'C8b', n FROM c8b
  UNION ALL
  SELECT copy, 'C8c', IF(COALESCE(n_rows, 0) > 0 AND scored_at IS NOT NULL, 0, 1) FROM c_meta
  UNION ALL
  SELECT m.copy, 'F', COALESCE(x.n, 0) + IF(g.n = 0, 1, 0)
  FROM cm m JOIN n_g g ON g.copy = m.copy LEFT JOIN f_bad x ON x.copy = m.copy
  UNION ALL
  SELECT m.copy, 'P1', COALESCE(a.n1, 0) + COALESCE(b.n1, 0) + IF(nb.n = 0, 1, 0)
  FROM cm m JOIN n_both nb ON nb.copy = m.copy LEFT JOIN p_fw a ON a.copy = m.copy LEFT JOIN p_gr b ON b.copy = m.copy
  UNION ALL
  SELECT m.copy, 'P2', COALESCE(a.n2, 0) + COALESCE(b.n2, 0)
  FROM cm m LEFT JOIN p_fw a ON a.copy = m.copy LEFT JOIN p_gr b ON b.copy = m.copy
  UNION ALL
  SELECT copy, 'P2n', n FROM n_p2
)
SELECT copy, chk, n FROM c_all;

WITH
res AS (
  SELECT copy, chk, n FROM l_out
  UNION ALL
  SELECT copy, chk, n FROM c_out
),
expect AS (   -- mode ZERO: must read 0; FIRE: must read >= 1 (a control); REPORT: printed, not asserted
  SELECT * FROM UNNEST([
    -- A PLAN ROW WITH ONE SCENARIO CANNOT BE GRADED AGAINST THE OTHER: the lift is a difference of two rows.
    STRUCT('L1a every plan row has one DO_NOTHING and one ACT row, and no ledger row lacks a plan row' AS check_name, 'L1a' AS chk, 'LIVE' AS copy, 'ZERO' AS mode),
    -- A NULL PREDICTION GRADES AS NOTHING: the grader's errors and the report card's sums skip it in silence.
    ('L1b the five predicted numbers are non-NULL', 'L1b', 'LIVE', 'ZERO'),
    ('L1c basis_clicks is non-NULL and >= 0', 'L1c', 'LIVE', 'ZERO'),
    -- A PREDICTION THAT CANNOT NAME ITS RULE CANNOT BE BLAMED ON ONE: prediction_regression names the rule that moved.
    ('L1d every row has a rule_version', 'L1d', 'LIVE', 'ZERO'),
    -- A MODEL THAT MOVES ROWS THE PLAN DOES NOT MOVE INVENTS LIFT (spec §14 E3).
    ('L2 ACT equals DO_NOTHING to the cent on every no-op row of an uncut campaign', 'L2', 'LIVE', 'ZERO'),
    ('L3 the two worked examples of the brief reproduce (10-03, plan B)', 'L3', 'LIVE', 'ZERO'),
    -- A LEDGER THAT READS DIFFERENTLY TWICE CANNOT BE FROZEN INTO A GRADE.
    ('L4 two reads of the view are equal row for row (floats within 1e-6)', 'L4', 'LIVE', 'ZERO'),
    ('L1a1 NEGATIVE CONTROL L1a FIRES: no ledger row', 'L1a', 'NC_EMPTY', 'FIRE'),
    ('L1a2 NEGATIVE CONTROL L1a FIRES: one ACT row removed', 'L1a', 'NC_L1_ONE_SCENARIO', 'FIRE'),
    ('L1b1 NEGATIVE CONTROL L1b FIRES: no ledger row', 'L1b', 'NC_EMPTY', 'FIRE'),
    ('L1b2 NEGATIVE CONTROL L1b FIRES: one pred_gp NULL', 'L1b', 'NC_L1_NULL_NUMBER', 'FIRE'),
    ('L1c1 NEGATIVE CONTROL L1c FIRES: no ledger row', 'L1c', 'NC_EMPTY', 'FIRE'),
    ('L1c2 NEGATIVE CONTROL L1c FIRES: one basis_clicks -1', 'L1c', 'NC_L1_NEG_BASIS', 'FIRE'),
    ('L1d1 NEGATIVE CONTROL L1d FIRES: no ledger row', 'L1d', 'NC_EMPTY', 'FIRE'),
    ('L1d2 NEGATIVE CONTROL L1d FIRES: one rule_version NULL', 'L1d', 'NC_L1_NO_RULE', 'FIRE'),
    ('L2a NEGATIVE CONTROL L2 FIRES: no ledger row', 'L2', 'NC_EMPTY', 'FIRE'),
    ('L2b NEGATIVE CONTROL L2 FIRES: one no-op row priced at r = 0.9', 'L2', 'NC_L2_R_09', 'FIRE'),
    ('L3a NEGATIVE CONTROL L3 FIRES: no ledger row', 'L3', 'NC_EMPTY', 'FIRE'),
    ('L3b NEGATIVE CONTROL L3 FIRES: example 1 ACT spend at r^1', 'L3', 'NC_L3_SPEND_R1', 'FIRE'),
    ('L3c NEGATIVE CONTROL L3 FIRES: example 2 ACT spend at the seat', 'L3', 'NC_L3_SEAT', 'FIRE'),
    ('L4a NEGATIVE CONTROL L4 FIRES: both reads empty', 'L4', 'NC_EMPTY', 'FIRE'),
    ('L4b NEGATIVE CONTROL L4 FIRES: the second read drifted and lost a row', 'L4', 'NC_L4_DRIFT', 'FIRE'),
    -- A PREDICTION WITH NO GRADE, OR TWO, IS A HOLE OR A DOUBLE COUNT IN EVERY REPORT-CARD SUM; A GRADE MADE
    -- BEFORE ITS HORIZON SETTLED IS FROZEN ON NUMBERS STILL MOVING.
    ('C2 every ledger row gradable on the house watermark has exactly one current grade, and no graded prediction lacks one', 'C2', 'LIVE', 'ZERO'),
    -- A GRADER THAT GRADES TWICE, OR RE-GRADES PART OF A BAND, MOVES GRADES NIGHT TO NIGHT WITH NO ONE ASKING.
    ('C3 the record: one row per prediction per regrade_seq from 0, a reason on every re-grade and no first grade, every re-grade run covered its band', 'C3', 'LIVE', 'ZERO'),
    -- A LABEL OUTSIDE THE FOUR IS COUNTED NOWHERE ON THE CARD.
    ('C4a every current grade carries one of RIGHT, WRONG, INCONCLUSIVE, UNGRADABLE', 'C4a', 'LIVE', 'ZERO'),
    -- A LABEL ON THE WRONG SIDE OF THE LINE CALLS NOISE WRONG, OR HIDES A WRONG CALL AS NOISE.
    ('C4b no INCONCLUSIVE row with a click at or above its line, no RIGHT or WRONG row below it or without one', 'C4b', 'LIVE', 'ZERO'),
    -- A FABRICATED GRADE IN THE APPEND-ONLY TABLE COULD NEVER BE REMOVED.
    ('C5z no fixture row in the grade table or on the report card (fixtures live in copies)', 'C5z', 'LIVE', 'ZERO'),
    -- A CHECK THAT IS NOT ON THE BOARD CANNOT GO RED.
    ('C8a prediction_grades_fresh, prediction_regression, response_model_unverified are on V_ENGINE_HEALTH once each', 'C8a', 'LIVE', 'ZERO'),
    ('C8b prediction_grades_fresh is GREEN, measured 0', 'C8b', 'LIVE', 'ZERO'),
    ('C8c the report card was rebuilt by a grader run (rows and a scored_at)', 'C8c', 'LIVE', 'ZERO'),
    -- A PREDICTION THAT CHANGES AFTER IT IS GRADED WAS NEVER WRITTEN DOWN BEFORE ITS OUTCOME (contract item 1).
    ('F every grade row, re-grades included, still equals the ledger row it was graded from', 'F', 'LIVE', 'ZERO'),
    -- PIECE 6 RE-POINTS FN_PLAN_SCORECARD AT THE GRADE TABLE: A DIFFERENT ALLOCATION THERE CHANGES THE LIVE-PLAN VERDICT.
    ('P1 parity: FN_PLAN_SCORECARD GRADE and FAMILY_WEEK allocation equal the grade table computed the FN way, nights both grade, within a cent', 'P1', 'LIVE', 'ZERO'),
    ('P2 parity: FN realised net, net at realised returns, unrealised allocation equal the grade table, family-nights both grade on one clock, within a cent', 'P2', 'LIVE', 'ZERO'),
    ('P2n REPORT family-nights P2 compares on the live record (both grade, one clock, not restated)', 'P2n', 'LIVE', 'REPORT'),
    ('C2a NEGATIVE CONTROL C2 FIRES: no grade and no ledger row', 'C2', 'NC_EMPTY', 'FIRE'),
    ('C2b NEGATIVE CONTROL C2 FIRES: one gradable prediction ungraded', 'C2', 'NC_C2_UNGRADED', 'FIRE'),
    ('C2c NEGATIVE CONTROL C2 FIRES: one prediction with two current grades', 'C2', 'NC_C2_TWO_CURRENT', 'FIRE'),
    ('C2d NEGATIVE CONTROL C2 FIRES: a grade on a ledger row not yet gradable', 'C2', 'NC_C2_EARLY', 'FIRE'),
    ('C3a NEGATIVE CONTROL C3 FIRES: no grade row', 'C3', 'NC_EMPTY', 'FIRE'),
    ('C3b NEGATIVE CONTROL C3 FIRES: a graded prediction graded again (a second regrade_seq 0)', 'C3', 'NC_C3_SECOND_GRADE', 'FIRE'),
    ('C3c NEGATIVE CONTROL C3 FIRES: a re-grade without its reason', 'C3', 'NC_C3_NO_REASON', 'FIRE'),
    ('C3d NEGATIVE CONTROL C3 FIRES: one prediction left out of its re-grade run', 'C3', 'NC_C3_BAND_HOLE', 'FIRE'),
    ('C4a1 NEGATIVE CONTROL C4a FIRES: no grade', 'C4a', 'NC_EMPTY', 'FIRE'),
    ('C4a2 NEGATIVE CONTROL C4a FIRES: one current label NULL', 'C4a', 'NC_C4_NO_LABEL', 'FIRE'),
    ('C4b1 NEGATIVE CONTROL C4b FIRES: an INCONCLUSIVE row with a line at its own clicks', 'C4b', 'NC_C4_INCONCLUSIVE_AT_LINE', 'FIRE'),
    ('C4b2 NEGATIVE CONTROL C4b FIRES: a row with clicks labelled RIGHT with no line', 'C4b', 'NC_C4_RIGHT_NO_LINE', 'FIRE'),
    ('C5a POSITIVE CONTROL C5 READS 0: three fixtures labelled as their keywords name them', 'C5', 'PC_C5_FIXTURES', 'ZERO'),
    ('C5b NEGATIVE CONTROL C5 FIRES: the RIGHT and WRONG fixture labels swapped', 'C5', 'NC_C5_SWAPPED', 'FIRE'),
    ('C5z1 NEGATIVE CONTROL C5z FIRES: fixture grades in the grade table', 'C5z', 'PC_C5_FIXTURES', 'FIRE'),
    ('C5z2 NEGATIVE CONTROL C5z FIRES: a fixture row on the report card', 'C5z', 'NC_C5Z_CARD', 'FIRE'),
    ('C8a1 NEGATIVE CONTROL C8a FIRES: no board row', 'C8a', 'NC_EMPTY', 'FIRE'),
    ('C8a2 NEGATIVE CONTROL C8a FIRES: prediction_regression gone from the board', 'C8a', 'NC_C8_MISSING', 'FIRE'),
    ('C8b1 NEGATIVE CONTROL C8b FIRES: no board row', 'C8b', 'NC_EMPTY', 'FIRE'),
    ('C8b2 NEGATIVE CONTROL C8b FIRES: prediction_grades_fresh RED', 'C8b', 'NC_C8_RED', 'FIRE'),
    ('C8c1 NEGATIVE CONTROL C8c FIRES: an empty report card', 'C8c', 'NC_C8_NO_RUN', 'FIRE'),
    ('F1 NEGATIVE CONTROL F FIRES: no grade row', 'F', 'NC_EMPTY', 'FIRE'),
    ('F2 NEGATIVE CONTROL F FIRES: one graded ledger row with pred_net moved by 0.01', 'F', 'NC_F_MOVED', 'FIRE'),
    ('F3 NEGATIVE CONTROL F FIRES: one graded ledger row gone', 'F', 'NC_F_LOST', 'FIRE'),
    ('P1a NEGATIVE CONTROL P1 FIRES: no night both grade', 'P1', 'NC_EMPTY', 'FIRE'),
    ('P1b NEGATIVE CONTROL P1 FIRES: one allocation + 0.02', 'P1', 'NC_P1_ALLOC', 'FIRE'),
    ('P2a POSITIVE CONTROL P1 READS 0 ON FN CLOCK: the nights both grade re-read on FN window', 'P1', 'PC_P2_FN_CLOCK', 'ZERO'),
    ('P2b POSITIVE CONTROL P2 READS 0 ON FN CLOCK: the nights both grade re-read on FN window', 'P2', 'PC_P2_FN_CLOCK', 'ZERO'),
    ('P2c POSITIVE CONTROL P2 COMPARES ON FN CLOCK: P2n >= 1 there', 'P2n', 'PC_P2_FN_CLOCK', 'FIRE'),
    ('P2d NEGATIVE CONTROL P2 FIRES: FN net_at_realized_a + 0.02 on a compared family-night', 'P2', 'NC_P2_FN_DOCTORED', 'FIRE')
  ])
)
SELECT e.check_name, e.copy, r.n AS violations,
       CASE e.mode
         WHEN 'ZERO' THEN IF(r.n = 0, 'PASS', 'FAIL')
         WHEN 'FIRE' THEN IF(r.n >= 1, 'PASS', 'FAIL')
         ELSE 'REPORT'
       END AS result
FROM expect e
LEFT JOIN res r ON r.chk = e.chk AND r.copy = e.copy
ORDER BY e.check_name;
