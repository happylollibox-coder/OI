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
-- / C05c tie each copy to the deployed view's own output on the live data so the two cannot drift
-- apart unseen. THE EXPRESSIONS MUST CHANGE TOGETHER: c32's pipe_fail HAVING, c31's plan_clock
-- GREATEST, c28's guard COUNTIFs, and the brief's `health` aggregate each have one twin below.
--
-- RUN 2026-10-01 after the first deploy: 17 rows, every one PASS. The intermediates were then
-- printed from the same temp tables so each PASS is known to be a control that FIRED, not a
-- vacuous one (the live figures are the board's, never this file's):
--   C02b: LIVE last_plan 2026-10-01 = due 2026-10-01 (GREEN); NC_DROP_LATEST last_plan
--         2026-09-30 < due 2026-10-01 (RED, 1 night); NC_EMPTY last_plan NULL (RED).
--   C03a/b/c: the victim chosen was REBUILD_T_CAMPAIGN_PRODUCT_SCOPE (most runs in 30 days with
--         its three most recent OK); the twin named it on NC3 and nothing on NC2; on LIVE it
--         named nothing, and the deployed check measured 0.
--   C04: the live brief carried one SYSTEM row, rank 7, status RED, from_value 3, naming the
--         board's three standing REDs; C04a/b/c each returned >= 1 on the doctored copy.
--   C05a: on NC_ALARM the twin read n_red 4, n_alarm 1, and its list led with
--         'plan_partition_fresh (last plan 2026-09-28, 3 night(s) missing · doctored ...)'.
--   C05b: on NC_ALL_GREEN the twin read n_red 0, n_alarm 0, list NULL.
--   C05c: on LIVE the twin read 32 checks, 3 RED — equal to the deployed row.
--   C06a/b: the live plan had 17 rows under the guard preconditions and 2 HELD_UNSETTLED rows;
--         the twin read 1 on NC_NULL_RELEASE, 1 on NC_HELD_WEAK, 0 on LIVE; the deployed check
--         measured 0 (C06c).
-- The two '(vacuous when ...)' controls say so in their names: a negative control needs a row to
-- doctor, and a live plan with no row under the guard and nothing held is a legitimate state, not
-- a defect — the live positives C06c and C02 are conclusive on every partition.
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
    IF(rn = (SELECT MIN(rn) FROM plb WHERE verdict = 'HELD_UNSETTLED'), FALSE, last_day_strong) AS last_day_strong)
  FROM plb;
-- TWIN of V_ENGINE_HEALTH c28 (guard): the two COUNTIFs that make its measured value
CREATE TEMP TABLE guard_fired AS
  SELECT copy,
         COUNTIF(under_guard AND COALESCE(guard_released_by, '') NOT IN ('HOLD_EXPIRED', 'LAST_DAY_NOT_STRONG'))
       + COUNTIF(verdict = 'HELD_UNSETTLED' AND NOT COALESCE(last_day_strong, FALSE)) AS v
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
                                             WHEN 'plan_partition_fresh' THEN 2 ELSE 3 END, check_name) AS red_list
  FROM board_copies GROUP BY 1;

-- ---- C04: the SYSTEM row's shape, written once and run on the live row and on doctored copies ----
-- n_rows = how many SYSTEM rows the brief carries (must be 1); red_names = the board's RED checks.
CREATE TEMP FUNCTION sys_row_violations(n_rows INT64, section_rank INT64, status STRING,
                                        from_value FLOAT64, detail STRING, item STRING, action STRING,
                                        campaign_id STRING, keyword_id STRING,
                                        red_names ARRAY<STRING>) AS (
  IF(n_rows != 1, 1, 0)
  + IF(section_rank != 7, 1, 0)
  + IF(campaign_id IS NOT NULL OR keyword_id IS NOT NULL, 1, 0)
  + IF(COALESCE(detail, '') NOT LIKE 'SYSTEM: %' OR COALESCE(item, '') = '' OR COALESCE(action, '') = '', 1, 0)
  + IF(status != IF(ARRAY_LENGTH(red_names) > 0, 'RED', 'GREEN'), 1, 0)
  + IF(from_value IS NULL OR from_value != ARRAY_LENGTH(red_names), 1, 0)
  + (SELECT COUNT(*) FROM UNNEST(red_names) AS r WHERE COALESCE(detail, '') NOT LIKE CONCAT('%', r, '%'))
);

WITH
expected AS (
  SELECT name FROM UNNEST(['plan_window_complete_days', 'plan_pot_reconciliation', 'plan_one_move_per_notgood',
                           'plan_ownership_no_foreign_go', 'plan_both_plans_written', 'plan_settle_guard_holds',
                           'plan_settle_curve_coverage', 'plan_proposal_lag_days', 'plan_partition_fresh',
                           'pipeline_step_failing']) AS name
),
red_names AS (SELECT ARRAY_AGG(check_name ORDER BY check_name) AS names FROM board WHERE status = 'RED'),
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
-- are the live ones; the controls are conclusive only while the board has at least one RED,
-- which it has had every day since 2026-08-16 — see C04b, which is conclusive regardless).
c04a AS (
  SELECT 'C04a NEGATIVE CONTROL C04 FIRES when a RED name is removed from the detail (vacuous while the board has no RED)',
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
      UNION ALL SELECT * FROM c04c UNION ALL SELECT * FROM c05a UNION ALL SELECT * FROM c05b
      UNION ALL SELECT * FROM c05c UNION ALL SELECT * FROM c06a UNION ALL SELECT * FROM c06b
      UNION ALL SELECT * FROM c06c UNION ALL SELECT * FROM c07)
ORDER BY check_name;
