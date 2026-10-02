-- =============================================================================================
-- PLAN_HEALTH acceptance — v27.152 (2026-10-01). The plan's health checks on V_ENGINE_HEALTH
-- (c23–c32, plan Task 5 as corrected) and the SYSTEM line of V_DAILY_BRIEF that carries their
-- RED rows to the one query Ori reads every morning. EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Objects: scripts/bigquery/views/V_ENGINE_HEALTH.sql, scripts/bigquery/views/V_DAILY_BRIEF.sql.
-- SOP: architecture/NEXT_WEEK_MONEY.md §6, architecture/ENGINE_HEALTH.md, architecture/DAILY_BRIEF.md.
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
-- The '(vacuous when ...)' controls C06a/C06b, and C04a's '(nothing to remove ...)', say so in
-- their names: a negative control needs a row to doctor, and a live plan with no row under the
-- guard and nothing held, or a board with no RED, is a legitimate state, not a defect — the live
-- positives C06c, C02 and C04f, and the board-with-no-RED pair C04d/C04e, are conclusive on every
-- partition and every board.
-- =============================================================================================

-- ---- the two surfaces, read ONCE each (both are planning-ceiling views; one scan apiece) ----
CREATE TEMP TABLE board AS
  SELECT check_name, measured, threshold, status, detail FROM `onyga-482313.OI.V_ENGINE_HEALTH`;
CREATE TEMP TABLE brief AS
  SELECT section, section_rank, source, campaign_name, item, action, from_value, to_value, status,
         detail, campaign_id, keyword_id
  FROM `onyga-482313.OI.V_DAILY_BRIEF`;
CREATE TEMP TABLE brief_sys AS SELECT * FROM brief WHERE section = 'SYSTEM';

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

-- ---- C02b: plan_partition_fresh — LIVE / latest partition dropped / no partition ----
CREATE TEMP TABLE plan_nights AS SELECT DISTINCT as_of FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`;
-- TWIN of V_ENGINE_HEALTH c31 (plan_clock): due = the later of the Los Angeles day the plan step
-- last ran (OK or FAIL) and yesterday; RED when the latest plan is older than that, or absent
CREATE TEMP TABLE plan_clock_copies AS
  SELECT copy, last_plan,
         GREATEST(COALESCE((SELECT MAX(DATE(started_at, 'America/Los_Angeles')) FROM runs
                            WHERE procedure_name = 'SP_BUILD_NEXT_WEEK_PLAN'), DATE '1900-01-01'),
                  DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY)) AS due
  FROM (SELECT 'LIVE' AS copy, MAX(as_of) AS last_plan FROM plan_nights
        UNION ALL
        SELECT 'NC_DROP_LATEST', MAX(as_of) FROM plan_nights
        WHERE as_of < (SELECT MAX(as_of) FROM plan_nights)
        UNION ALL
        SELECT 'NC_EMPTY', MAX(as_of) FROM plan_nights WHERE FALSE);

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

-- ---- C05: the brief's SYSTEM line — LIVE / every status GREEN / an alarm doctored RED ----
CREATE TEMP TABLE board_copies AS
  SELECT 'LIVE' AS copy, check_name, status, detail FROM board
  UNION ALL
  SELECT 'NC_ALL_GREEN', check_name, IF(status = 'RED', 'GREEN', status), detail FROM board
  UNION ALL
  SELECT 'NC_ALARM', check_name,
         IF(check_name = 'plan_partition_fresh', 'RED', status),
         IF(check_name = 'plan_partition_fresh',
            'last plan 2026-09-28, 3 night(s) missing · doctored: negative control NC_ALARM', detail)
  FROM board;
-- TWIN of V_DAILY_BRIEF `health` (v27.152): the aggregate the SYSTEM line is built from
CREATE TEMP TABLE sys_twin AS
  SELECT copy,
         COUNT(*) AS n_checks,
         COUNTIF(status = 'RED') AS n_red,
         COUNTIF(status = 'RED' AND check_name IN ('pipeline_step_failing', 'plan_partition_fresh')) AS n_alarm,
         STRING_AGG(IF(status = 'RED',
                       IF(check_name IN ('pipeline_step_failing', 'plan_partition_fresh'),
                          CONCAT(check_name, ' (', COALESCE(detail, 'no detail'), ')'), check_name),
                       NULL), '; '
                    ORDER BY CASE check_name WHEN 'pipeline_step_failing' THEN 1
                                             WHEN 'plan_partition_fresh' THEN 2 ELSE 3 END, check_name) AS red_list,
         COALESCE(MAX(IF(check_name = 'plan_partition_fresh',  SPLIT(detail, ' · ')[SAFE_OFFSET(0)], NULL)),
                  'plan_partition_fresh is not on the board') AS plan_clause,
         COALESCE(MAX(IF(check_name = 'pipeline_step_failing', SPLIT(detail, ' · ')[SAFE_OFFSET(0)], NULL)),
                  'pipeline_step_failing is not on the board') AS pipe_clause
  FROM board_copies GROUP BY 1;
-- the board's RED names, per copy. ARRAY_AGG over zero RED rows is NULL, not []: ARRAY_LENGTH(NULL)
-- is NULL, every IF on it takes its else branch and every != against it goes quiet, so the empty
-- case is pinned to [] here (and in red_names below), and the row test never sees a NULL array.
-- IGNORE NULLS keeps a copy with no RED row as a row of its own; a WHERE status = 'RED' would drop it.
CREATE TEMP TABLE red_names_copies AS
  SELECT copy,
         COALESCE(ARRAY_AGG(IF(status = 'RED', check_name, NULL) IGNORE NULLS ORDER BY check_name), []) AS names
  FROM board_copies GROUP BY 1;
-- TWIN of V_DAILY_BRIEF `system_health` (v27.152): the SYSTEM row as the brief renders it from the
-- aggregate above — the deployed view cannot be pointed at a doctored board, so this is how the
-- row test is run on one. C04f ties the LIVE rendering to the deployed row; the all-green branch
-- (the ELSE of status, action and detail) is copied from the view and can only be tied live on a
-- morning the board has no RED.
CREATE TEMP TABLE sys_rows AS
  SELECT t.copy, 1 AS n_rows, 7 AS section_rank,
         CASE WHEN t.n_checks = 0 THEN 'RED' WHEN t.n_red > 0 THEN 'RED' ELSE 'GREEN' END AS status,
         CAST(t.n_red AS FLOAT64) AS from_value,
         CONCAT('SYSTEM: ', CAST(t.n_red AS STRING), ' check', IF(t.n_red = 1, '', 's'), ' RED',
                IF(t.n_red > 0,
                   CONCAT(' — ', COALESCE(t.red_list, '(the list could not be built)')),
                   CONCAT(' — every check on the board is green, amber or a report · ',
                          COALESCE(t.plan_clause, 'no plan clause'), ' · ', COALESCE(t.pipe_clause, 'no pipeline clause'))),
                ' · ', CAST(t.n_checks AS STRING), ' checks read live from V_ENGINE_HEALTH',
                '; the board: SELECT check_name, measured, status, threshold, detail FROM V_ENGINE_HEALTH ORDER BY status = \'GREEN\', check_name') AS detail,
         FORMAT('%d of %d checks RED', t.n_red, t.n_checks) AS item,
         CASE WHEN t.n_checks = 0 THEN 'the board is empty — V_ENGINE_HEALTH returned no rows; read the view by hand before trusting anything above this line'
              WHEN t.n_alarm > 0 THEN 'A NIGHT WAS NOT SAVED — read the failing step\'s error in this line, fix it, and run the step by hand; nothing re-runs it for you, and PLANNED above may be quoting a plan older than it looks'
              WHEN t.n_red > 0 THEN 'read the RED rows on V_ENGINE_HEALTH — each names what it measures and what breaks when it fires'
              ELSE 'nothing to do — no check is RED' END AS action,
         CAST(NULL AS STRING) AS campaign_id, CAST(NULL AS STRING) AS keyword_id,
         r.names
  FROM sys_twin t JOIN red_names_copies r USING (copy);

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
                           'pipeline_step_failing']) AS name
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
  SELECT 'C01 the ten v27.152 checks are on the board, once each' AS check_name,
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
  SELECT 'C02b NEGATIVE CONTROL plan_partition_fresh FIRES: latest partition dropped -> RED with >= 1 night missing; no partition -> RED',
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
      UNION ALL SELECT * FROM c07)
ORDER BY check_name;
