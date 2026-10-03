-- =============================================================================================
-- PLAN_HEALTH acceptance — v27.152 (2026-10-01). The plan's health checks on V_ENGINE_HEALTH
-- (c23–c32, plan Task 5 as corrected) and the SYSTEM line of V_DAILY_BRIEF that carries their
-- RED rows to the one query Ori reads every morning. EVERY ROW MUST READ PASS.
-- v27.163: plus plan_pass_failed, the board's memory and the SYSTEM line's NEW / standing (A1–A3).
-- v27.176: plus the learning contract's checks prediction_grades_fresh, prediction_regression and
-- response_model_unverified (V_ENGINE_HEALTH c35-c37) and their place on the SYSTEM line (P0-P5).
-- A long job (the brief is read in full): submit with --nosync and poll, then read the last child job.
--   bq query --nosync --format=none --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^[[:space:]]*--' FILE)"
-- Objects: scripts/bigquery/views/V_ENGINE_HEALTH.sql, scripts/bigquery/views/V_DAILY_BRIEF.sql,
-- scripts/bigquery/tables/FACT_ENGINE_HEALTH_HISTORY.sql, scripts/bigquery/procedures/SP_SNAPSHOT_ENGINE_HEALTH.sql.
-- SOP: architecture/NEXT_WEEK_MONEY.md §6, architecture/ENGINE_HEALTH.md, architecture/DAILY_BRIEF.md,
-- architecture/LEARNING.md §6.
--
-- WHY THIS FILE EXISTS. SP_BUILD_NEXT_WEEK_PLAN failed every pass from 2026-08-29 to 2026-09-28.
-- LOG_PIPELINE_RUNS logged every failure and nothing Ori reads said so. Two alarm checks now
-- sit on the board (plan_partition_fresh, pipeline_step_failing) and the brief folds the board's
-- RED rows into one SYSTEM line. This file proves (1) the checks are on the board, (2) the alarms
-- FIRE on doctored copies and HOLD on copies that should not fire, (3) the brief line names every
-- RED check and says A NIGHT WAS NOT SAVED when an alarm is RED.
--
-- NEGATIVE CONTROLS ARE STANDING CHECKS HERE, NOT A ONE-OFF. Each alarm's expression is copied
-- into this file and run over LIVE and doctored TEMP copies in one statement — the deployed view
-- cannot be pointed at a temp table, so the copy is the only way to prove firing, and C03c / C06c
-- / C05c / C04f tie each copy to the deployed view's own output on the live data so the two cannot
-- drift apart unseen. THE EXPRESSIONS MUST CHANGE TOGETHER: c32's pipe_fail HAVING, c31's
-- plan_clock GREATEST, c28's guard COUNTIFs, the brief's `health` aggregate and its `system_health`
-- rendering each have one twin below.
--
-- RUN 2026-10-01 after the first deploy: 17 rows, every one PASS. RE-RUN 2026-10-01 after the C04a
-- fix below: 20 rows, every one PASS, on the live board (32 checks, 3 RED). The intermediates were
-- then printed from the same temp tables so each PASS is known to be a control that FIRED, not a
-- vacuous one (the live figures are the board's, never this file's):
--   C02b: LIVE last_plan 2026-10-01 = due 2026-10-01 (GREEN); NC_DROP_LATEST last_plan
--         2026-09-30 < due 2026-10-01 (RED, 1 night); NC_EMPTY last_plan NULL (RED).
--   C03a/b/c: the victim chosen was REBUILD_T_CAMPAIGN_PRODUCT_SCOPE (most runs in 30 days with
--         its three most recent OK); the twin named it on NC3 and nothing on NC2; on LIVE it
--         named nothing, and the deployed check measured 0.
--   C04: the live brief carried one SYSTEM row, rank 7, status RED, from_value 3, naming the
--         board's three standing REDs; C04a/b/c each returned >= 1 on the doctored copy.
--   C04d/e: the row rendered for NC_ALL_GREEN read status GREEN, from_value 0, item '0 of 32
--         checks RED', action 'nothing to do — no check is RED', detail 'SYSTEM: 0 checks RED —
--         every check on the board is green, amber or a report · last plan 2026-10-01, 0 night(s)
--         missing · no step has failed ...', 0 names; the row test read 0 on it as rendered and 1
--         with from_value 1.0 (and 1 with from_value 1.0 on LIVE and on NC_ALARM too).
--   C04f: the row rendered for LIVE equalled the deployed SYSTEM row on status, from_value, item,
--         action and the whole detail, and its names equalled red_names.
--   C05a: on NC_ALARM the twin read n_red 4, n_alarm 1, and its list led with
--         'plan_partition_fresh (last plan 2026-09-28, 3 night(s) missing · doctored ...)'.
--   C05b: on NC_ALL_GREEN the twin read n_red 0, n_alarm 0, list NULL.
--   C05c: on LIVE the twin read 32 checks, 3 RED — equal to the deployed row.
--   C06a/b: the live plan had 17 rows under the guard preconditions and 2 HELD_UNSETTLED rows;
--         the twin read 1 on NC_NULL_RELEASE, 1 on NC_HELD_WEAK, 0 on LIVE; the deployed check
--         measured 0 (C06c).
--
-- THE SUITE ON A BOARD WITH NO RED (measured 2026-10-01). The whole file was run over a scratch
-- copy in which every RED status on the board read GREEN and the brief's SYSTEM row was the one
-- the `system_health` twin renders over that board (status GREEN, from_value 0): 20 rows, every
-- one PASS — C04 0, C04a 0 (nothing to remove), C04b/C04c 0 (each fired), C04d 0, C04e 0, C04f 0,
-- C05c 0. The committed v27.152 file on the same board read C04a FAIL (violations 1) and scored 0
-- for a SYSTEM row saying 1 check RED over the clean board: ARRAY_AGG over zero RED rows is NULL,
-- not [], ARRAY_LENGTH(NULL) is NULL, the IF guarding C04a took its else branch, and the count
-- term `from_value != ARRAY_LENGTH(red_names)` compared against NULL and went quiet. red_names and
-- red_names_copies now pin the empty case to [] and sys_row_violations reads a NULL array as [].
-- The green branch of the rendering twin (the ELSE of status, action and detail) is copied from
-- the view; the LIVE tie in C04f exercises the RED branch only, and the green branch can be tied
-- to the deployed row only on a morning the board has no RED.
--
-- v27.156 (2026-10-02, piece-1 plan Task 2, P-18): c28's hold half reads hold_kept_by — a hold is
-- also kept while the very good day that started it is still inside the window. The twin below
-- mirrors it, NC_HELD_WEAK now names LAST_DAY on the row it weakens, and two copies that are never
-- vacuous MAKE the lowest-numbered served row HELD first: C06d (strong day one day before
-- window_from — must fire) and C06e (strong day on window_from — must not). Run 2026-10-02 (Los
-- Angeles) after deploying V_ENGINE_HEALTH v27.156: 22 rows, every one PASS; the live plan
-- (partition 2026-10-02) had 6 rows under the guard preconditions, all LAST_DAY_NOT_STRONG, and
-- 0 HELD, so C06a fired on a real row and C06b was vacuous, as its name says.
--
-- v27.160 follow-up (2026-10-03, piece-1 Task 6, second review): C02b's NC_DROP_LATEST dropped only
-- MAX(as_of). Since v27.160 the 01:35 New York pass (about 22:35 Los Angeles, day D) writes as_of
-- D+1; with that one partition dropped, D was left, due was D (the Los Angeles day the step last
-- ran), the control did not fire and C02b read FAIL. NC_DROP_LATEST now drops every partition dated
-- on or after reached_on, the Los Angeles day the plan step last ran (due when it has no run in 30
-- days); reached_on <= due, so every partition dated on or after due is dropped at every hour.
-- Measured 2026-10-03 03:53 UTC on this file's own runs / plan_nights / plan_due / plan_clock_copies
-- statements and c02b expression, comment lines stripped, CURRENT_DATE('America/Los_Angeles') and
-- CURRENT_DATE() pinned, LOG_PIPELINE_RUNS cut at the pinned instant plus simulated OK rows of
-- SP_BUILD_NEXT_WEEK_PLAN, FACT_PLAN_NEXT_WEEK's nights cut at 2026-10-02 plus simulated ones; OLD =
-- the 63192fd text, NEW = this text; jobs t6r3_c02b_{OLD,NEW,LIT}_<instant>_035333, 24 jobs, 220.6
-- slot-s, no FACT_AMAZON_ADS. C02b OLD / NEW, with NC_DROP_LATEST's last_plan against due:
--   live, 20:53 Los Angeles 10-02 (LIVE_REAL) ............................ 0 / 0  both 10-01 < 10-02
--   10:30 Los Angeles 10-02, after the 12:40 New York pass (F) ............ 0 / 0  both 10-01 < 10-02
--   22:40 Los Angeles 10-02 after a simulated 01:35 New York pass: an OK
--     row at 05:36 UTC 10-03 and a partition dated 10-03 (B) ............. 1 / 0  OLD 10-02 = due 10-02; NEW 10-01
--   the same instant, the pass rewriting 10-02 as under v27.159 (C) ...... 0 / 0
--   00:30 Los Angeles 10-03, before the 04:10 New York pass (E) ........... 1 / 0  OLD 10-02 = due 10-02; NEW 10-01
--   01:20 Los Angeles 10-03, after a simulated 04:10 New York pass: an OK
--     row at 08:11 UTC (D) ............................................... 0 / 0  due 10-03; both 10-02
-- So the old form failed from the 01:35 New York pass until the 04:10 one, past Los Angeles midnight.
-- WHY reached_on AND NOT due (LIT = NEW with `as_of < due`): LIT also reads 0 at B and E, but the
-- latest partition below due is below due whatever due is, so LIT cannot see a twin that fires a
-- day late. A twin whose due lost its reached-on term (due = Los Angeles yesterday only) reads
-- OLD 1 / NEW 1 / LIT 0 at F and at B (LAG_F, LAG_B: NEW's NC 10-01 = lagged due 10-01).
-- The whole file, run live after the change at 03:56 UTC 10-03 (20:56 Los Angeles 10-02, before
-- that night's 01:35 New York pass), job t6r3_ph_full_035632: 22 rows, every one PASS; 67,384.0
-- slot-s (63,999.7 the V_DAILY_BRIEF read, 3,342.5 the V_ENGINE_HEALTH read, the other 16
-- statements 41.8 together), 713 MB billed, 115 s.
--
-- v27.163 (2026-10-03, piece-1 plan Task 9): A1 plan_pass_failed (V_ENGINE_HEALTH c34), A2 the SYSTEM
-- line's NEW / standing reading of the board's memory (V_DAILY_BRIEF hs_meta / hs_run / health /
-- system_health), A3 the memory itself (FACT_ENGINE_HEALTH_HISTORY, SP_SNAPSHOT_ENGINE_HEALTH). C01
-- names plan_pass_failed too. The twins of `health` and `system_health` were restated to the
-- v27.163 view, and C04f ties the restated rendering to the deployed row on the live board and the
-- live memory. Each twin runs on its surface's own instant (board_at / brief_at, captured in the
-- statement that read the surface) and on LOG_PIPELINE_RUNS / FACT_ENGINE_HEALTH_HISTORY AS OF that
-- instant, so a pass writing while this file runs cannot split a twin from its view.
--   A1 copies of the plan step's runs (synthetic ones at hours before board_at): LIVE; NC_LATEST_FAIL
--      (the latest live run set FAIL); NC_FAIL_IN_24H (OK 1 h, FAIL 5 h, OK 13 h: the 09-29..10-01
--      pattern); HC_OLD_FAIL (OK 1 h, OK 13 h, FAIL 25 h: the plan's control, must read GREEN);
--      NC_NO_RUN_24H (OK 30 h); NC_LATEST_FAIL_OLD (FAIL 30 h); NC_EMPTY (no run).
--   A2 memories read against a board copy on which six named checks are RED and every other GREEN:
--      BD (snapshots 50, 26, 2 h before brief_at; X GREEN gap, U AMBER gap, V absent from the middle
--      snapshot, Y = plan_partition_fresh unbroken, Z from the middle snapshot, W RED on the board
--      only), BD_RECENT (the middle snapshot at 20 h), BD_FIRST (one snapshot, all six RED: the first
--      morning), BD_EMPTY (no snapshot). bd_expect holds the answers, from the declared times only.
--   A3 the live memory, NC_DUP (one row of the latest snapshot repeated), NC_DROP (one removed), and
--      three synthetic runs around the first snapshot (HC_ONE holds it, NC_TWO also holds a doctored
--      second snapshot a second later, NC_NONE ends an hour before it).
-- v27.163 runs (2026-10-03, after deploying V_ENGINE_HEALTH, V_DAILY_BRIEF, the table, the
-- procedure and the orchestrator; the memory held two hand-CALL snapshots, 06:29:12 and 06:56:52 UTC,
-- 34 rows each, 3 RED, the second after the board's last deploy at 06:48:16):
--   * the whole file, job bqjob_r43c4576878d111d2_000001a1008dc061_1 (--nosync, 35 statements,
--     168 s): 42 rows, every one PASS. 29,439.4 slot-s — the V_DAILY_BRIEF read 26,479.0, the
--     V_ENGINE_HEALTH read 2,849.7, the other 33 statements 110.7; 384,603,113 bytes.
--   * the same file with the brief read cut to WHERE section = 'SYSTEM' (the scorecard arms pruned),
--     job bqjob_r6731afcea40c85f2_000001a1007e981f_1: 40 rows PASS (C04f equal), 7,488.8 slot-s.
-- Intermediates, read from the whole file's temp tables (board_at 06:57:33.682, brief_at
-- 06:57:59.541 UTC), so each PASS is known to be a control that fired:
--   A1  LIVE GREEN 0 'latest plan run OK 2026-10-03 01:35 New York · 0 of 3 plan run(s) in the last
--       24 hours failed · last failure 2026-10-02 01:34 New York ...', equal to the deployed row (A1e).
--       NC_LATEST_FAIL RED 1; NC_FAIL_IN_24H RED 1 ('1 of 3 ... failed'); HC_OLD_FAIL GREEN 0 ('0 of
--       2', the 25-hour failure still named); NC_NO_RUN_24H RED 0; NC_EMPTY RED 0 ('latest plan run
--       none in 30 days'); NC_LATEST_FAIL_OLD RED 1. A1f: NC_PASS_FAILED's line RED, 'A PLAN PASS
--       FAILED — ...', 'NEW since the last snapshot (2026-10-03 02:56 New York): plan_pass_failed
--       (FAIL 2026-10-01 12:58 New York: doctored ...'.
--   A2  BD red_since X/U/V 10-03 04:57 UTC (2 h), Y 10-01 04:57 (50 h, the first snapshot), Z 10-02
--       04:57 (26 h), W none — each equal to bd_expect; the gaps-ignored form read 10-01 04:57 for
--       X, U and V (A2b: 3). BD n_red 6, n_new 4; BD_RECENT n_new 5 (Z NEW); BD_FIRST n_new 0, six
--       standing 'or earlier'; BD_EMPTY the v27.152 list plus 'the board's memory
--       (FACT_ENGINE_HEALTH_HISTORY) is empty ...'. A2c_nc: BD_RECENT's lines differ from BD's
--       expected; A2de_nc: both tests fail on BD.
--   A3  live memory 68 rows, 68 distinct (snapshot_at, check_name); NC_DUP 69 / 68 (fires); NC_DROP
--       67 (the latest snapshot misses 1); A3b judged (the board deployed before the latest
--       snapshot): 0. A3c: 0 orchestrator runs of the step logged at the run (vacuous, as named —
--       the first pass to run Refresh Task 23 starts 03:35 New York); HC_ONE 1 snapshot, NC_TWO 2,
--       NC_NONE 0.
--   LIVE SYSTEM row: 'SYSTEM: 3 checks RED — nothing NEW in the last 24 hours · standing:
--       contradiction_rate since 2026-10-03 or earlier, seat_every_occupant_numbered since
--       2026-10-03 or earlier, seat_past_due_in_future_tense since 2026-10-03 or earlier · the
--       board's memory: 2 snapshots, 2026-10-03 02:29 to 2026-10-03 02:56 New York · 34 checks ...'.
--       The v27.152 rendering of the first snapshot (plan_pass_failed left out) read 'SYSTEM: 3
--       checks RED — contradiction_rate; seat_every_occupant_numbered;
--       seat_past_due_in_future_tense · 33 checks ...'.
--
-- v27.176 (2026-10-04, learning-contract piece 2, Task 6; architecture/LEARNING.md §6): P0-P5, the
-- learning contract's three checks on V_ENGINE_HEALTH (c35-c37) and the two RED-able ones on the SYSTEM
-- line. sys_twin's `pri` list and quoting were restated with V_DAILY_BRIEF v27.176 (prediction_grades_fresh
-- 4, prediction_regression 5, every other check 6, detail quoted for pri <= 5), and A2a's emptiness term
-- counts ten rendered copies (NC_PRED_RED and NC_PRED_ORDER added to board_copies, on the live memory).
--   P0 the three checks are on the board, once each.
--   P1-P3 run V_ENGINE_HEALTH's lrn_due .. c37 text, pasted VERBATIM below (THE TWO MUST CHANGE
--      TOGETHER), once per copy on that copy's seven inputs (lrn_set .. lrn_card_meta). The inputs are
--      read as the board read them: the tables AS OF board_at, FN_ADS_ANCHOR_CAP()'s rule at board_at,
--      the ledger cut to nights built by board_at. The copies are in p_copies, what each must read on the
--      check it doctors in p_expect (status, measured or LIVE's plus a delta, a detail pattern), and
--      every check a copy does not doctor must read LIVE's row exactly (p_others). Each has an emptiness
--      term: its picks exist and every expected row was produced.
--   P5 the twin's LIVE copy equals the deployed rows (measured, threshold, status, detail) and every
--      copy ran. P4a / P4b the SYSTEM twin on the two board copies.
--   TEXT IDENTITY: the lrn_due .. c37 block below must equal V_ENGINE_HEALTH.sql's byte for byte, and the
--   deployed definition must carry it (whitespace-normalised). Check both with:
--   python3 -c "import re,json,subprocess;b=lambda t:t[t.index('\nlrn_due AS ('):t.index('\n)',t.index('\nc37 AS ('))+2];v=open('scripts/bigquery/views/V_ENGINE_HEALTH.sql').read();a=open('scripts/bigquery/tests/PLAN_HEALTH_acceptance.sql').read();d=json.loads(subprocess.check_output(['bq','query','--project_id=onyga-482313','--use_legacy_sql=false','--format=json',\"SELECT view_definition FROM \`onyga-482313.OI.INFORMATION_SCHEMA.VIEWS\` WHERE table_name='V_ENGINE_HEALTH'\"]))[0]['view_definition'];n=lambda s:re.sub(r'\s+',' ',s);print('file==acceptance',b(v)==b(a),'deployed carries it',n(b(v)) in n(d))"
--   After the deploy (V_ENGINE_HEALTH 22:47:49 UTC 2026-10-03): file==acceptance True, deployed carries it True.
-- v27.176 RUN, 2026-10-03 22:58-23:04 UTC, after deploying V_ENGINE_HEALTH and V_DAILY_BRIEF (job
-- t6_ph_full_1791068301, --nosync, 73 statements, 323 s): 49 rows, every one PASS. 68,535.0 slot-s — the
-- V_DAILY_BRIEF read 54,735.8, the V_ENGINE_HEALTH read 13,165.9, the other 71 statements 633.3;
-- 1,079,137,462 bytes. The readings, from the P section run alone on the board filtered to the three
-- checks with the same picks (job t6_ponly2_1791068157, 44 statements, 445.4 slot-s, 108 s):
--   LIVE      prediction_grades_fresh GREEN 0 ('0 of 8944 ledger rows past due have no grade · watermark
--             2026-10-02 = LEAST(FACT_AMAZON_ADS newest day 2026-10-03, FN_ADS_ANCHOR_CAP() 2026-10-02) · ...
--             8644 ledger rows not yet past due, the next when the watermark reaches 2026-10-18 ...');
--             prediction_regression INFO 0 ('YOUNG — PLAN_A: YOUNG, 1 of 6 windows graded (2026-08-23); ...');
--             response_model_unverified INFO 0 (3832 moves applied as DO_NOTHING, 198 OTHER_ACTION, 4472
--             current ACT grades).
--   P1        NC_P1_UNGRADED RED 1 (nights 2026-08-23 to 2026-08-23) · NC_P1_PAST_GRACE RED 1 (nights
--             2026-09-30 to 2026-09-30) · HC_P1_GRACE GREEN 0 (8645 not yet past due, the next on
--             2026-10-03) · NC_P1_EMPTY RED 0 ('0 of 0') · NC_P1_NO_SETTING RED 0 · NC_P1_NO_WATERMARK RED 0.
--   P2        HC_P2_FLAT GREEN 0 · NC_P2_MAE_WORSE RED 1 (PLAN_B 0.6000 against 0.5000, WORSE on accuracy,
--             'changed between them: builder_version gone pre-v27.170, builder_version new v27.171,
--             rule_version gone R0:pre-v27.170, rule_version new R0:v27.171') · HC_P2_MAE_WITHIN GREEN 0
--             (0.5400 against 0.5000) · NC_P2_CF_WORSE RED 1 (-0.2000 against -0.1000, WORSE on money) ·
--             NC_P2_YOUNG INFO 0 (5 of 6) · NC_P2_EMPTY RED 0 · NC_P2_NO_SETTING RED 0.
--   P3        NC_P3_ACT_APPLIED GREEN 1 · HC_P3_NOOP_APPLIED INFO 0 ('1 applied on rows the plan moved
--             nothing') · HC_P3_UNGRADABLE INFO 0.
--   No check a copy did not doctor moved on any copy (p_others: 0 rows differ).
--   P4a / P4b against the v27.163 list (the same two boards, job t6_pri_mut_1791068659): it reads
--   'prediction_grades_fresh' with no detail (P4a would fail) and 'plan_pass_failed (...);
--   plan_both_plans_written; prediction_grades_fresh; prediction_regression' (P4b would fail); the
--   v27.176 list reads them as the two checks expect.
--
-- plan_one_move_per_notgood (V_ENGINE_HEALTH c25) has no twin in this file: C01 only checks that it
-- is on the board. Its negative controls run the view's OWN c25 text on doctored copies of the plan,
-- in scripts/bigquery/tests/check_plan_seat_controls.py (readings HM / HS); the results are in
-- V_ENGINE_HEALTH.sql's header (v27.159).
--
-- The '(vacuous when ...)' controls C06a/C06b, and C04a's '(nothing to remove ...)', say so in
-- their names: a negative control needs a row to doctor, and a live plan with no row under the
-- guard and nothing held, or a board with no RED, is a legitimate state, not a defect — the live
-- positives C06c, C02 and C04f, and the board-with-no-RED pair C04d/C04e, are conclusive on every
-- partition and every board.
-- =============================================================================================

-- v27.163: the two surfaces' own clocks. CURRENT_TIMESTAMP() is one value inside a statement, the
-- views' included, and a new value in each statement of a script (measured 2026-10-03: two
-- statements of one script read 06:23:05 and 06:23:08). So each read records its own instant, and
-- every twin below runs on that instant and on the tables AS OF it (FOR SYSTEM_TIME AS OF): a pass
-- that writes a log row or a snapshot while this file runs cannot make a twin read what the view
-- did not.
DECLARE board_at TIMESTAMP;
DECLARE brief_at TIMESTAMP;

-- ---- the two surfaces, read ONCE each (both are planning-ceiling views; one scan apiece) ----
CREATE TEMP TABLE board AS
  SELECT check_name, measured, threshold, status, detail, CURRENT_TIMESTAMP() AS read_at
  FROM `onyga-482313.OI.V_ENGINE_HEALTH`;
SET board_at = (SELECT COALESCE(MAX(read_at), CURRENT_TIMESTAMP()) FROM board);
CREATE TEMP TABLE brief AS
  SELECT section, section_rank, source, campaign_name, item, action, from_value, to_value, status,
         detail, campaign_id, keyword_id, CURRENT_TIMESTAMP() AS read_at
  FROM `onyga-482313.OI.V_DAILY_BRIEF`;
SET brief_at = (SELECT COALESCE(MAX(read_at), CURRENT_TIMESTAMP()) FROM brief);
CREATE TEMP TABLE brief_sys AS SELECT * FROM brief WHERE section = 'SYSTEM';
-- v27.163: the board's memory as the brief read it
CREATE TEMP TABLE hist AS
  SELECT snapshot_at, check_name, status, measured, detail
  FROM `onyga-482313.OI.FACT_ENGINE_HEALTH_HISTORY` FOR SYSTEM_TIME AS OF brief_at;

-- ---- C03: pipeline_step_failing — LIVE / NC3 (fires) / NC2 (holds) copies of the run log ----
CREATE TEMP TABLE runs AS
  SELECT procedure_name, status, error_message, started_at,
         ROW_NUMBER() OVER (PARTITION BY procedure_name ORDER BY started_at DESC) AS rn
  FROM `onyga-482313.OI.LOG_PIPELINE_RUNS`
  WHERE run_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY);
-- the victim: a procedure whose three most recent runs are OK — the one with the most runs, ties
-- by name, so the choice is deterministic and the control is never run on a step already failing
CREATE TEMP TABLE victim AS
  SELECT procedure_name FROM runs GROUP BY 1
  HAVING COUNTIF(rn <= 3 AND status = 'OK') = 3
  ORDER BY COUNT(*) DESC, procedure_name LIMIT 1;
CREATE TEMP TABLE runs_copies AS
  SELECT 'LIVE' AS copy, procedure_name, status, started_at, rn FROM runs
  UNION ALL
  SELECT 'NC3', r.procedure_name,
         IF(r.procedure_name = v.procedure_name AND r.rn <= 3, 'FAIL', r.status), r.started_at, r.rn
  FROM runs r CROSS JOIN victim v
  UNION ALL
  SELECT 'NC2', r.procedure_name,
         IF(r.procedure_name = v.procedure_name AND r.rn <= 2, 'FAIL', r.status), r.started_at, r.rn
  FROM runs r CROSS JOIN victim v;
-- TWIN of V_ENGINE_HEALTH c32 (pipe_fail): three most recent runs, all FAIL
CREATE TEMP TABLE pipe_fired AS
  SELECT copy, procedure_name
  FROM runs_copies WHERE rn <= 3
  GROUP BY 1, 2
  HAVING COUNT(*) = 3 AND COUNTIF(status = 'FAIL') = 3;

-- ---- C02b: plan_partition_fresh — LIVE / every partition from the step's last day dropped / no partition ----
CREATE TEMP TABLE plan_nights AS SELECT DISTINCT as_of FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`;
-- TWIN of V_ENGINE_HEALTH c31 (plan_clock): due = the later of the Los Angeles day the plan step
-- last ran (OK or FAIL) and yesterday; RED when the latest plan is older than that, or absent.
-- reached_on is the first of the two days alone (NULL when the step has no run in 30 days).
CREATE TEMP TABLE plan_due AS
  SELECT reached_on,
         GREATEST(COALESCE(reached_on, DATE '1900-01-01'),
                  DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY)) AS due
  FROM (SELECT MAX(DATE(started_at, 'America/Los_Angeles')) AS reached_on FROM runs
        WHERE procedure_name = 'SP_BUILD_NEXT_WEEK_PLAN');
-- NC_DROP_LATEST drops EVERY partition dated on or after the Los Angeles day the plan step last ran
-- (due when the step has no run), not only MAX(as_of). reached_on <= due, so every partition dated
-- on or after due is dropped at every hour. Since v27.160 the 01:35 New York pass (about 22:35 Los
-- Angeles, day D) writes as_of D+1; dropping only that one left D = due, and the control did not
-- fire from that pass until the 04:10 New York pass (measured 2026-10-03, see the header).
CREATE TEMP TABLE plan_clock_copies AS
  SELECT c.copy, c.last_plan, d.due
  FROM (SELECT 'LIVE' AS copy, MAX(as_of) AS last_plan FROM plan_nights
        UNION ALL
        SELECT 'NC_DROP_LATEST', MAX(as_of) FROM plan_nights
        WHERE as_of < (SELECT COALESCE(reached_on, due) FROM plan_due)
        UNION ALL
        SELECT 'NC_EMPTY', MAX(as_of) FROM plan_nights WHERE FALSE) c
  CROSS JOIN plan_due d;

-- ---- C06: plan_settle_guard_holds — LIVE / one release nulled / one hold weakened ----
CREATE TEMP TABLE plb AS
  SELECT *,
         (side = 'NOT_GOOD' AND COALESCE(was_good, FALSE) AND COALESCE(served, FALSE)
          AND NOT COALESCE(settled, FALSE)) AS under_guard,
         ROW_NUMBER() OVER (ORDER BY campaign_id, keyword_id) AS rn
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`) AND is_live_plan;
CREATE TEMP TABLE plb_copies AS
  SELECT 'LIVE' AS copy, * FROM plb
  UNION ALL
  SELECT 'NC_NULL_RELEASE', * REPLACE (
    IF(rn = (SELECT MIN(rn) FROM plb WHERE under_guard), NULL, guard_released_by) AS guard_released_by)
  FROM plb
  UNION ALL
  SELECT 'NC_HELD_WEAK', * REPLACE (
    IF(rn = (SELECT MIN(rn) FROM plb WHERE verdict = 'HELD_UNSETTLED'), FALSE, last_day_strong) AS last_day_strong,
    IF(rn = (SELECT MIN(rn) FROM plb WHERE verdict = 'HELD_UNSETTLED'), 'LAST_DAY', hold_kept_by) AS hold_kept_by)
  FROM plb
  -- v27.156 (P-18): a hold kept by the very good day that started it. The live plan may hold
  -- nothing, so these two copies MAKE the lowest-numbered served row a HELD row first; they are
  -- never vacuous. Strong day one day before window_from -> fires; on window_from -> holds.
  UNION ALL
  SELECT 'NC_HELD_SD_OUT', * REPLACE (
    IF(rn = (SELECT MIN(rn) FROM plb WHERE served), 'HELD_UNSETTLED', verdict) AS verdict,
    IF(rn = (SELECT MIN(rn) FROM plb WHERE served), FALSE, last_day_strong) AS last_day_strong,
    IF(rn = (SELECT MIN(rn) FROM plb WHERE served), 'STRONG_DAY_IN_WINDOW', hold_kept_by) AS hold_kept_by,
    IF(rn = (SELECT MIN(rn) FROM plb WHERE served), DATE_SUB(window_from, INTERVAL 1 DAY), hold_strong_day) AS hold_strong_day)
  FROM plb
  UNION ALL
  SELECT 'HC_HELD_SD_IN', * REPLACE (
    IF(rn = (SELECT MIN(rn) FROM plb WHERE served), 'HELD_UNSETTLED', verdict) AS verdict,
    IF(rn = (SELECT MIN(rn) FROM plb WHERE served), FALSE, last_day_strong) AS last_day_strong,
    IF(rn = (SELECT MIN(rn) FROM plb WHERE served), 'STRONG_DAY_IN_WINDOW', hold_kept_by) AS hold_kept_by,
    IF(rn = (SELECT MIN(rn) FROM plb WHERE served), window_from, hold_strong_day) AS hold_strong_day)
  FROM plb;
-- TWIN of V_ENGINE_HEALTH c28 (guard): the two COUNTIFs that make its measured value
-- (v27.156: the hold half reads hold_kept_by, P-18)
CREATE TEMP TABLE guard_fired AS
  SELECT copy,
         COUNTIF(under_guard AND COALESCE(guard_released_by, '') NOT IN ('HOLD_EXPIRED', 'LAST_DAY_NOT_STRONG'))
       + COUNTIF(verdict = 'HELD_UNSETTLED'
                 AND NOT (COALESCE(last_day_strong, FALSE)
                          OR (COALESCE(hold_kept_by, '') = 'STRONG_DAY_IN_WINDOW'
                              AND COALESCE(window_from <= hold_strong_day, FALSE)))) AS v
  FROM plb_copies GROUP BY 1;

-- ---- A1 (v27.163): plan_pass_failed — LIVE / doctored copies of the plan step's runs ----
-- LIVE is the log AS THE BOARD READ IT, and the twin's clock is the board's own instant (board_at),
-- so its 24-hour fence and its 30-day window are the view's.
CREATE TEMP TABLE ppr_live AS
  SELECT status, error_message, started_at
  FROM `onyga-482313.OI.LOG_PIPELINE_RUNS` FOR SYSTEM_TIME AS OF board_at
  WHERE procedure_name = 'SP_BUILD_NEXT_WEEK_PLAN'
    AND run_date >= DATE_SUB(DATE(board_at), INTERVAL 30 DAY);
CREATE TEMP TABLE ppr_copies AS
  SELECT 'LIVE' AS copy, status, error_message, started_at FROM ppr_live
  UNION ALL
  -- the plan's control: the latest live run doctored FAIL
  SELECT 'NC_LATEST_FAIL',
         IF(started_at = (SELECT MAX(started_at) FROM ppr_live), 'FAIL', status),
         IF(started_at = (SELECT MAX(started_at) FROM ppr_live), 'doctored: negative control NC_LATEST_FAIL', error_message),
         started_at
  FROM ppr_live
  UNION ALL
  SELECT k.copy, k.s, k.e, TIMESTAMP_SUB(board_at, INTERVAL k.h HOUR)
  FROM UNNEST([
    -- the piece-0 pattern (3 of 9 passes 09-29..10-01): the latest run OK, an earlier pass of the day refused
    STRUCT<copy STRING, s STRING, e STRING, h INT64>('NC_FAIL_IN_24H', 'OK', NULL, 1),
    ('NC_FAIL_IN_24H', 'FAIL', 'doctored: negative control NC_FAIL_IN_24H', 5),
    ('NC_FAIL_IN_24H', 'OK', NULL, 13),
    -- the plan's holding control: the latest run OK after a failure older than 24 hours
    ('HC_OLD_FAIL', 'OK', NULL, 1), ('HC_OLD_FAIL', 'OK', NULL, 13),
    ('HC_OLD_FAIL', 'FAIL', 'doctored: holding control HC_OLD_FAIL', 25),
    -- emptiness: the step logged no run in the last 24 hours
    ('NC_NO_RUN_24H', 'OK', NULL, 30),
    -- the latest run failed, more than 24 hours ago
    ('NC_LATEST_FAIL_OLD', 'FAIL', 'doctored: negative control NC_LATEST_FAIL_OLD', 30)
  ]) AS k;
-- TWIN of V_ENGINE_HEALTH ppr / ppf / c34 (v27.163), per copy, CURRENT_TIMESTAMP() read as board_at.
-- NC_EMPTY (no run at all in 30 days) is a copy with no row: the LEFT JOIN keeps it.
CREATE TEMP TABLE ppf_twin AS
  WITH ppr AS (
    SELECT copy, status, error_message, started_at,
           ROW_NUMBER() OVER (PARTITION BY copy ORDER BY started_at DESC) AS rn
    FROM ppr_copies
  ),
  ppf AS (
    SELECT c.copy,
           COUNTIF(status = 'FAIL' AND (rn = 1 OR started_at >= TIMESTAMP_SUB(board_at, INTERVAL 24 HOUR))) AS n_fail,
           COUNTIF(started_at >= TIMESTAMP_SUB(board_at, INTERVAL 24 HOUR)) AS n_24h,
           COUNTIF(status = 'FAIL' AND started_at >= TIMESTAMP_SUB(board_at, INTERVAL 24 HOUR)) AS n_fail_24h,
           MAX(IF(rn = 1, status, NULL)) AS latest_status,
           MAX(IF(rn = 1, started_at, NULL)) AS latest_at,
           ARRAY_AGG(IF(status = 'FAIL' AND (rn = 1 OR started_at >= TIMESTAMP_SUB(board_at, INTERVAL 24 HOUR)),
                        STRUCT(started_at AS fail_at, error_message AS fail_msg), NULL)
                     IGNORE NULLS ORDER BY started_at DESC LIMIT 1)[SAFE_OFFSET(0)] AS fail,
           MAX(IF(status = 'FAIL', started_at, NULL)) AS last_fail_30d
    FROM (SELECT cp AS copy FROM UNNEST(['LIVE', 'NC_LATEST_FAIL', 'NC_FAIL_IN_24H', 'HC_OLD_FAIL',
                                          'NC_NO_RUN_24H', 'NC_LATEST_FAIL_OLD', 'NC_EMPTY']) AS cp) c
    LEFT JOIN ppr ON ppr.copy = c.copy
    GROUP BY c.copy
  )
  SELECT copy,
    CAST(n_fail AS FLOAT64) AS measured,
    CASE WHEN n_24h = 0 THEN 'RED' WHEN n_fail > 0 THEN 'RED' ELSE 'GREEN' END AS status,
    CONCAT(
      IF(fail.fail_at IS NOT NULL,
         CONCAT('FAIL ', FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', fail.fail_at, 'America/New_York'), ' New York: ',
                SUBSTR(COALESCE(fail.fail_msg, '(no message)'), 1, 160), ' · '),
         ''),
      IF(n_24h = 0,
         'no plan run logged in the last 24 hours · ',
         ''),
      'latest plan run ', COALESCE(latest_status, 'none'), ' ',
      COALESCE(CONCAT(FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', latest_at, 'America/New_York'), ' New York'), 'in 30 days'),
      ' · ', CAST(n_fail_24h AS STRING), ' of ', CAST(n_24h AS STRING), ' plan run(s) in the last 24 hours failed',
      ' · last failure ', COALESCE(CONCAT(FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', last_fail_30d, 'America/New_York'), ' New York'), 'none in 30 days'),
      ' · the step is SP_BUILD_NEXT_WEEK_PLAN (Refresh Task 20.8c); nothing re-runs a failed pass by itself') AS detail
  FROM ppf;

-- ---- C05 / A2: the brief's SYSTEM line — copies of the board, each read against a copy of the memory ----
-- v27.163 A2: six checks forced RED on an otherwise GREEN board, each with a run of its own in the
-- synthetic memories below. Y is an alarm (its detail is quoted); the other five are plain checks.
-- All six are on the board (C01 names them), so a missing one fails A2a/A2c rather than passing.
CREATE TEMP TABLE bd_names AS
  SELECT * FROM UNNEST([
    -- role, check, its status on snapshots 1, 2, 3 (R RED, A AMBER, G GREEN, - absent)
    STRUCT<role STRING, name STRING, pat STRING>('X', 'plan_both_plans_written', 'RGR'),   -- a GREEN gap
    ('U', 'plan_one_move_per_notgood', 'RAR'),                                              -- an AMBER gap
    ('V', 'plan_pot_reconciliation', 'R-R'),                                                -- absent from a snapshot
    ('Y', 'plan_partition_fresh', 'RRR'),                                                   -- unbroken since the memory began
    ('Z', 'plan_proposal_lag_days', 'GRR'),                                                 -- run from snapshot 2
    ('W', 'plan_window_complete_days', 'GGG')                                               -- RED on the board only
  ]);
CREATE TEMP TABLE board_copies AS
  SELECT 'LIVE' AS copy, check_name, status, detail FROM board
  UNION ALL
  SELECT 'NC_ALL_GREEN', check_name, IF(status = 'RED', 'GREEN', status), detail FROM board
  UNION ALL
  SELECT 'NC_ALARM', check_name,
         IF(check_name = 'plan_partition_fresh', 'RED', status),
         IF(check_name = 'plan_partition_fresh',
            'last plan 2026-09-28, 3 night(s) missing · doctored: negative control NC_ALARM', detail)
  FROM board
  UNION ALL
  -- v27.163: plan_pass_failed doctored RED on an otherwise green board
  SELECT 'NC_PASS_FAILED', check_name,
         IF(check_name = 'plan_pass_failed', 'RED', IF(status = 'RED', 'GREEN', status)),
         IF(check_name = 'plan_pass_failed',
            'FAIL 2026-10-01 12:58 New York: doctored: negative control NC_PASS_FAILED · latest plan run OK 2026-10-02 04:05 New York', detail)
  FROM board
  UNION ALL
  -- v27.176 P4a: prediction_grades_fresh doctored RED on an otherwise green board
  SELECT 'NC_PRED_RED', check_name,
         IF(check_name = 'prediction_grades_fresh', 'RED', IF(status = 'RED', 'GREEN', status)),
         IF(check_name = 'prediction_grades_fresh',
            '3 of 8944 ledger rows past due have no grade (nights 2026-08-23 to 2026-08-23) · doctored: negative control NC_PRED_RED', detail)
  FROM board
  UNION ALL
  -- v27.176 P4b: plan_pass_failed, the two learning checks and one plain check RED, every other GREEN
  SELECT 'NC_PRED_ORDER', check_name,
         IF(check_name IN ('plan_pass_failed', 'prediction_grades_fresh', 'prediction_regression', 'plan_both_plans_written'),
            'RED', IF(status = 'RED', 'GREEN', status)),
         CASE check_name WHEN 'plan_pass_failed'        THEN 'doctored: NC_PRED_ORDER pass'
                         WHEN 'prediction_grades_fresh' THEN 'doctored: NC_PRED_ORDER grades'
                         WHEN 'prediction_regression'   THEN 'doctored: NC_PRED_ORDER regression'
                         ELSE detail END
  FROM board
  UNION ALL
  -- v27.163 A2: the six RED, everything else GREEN, read against four memories
  SELECT cp, b.check_name, IF(n.name IS NOT NULL, 'RED', 'GREEN'), b.detail
  FROM board b
  LEFT JOIN bd_names n ON n.name = b.check_name
  CROSS JOIN UNNEST(['BD', 'BD_EMPTY', 'BD_FIRST', 'BD_RECENT']) AS cp;
-- the memory each copy is read against. LIVE, the three v27.152 copies, NC_PASS_FAILED and (v27.176)
-- NC_PRED_RED / NC_PRED_ORDER read the live memory.
-- BD: snapshots 50, 26 and 2 hours before the brief's read; BD_RECENT: 50, 20 and 2 (Z's run then
-- starts inside the 24 hours); BD_FIRST: one snapshot an hour before, the six RED on it (the first
-- morning of a memory); BD_EMPTY: none.
CREATE TEMP TABLE hist_copies AS
  SELECT cp AS copy, snapshot_at, check_name, status
  FROM hist CROSS JOIN UNNEST(['LIVE', 'NC_ALL_GREEN', 'NC_ALARM', 'NC_PASS_FAILED', 'NC_PRED_RED', 'NC_PRED_ORDER']) AS cp
  UNION ALL
  SELECT k.copy, TIMESTAMP_SUB(brief_at, INTERVAL k.h HOUR), b.check_name,
         CASE SUBSTR(COALESCE(n.pat, 'GGG'), k.slot, 1) WHEN 'R' THEN 'RED' WHEN 'A' THEN 'AMBER' ELSE 'GREEN' END
  FROM board b
  LEFT JOIN bd_names n ON n.name = b.check_name
  CROSS JOIN UNNEST([STRUCT<copy STRING, slot INT64, h INT64>('BD', 1, 50), ('BD', 2, 26), ('BD', 3, 2),
                     ('BD_RECENT', 1, 50), ('BD_RECENT', 2, 20), ('BD_RECENT', 3, 2)]) AS k
  WHERE SUBSTR(COALESCE(n.pat, 'GGG'), k.slot, 1) != '-'
  UNION ALL
  SELECT 'BD_FIRST', TIMESTAMP_SUB(brief_at, INTERVAL 1 HOUR), b.check_name, IF(n.name IS NOT NULL, 'RED', 'GREEN')
  FROM board b LEFT JOIN bd_names n ON n.name = b.check_name;
-- TWIN of V_DAILY_BRIEF hs_meta / hs_run (v27.163), per copy
CREATE TEMP TABLE hs_meta_twin AS
  SELECT c.copy, COUNT(DISTINCT h.snapshot_at) AS n_snaps, MIN(h.snapshot_at) AS first_at, MAX(h.snapshot_at) AS last_at
  FROM (SELECT DISTINCT copy FROM board_copies) c
  LEFT JOIN hist_copies h ON h.copy = c.copy
  GROUP BY 1;
CREATE TEMP TABLE hs_run_twin AS
  SELECT copy, check_name,
         MIN(IF(snapshot_at > COALESCE(last_break, TIMESTAMP '1900-01-01'), snapshot_at, NULL)) AS red_since
  FROM (SELECT s.copy, s.snapshot_at, c.check_name,
               MAX(IF(r.check_name IS NULL, s.snapshot_at, NULL)) OVER (PARTITION BY s.copy, c.check_name) AS last_break
        FROM (SELECT DISTINCT copy, snapshot_at FROM hist_copies) s
        JOIN (SELECT DISTINCT copy, check_name FROM hist_copies) c ON c.copy = s.copy
        LEFT JOIN (SELECT DISTINCT copy, snapshot_at, check_name FROM hist_copies WHERE status = 'RED') r
          ON r.copy = s.copy AND r.snapshot_at = s.snapshot_at AND r.check_name = c.check_name)
  GROUP BY 1, 2;
-- TWIN of V_DAILY_BRIEF `health` (v27.152, v27.163, v27.176: prediction_grades_fresh 4 and
-- prediction_regression 5 in `pri`, every other check 6, detail quoted for pri <= 5): the aggregate the
-- SYSTEM line is built from, CURRENT_TIMESTAMP() read as brief_at
CREATE TEMP TABLE sys_twin AS
  SELECT copy,
         COUNT(*) AS n_checks,
         COUNTIF(status = 'RED') AS n_red,
         COUNTIF(status = 'RED' AND pri <= 2) AS n_alarm,
         COUNTIF(status = 'RED' AND pri = 3) AS n_pass_failed,
         COUNTIF(status = 'RED' AND is_new) AS n_new,
         STRING_AGG(IF(status = 'RED', said, NULL), '; ' ORDER BY pri, check_name) AS red_list,
         STRING_AGG(IF(status = 'RED' AND is_new,
                       CONCAT('NEW since ',
                              IF(red_since IS NULL,
                                 CONCAT('the last snapshot (', FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', last_at, 'America/New_York'), ' New York)'),
                                 CONCAT(FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', red_since, 'America/New_York'), ' New York')),
                              ': ', said),
                       NULL), '; ' ORDER BY pri, check_name) AS new_list,
         STRING_AGG(IF(status = 'RED' AND NOT is_new AND n_snaps > 0,
                       CONCAT(check_name, ' since ', FORMAT_TIMESTAMP('%Y-%m-%d', red_since, 'America/New_York'),
                              IF(red_since = first_at, ' or earlier', ''),
                              IF(pri <= 5, CONCAT(' (', COALESCE(detail, 'no detail'), ')'), '')),
                       NULL), ', ' ORDER BY pri, check_name) AS standing_list,
         COALESCE(MAX(IF(check_name = 'plan_partition_fresh',  SPLIT(detail, ' · ')[SAFE_OFFSET(0)], NULL)),
                  'plan_partition_fresh is not on the board') AS plan_clause,
         COALESCE(MAX(IF(check_name = 'plan_pass_failed',      SPLIT(detail, ' · ')[SAFE_OFFSET(0)], NULL)),
                  'plan_pass_failed is not on the board') AS pass_clause,
         COALESCE(MAX(IF(check_name = 'pipeline_step_failing', SPLIT(detail, ' · ')[SAFE_OFFSET(0)], NULL)),
                  'pipeline_step_failing is not on the board') AS pipe_clause
  FROM (SELECT *,
               IF(pri <= 5, CONCAT(check_name, ' (', COALESCE(detail, 'no detail'), ')'), check_name) AS said,
               (status = 'RED' AND n_snaps > 0
                AND (red_since IS NULL
                     OR (red_since > first_at
                         AND red_since >= TIMESTAMP_SUB(brief_at, INTERVAL 24 HOUR)))) AS is_new
        FROM (SELECT b.copy, b.check_name, b.status, b.detail, r.red_since, m.n_snaps, m.first_at, m.last_at,
                     CASE b.check_name WHEN 'pipeline_step_failing'   THEN 1
                                       WHEN 'plan_partition_fresh'    THEN 2
                                       WHEN 'plan_pass_failed'        THEN 3
                                       WHEN 'prediction_grades_fresh' THEN 4
                                       WHEN 'prediction_regression'   THEN 5
                                       ELSE 6 END AS pri
              FROM board_copies b
              LEFT JOIN hs_run_twin r ON r.copy = b.copy AND r.check_name = b.check_name
              JOIN hs_meta_twin m ON m.copy = b.copy))
  GROUP BY copy;
-- the board's RED names, per copy. ARRAY_AGG over zero RED rows is NULL, not []: ARRAY_LENGTH(NULL)
-- is NULL, every IF on it takes its else branch and every != against it goes quiet, so the empty
-- case is pinned to [] here (and in red_names below), and the row test never sees a NULL array.
-- IGNORE NULLS keeps a copy with no RED row as a row of its own; a WHERE status = 'RED' would drop it.
CREATE TEMP TABLE red_names_copies AS
  SELECT copy,
         COALESCE(ARRAY_AGG(IF(status = 'RED', check_name, NULL) IGNORE NULLS ORDER BY check_name), []) AS names
  FROM board_copies GROUP BY 1;
-- TWIN of V_DAILY_BRIEF `system_health` (v27.152, v27.163): the SYSTEM row as the brief renders it
-- from the aggregate above — the deployed view cannot be pointed at a doctored board or memory, so
-- this is how the row test is run on one. C04f ties the LIVE rendering to the deployed row; the
-- branches the live board does not take (all green, an empty memory, a NEW RED) are copied from the
-- view and tied live only on a morning the board takes them.
CREATE TEMP TABLE sys_rows AS
  SELECT t.copy, 1 AS n_rows, 7 AS section_rank,
         CASE WHEN t.n_checks = 0 THEN 'RED' WHEN t.n_red > 0 THEN 'RED' ELSE 'GREEN' END AS status,
         CAST(t.n_red AS FLOAT64) AS from_value,
         CONCAT('SYSTEM: ', CAST(t.n_red AS STRING), ' check', IF(t.n_red = 1, '', 's'), ' RED',
                CASE WHEN t.n_red = 0 THEN
                       CONCAT(' — every check on the board is green, amber or a report · ',
                              COALESCE(t.plan_clause, 'no plan clause'), ' · ', COALESCE(t.pass_clause, 'no plan run clause'),
                              ' · ', COALESCE(t.pipe_clause, 'no pipeline clause'))
                     WHEN m.n_snaps = 0 THEN
                       CONCAT(' — ', COALESCE(t.red_list, '(the list could not be built)'))
                     ELSE
                       CONCAT(' — ', COALESCE(t.new_list, 'nothing NEW in the last 24 hours'),
                              IF(t.standing_list IS NULL, '', CONCAT(' · standing: ', t.standing_list)))
                END,
                ' · ',
                IF(m.n_snaps = 0,
                   'the board\'s memory (FACT_ENGINE_HEALTH_HISTORY) is empty, so this line cannot tell a new RED from a standing one',
                   FORMAT('the board\'s memory: %d snapshot%s, %s to %s New York', m.n_snaps, IF(m.n_snaps = 1, '', 's'),
                          FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', m.first_at, 'America/New_York'),
                          FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', m.last_at, 'America/New_York'))),
                ' · ', CAST(t.n_checks AS STRING), ' checks read live from V_ENGINE_HEALTH',
                '; the board: SELECT check_name, measured, status, threshold, detail FROM V_ENGINE_HEALTH ORDER BY status = \'GREEN\', check_name') AS detail,
         FORMAT('%d of %d checks RED', t.n_red, t.n_checks) AS item,
         CASE WHEN t.n_checks = 0 THEN 'the board is empty — V_ENGINE_HEALTH returned no rows; read the view by hand before trusting anything above this line'
              WHEN t.n_alarm > 0 THEN 'A NIGHT WAS NOT SAVED — read the failing step\'s error in this line, fix it, and run the step by hand; nothing re-runs it for you, and PLANNED above may be quoting a plan older than it looks'
              WHEN t.n_pass_failed > 0 THEN 'A PLAN PASS FAILED — read the error quoted in this line and fix its cause; nothing re-runs a failed pass for you'
              WHEN t.n_new > 0 THEN 'a NEW check is RED — read the one(s) after NEW in this line on V_ENGINE_HEALTH first; each names what it measures and what breaks when it fires'
              WHEN t.n_red > 0 THEN 'read the RED rows on V_ENGINE_HEALTH — each names what it measures and what breaks when it fires'
              ELSE 'nothing to do — no check is RED' END AS action,
         CAST(NULL AS STRING) AS campaign_id, CAST(NULL AS STRING) AS keyword_id,
         r.names
  FROM sys_twin t JOIN red_names_copies r USING (copy) JOIN hs_meta_twin m USING (copy);
-- A2's expected answers on the BD memories, from the declared snapshot times (brief_at − 50 h, − 26 h
-- or − 20 h, − 2 h): never from the twin
CREATE TEMP TABLE bd_expect AS
  SELECT n.role, n.name,
         CASE n.role WHEN 'X' THEN TIMESTAMP_SUB(brief_at, INTERVAL 2 HOUR)
                     WHEN 'U' THEN TIMESTAMP_SUB(brief_at, INTERVAL 2 HOUR)
                     WHEN 'V' THEN TIMESTAMP_SUB(brief_at, INTERVAL 2 HOUR)
                     WHEN 'Y' THEN TIMESTAMP_SUB(brief_at, INTERVAL 50 HOUR)
                     WHEN 'Z' THEN TIMESTAMP_SUB(brief_at, INTERVAL 26 HOUR)
                     ELSE NULL END AS red_since,
         -- the form A2b refutes: the earliest RED snapshot, gaps ignored
         CASE WHEN STRPOS(n.pat, 'R') = 0 THEN NULL
              ELSE TIMESTAMP_SUB(brief_at, INTERVAL [50, 26, 2][OFFSET(STRPOS(n.pat, 'R') - 1)] HOUR) END AS earliest_red
  FROM bd_names n;
-- A2c's expected NEW and standing lists on BD, from the declared times and Y's live detail
CREATE TEMP TABLE bd_lines AS
  SELECT CONCAT(
           'NEW since ', FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', TIMESTAMP_SUB(brief_at, INTERVAL 2 HOUR), 'America/New_York'), ' New York: plan_both_plans_written; ',
           'NEW since ', FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', TIMESTAMP_SUB(brief_at, INTERVAL 2 HOUR), 'America/New_York'), ' New York: plan_one_move_per_notgood; ',
           'NEW since ', FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', TIMESTAMP_SUB(brief_at, INTERVAL 2 HOUR), 'America/New_York'), ' New York: plan_pot_reconciliation; ',
           'NEW since the last snapshot (', FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', TIMESTAMP_SUB(brief_at, INTERVAL 2 HOUR), 'America/New_York'), ' New York): plan_window_complete_days') AS exp_new,
         CONCAT(
           'plan_partition_fresh since ', FORMAT_TIMESTAMP('%Y-%m-%d', TIMESTAMP_SUB(brief_at, INTERVAL 50 HOUR), 'America/New_York'), ' or earlier (',
           (SELECT detail FROM board WHERE check_name = 'plan_partition_fresh'), '), ',
           'plan_proposal_lag_days since ', FORMAT_TIMESTAMP('%Y-%m-%d', TIMESTAMP_SUB(brief_at, INTERVAL 26 HOUR), 'America/New_York')) AS exp_standing;

-- ---- A3 (v27.163): the snapshot table, as the brief read it ----
-- every OK run of the snapshot step the orchestrator logged (a hand CALL logs none)
CREATE TEMP TABLE snap_runs AS
  SELECT started_at, finished_at
  FROM `onyga-482313.OI.LOG_PIPELINE_RUNS` FOR SYSTEM_TIME AS OF brief_at
  WHERE procedure_name = 'SP_SNAPSHOT_ENGINE_HEALTH' AND status = 'OK' AND run_date >= DATE '2026-10-03';
-- the memory's snapshot times, and a doctored memory (TWO) with a second snapshot one second after the first
CREATE TEMP TABLE snap_times AS
  SELECT 'LIVE' AS mem, snapshot_at FROM (SELECT DISTINCT snapshot_at FROM hist)
  UNION ALL
  SELECT 'TWO', snapshot_at FROM (SELECT DISTINCT snapshot_at FROM hist)
  UNION ALL
  SELECT 'TWO', TIMESTAMP_ADD(MIN(snapshot_at), INTERVAL 1 SECOND) FROM hist;
-- the runs judged: the live log's OK runs against the live memory, and three synthetic runs around the
-- FIRST snapshot — HC_ONE holds it, NC_TWO holds it and the doctored second one, NC_NONE ends an hour
-- before it. The synthetic three make A3c's controls independent of whether a pass has run the step.
CREATE TEMP TABLE snap_run_copies AS
  SELECT 'LIVE' AS copy, 'LIVE' AS mem, started_at, finished_at FROM snap_runs
  UNION ALL
  SELECT 'HC_ONE', 'LIVE', TIMESTAMP_SUB(MIN(snapshot_at), INTERVAL 1 SECOND), TIMESTAMP_ADD(MIN(snapshot_at), INTERVAL 60 SECOND) FROM hist
  UNION ALL
  SELECT 'NC_TWO', 'TWO', TIMESTAMP_SUB(MIN(snapshot_at), INTERVAL 1 SECOND), TIMESTAMP_ADD(MIN(snapshot_at), INTERVAL 60 SECOND) FROM hist
  UNION ALL
  SELECT 'NC_NONE', 'LIVE', TIMESTAMP_SUB(MIN(snapshot_at), INTERVAL 2 HOUR), TIMESTAMP_SUB(MIN(snapshot_at), INTERVAL 1 HOUR) FROM hist;
CREATE TEMP TABLE snap_per_run AS
  SELECT r.copy, r.started_at, COUNT(DISTINCT t.snapshot_at) AS n_snaps
  FROM snap_run_copies r
  LEFT JOIN snap_times t ON t.mem = r.mem AND t.snapshot_at BETWEEN r.started_at AND r.finished_at
  GROUP BY 1, 2;
-- nothing twice / one row per check, run on the live memory and on two doctored copies of it:
-- NC_DUP repeats one row of the latest snapshot, NC_DROP removes one
CREATE TEMP TABLE hist_dup_copies AS
  SELECT 'LIVE' AS copy, snapshot_at, check_name FROM hist
  UNION ALL
  SELECT 'NC_DUP', snapshot_at, check_name FROM hist
  UNION ALL
  SELECT 'NC_DUP', snapshot_at, MIN(check_name) FROM hist
  WHERE snapshot_at = (SELECT MAX(snapshot_at) FROM hist) GROUP BY snapshot_at
  UNION ALL
  SELECT 'NC_DROP', snapshot_at, check_name FROM hist
  WHERE NOT (snapshot_at = (SELECT MAX(snapshot_at) FROM hist)
             AND check_name = (SELECT MIN(check_name) FROM hist WHERE snapshot_at = (SELECT MAX(snapshot_at) FROM hist)));

-- ---- P (v27.176): the learning contract's checks, V_ENGINE_HEALTH c35-c37, on doctored copies ----
-- The seven inputs as the board read them: the tables AS OF board_at, FN_ADS_ANCHOR_CAP()'s rule at
-- board_at (the function reads the clock and cannot be pointed at an instant: its body is two lines,
-- scripts/bigquery/functions/FN_ADS_ANCHOR_CAP.sql), and the ledger — a view, which time travel cannot
-- read — cut to the nights built by board_at. P5 ties the LIVE copy to the deployed rows, so a drift
-- between these inputs and the view's own input CTEs fails there.
CREATE TEMP TABLE p_set AS
  SELECT CAST(MAX(IF(threshold_key = 'SETTLE_HORIZON_DAYS', threshold_value, NULL)) AS INT64) AS settle_days,
         CAST(MAX(IF(threshold_key = 'MIN_GRADED_WINDOWS', threshold_value, NULL)) AS INT64) AS min_windows,
         MAX(IF(threshold_key = 'REGRESSION_MAX', threshold_value, NULL)) AS regression_max
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS` FOR SYSTEM_TIME AS OF board_at
  WHERE strategy_id = 'LEARNING' AND coach_mode = 'GUARDIAN' AND product_family IS NULL
    AND threshold_key IN ('SETTLE_HORIZON_DAYS', 'MIN_GRADED_WINDOWS', 'REGRESSION_MAX');
CREATE TEMP TABLE p_wm AS
  SELECT MAX(date) AS ads_max,
         IF(EXTRACT(HOUR FROM DATETIME(board_at, 'America/Los_Angeles')) >= 22,
            DATE(board_at, 'America/Los_Angeles'),
            DATE_SUB(DATE(board_at, 'America/Los_Angeles'), INTERVAL 1 DAY)) AS anchor_cap
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` FOR SYSTEM_TIME AS OF board_at;
CREATE TEMP TABLE p_led AS
  SELECT predictor, variant, as_of, campaign_id, keyword_id, scenario, horizon_to
  FROM `onyga-482313.OI.V_PREDICTION_LEDGER`
  WHERE built_at <= board_at;
CREATE TEMP TABLE p_grd0 AS
  SELECT predictor, variant, as_of, campaign_id, keyword_id, scenario, regrade_seq,
         is_applied, act_is_noop, applied_scenario, grade
  FROM `onyga-482313.OI.FACT_PREDICTION_GRADE` FOR SYSTEM_TIME AS OF board_at
  WHERE predictor <> 'FIXTURE';
-- the current ACT grades, numbered so a control can pick one
CREATE TEMP TABLE p_act0 AS
  SELECT predictor, variant, as_of, campaign_id, keyword_id, is_applied, act_is_noop, applied_scenario, grade,
         ROW_NUMBER() OVER (ORDER BY as_of, predictor, variant, campaign_id, keyword_id) AS rn
  FROM (SELECT * FROM p_grd0 WHERE scenario = 'ACT'
        QUALIFY ROW_NUMBER() OVER (PARTITION BY predictor, variant, as_of, campaign_id, keyword_id, scenario
                                   ORDER BY regrade_seq DESC) = 1);
CREATE TEMP TABLE p_card0 AS
  SELECT * FROM `onyga-482313.OI.T_PREDICTION_SCORECARD` FOR SYSTEM_TIME AS OF board_at
  WHERE predictor <> 'FIXTURE';
-- the picks: the first past-due ledger row that holds a grade (NC_P1_UNGRADED removes its grade), the
-- first current ACT grade with a move and not UNGRADABLE, the first with no move (P3 apply them)
CREATE TEMP TABLE p_pick AS
SELECT
  (SELECT AS STRUCT l.predictor, l.variant, l.as_of, l.campaign_id, l.keyword_id, l.scenario
   FROM p_led l CROSS JOIN p_set s CROSS JOIN p_wm w
   JOIN (SELECT DISTINCT predictor, variant, as_of, campaign_id, keyword_id, scenario FROM p_grd0) g
     USING (predictor, variant, as_of, campaign_id, keyword_id, scenario)
   WHERE DATE_ADD(l.horizon_to, INTERVAL (s.settle_days + 1) DAY) <= LEAST(w.ads_max, w.anchor_cap)
   ORDER BY l.as_of, l.predictor, l.variant, l.campaign_id, l.keyword_id, l.scenario LIMIT 1) AS ungraded,
  (SELECT MIN(rn) FROM p_act0 WHERE NOT COALESCE(act_is_noop, FALSE) AND grade != 'UNGRADABLE') AS act_move_rn,
  (SELECT MIN(rn) FROM p_act0 WHERE COALESCE(act_is_noop, FALSE)) AS act_noop_rn;
CREATE TEMP TABLE p_copies AS
  SELECT copy FROM UNNEST(['LIVE',
    'NC_P1_UNGRADED', 'HC_P1_GRACE', 'NC_P1_PAST_GRACE', 'NC_P1_EMPTY', 'NC_P1_NO_SETTING', 'NC_P1_NO_WATERMARK',
    'HC_P2_FLAT', 'NC_P2_MAE_WORSE', 'HC_P2_MAE_WITHIN', 'NC_P2_CF_WORSE', 'NC_P2_YOUNG', 'NC_P2_EMPTY', 'NC_P2_NO_SETTING',
    'NC_P3_ACT_APPLIED', 'HC_P3_NOOP_APPLIED', 'HC_P3_UNGRADABLE']) AS copy;
-- the settings, the watermark and the ledger per copy. NC_P1_* doctor these: a setting or the ads
-- table's newest day removed, the ledger emptied, or one synthetic ledger row with no grade added —
-- in the grace night (gradable tonight, horizon_to + SETTLE_HORIZON_DAYS = the watermark: must hold)
-- or one night past it (horizon_to + SETTLE_HORIZON_DAYS + 1 = the watermark: must fire)
CREATE TEMP TABLE cp_set AS
  SELECT c.copy, IF(c.copy = 'NC_P1_NO_SETTING', NULL, s.settle_days) AS settle_days, s.min_windows,
         IF(c.copy = 'NC_P2_NO_SETTING', NULL, s.regression_max) AS regression_max
  FROM p_copies c CROSS JOIN p_set s;
CREATE TEMP TABLE cp_wm AS
  SELECT c.copy, IF(c.copy = 'NC_P1_NO_WATERMARK', NULL, w.ads_max) AS ads_max, w.anchor_cap,
         LEAST(IF(c.copy = 'NC_P1_NO_WATERMARK', NULL, w.ads_max), w.anchor_cap) AS wm
  FROM p_copies c CROSS JOIN p_wm w;
CREATE TEMP TABLE cp_led AS
  SELECT c.copy, l.predictor, l.variant, l.as_of, l.campaign_id, l.keyword_id, l.scenario, l.horizon_to
  FROM p_copies c CROSS JOIN p_led l
  WHERE c.copy != 'NC_P1_EMPTY'
  UNION ALL
  SELECT c.copy, 'PLAN_B', 'B', DATE '2026-09-30', 'P1_SYNTHETIC', 'P1_SYNTHETIC', 'DO_NOTHING',
         DATE_SUB(LEAST(w.ads_max, w.anchor_cap), INTERVAL (s.settle_days + IF(c.copy = 'NC_P1_PAST_GRACE', 1, 0)) DAY)
  FROM p_copies c CROSS JOIN p_wm w CROSS JOIN p_set s
  WHERE c.copy IN ('HC_P1_GRACE', 'NC_P1_PAST_GRACE');
CREATE TEMP TABLE cp_grd AS
  SELECT c.copy, g.predictor, g.variant, g.as_of, g.campaign_id, g.keyword_id, g.scenario
  FROM p_copies c
  CROSS JOIN (SELECT DISTINCT predictor, variant, as_of, campaign_id, keyword_id, scenario FROM p_grd0) g
  CROSS JOIN p_pick k
  WHERE NOT COALESCE(c.copy = 'NC_P1_UNGRADED'
                     AND g.predictor = k.ungraded.predictor AND g.variant = k.ungraded.variant
                     AND g.as_of = k.ungraded.as_of AND g.campaign_id = k.ungraded.campaign_id
                     AND g.keyword_id = k.ungraded.keyword_id AND g.scenario = k.ungraded.scenario, FALSE);
-- the current ACT grades per copy. NC_P3_ACT_APPLIED: the picked move applied (an uploaded plan
-- matched it: must leave INFO); HC_P3_NOOP_APPLIED: the picked no-move row applied (must stay);
-- HC_P3_UNGRADABLE: the move applied but its row UNGRADABLE (must stay)
CREATE TEMP TABLE cp_act AS
  SELECT c.copy,
         IF(COALESCE((c.copy IN ('NC_P3_ACT_APPLIED', 'HC_P3_UNGRADABLE') AND a.rn = k.act_move_rn)
                     OR (c.copy = 'HC_P3_NOOP_APPLIED' AND a.rn = k.act_noop_rn), FALSE), TRUE, a.is_applied) AS is_applied,
         a.act_is_noop,
         IF(COALESCE((c.copy IN ('NC_P3_ACT_APPLIED', 'HC_P3_UNGRADABLE') AND a.rn = k.act_move_rn)
                     OR (c.copy = 'HC_P3_NOOP_APPLIED' AND a.rn = k.act_noop_rn), FALSE), 'ACT', a.applied_scenario) AS applied_scenario,
         IF(COALESCE(c.copy = 'HC_P3_UNGRADABLE' AND a.rn = k.act_move_rn, FALSE), 'UNGRADABLE', a.grade) AS grade
  FROM p_copies c CROSS JOIN p_act0 a CROSS JOIN p_pick k;
-- the report card per copy. The live card, except: HC_P2_* / NC_P2_* (but NC_P2_EMPTY and
-- NC_P2_NO_SETTING) read a synthetic card of six graded weeks per plan, 2026-08-02 .. 2026-09-06
-- (wr 1 the newest), every week mae_net_usd 50 on real_spend 100 (mae_net_share 0.5) and
-- counterfactual_net_per_alloc -0.1 on alloc_spend 100, versions R0:pre-v27.170 / pre-v27.170; on
-- PLAN_B's three newest weeks NC_P2_MAE_WORSE has mae_net_usd 60 (0.6: 20% worse, beyond 10%) and the
-- versions R0:v27.171 / v27.171, HC_P2_MAE_WITHIN 54 (0.54: 8% worse, within it), NC_P2_CF_WORSE
-- -0.2; NC_P2_YOUNG drops the oldest week (5 of 6); NC_P2_EMPTY has no card at all
CREATE TEMP TABLE p_syn AS
  SELECT c.copy, p AS predictor, DATE_ADD(DATE '2026-08-02', INTERVAL 7 * k DAY) AS window_from, 6 - k AS wr
  FROM p_copies c, UNNEST(['PLAN_A', 'PLAN_B']) AS p, UNNEST(GENERATE_ARRAY(0, 5)) AS k
  WHERE c.copy IN ('HC_P2_FLAT', 'NC_P2_MAE_WORSE', 'HC_P2_MAE_WITHIN', 'NC_P2_CF_WORSE', 'NC_P2_YOUNG')
    AND NOT (c.copy = 'NC_P2_YOUNG' AND k = 0);
CREATE TEMP TABLE cp_card AS
  SELECT c.copy, x.predictor, x.row_type, x.window_from, x.mae_net_usd, x.real_spend,
         x.counterfactual_net_per_alloc, x.alloc_spend, x.rule_versions, x.builder_versions
  FROM p_copies c CROSS JOIN p_card0 x
  WHERE c.copy NOT IN ('HC_P2_FLAT', 'NC_P2_MAE_WORSE', 'HC_P2_MAE_WITHIN', 'NC_P2_CF_WORSE', 'NC_P2_YOUNG', 'NC_P2_EMPTY')
    AND x.level = 'WINDOW' AND x.family = 'ALL' AND x.calendar_state = 'ALL'
    AND ((x.row_type = 'ACCURACY' AND x.scenario = 'APPLIED') OR x.row_type = 'MONEY')
  UNION ALL
  SELECT y.copy, y.predictor, r, y.window_from,
         IF(r = 'ACCURACY',
            CASE WHEN y.predictor = 'PLAN_B' AND y.wr <= 3 AND y.copy = 'NC_P2_MAE_WORSE' THEN 60.0
                 WHEN y.predictor = 'PLAN_B' AND y.wr <= 3 AND y.copy = 'HC_P2_MAE_WITHIN' THEN 54.0
                 ELSE 50.0 END, NULL),
         IF(r = 'ACCURACY', 100.0, NULL),
         IF(r = 'MONEY', IF(y.predictor = 'PLAN_B' AND y.wr <= 3 AND y.copy = 'NC_P2_CF_WORSE', -0.2, -0.1), NULL),
         IF(r = 'MONEY', 100.0, NULL),
         IF(y.predictor = 'PLAN_B' AND y.wr <= 3 AND y.copy = 'NC_P2_MAE_WORSE', 'R0:v27.171', 'R0:pre-v27.170'),
         IF(y.predictor = 'PLAN_B' AND y.wr <= 3 AND y.copy = 'NC_P2_MAE_WORSE', 'v27.171', 'pre-v27.170')
  FROM p_syn y, UNNEST(['ACCURACY', 'MONEY']) AS r;
CREATE TEMP TABLE cp_card_meta AS
  SELECT c.copy,
         CASE WHEN c.copy = 'NC_P2_EMPTY' THEN 0
              WHEN c.copy IN ('HC_P2_FLAT', 'NC_P2_MAE_WORSE', 'HC_P2_MAE_WITHIN', 'NC_P2_CF_WORSE', 'NC_P2_YOUNG')
                THEN (SELECT COUNT(*) FROM cp_card k WHERE k.copy = c.copy)
              ELSE (SELECT COUNT(*) FROM p_card0) END AS n_rows,
         IF(c.copy = 'NC_P2_EMPTY', CAST(NULL AS TIMESTAMP), (SELECT MAX(scored_at) FROM p_card0)) AS scored_at
  FROM p_copies c;
-- TWIN of V_ENGINE_HEALTH lrn_due .. c37, pasted below VERBATIM (the text-identity command is in the
-- header), run once per copy on that copy's seven inputs
CREATE TEMP TABLE p_twin (copy STRING, check_name STRING, measured FLOAT64, threshold STRING, status STRING, detail STRING);
FOR cp IN (SELECT copy FROM p_copies ORDER BY copy) DO
  INSERT INTO p_twin (copy, check_name, measured, threshold, status, detail)
  WITH
lrn_set AS (SELECT settle_days, min_windows, regression_max FROM cp_set WHERE copy = cp.copy),
lrn_wm AS (SELECT ads_max, anchor_cap, wm FROM cp_wm WHERE copy = cp.copy),
lrn_led AS (SELECT predictor, variant, as_of, campaign_id, keyword_id, scenario, horizon_to FROM cp_led WHERE copy = cp.copy),
lrn_grd AS (SELECT predictor, variant, as_of, campaign_id, keyword_id, scenario FROM cp_grd WHERE copy = cp.copy),
lrn_act AS (SELECT is_applied, act_is_noop, applied_scenario, grade FROM cp_act WHERE copy = cp.copy),
lrn_card AS (SELECT predictor, row_type, window_from, mae_net_usd, real_spend, counterfactual_net_per_alloc, alloc_spend,
                    rule_versions, builder_versions FROM cp_card WHERE copy = cp.copy),
lrn_card_meta AS (SELECT n_rows, scored_at FROM cp_card_meta WHERE copy = cp.copy),
lrn_due AS (  -- each ledger row: past due (one night after the house watermark made it gradable) or not, graded or not
  SELECT l.predictor, l.as_of,
         DATE_ADD(l.horizon_to, INTERVAL (s.settle_days + 1) DAY) AS due_on,
         COALESCE(DATE_ADD(l.horizon_to, INTERVAL (s.settle_days + 1) DAY) <= w.wm, FALSE) AS is_due,
         g.predictor IS NOT NULL AS graded
  FROM lrn_led l
  CROSS JOIN lrn_set s
  CROSS JOIN lrn_wm w
  LEFT JOIN lrn_grd g
    ON g.predictor = l.predictor AND g.variant = l.variant AND g.as_of = l.as_of
   AND g.campaign_id = l.campaign_id AND g.keyword_id = l.keyword_id AND g.scenario = l.scenario
),
c35 AS (  -- the grader keeps up: no ledger row stays ungraded a night after the house watermark made it gradable
  SELECT 'prediction_grades_fresh' AS check_name,
    CAST(COUNTIF(is_due AND NOT graded) AS FLOAT64),
    'ledger rows (V_PREDICTION_LEDGER, both scenarios) with no grade in FACT_PREDICTION_GRADE one night after they became gradable: horizon_to + SETTLE_HORIZON_DAYS + 1 on or before the house watermark LEAST(MAX(FACT_AMAZON_ADS.date), FN_ADS_ANCHOR_CAP()) · red > 0; red when no ledger row is that old (an empty population), or the setting or the watermark is missing',
    CASE WHEN (SELECT settle_days FROM lrn_set) IS NULL OR (SELECT wm FROM lrn_wm) IS NULL THEN 'RED'
         WHEN COUNTIF(is_due) = 0 THEN 'RED'
         WHEN COUNTIF(is_due AND NOT graded) > 0 THEN 'RED'
         ELSE 'GREEN' END,
    CONCAT(
      IF((SELECT settle_days FROM lrn_set) IS NULL,
         'SETTLE_HORIZON_DAYS is not in DE_COACH_THRESHOLDS (LEARNING, GUARDIAN, family NULL), so no row can fall due · ', ''),
      IF((SELECT wm FROM lrn_wm) IS NULL, 'the house watermark is NULL (FACT_AMAZON_ADS holds no row) · ', ''),
      CAST(COUNTIF(is_due AND NOT graded) AS STRING), ' of ', CAST(COUNTIF(is_due) AS STRING),
      ' ledger rows past due have no grade',
      IF(COUNTIF(is_due AND NOT graded) > 0,
         CONCAT(' (nights ', CAST(MIN(IF(is_due AND NOT graded, as_of, NULL)) AS STRING), ' to ',
                CAST(MAX(IF(is_due AND NOT graded, as_of, NULL)) AS STRING), ')'),
         ''),
      ' · watermark ', COALESCE(CAST((SELECT wm FROM lrn_wm) AS STRING), 'NULL'),
      ' = LEAST(FACT_AMAZON_ADS newest day ', COALESCE(CAST((SELECT ads_max FROM lrn_wm) AS STRING), 'none'),
      ', FN_ADS_ANCHOR_CAP() ', COALESCE(CAST((SELECT anchor_cap FROM lrn_wm) AS STRING), 'NULL'), ')',
      ' · a row is gradable at horizon end + ', COALESCE(CAST((SELECT settle_days FROM lrn_set) AS STRING), '(no setting)'),
      ' days, past due one night later · ', CAST(COUNTIF(NOT is_due) AS STRING), ' ledger rows not yet past due',
      COALESCE(CONCAT(', the next when the watermark reaches ', CAST(MIN(IF(NOT is_due, due_on, NULL)) AS STRING)), ''),
      ' · the grader is SP_GRADE_PREDICTIONS (Refresh Task 20.8f); nothing re-runs it by itself')
  FROM lrn_due
),
lrn_win AS (  -- one row per predictor and graded window (the Sunday-start week of as_of: the card's WINDOW level), newest first
  SELECT predictor, window_from,
         SUM(IF(row_type = 'ACCURACY', mae_net_usd, NULL)) AS mae_usd,
         SUM(IF(row_type = 'ACCURACY', real_spend, NULL)) AS real_spend,
         SUM(IF(row_type = 'MONEY', counterfactual_net_per_alloc * alloc_spend, NULL)) AS cf_net,
         SUM(IF(row_type = 'MONEY', alloc_spend, NULL)) AS alloc,
         STRING_AGG(IF(row_type = 'MONEY', rule_versions, NULL), ',') AS rvs,
         STRING_AGG(IF(row_type = 'MONEY', builder_versions, NULL), ',') AS bvs,
         ROW_NUMBER() OVER (PARTITION BY predictor ORDER BY window_from DESC) AS wr
  FROM lrn_card
  GROUP BY predictor, window_from
),
lrn_span AS (  -- per predictor: the trailing MIN_GRADED_WINDOWS windows (t) and the MIN_GRADED_WINDOWS before them (p), each pooled
  SELECT w.predictor, COUNT(*) AS n_windows,
         STRING_AGG(CAST(w.window_from AS STRING), ' ' ORDER BY w.window_from) AS all_weeks,
         STRING_AGG(IF(w.wr <= s.min_windows, CAST(w.window_from AS STRING), NULL), ' ' ORDER BY w.window_from) AS t_weeks,
         STRING_AGG(IF(w.wr > s.min_windows AND w.wr <= 2 * s.min_windows, CAST(w.window_from AS STRING), NULL), ' '
                    ORDER BY w.window_from) AS p_weeks,
         SAFE_DIVIDE(SUM(IF(w.wr <= s.min_windows, w.mae_usd, NULL)),
                     SUM(IF(w.wr <= s.min_windows, w.real_spend, NULL))) AS mae_t,
         SAFE_DIVIDE(SUM(IF(w.wr > s.min_windows AND w.wr <= 2 * s.min_windows, w.mae_usd, NULL)),
                     SUM(IF(w.wr > s.min_windows AND w.wr <= 2 * s.min_windows, w.real_spend, NULL))) AS mae_p,
         SAFE_DIVIDE(SUM(IF(w.wr <= s.min_windows, w.cf_net, NULL)),
                     SUM(IF(w.wr <= s.min_windows, w.alloc, NULL))) AS cf_t,
         SAFE_DIVIDE(SUM(IF(w.wr > s.min_windows AND w.wr <= 2 * s.min_windows, w.cf_net, NULL)),
                     SUM(IF(w.wr > s.min_windows AND w.wr <= 2 * s.min_windows, w.alloc, NULL))) AS cf_p
  FROM lrn_win w
  CROSS JOIN lrn_set s
  GROUP BY w.predictor
),
lrn_chg AS (  -- per predictor, every rule or builder version behind one span and not the other: what changed between them
  SELECT predictor, STRING_AGG(CONCAT(kind, IF(in_t, ' new ', ' gone '), v), ', ' ORDER BY kind, in_t, v) AS changed
  FROM (SELECT w.predictor, x.kind, v,
               LOGICAL_OR(w.wr <= s.min_windows) AS in_t,
               LOGICAL_OR(w.wr > s.min_windows) AS in_p
        FROM lrn_win w
        CROSS JOIN lrn_set s
        CROSS JOIN UNNEST([STRUCT('rule_version' AS kind, w.rvs AS vs), STRUCT('builder_version' AS kind, w.bvs AS vs)]) AS x
        CROSS JOIN UNNEST(SPLIT(x.vs, ',')) AS v
        WHERE w.wr <= 2 * s.min_windows
        GROUP BY w.predictor, x.kind, v)
  WHERE in_t != in_p
  GROUP BY predictor
),
lrn_reg AS (  -- per predictor: judged once it has twice MIN_GRADED_WINDOWS windows; worse = by more than REGRESSION_MAX of the earlier value
  SELECT p.predictor, p.n_windows, p.all_weeks, p.t_weeks, p.p_weeks, p.mae_t, p.mae_p, p.cf_t, p.cf_p, c.changed,
         p.n_windows >= 2 * s.min_windows AS judged,
         COALESCE(p.mae_t - p.mae_p > s.regression_max * ABS(p.mae_p), FALSE) AS mae_worse,
         COALESCE(p.cf_p - p.cf_t > s.regression_max * ABS(p.cf_p), FALSE) AS cf_worse,
         s.min_windows
  FROM lrn_span p
  CROSS JOIN lrn_set s
  LEFT JOIN lrn_chg c ON c.predictor = p.predictor
),
lrn_reg_line AS (  -- one sentence per predictor, built one level below the check's aggregate
  SELECT predictor, judged, mae_worse, cf_worse,
         IF(COALESCE(judged, FALSE),
            CONCAT(predictor, ': mae_net_share ', COALESCE(FORMAT('%.4f', mae_t), 'none'), ' over ', COALESCE(t_weeks, '-'),
                   ' against ', COALESCE(FORMAT('%.4f', mae_p), 'none'), ' over ', COALESCE(p_weeks, '-'),
                   ', counterfactual_net_per_alloc ', COALESCE(FORMAT('%.4f', cf_t), 'none'),
                   ' against ', COALESCE(FORMAT('%.4f', cf_p), 'none'),
                   CASE WHEN mae_worse AND cf_worse THEN ' — WORSE on accuracy and on money'
                        WHEN mae_worse THEN ' — WORSE on accuracy'
                        WHEN cf_worse THEN ' — WORSE on money'
                        ELSE ' — not worse by more than the margin' END,
                   IF(changed IS NULL, ' · no rule or builder version changed between them',
                      CONCAT(' · changed between them: ', changed))),
            CONCAT(predictor, ': YOUNG, ', CAST(n_windows AS STRING), ' of ', COALESCE(CAST(2 * min_windows AS STRING), '?'),
                   ' windows graded (', COALESCE(all_weeks, '-'), ')')) AS line
  FROM lrn_reg
),
c36 AS (  -- the predictions do not get quietly worse: trailing windows against the ones before them, per predictor
  SELECT 'prediction_regression',
    CAST(COUNTIF(COALESCE(judged, FALSE) AND (mae_worse OR cf_worse)) AS FLOAT64),
    'predictors whose trailing MIN_GRADED_WINDOWS graded windows (the Sunday-start weeks of as_of: the report card\'s WINDOW rows, family ALL) are worse than the MIN_GRADED_WINDOWS before them by more than REGRESSION_MAX of the earlier value, on mae_net_share of the applied scenario (higher is worse) or counterfactual_net_per_alloc (lower is worse) · red > 0; INFO (YOUNG) while no predictor has twice MIN_GRADED_WINDOWS graded windows; red when the report card is empty or a setting is missing',
    CASE WHEN (SELECT min_windows FROM lrn_set) IS NULL OR (SELECT regression_max FROM lrn_set) IS NULL THEN 'RED'
         WHEN (SELECT n_rows FROM lrn_card_meta) = 0 THEN 'RED'
         WHEN COUNTIF(COALESCE(judged, FALSE) AND (mae_worse OR cf_worse)) > 0 THEN 'RED'
         WHEN COUNTIF(COALESCE(judged, FALSE)) = 0 THEN 'INFO'
         ELSE 'GREEN' END,
    CONCAT(
      IF((SELECT min_windows FROM lrn_set) IS NULL OR (SELECT regression_max FROM lrn_set) IS NULL,
         'MIN_GRADED_WINDOWS or REGRESSION_MAX is not in DE_COACH_THRESHOLDS (LEARNING, GUARDIAN, family NULL) · ', ''),
      IF((SELECT n_rows FROM lrn_card_meta) = 0,
         'the report card T_PREDICTION_SCORECARD is empty: SP_GRADE_PREDICTIONS has not rebuilt it · ', ''),
      IF(COUNTIF(COALESCE(judged, FALSE)) = 0, 'YOUNG — ', ''),
      COALESCE(STRING_AGG(line, '; ' ORDER BY predictor), 'no graded window on the card'),
      ' · the trailing ', COALESCE(CAST((SELECT min_windows FROM lrn_set) AS STRING), '(no setting)'),
      ' windows against the ', COALESCE(CAST((SELECT min_windows FROM lrn_set) AS STRING), '(no setting)'),
      ' before them; RED when worse by more than ', COALESCE(CAST((SELECT regression_max FROM lrn_set) AS STRING), '(no setting)'),
      ' of the earlier value · the card was scored ',
      COALESCE(FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', (SELECT scored_at FROM lrn_card_meta), 'America/New_York'), 'never'),
      ' New York')
  FROM lrn_reg_line
),
c37 AS (  -- REPORTS: the response model is tested only where an uploaded plan matched a move
  SELECT 'response_model_unverified',
    CAST(COUNTIF(is_applied AND NOT COALESCE(act_is_noop, FALSE) AND grade != 'UNGRADABLE') AS FLOAT64),
    'current ACT-scenario grades that applied (an uploaded plan matched every component) on a plan row with a bid, state or budget component: the grades that test the response model RM1 · INFO (reports) until one exists, then GREEN; never red',
    IF(COUNTIF(is_applied AND NOT COALESCE(act_is_noop, FALSE) AND grade != 'UNGRADABLE') > 0, 'GREEN', 'INFO'),
    CONCAT(CAST(COUNTIF(is_applied AND NOT COALESCE(act_is_noop, FALSE) AND grade != 'UNGRADABLE') AS STRING),
           ' ACT grades applied with a move · ', CAST(COUNTIF(is_applied AND COALESCE(act_is_noop, FALSE)) AS STRING),
           ' applied on rows the plan moved nothing · ',
           CAST(COUNTIF(NOT COALESCE(act_is_noop, FALSE) AND applied_scenario = 'DO_NOTHING') AS STRING),
           ' with a move whose row applied as DO_NOTHING (no uploaded plan matched) · ',
           CAST(COUNTIF(applied_scenario = 'OTHER_ACTION') AS STRING), ' OTHER_ACTION · ',
           CAST(COUNT(*) AS STRING), ' current ACT grades · RM1 is graded only where an uploaded plan matched (piece 3); until then ACT and lift are ungraded (architecture/LEARNING.md §9)')
  FROM lrn_act
)
  SELECT cp.copy, * FROM c35 UNION ALL SELECT cp.copy, * FROM c36 UNION ALL SELECT cp.copy, * FROM c37;
END FOR;
-- what each doctored copy must read on the check it doctors: status (NULL = LIVE's), measured (NULL =
-- LIVE's plus delta) and a pattern its detail must match. Every check a copy does not doctor must read
-- exactly LIVE's row (P1-P3 count both).
CREATE TEMP TABLE p_expect AS
  SELECT * FROM UNNEST([
    STRUCT<copy STRING, check_name STRING, exp_status STRING, exp_measured FLOAT64, delta FLOAT64, detail_like STRING>
    ('NC_P1_UNGRADED', 'prediction_grades_fresh', 'RED', NULL, 1, '% ledger rows past due have no grade (nights %'),
    ('HC_P1_GRACE', 'prediction_grades_fresh', NULL, NULL, 0, '% ledger rows past due have no grade%'),
    ('NC_P1_PAST_GRACE', 'prediction_grades_fresh', 'RED', NULL, 1, '% ledger rows past due have no grade (nights %'),
    ('NC_P1_EMPTY', 'prediction_grades_fresh', 'RED', 0, NULL, '0 of 0 ledger rows past due have no grade · %'),
    ('NC_P1_NO_SETTING', 'prediction_grades_fresh', 'RED', 0, NULL, 'SETTLE_HORIZON_DAYS is not in DE_COACH_THRESHOLDS %0 of 0 ledger rows past due%'),
    ('NC_P1_NO_WATERMARK', 'prediction_grades_fresh', 'RED', 0, NULL, 'the house watermark is NULL (FACT_AMAZON_ADS holds no row) · 0 of 0 ledger rows past due%'),
    ('HC_P2_FLAT', 'prediction_regression', 'GREEN', 0, NULL,
     'PLAN_A: mae_net_share 0.5000 over 2026-08-23 2026-08-30 2026-09-06 against 0.5000 over 2026-08-02 2026-08-09 2026-08-16, counterfactual_net_per_alloc -0.1000 against -0.1000 — not worse by more than the margin · no rule or builder version changed between them; PLAN_B: mae_net_share 0.5000 %'),
    ('NC_P2_MAE_WORSE', 'prediction_regression', 'RED', 1, NULL,
     '%; PLAN_B: mae_net_share 0.6000 over 2026-08-23 2026-08-30 2026-09-06 against 0.5000 over 2026-08-02 2026-08-09 2026-08-16, counterfactual_net_per_alloc -0.1000 against -0.1000 — WORSE on accuracy · changed between them: builder_version gone pre-v27.170, builder_version new v27.171, rule_version gone R0:pre-v27.170, rule_version new R0:v27.171 · %'),
    ('HC_P2_MAE_WITHIN', 'prediction_regression', 'GREEN', 0, NULL,
     '%; PLAN_B: mae_net_share 0.5400 over % against 0.5000 over %— not worse by more than the margin%'),
    ('NC_P2_CF_WORSE', 'prediction_regression', 'RED', 1, NULL,
     '%; PLAN_B: mae_net_share 0.5000 %counterfactual_net_per_alloc -0.2000 against -0.1000 — WORSE on money%'),
    ('NC_P2_YOUNG', 'prediction_regression', 'INFO', 0, NULL,
     'YOUNG — PLAN_A: YOUNG, 5 of 6 windows graded (2026-08-09 2026-08-16 2026-08-23 2026-08-30 2026-09-06); PLAN_B: YOUNG, 5 of 6 windows graded %'),
    ('NC_P2_EMPTY', 'prediction_regression', 'RED', 0, NULL, '%the report card T_PREDICTION_SCORECARD is empty: SP_GRADE_PREDICTIONS has not rebuilt it · %'),
    ('NC_P2_NO_SETTING', 'prediction_regression', 'RED', NULL, 0, 'MIN_GRADED_WINDOWS or REGRESSION_MAX is not in DE_COACH_THRESHOLDS %'),
    ('NC_P3_ACT_APPLIED', 'response_model_unverified', 'GREEN', NULL, 1, '% ACT grades applied with a move · %'),
    ('HC_P3_NOOP_APPLIED', 'response_model_unverified', NULL, NULL, 0, '% ACT grades applied with a move · % applied on rows the plan moved nothing · %'),
    ('HC_P3_UNGRADABLE', 'response_model_unverified', NULL, NULL, 0, '% ACT grades applied with a move · %')
  ]);
CREATE TEMP TABLE p_result AS
  SELECT e.*, t.status, t.measured, t.detail,
         l.status AS live_status, l.measured AS live_measured,
         (t.check_name IS NOT NULL
          AND t.status = COALESCE(e.exp_status, l.status)
          AND t.measured = COALESCE(e.exp_measured, l.measured + e.delta)
          AND t.detail LIKE e.detail_like) AS ok
  FROM p_expect e
  LEFT JOIN p_twin t ON t.copy = e.copy AND t.check_name = e.check_name
  LEFT JOIN p_twin l ON l.copy = 'LIVE' AND l.check_name = e.check_name;
-- every check a copy does not doctor, against LIVE's row
CREATE TEMP TABLE p_others AS
  SELECT t.copy, t.check_name,
         COALESCE(t.measured = l.measured AND t.status = l.status AND t.detail = l.detail, FALSE) AS same
  FROM p_twin t
  JOIN p_twin l ON l.copy = 'LIVE' AND l.check_name = t.check_name
  JOIN p_expect e ON e.copy = t.copy
  WHERE t.check_name != e.check_name;

-- ---- C04: the SYSTEM row's shape, written once and run on the live row and on doctored copies ----
-- n_rows = how many SYSTEM rows the brief carries (must be 1); red_names = the board's RED checks.
-- A NULL red_names is read as [] (no RED), never as 'nothing to compare': with a NULL array the
-- count term scored 0 for a wrong count and the IF guarding C04a took its else branch (measured
-- 2026-10-01, see the header).
CREATE TEMP FUNCTION sys_row_violations(n_rows INT64, section_rank INT64, status STRING,
                                        from_value FLOAT64, detail STRING, item STRING, action STRING,
                                        campaign_id STRING, keyword_id STRING,
                                        red_names ARRAY<STRING>) AS (
  IF(n_rows != 1, 1, 0)
  + IF(section_rank != 7, 1, 0)
  + IF(campaign_id IS NOT NULL OR keyword_id IS NOT NULL, 1, 0)
  + IF(COALESCE(detail, '') NOT LIKE 'SYSTEM: %' OR COALESCE(item, '') = '' OR COALESCE(action, '') = '', 1, 0)
  + IF(status != IF(ARRAY_LENGTH(COALESCE(red_names, [])) > 0, 'RED', 'GREEN'), 1, 0)
  + IF(from_value IS NULL OR from_value != ARRAY_LENGTH(COALESCE(red_names, [])), 1, 0)
  + (SELECT COUNT(*) FROM UNNEST(COALESCE(red_names, [])) AS r WHERE COALESCE(detail, '') NOT LIKE CONCAT('%', r, '%'))
);

WITH
expected AS (
  SELECT name FROM UNNEST(['plan_window_complete_days', 'plan_pot_reconciliation', 'plan_one_move_per_notgood',
                           'plan_ownership_no_foreign_go', 'plan_both_plans_written', 'plan_settle_guard_holds',
                           'plan_settle_curve_coverage', 'plan_proposal_lag_days', 'plan_partition_fresh',
                           'pipeline_step_failing', 'plan_pass_failed']) AS name
),
-- [] on a board with no RED, never NULL (ARRAY_AGG over zero rows is NULL; C04f holds this equal
-- to the LIVE row of red_names_copies so the two forms cannot drift)
red_names AS (SELECT COALESCE(ARRAY_AGG(check_name ORDER BY check_name), []) AS names FROM board WHERE status = 'RED'),
live_sys AS (
  -- one row even when the brief carries no SYSTEM row, so the function sees n_rows = 0 and fires
  SELECT COUNT(*) AS n_rows, MAX(section_rank) AS section_rank, MAX(status) AS status,
         MAX(from_value) AS from_value, MAX(detail) AS detail, MAX(item) AS item, MAX(action) AS action,
         MAX(campaign_id) AS campaign_id, MAX(keyword_id) AS keyword_id
  FROM brief_sys
),
-- A CHECK THAT IS NOT ON THE BOARD CANNOT GO RED, AND THE BRIEF READS THE BOARD: a renamed or
-- dropped check is an alarm that no longer exists. (A doubled one would double its line.)
c01 AS (
  SELECT 'C01 the ten v27.152 checks and v27.163 plan_pass_failed are on the board, once each' AS check_name,
         (SELECT COUNT(*) FROM expected e WHERE NOT EXISTS (SELECT 1 FROM board b WHERE b.check_name = e.name))
       + (SELECT COUNT(*) FROM (SELECT check_name FROM board b JOIN expected e ON e.name = b.check_name
                                GROUP BY 1 HAVING COUNT(*) > 1)) AS violations
),
-- THE PLAN STEP DID NOT SAVE LAST NIGHT'S PARTITION: PLANNED and SEATS are quoting a plan older
-- than they look, and the morning's upload is built off it.
c02 AS (
  SELECT 'C02 plan_partition_fresh is GREEN today and names the latest partition',
         (SELECT IF(COUNT(*) = 0, 1, 0) FROM board WHERE check_name = 'plan_partition_fresh')
       + (SELECT COUNTIF(status != 'GREEN') FROM board WHERE check_name = 'plan_partition_fresh')
       + (SELECT COUNTIF(detail NOT LIKE CONCAT('last plan ', CAST((SELECT MAX(as_of) FROM plan_nights) AS STRING), ', 0 night(s) missing%'))
          FROM board WHERE check_name = 'plan_partition_fresh')
),
-- THE ALARM NEVER FIRES: a dropped night reads GREEN and the outage repeats unseen.
c02b AS (
  SELECT 'C02b NEGATIVE CONTROL plan_partition_fresh FIRES: every partition from the Los Angeles day the plan step last ran dropped -> RED with >= 1 night missing; no partition -> RED',
         (SELECT IF(COUNTIF(copy = 'NC_DROP_LATEST' AND last_plan < due AND DATE_DIFF(due, last_plan, DAY) >= 1) = 1, 0, 1)
                 + IF(COUNTIF(copy = 'NC_EMPTY' AND last_plan IS NULL) = 1, 0, 1)
                 + IF(COUNTIF(copy = 'LIVE' AND last_plan >= due) = 1, 0, 1)
          FROM plan_clock_copies)
),
-- THE GENERIC ALARM NEVER FIRES: the next step that breaks for a month is logged and unnamed.
c03a AS (
  SELECT 'C03a NEGATIVE CONTROL pipeline_step_failing FIRES: a healthy procedure with its three most recent runs set to FAIL is named',
         (SELECT IF(COUNT(*) = 0, 1, 0) FROM victim)
       + (SELECT IF(COUNT(*) = 1, 0, 1) FROM pipe_fired f JOIN victim v USING (procedure_name) WHERE f.copy = 'NC3')
),
-- THE ALARM CRIES WOLF: one bad pass names a step, and the line is ignored like the three REDs
-- before it.
c03b AS (
  SELECT 'C03b NEGATIVE CONTROL pipeline_step_failing HOLDS: two FAILs of three do not name it',
         (SELECT IF(COUNT(*) = 0, 1, 0) FROM victim)
       + (SELECT COUNT(*) FROM pipe_fired f JOIN victim v USING (procedure_name) WHERE f.copy = 'NC2')
),
-- THIS FILE'S COPY OF THE EXPRESSION HAS DRIFTED FROM THE VIEW: the controls above prove a check
-- that is no longer the deployed one.
c03c AS (
  SELECT 'C03c the deployed pipeline_step_failing agrees with this file\'s twin on the live log (count and names)',
         (SELECT IF(COUNT(*) = 0, 1, 0) FROM board WHERE check_name = 'pipeline_step_failing')
       + (SELECT COUNTIF(measured != (SELECT COUNT(*) FROM pipe_fired WHERE copy = 'LIVE'))
          FROM board WHERE check_name = 'pipeline_step_failing')
       + (SELECT COUNT(*) FROM pipe_fired f
          WHERE f.copy = 'LIVE'
            AND NOT EXISTS (SELECT 1 FROM board b WHERE b.check_name = 'pipeline_step_failing'
                            AND b.detail LIKE CONCAT('%', f.procedure_name, ': %')))
),
-- THE ALARM DOES NOT REACH THE ONE QUERY ORI READS: a RED on the board and a quiet brief.
c04 AS (
  SELECT 'C04 the brief carries ONE SYSTEM row at rank 7, RED iff the board has a RED, counting and naming every RED check, blank nowhere',
         (SELECT sys_row_violations(n_rows, section_rank, status, from_value, detail, item, action,
                                    campaign_id, keyword_id, (SELECT names FROM red_names))
          FROM live_sys)
),
-- C04's own negative controls, on doctored copies of the live SYSTEM row (the board's RED names
-- are the live ones). C04a needs a RED name to remove, so on a board with no RED it reads 0 and
-- says so; C04b/C04c are conclusive on any board, and C04d/C04e cover the board with no RED.
c04a AS (
  SELECT 'C04a NEGATIVE CONTROL C04 FIRES when a RED name is removed from the detail (nothing to remove on a board with no RED: 0, see C04d/C04e)',
         (SELECT IF(ARRAY_LENGTH(names) = 0, 0,
                    IF((SELECT sys_row_violations(n_rows, section_rank, status, from_value,
                                                  REPLACE(detail, COALESCE(names[SAFE_OFFSET(0)], ''), 'xx'), item, action,
                                                  campaign_id, keyword_id, names)
                        FROM live_sys) >= 1, 0, 1))
          FROM red_names)
),
c04b AS (
  SELECT 'C04b NEGATIVE CONTROL C04 FIRES when the status is flipped',
         (SELECT IF((SELECT sys_row_violations(n_rows, section_rank, IF(status = 'RED', 'GREEN', 'RED'), from_value,
                                               detail, item, action, campaign_id, keyword_id, names)
                     FROM live_sys) >= 1, 0, 1)
          FROM red_names)
),
c04c AS (
  SELECT 'C04c NEGATIVE CONTROL C04 FIRES when the row is doubled',
         (SELECT IF((SELECT sys_row_violations(2, section_rank, status, from_value, detail, item, action,
                                               campaign_id, keyword_id, names)
                     FROM live_sys) >= 1, 0, 1)
          FROM red_names)
),
-- THE ONE STATE THE LINE CALLS THE GOAL READS FAIL: the morning the board is finally clean, C04
-- goes red on the SYSTEM row, and Ori learns to read past a FAIL in this file.
c04d AS (
  SELECT 'C04d C04 HOLDS on an all-green board: the SYSTEM row rendered for NC_ALL_GREEN is GREEN, counts 0, names nothing, says nothing to do, and passes the row test',
         (SELECT IF(COUNT(*) = 1, 0, 1) FROM sys_rows WHERE copy = 'NC_ALL_GREEN')
       + (SELECT COALESCE(MAX(sys_row_violations(n_rows, section_rank, status, from_value, detail, item, action,
                                                 campaign_id, keyword_id, names)), 1)
          FROM sys_rows WHERE copy = 'NC_ALL_GREEN')
       + (SELECT COUNTIF(NOT (status = 'GREEN' AND from_value = 0 AND ARRAY_LENGTH(names) = 0
                              AND action = 'nothing to do — no check is RED'
                              AND detail LIKE 'SYSTEM: 0 checks RED — every check on the board is green, amber or a report · last plan %'))
          FROM sys_rows WHERE copy = 'NC_ALL_GREEN')
),
-- A WRONG RED COUNT PASSES ON A GREEN BOARD: with no RED name the count term compared against a
-- NULL array and went quiet, so a line reading '1 of 32 checks RED' over a clean board read PASS.
c04e AS (
  SELECT 'C04e NEGATIVE CONTROL C04 FIRES on an all-green board when the RED count is wrong: from_value 1 with no RED name -> >= 1',
         (SELECT IF(COUNT(*) = 1, 0, 1) FROM sys_rows WHERE copy = 'NC_ALL_GREEN')
       + (SELECT IF(COALESCE(MAX(sys_row_violations(n_rows, section_rank, status, 1.0, detail, item, action,
                                                    campaign_id, keyword_id, names)), 0) >= 1, 0, 1)
          FROM sys_rows WHERE copy = 'NC_ALL_GREEN')
),
-- THE RENDERING TWIN HAS DRIFTED FROM THE VIEW: C04d/C04e prove a row the brief no longer renders.
c04f AS (
  SELECT 'C04f the rendering twin\'s LIVE row equals the deployed SYSTEM row (status, from_value, item, action, detail) and its names equal red_names',
         (SELECT IF(COUNT(*) = 1, 0, 1) FROM sys_rows WHERE copy = 'LIVE')
       + (SELECT COUNT(*) FROM sys_rows t, live_sys s
          WHERE t.copy = 'LIVE'
            AND NOT COALESCE(t.status = s.status AND t.from_value = s.from_value AND t.item = s.item
                             AND t.action = s.action AND t.detail = s.detail, FALSE))
       + (SELECT COUNT(*) FROM sys_rows t, red_names r
          WHERE t.copy = 'LIVE'
            AND NOT COALESCE(ARRAY_TO_STRING(t.names, '|') = ARRAY_TO_STRING(r.names, '|'), FALSE))
),
-- THE LINE DOES NOT SAY A NIGHT WAS NOT SAVED when the alarm is RED, or does not quote the board's
-- own words for it (the last plan date, the nights missing): Ori reads 'checks RED' and moves on.
c05a AS (
  SELECT 'C05a NEGATIVE CONTROL the SYSTEM twin FIRES: plan_partition_fresh doctored RED -> an alarm, quoted with its detail first',
         (SELECT IF(n_alarm >= 1
                    AND (red_list LIKE 'plan_partition_fresh (last plan 2026-09-28, 3 night(s) missing%'
                         -- pipeline_step_failing, were it RED on the same day, would lead the list
                         OR red_list LIKE 'pipeline_step_failing (%; plan_partition_fresh (last plan 2026-09-28, 3 night(s) missing%'), 0, 1)
          FROM sys_twin WHERE copy = 'NC_ALARM')
),
-- THE LINE CANNOT GO QUIET: a healthy board still prints names, and the reader stops trusting it.
c05b AS (
  SELECT 'C05b NEGATIVE CONTROL the SYSTEM twin HOLDS: every status GREEN -> 0 RED and no list',
         (SELECT IF(n_red = 0 AND n_alarm = 0 AND red_list IS NULL, 0, 1) FROM sys_twin WHERE copy = 'NC_ALL_GREEN')
),
-- THE TWIN HAS DRIFTED FROM THE VIEW: C05a/C05b prove a line the brief no longer builds.
c05c AS (
  SELECT 'C05c the twin\'s live reading equals the deployed SYSTEM row (RED count, status, every name)',
         (SELECT IF(t.n_red = s.from_value AND (t.n_red > 0) = (s.status = 'RED')
                    AND t.n_checks = (SELECT COUNT(*) FROM board), 0, 1)
          FROM sys_twin t, live_sys s WHERE t.copy = 'LIVE')
       + (SELECT COUNT(*) FROM UNNEST((SELECT names FROM red_names)) AS r
          WHERE NOT EXISTS (SELECT 1 FROM sys_twin t WHERE t.copy = 'LIVE' AND t.red_list LIKE CONCAT('%', r, '%')))
),
-- A DEMOTION UNDER THE GUARD WITH NO PUBLISHED RELEASE READS GREEN: the veto that cost a month
-- of plans comes back as silence instead of as a RED.
c06a AS (
  SELECT 'C06a NEGATIVE CONTROL plan_settle_guard_holds FIRES: one under-guard row\'s guard_released_by nulled -> 1 (vacuous when the live plan has no under-guard row)',
         (SELECT IF((SELECT COUNTIF(under_guard) FROM plb) = 0, 0,
                    IF((SELECT v FROM guard_fired WHERE copy = 'NC_NULL_RELEASE') = 1, 0, 1)))
),
-- A HOLD THAT WAS NOT EARNED BY A VERY GOOD LAST DAY READS GREEN: P-14c is not asserted anywhere
-- the brief can see.
c06b AS (
  SELECT 'C06b NEGATIVE CONTROL plan_settle_guard_holds FIRES: one HELD_UNSETTLED row\'s last_day_strong flipped -> 1 (vacuous when the live plan holds nothing)',
         (SELECT IF((SELECT COUNTIF(verdict = 'HELD_UNSETTLED') FROM plb) = 0, 0,
                    IF((SELECT v FROM guard_fired WHERE copy = 'NC_HELD_WEAK') = 1, 0, 1)))
),
-- P-18 (v27.156): A HOLD KEPT BY A STRONG DAY THAT HAS LEFT THE WINDOW READS GREEN.
c06d AS (
  SELECT 'C06d NEGATIVE CONTROL plan_settle_guard_holds FIRES: a HELD row kept by STRONG_DAY_IN_WINDOW whose strong day is one day before window_from -> 1',
         (SELECT IF(v = (SELECT v FROM guard_fired WHERE copy = 'LIVE') + 1, 0, 1)
          FROM guard_fired WHERE copy = 'NC_HELD_SD_OUT')
),
-- ...AND A HOLD KEPT BY A STRONG DAY STILL IN THE WINDOW READS RED: the board would cry wolf on
-- the rule Ori ruled.
c06e AS (
  SELECT 'C06e plan_settle_guard_holds HOLDS: the same HELD row with its strong day on window_from -> unchanged from LIVE',
         (SELECT IF(v = (SELECT v FROM guard_fired WHERE copy = 'LIVE'), 0, 1)
          FROM guard_fired WHERE copy = 'HC_HELD_SD_IN')
),
c06c AS (
  SELECT 'C06c the deployed plan_settle_guard_holds agrees with this file\'s twin on the live plan',
         (SELECT IF(COUNT(*) = 0, 1, 0) FROM board WHERE check_name = 'plan_settle_guard_holds')
       + (SELECT COUNTIF(measured != (SELECT v FROM guard_fired WHERE copy = 'LIVE'))
          FROM board WHERE check_name = 'plan_settle_guard_holds')
),
-- ───────────────────────────────────────────────────────────────────────────────────────────
-- v27.163 (piece-1 plan Task 9). A1 plan_pass_failed, A2 the SYSTEM line's NEW / standing, A3 the
-- snapshot table. Each control's measured result is in this file's header.
-- ───────────────────────────────────────────────────────────────────────────────────────────
-- A REFUSED PASS READS GREEN: the 3 of 9 refusals 09-29..10-01 repeat unseen while each night is
-- saved by another pass.
a1a AS (
  SELECT 'A1a NEGATIVE CONTROL plan_pass_failed FIRES: the latest live run doctored FAIL -> RED, counted, its message quoted with its time',
         (SELECT IF(COUNT(*) = 0, 1, 0) FROM ppr_live)
       + (SELECT COUNTIF(NOT (status = 'RED' AND measured >= 1
                              AND detail LIKE 'FAIL % New York: doctored: negative control NC_LATEST_FAIL%'))
          FROM ppf_twin WHERE copy = 'NC_LATEST_FAIL')
),
a1b AS (
  SELECT 'A1b NEGATIVE CONTROL plan_pass_failed FIRES: the latest run OK, an earlier run in the last 24 hours FAIL (the 09-29..10-01 pattern) -> RED, 1',
         (SELECT COUNTIF(NOT (status = 'RED' AND measured = 1
                              AND detail LIKE 'FAIL % New York: doctored: negative control NC_FAIL_IN_24H · latest plan run OK %'))
          FROM ppf_twin WHERE copy = 'NC_FAIL_IN_24H')
),
-- THE ALARM CRIES WOLF FOR A DAY AFTER A FIXED FAILURE, and is read past like the standing REDs.
a1c AS (
  SELECT 'A1c plan_pass_failed HOLDS: the latest run OK after a failure older than 24 hours -> GREEN, 0, the old failure still named',
         (SELECT COUNTIF(NOT (status = 'GREEN' AND measured = 0
                              AND detail LIKE 'latest plan run OK %· 0 of 2 plan run(s) in the last 24 hours failed · last failure %'))
          FROM ppf_twin WHERE copy = 'HC_OLD_FAIL')
),
-- AN EMPTY LOG READS GREEN: an orchestrator that stopped reaching the step has no FAIL to count.
a1d AS (
  SELECT 'A1d NEGATIVE CONTROL plan_pass_failed FIRES on an empty input: no run in 24 hours -> RED; no run in 30 days -> RED; the latest run FAIL 30 hours ago -> RED, 1',
         (SELECT COUNTIF(NOT (status = 'RED' AND measured = 0
                              AND detail LIKE 'no plan run logged in the last 24 hours · latest plan run OK %'))
          FROM ppf_twin WHERE copy = 'NC_NO_RUN_24H')
       + (SELECT COUNTIF(NOT (status = 'RED' AND measured = 0
                              AND detail LIKE 'no plan run logged in the last 24 hours · latest plan run none in 30 days · 0 of 0 %'))
          FROM ppf_twin WHERE copy = 'NC_EMPTY')
       + (SELECT COUNTIF(NOT (status = 'RED' AND measured = 1
                              AND detail LIKE 'FAIL % New York: doctored: negative control NC_LATEST_FAIL_OLD · no plan run logged %'))
          FROM ppf_twin WHERE copy = 'NC_LATEST_FAIL_OLD')
       + (SELECT IF(COUNT(*) = 7, 0, 1) FROM ppf_twin)
),
-- THIS FILE'S TWIN HAS DRIFTED FROM THE VIEW: A1a..A1d prove a check that is no longer deployed.
a1e AS (
  SELECT 'A1e the deployed plan_pass_failed equals this file\'s twin on the live log, read as of the board (measured, status, detail)',
         (SELECT IF(COUNT(*) = 1, 0, 1) FROM board WHERE check_name = 'plan_pass_failed')
       + (SELECT COUNT(*) FROM board b, ppf_twin t
          WHERE b.check_name = 'plan_pass_failed' AND t.copy = 'LIVE'
            AND NOT COALESCE(b.measured = t.measured AND b.status = t.status AND b.detail = t.detail, FALSE))
),
-- A REFUSED PASS NEVER REACHES THE MORNING LINE, or reaches it as a name with no error.
a1f AS (
  SELECT 'A1f NEGATIVE CONTROL the SYSTEM line on plan_pass_failed doctored RED (all else green): RED, says A PLAN PASS FAILED, quotes its error',
         (SELECT COUNTIF(NOT (status = 'RED' AND action LIKE 'A PLAN PASS FAILED — %'
                              AND detail LIKE '%plan_pass_failed (FAIL 2026-10-01 12:58 New York: doctored: negative control NC_PASS_FAILED%'))
          FROM sys_rows WHERE copy = 'NC_PASS_FAILED')
       + (SELECT IF(COUNT(*) = 1, 0, 1) FROM sys_rows WHERE copy = 'NC_PASS_FAILED')
),
-- red_since IS NOT THE START OF THE UNBROKEN RUN: a check that went GREEN and RED again reads as
-- standing since its first RED, which is the old problem with a date on it.
a2a AS (
  SELECT 'A2a red_since is the first snapshot of the unbroken RED run on BD: GREEN gap, AMBER gap and absence each restart it; unbroken = the first snapshot; not RED on the latest = none',
         (SELECT COUNT(*) FROM bd_expect e
          LEFT JOIN hs_run_twin r ON r.copy = 'BD' AND r.check_name = e.name
          WHERE NOT COALESCE(r.red_since = e.red_since, r.red_since IS NULL AND e.red_since IS NULL))
       + (SELECT IF(COUNT(*) = 6, 0, 1) FROM bd_expect e JOIN board b ON b.check_name = e.name)
       -- emptiness: every copy the A2 tests read has its one rendered row (a missing copy would pass them)
       -- v27.176: ten copies (NC_PRED_RED and NC_PRED_ORDER added)
       + (SELECT IF(COUNT(DISTINCT copy) = 10 AND COUNT(*) = 10, 0, 1) FROM sys_rows)
),
-- A2a CANNOT FAIL: it would pass a red_since that ignores the gaps.
a2b AS (
  SELECT 'A2b NEGATIVE CONTROL the earliest-RED form (gaps ignored) differs from A2a\'s answer on the three gapped checks of BD -> 3',
         (SELECT IF(COUNTIF(NOT COALESCE(e.earliest_red = e.red_since, e.earliest_red IS NULL AND e.red_since IS NULL)) = 3, 0, 1)
          FROM bd_expect e)
),
-- THE LINE CALLS A WEEKS-OLD RED NEW, OR A NEW ONE STANDING: the reader cannot tell new from old.
a2c AS (
  SELECT 'A2c the SYSTEM line on BD: X, U, V, W after NEW, each with its start (W since the last snapshot), then standing: Y since the first snapshot or earlier with its detail, Z since its date; the row test passes',
         (SELECT COUNTIF(NOT COALESCE(t.new_list = l.exp_new AND t.standing_list = l.exp_standing
                                      AND t.n_red = 6 AND t.n_new = 4, FALSE))
          FROM sys_twin t CROSS JOIN bd_lines l WHERE t.copy = 'BD')
       + (SELECT COUNTIF(NOT STARTS_WITH(x.detail, CONCAT('SYSTEM: 6 checks RED — ', t.new_list, ' · standing: ', t.standing_list,
                                                          ' · the board\'s memory: 3 snapshots, ')))
          FROM sys_rows x JOIN sys_twin t USING (copy) WHERE x.copy = 'BD')
       + (SELECT COUNT(*) FROM sys_rows
          WHERE copy IN ('BD', 'BD_EMPTY', 'BD_FIRST', 'BD_RECENT')
            AND sys_row_violations(n_rows, section_rank, status, from_value, detail, item, action,
                                   campaign_id, keyword_id, names) > 0)
),
-- THE FIRST MORNING OF THE MEMORY CALLS EVERY STANDING RED NEW: REDs older than the memory come back as news.
a2d AS (
  SELECT 'A2d HOLDS on the first morning: a one-snapshot memory with all six RED on it (BD_FIRST) -> nothing NEW, six standing, each "or earlier"',
         (SELECT COUNTIF(NOT (t.n_new = 0 AND t.new_list IS NULL
                              AND ARRAY_LENGTH(REGEXP_EXTRACT_ALL(t.standing_list, r' or earlier')) = 6
                              AND x.detail LIKE 'SYSTEM: 6 checks RED — nothing NEW in the last 24 hours · standing: %'
                              AND x.detail NOT LIKE '%NEW since%'))
          FROM sys_twin t JOIN sys_rows x USING (copy) WHERE t.copy = 'BD_FIRST')
),
-- AN EMPTY MEMORY CALLS EVERYTHING NEW, or says nothing about why it cannot tell.
a2e AS (
  SELECT 'A2e an empty memory says so (BD_EMPTY): every RED listed as v27.152 did, the memory named empty, neither NEW nor standing',
         (SELECT COUNTIF(NOT COALESCE(STARTS_WITH(x.detail, CONCAT('SYSTEM: 6 checks RED — ', t.red_list,
                                                    ' · the board\'s memory (FACT_ENGINE_HEALTH_HISTORY) is empty, so this line cannot tell a new RED from a standing one · '))
                              AND x.detail NOT LIKE '%NEW since%' AND x.detail NOT LIKE '%standing:%', FALSE))
          FROM sys_twin t JOIN sys_rows x USING (copy) WHERE t.copy = 'BD_EMPTY')
),
-- A2c / A2d / A2e CANNOT FAIL: each test, run on a memory it must reject.
a2c_nc AS (
  SELECT 'A2c NEGATIVE CONTROL A2c\'s expected lines against BD_RECENT (Z moved from standing to NEW) -> the comparison fires',
         (SELECT IF(COUNTIF(COALESCE(t.new_list = l.exp_new AND t.standing_list = l.exp_standing, FALSE)) = 0
                    AND COUNT(*) = 1, 0, 1)
          FROM sys_twin t CROSS JOIN bd_lines l WHERE t.copy = 'BD_RECENT')
),
a2de_nc AS (
  SELECT 'A2d/A2e NEGATIVE CONTROL their tests run on BD (four NEW, a three-snapshot memory) -> both fire',
         (SELECT IF(COUNTIF(t.n_new = 0 AND t.new_list IS NULL
                            AND ARRAY_LENGTH(REGEXP_EXTRACT_ALL(t.standing_list, r' or earlier')) = 6
                            AND x.detail LIKE 'SYSTEM: 6 checks RED — nothing NEW in the last 24 hours · standing: %'
                            AND x.detail NOT LIKE '%NEW since%') = 0, 0, 1)
          FROM sys_twin t JOIN sys_rows x USING (copy) WHERE t.copy = 'BD')
       + (SELECT IF(COUNTIF(COALESCE(STARTS_WITH(x.detail, CONCAT('SYSTEM: 6 checks RED — ', t.red_list,
                                                    ' · the board\'s memory (FACT_ENGINE_HEALTH_HISTORY) is empty, so this line cannot tell a new RED from a standing one · '))
                                     AND x.detail NOT LIKE '%NEW since%' AND x.detail NOT LIKE '%standing:%', FALSE)) = 0, 0, 1)
          FROM sys_twin t JOIN sys_rows x USING (copy) WHERE t.copy = 'BD')
),
-- THE 24-HOUR FENCE IS NOT THERE: a run that started yesterday morning is still called NEW tonight,
-- or one that started this morning is called standing.
a2f AS (
  SELECT 'A2f NEGATIVE CONTROL the 24-hour fence: Z\'s run started 20 hours before (BD_RECENT) -> NEW; 26 hours before (BD) -> standing',
         (SELECT COUNTIF(NOT (STRPOS(COALESCE(new_list, ''), 'plan_proposal_lag_days') > 0
                              AND STRPOS(COALESCE(standing_list, ''), 'plan_proposal_lag_days') = 0 AND n_new = 5))
          FROM sys_twin WHERE copy = 'BD_RECENT')
       + (SELECT COUNTIF(NOT (STRPOS(COALESCE(new_list, ''), 'plan_proposal_lag_days') = 0
                              AND STRPOS(COALESCE(standing_list, ''), 'plan_proposal_lag_days') > 0))
          FROM sys_twin WHERE copy = 'BD')
),
-- THE MEMORY HOLDS A CHECK TWICE FOR ONE PASS: red_since and the counts read a doubled row. Red when
-- the memory is empty (the brief then cannot tell new from standing).
a3a AS (
  SELECT 'A3a nothing twice: no (snapshot_at, check_name) twice in FACT_ENGINE_HEALTH_HISTORY; red when it holds no snapshot',
         (SELECT COUNT(*) FROM (SELECT snapshot_at, check_name FROM hist_dup_copies WHERE copy = 'LIVE'
                                GROUP BY 1, 2 HAVING COUNT(*) > 1))
       + (SELECT IF(COUNT(*) = 0, 1, 0) FROM hist)
),
a3a_nc AS (
  SELECT 'A3a NEGATIVE CONTROL one row of the latest snapshot repeated (NC_DUP) -> 1',
         (SELECT IF(COUNT(*) = 1, 0, 1) FROM (SELECT snapshot_at, check_name FROM hist_dup_copies WHERE copy = 'NC_DUP'
                                               GROUP BY 1, 2 HAVING COUNT(*) > 1))
),
-- A SNAPSHOT MISSES A CHECK: that check's RED run breaks there and it comes back as NEW.
-- Judged when V_ENGINE_HEALTH was last deployed before the latest snapshot (a deploy that adds or
-- renames a check after it would read as a difference); otherwise 0, and the header says so.
a3b AS (
  SELECT 'A3b one row per check: the latest snapshot holds exactly the board\'s checks (0 when the board was deployed after the latest snapshot)',
         (SELECT IF(COALESCE((SELECT TIMESTAMP_MILLIS(last_modified_time) FROM `onyga-482313.OI.__TABLES__`
                              WHERE table_id = 'V_ENGINE_HEALTH') > (SELECT MAX(snapshot_at) FROM hist), TRUE), 0,
                    (SELECT COUNT(*) FROM board b
                     WHERE b.check_name NOT IN (SELECT check_name FROM hist WHERE snapshot_at = (SELECT MAX(snapshot_at) FROM hist)))
                  + (SELECT COUNT(*) FROM hist h
                     WHERE h.snapshot_at = (SELECT MAX(snapshot_at) FROM hist)
                       AND h.check_name NOT IN (SELECT check_name FROM board))))
),
a3b_nc AS (
  SELECT 'A3b NEGATIVE CONTROL one row of the latest snapshot removed (NC_DROP) -> its check set misses 1',
         (SELECT IF(COUNT(*) = 1, 0, 1) FROM hist_dup_copies l
          WHERE l.copy = 'LIVE' AND l.snapshot_at = (SELECT MAX(snapshot_at) FROM hist)
            AND l.check_name NOT IN (SELECT check_name FROM hist_dup_copies d
                                     WHERE d.copy = 'NC_DROP' AND d.snapshot_at = (SELECT MAX(snapshot_at) FROM hist)))
),
-- A PASS WRITES TWO SNAPSHOTS, OR NONE: the memory skips a pass or doubles one.
a3c AS (
  SELECT 'A3c one snapshot per pass: every OK run of SP_SNAPSHOT_ENGINE_HEALTH the orchestrator logged holds exactly one snapshot in [started_at, finished_at] (vacuous before the first pass runs Refresh Task 23; the header counts the runs judged)',
         (SELECT COUNTIF(n_snaps != 1) FROM snap_per_run WHERE copy = 'LIVE')
),
a3c_nc AS (
  SELECT 'A3c NEGATIVE CONTROL on runs around the first snapshot: one held (HC_ONE) -> 0; a second snapshot a second later (NC_TWO) -> 1; a run an hour before it (NC_NONE) -> 1',
         (SELECT IF(COUNTIF(copy = 'HC_ONE' AND n_snaps = 1) = 1
                    AND COUNTIF(copy = 'NC_TWO' AND n_snaps = 2) = 1
                    AND COUNTIF(copy = 'NC_NONE' AND n_snaps = 0) = 1, 0, 1)
          FROM snap_per_run)
),
-- ───────────────────────────────────────────────────────────────────────────────────────────
-- v27.176 (learning-contract piece 2, Task 6). P0 the three checks on the board, P1-P3 their negative
-- controls (V_ENGINE_HEALTH's own c35-c37 text on doctored inputs), P5 the twin tied to the deployed
-- rows, P4 the brief's SYSTEM line on the two RED-able ones. Measured results in this file's header.
-- ───────────────────────────────────────────────────────────────────────────────────────────
-- A LEARNING CHECK THAT IS NOT ON THE BOARD CANNOT GO RED: the grader stops and nothing says so.
p0 AS (
  SELECT 'P0 the learning contract\'s three checks are on the board, once each (prediction_grades_fresh, prediction_regression, response_model_unverified)',
         (SELECT COUNT(*) FROM UNNEST(['prediction_grades_fresh', 'prediction_regression', 'response_model_unverified']) AS n
          WHERE (SELECT COUNT(*) FROM board b WHERE b.check_name = n) != 1)
),
-- THE GRADER STOPS AND THE BOARD STAYS GREEN: predictions go ungraded and the report card goes stale.
p1 AS (
  SELECT 'P1 NEGATIVE CONTROLS prediction_grades_fresh on doctored inputs: a past-due row\'s grade removed -> RED +1; a row one night past the grace -> RED +1; a row in the grace night -> holds; no ledger row, no setting, no watermark -> RED; no other check moves',
         (SELECT COUNTIF(NOT COALESCE(ok, FALSE)) FROM p_result WHERE STRPOS(copy, '_P1_') > 0)
       + (SELECT COUNTIF(NOT same) FROM p_others WHERE STRPOS(copy, '_P1_') > 0)
       + (SELECT IF(COUNT(*) = 6, 0, 1) FROM p_result WHERE STRPOS(copy, '_P1_') > 0)
       + (SELECT IF(ungraded IS NULL, 1, 0) FROM p_pick)
),
-- A FORECAST THAT GETS WORSE READS GREEN, or a margin of 8% reads RED: the regression alarm is noise.
p2 AS (
  SELECT 'P2 NEGATIVE CONTROLS prediction_regression on synthetic cards (six weeks a plan): PLAN_B\'s trailing three 20% worse on mae_net_share -> RED 1, naming the versions that changed; 8% worse -> holds; counterfactual_net_per_alloc worse -> RED 1; five weeks -> INFO YOUNG; an empty card or no setting -> RED; no other check moves',
         (SELECT COUNTIF(NOT COALESCE(ok, FALSE)) FROM p_result WHERE STRPOS(copy, '_P2_') > 0)
       + (SELECT COUNTIF(NOT same) FROM p_others WHERE STRPOS(copy, '_P2_') > 0)
       + (SELECT IF(COUNT(*) = 7, 0, 1) FROM p_result WHERE STRPOS(copy, '_P2_') > 0)
),
-- THE RESPONSE MODEL READS VERIFIED BEFORE ANY PLAN WAS UPLOADED, or stays unverified after one was.
p3 AS (
  SELECT 'P3 CONTROLS response_model_unverified: one current ACT grade with a move applied -> GREEN +1; one with no move applied, or one UNGRADABLE -> holds; no other check moves',
         (SELECT COUNTIF(NOT COALESCE(ok, FALSE)) FROM p_result WHERE STRPOS(copy, '_P3_') > 0)
       + (SELECT COUNTIF(NOT same) FROM p_others WHERE STRPOS(copy, '_P3_') > 0)
       + (SELECT IF(COUNT(*) = 3, 0, 1) FROM p_result WHERE STRPOS(copy, '_P3_') > 0)
       + (SELECT IF(act_move_rn IS NULL, 1, 0) + IF(act_noop_rn IS NULL, 1, 0) FROM p_pick)
),
-- THIS FILE'S INPUTS OR TEXT HAVE DRIFTED FROM THE VIEW: P1-P3 prove checks that are no longer deployed.
p5 AS (
  SELECT 'P5 the deployed c35-c37 rows equal this file\'s twin on its LIVE inputs (measured, threshold, status, detail), and the twin ran every copy',
         (SELECT COUNT(*) FROM UNNEST(['prediction_grades_fresh', 'prediction_regression', 'response_model_unverified']) AS n
          WHERE NOT COALESCE((SELECT LOGICAL_AND(b.measured = t.measured AND b.threshold = t.threshold
                                                 AND b.status = t.status AND b.detail = t.detail)
                              FROM board b JOIN p_twin t ON t.copy = 'LIVE' AND t.check_name = b.check_name
                              WHERE b.check_name = n), FALSE))
       + (SELECT IF(COUNT(*) = 3 * (SELECT COUNT(*) FROM p_copies) AND COUNT(DISTINCT copy) = (SELECT COUNT(*) FROM p_copies), 0, 1)
          FROM p_twin)
),
-- A RED LEARNING CHECK REACHES THE MORNING LINE AS A BARE NAME: Ori sees "prediction_grades_fresh" and
-- not which nights went ungraded.
p4a AS (
  SELECT 'P4a NEGATIVE CONTROL the SYSTEM line on prediction_grades_fresh doctored RED (all else green): RED, NEW, its detail quoted, the row test passes',
         (SELECT COUNTIF(NOT (status = 'RED'
                              AND action LIKE 'a NEW check is RED — %'
                              AND detail LIKE '%prediction_grades_fresh (3 of 8944 ledger rows past due have no grade (nights 2026-08-23 to 2026-08-23) · doctored: negative control NC_PRED_RED)%'
                              AND sys_row_violations(n_rows, section_rank, status, from_value, detail, item, action,
                                                     campaign_id, keyword_id, names) = 0))
          FROM sys_rows WHERE copy = 'NC_PRED_RED')
       + (SELECT IF(COUNT(*) = 1, 0, 1) FROM sys_rows WHERE copy = 'NC_PRED_RED')
),
-- THE LEARNING CHECKS JUMP AHEAD OF A NIGHT THAT WAS NOT SAVED, or fall behind a plain check unquoted.
p4b AS (
  SELECT 'P4b the SYSTEM line orders plan_pass_failed, prediction_grades_fresh, prediction_regression, then a plain check, quoting the first three only; the action stays A PLAN PASS FAILED',
         (SELECT COUNTIF(NOT COALESCE(red_list = 'plan_pass_failed (doctored: NC_PRED_ORDER pass); prediction_grades_fresh (doctored: NC_PRED_ORDER grades); prediction_regression (doctored: NC_PRED_ORDER regression); plan_both_plans_written', FALSE))
          FROM sys_twin WHERE copy = 'NC_PRED_ORDER')
       + (SELECT COUNTIF(NOT (status = 'RED' AND action LIKE 'A PLAN PASS FAILED — %')) FROM sys_rows WHERE copy = 'NC_PRED_ORDER')
       + (SELECT IF(COUNT(*) = 1, 0, 1) FROM sys_rows WHERE copy = 'NC_PRED_ORDER')
),
-- THE RITUAL QUERY'S ORDER CHANGED UNDER THE READER: a section moved, or SYSTEM shares a rank.
c07 AS (
  SELECT 'C07 section ranks: the six sections keep 1..6 and SYSTEM alone is 7',
         (SELECT COUNT(*) FROM (SELECT DISTINCT section, section_rank FROM brief) r
          WHERE NOT (r.section = 'PLANNED' AND r.section_rank = 1 OR r.section = 'SKIPPED' AND r.section_rank = 2
                  OR r.section = 'HAPPENED' AND r.section_rank = 3 OR r.section = 'VERDICT_NEW' AND r.section_rank = 4
                  OR r.section = 'ACTION_ITEM' AND r.section_rank = 5 OR r.section = 'SEATS' AND r.section_rank = 6
                  OR r.section = 'SYSTEM' AND r.section_rank = 7))
       + (SELECT IF(COUNT(*) = 0, 1, 0) FROM brief WHERE section = 'SYSTEM')
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM (SELECT * FROM c01 UNION ALL SELECT * FROM c02 UNION ALL SELECT * FROM c02b
      UNION ALL SELECT * FROM c03a UNION ALL SELECT * FROM c03b UNION ALL SELECT * FROM c03c
      UNION ALL SELECT * FROM c04 UNION ALL SELECT * FROM c04a UNION ALL SELECT * FROM c04b
      UNION ALL SELECT * FROM c04c UNION ALL SELECT * FROM c04d UNION ALL SELECT * FROM c04e
      UNION ALL SELECT * FROM c04f UNION ALL SELECT * FROM c05a UNION ALL SELECT * FROM c05b
      UNION ALL SELECT * FROM c05c UNION ALL SELECT * FROM c06a UNION ALL SELECT * FROM c06b
      UNION ALL SELECT * FROM c06c UNION ALL SELECT * FROM c06d UNION ALL SELECT * FROM c06e
      UNION ALL SELECT * FROM c07
      UNION ALL SELECT * FROM a1a UNION ALL SELECT * FROM a1b UNION ALL SELECT * FROM a1c
      UNION ALL SELECT * FROM a1d UNION ALL SELECT * FROM a1e UNION ALL SELECT * FROM a1f
      UNION ALL SELECT * FROM a2a UNION ALL SELECT * FROM a2b UNION ALL SELECT * FROM a2c
      UNION ALL SELECT * FROM a2d UNION ALL SELECT * FROM a2e UNION ALL SELECT * FROM a2f
      UNION ALL SELECT * FROM a2c_nc UNION ALL SELECT * FROM a2de_nc
      UNION ALL SELECT * FROM a3a UNION ALL SELECT * FROM a3a_nc UNION ALL SELECT * FROM a3b
      UNION ALL SELECT * FROM a3b_nc UNION ALL SELECT * FROM a3c UNION ALL SELECT * FROM a3c_nc
      UNION ALL SELECT * FROM p0 UNION ALL SELECT * FROM p1 UNION ALL SELECT * FROM p2
      UNION ALL SELECT * FROM p3 UNION ALL SELECT * FROM p5 UNION ALL SELECT * FROM p4a
      UNION ALL SELECT * FROM p4b)
ORDER BY check_name;
