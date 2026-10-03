-- =============================================================================================
-- HOLDOUT_INTEGRITY acceptance — v27.162 (2026-10-03), piece-1 plan Task 8: ruling R9 (spec P-23)
-- and audit fix #27; extended by the v27.162 follow-up (review of commit a2e7e1e: changes between the
-- assignment and the window start). EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^[[:space:]]*--' FILE)"
--   It runs 10+ minutes: submit with --nosync and poll with bq wait (the run below took 806 s).
-- Objects: scripts/bigquery/views/V_HOLDOUT_READOUT.sql (the CENSORED and PRE_WINDOW_CHANGE rows),
--          scripts/bigquery/views/V_ENGINE_HEALTH.sql (c33 holdout_unit_changed).
-- SOP: architecture/HOLDOUT.md §6 "Contamination"; architecture/ENGINE_HEALTH.md.
--
-- THE RULE UNDER TEST (R9, Ori 2026-10-02, option (a); HOLDOUT.md §6 #2). A HOLDOUT campaign that
-- changed inside its trial window [eligible_from, trial_end] — a change-log row that was applied
-- (V_PPC_CHANGE_LOG_APPLIED) or a change the observed-change ledger saw on Amazon (FACT_PPC_CHANGE_LOG
-- source OBSERVED) — is contaminated from the Los Angeles day of its first such change; it AND its
-- stratum-mates in both arms are censored from the earliest such day in the stratum.
-- CHANGES BEFORE THE WINDOW (the follow-up). The arms were frozen on assigned_at (2026-08-19); a change
-- from the assignment day (Los Angeles) to the day before eligible_from is NOT censored — whether it
-- contaminates is a ruling for Ori (HOLDOUT.md §6) — but the readout publishes one PRE_WINDOW_CHANGE
-- row per such HOLDOUT unit, dated by its first such change, and the board is AMBER while one stands.
--   H1  the readout's CENSORED rows are exactly the censoring: every unit the rule censors carries one
--       CENSORED row with that censored_from (and its own contaminated_on when it is a contaminated
--       HOLDOUT unit), and no other unit carries one; and its PRE_WINDOW_CHANGE rows are exactly the
--       HOLDOUT units changed before their window, each with pre_window_change_on = its first such
--       day. The expectation is re-derived HERE from the ledger (statements led and pre) — the
--       readout's derivation is what is under test. Emptiness terms: no HOLDOUT unit, no
--       observed-change row at all, or no estimate row (NOT_YET / READY) in the readout reads as a
--       violation, so an empty input can never pass.
--   H2  V_ENGINE_HEALTH holdout_unit_changed on the live board is AMBER with measured 0 while a change
--       before the window stands (GREEN with 0 when none does), and its own text (hu_gap, hu_pre_gap
--       and c33, pasted below VERBATIM from V_ENGINE_HEALTH.sql) reads RED on every doctored copy that
--       leaves a change uncensored, leaves a change before the window unpublished, or empties an
--       input, and GREEN on a copy with no change before the window. H2b ties the pasted text to the
--       deployed row on the live inputs: measured, status, threshold and the whole detail.
--   H3  the readout's gate still holds: before 2027-01-05 exactly one estimate row (NOT_YET), no
--       READY row, and no number on any row — the CENSORED and PRE_WINDOW_CHANGE rows carry dates and
--       a reason only.
-- THE COPIES. Each copy is a full set of the six inputs the check reads (hu_asg = the trial's units,
-- hu_led = the changes on HOLDOUT units inside the window, hu_pre = the changes on HOLDOUT units
-- before it, hu_obs = the observed ledger's size, hu_cens / hu_pre_ro / the readout rows). Picks are
-- deterministic (first by date, then unit_id). "hold" below = AMBER while the live ledger holds a
-- change before the window, else GREEN.
--   LIVE              everything as read.                            H1 0      H2 hold, 0
--   NC_DROP_ONE       the first contaminated HOLDOUT unit's CENSORED row removed (the plan's NC).
--                                                                    H1 >= 1   H2 RED, 1
--   NC_LATE           that row's censored_from one day later.        H1 >= 1   H2 RED, 1
--   NC_DROP_MATE      the first censored TREATED unit's row removed (a stratum-mate).
--                                                                    H1 >= 1   H2 RED, 1
--   HC_EXTRA          a CENSORED row added for an uncensored unit (over-censoring): H1 is two-sided
--                     and fires; the board counts only what is NOT censored and must hold.
--                                                                    H1 >= 1   H2 hold, 0
--   NC_NEW_CHANGE     the next console change: an observed change added on the HOLDOUT unit that is
--                     uncensored (else the latest censored), dated today (else the day before its
--                     censoring); the readout as read does not censor it. H1 >= 1   H2 RED, >= 1
--   NC_NO_HOLDOUT     the HOLDOUT rows of the assignment removed.     H1 >= 1   H2 RED (emptiness)
--   NC_NO_OBSERVED    the observed ledger empty (its rows out of hu_led and hu_pre, hu_obs 0).
--                                                                    H1 >= 1   H2 RED (emptiness)
--   NC_EMPTY_RO       the readout returns no row.                    H1 >= 1   H2 RED, every censored
--                                                                    unit + every unit changed before
--   NC_NUMBER         (H3 only) a CENSORED row carrying holdout_n 1. H3 >= 1
--   NC_PRE_DROP       the first PRE_WINDOW_CHANGE row removed.       H1 >= 1   H2 RED, 1
--   NC_PRE_LATE       that row's pre_window_change_on one day later. H1 >= 1   H2 RED, 1
--   HC_PRE_CLEAN      no change before the window: the pre rows out of the ledger and the
--                     PRE_WINDOW_CHANGE rows out of the readout.     H1 0      H2 GREEN, 0
--   NC_PRE_NEW        a change before the window added on the first HOLDOUT unit with none, dated
--                     the day before its eligible_from; the readout as read does not publish it.
--                                                                    H1 >= 1   H2 RED, 1
--   NC_NUMBER_PRE     (H3 only) a PRE_WINDOW_CHANGE row carrying holdout_n 1.  H3 >= 1
-- A copy whose pick does not exist (no contaminated unit, no censored TREATED unit, no uncensored
-- unit, no PRE_WINDOW_CHANGE row, no HOLDOUT unit without a change before its window, no change before
-- the window at all) says '(vacuous ...)' in its name and passes: a clean trial is a legitimate state,
-- and LIVE, NC_NO_HOLDOUT, NC_NO_OBSERVED and NC_EMPTY_RO are exercised on every input. The two
-- NC_NUMBER copies are left out of the H2 loop (H3 only).
-- TEXT IDENTITY: the hu_gap / hu_pre_gap / c33 block below must equal V_ENGINE_HEALTH.sql's byte for
-- byte, and the deployed definition must carry it (whitespace-normalised). Check both with:
--   python3 -c "import re,json,subprocess;b=lambda t:t[t.index('\nhu_gap AS ('):t.index('\n)\n',t.index('\nc33 AS ('))+2];v=open('scripts/bigquery/views/V_ENGINE_HEALTH.sql').read();a=open('scripts/bigquery/tests/HOLDOUT_INTEGRITY_acceptance.sql').read();d=json.loads(subprocess.check_output(['bq','query','--project_id=onyga-482313','--use_legacy_sql=false','--format=json',\"SELECT view_definition FROM \`onyga-482313.OI.INFORMATION_SCHEMA.VIEWS\` WHERE table_name='V_ENGINE_HEALTH'\"]))[0]['view_definition'];n=lambda s:re.sub(r'\s+',' ',s);print('file==acceptance',b(v)==b(a),'deployed carries it',n(b(v)) in n(d))"
--
-- RUN 2026-10-03 after deploying the follow-up's V_HOLDOUT_READOUT and V_ENGINE_HEALTH (job
-- bqjob_r1be9f278e3781e6f_000001a1004aff73_1, submitted --nosync, 109 statements, 806 s, 266.2
-- slot-s, 14.8 MB, no FACT_AMAZON_ADS): 31 rows, every one PASS, every control exercised (none
-- vacuous). Text identity after the deploy: file==acceptance True, deployed carries it True. Readings:
--   H1 violations: LIVE 0 (61 units the rule censors, 7 HOLDOUT units changed before the window) ·
--      NC_DROP_ONE 2 · NC_LATE 1 · NC_DROP_MATE 1 · HC_EXTRA 1 · NC_NEW_CHANGE 7 (67 units on that copy)
--      · NC_NO_HOLDOUT 69 · NC_NO_OBSERVED 72 (5 units changed before the window on that copy: the
--      logged rows only) · NC_EMPTY_RO 77 · NC_PRE_DROP 1 · NC_PRE_LATE 1 · NC_PRE_NEW 1 (the added
--      change on ME-SP/PHRASE (tween-girl-birthday-gift, Purple) 130253181662559, 2026-08-31) ·
--      HC_PRE_CLEAN 0.
--   H2 (status, measured): LIVE AMBER 0 · NC_DROP_ONE RED 1 · NC_LATE RED 1 · NC_DROP_MATE RED 1 ·
--      HC_EXTRA AMBER 0 · NC_NEW_CHANGE RED 6 · NC_NO_HOLDOUT RED 0 (emptiness) · NC_NO_OBSERVED RED 0
--      (emptiness) · NC_EMPTY_RO RED 68 (61 + 7) · NC_PRE_DROP RED 1 · NC_PRE_LATE RED 1 · NC_PRE_NEW
--      RED 1 · HC_PRE_CLEAN GREEN 0. H2a the deployed row AMBER 0; H2b equal on measured, status,
--      threshold and the whole detail.
--   H3 LIVE 0 (61 CENSORED rows, 7 PRE_WINDOW_CHANGE rows, 1 estimate row) · NC_NUMBER 1 ·
--      NC_NUMBER_PRE 1.
-- EARLIER RUNS (v27.162, before the follow-up): job bqjob_r5628fe341cbbaa3e_000001a1002f5b71_1, 66
-- statements, 249 s, 179.2 slot-s, 22 rows PASS, H2 LIVE GREEN 0 — the window-only check, which did
-- not see the 25 ledger rows on 7 HOLDOUT units between 2026-08-19 and 2026-08-31. The first run (job
-- bqjob_r740ea0939f232cc6_000001a100292209_1) also read 22 PASS and showed the board's RED detail
-- printing "censors it from NULL" (FORMAT('%t', NULL) is the string 'NULL', so the COALESCE never fell
-- through); both texts test IS NULL since.
-- =============================================================================================

-- ---- the live inputs, each read once ----
CREATE TEMP TABLE asg0 AS
  SELECT unit_id, unit_name, arm, stratum, eligible_from, trial_end, assigned_at
  FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
  WHERE trial_id = 'HOLDOUT-2026Q4-CAMPAIGN' AND unit_type = 'CAMPAIGN';
-- every change on a HOLDOUT unit inside its window, from the two sources the rule names (statement led)
CREATE TEMP TABLE led AS
  SELECT h.unit_id, h.unit_name, h.stratum, DATE(l.applied_at, 'America/Los_Angeles') AS change_day,
         l.change_id, l.source, l.action
  FROM asg0 h
  JOIN (SELECT campaign_id, applied_at, change_id, source, action FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
        UNION ALL
        SELECT campaign_id, applied_at, change_id, source, action FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
        WHERE source = 'OBSERVED') l
    ON l.campaign_id = h.unit_id
  WHERE h.arm = 'HOLDOUT'
    AND DATE(l.applied_at, 'America/Los_Angeles') BETWEEN h.eligible_from AND h.trial_end;
-- every change on a HOLDOUT unit from its assignment day to the day before its window start, from the
-- same two sources (statement pre; the v27.162 follow-up)
CREATE TEMP TABLE pre AS
  SELECT h.unit_id, h.unit_name, h.stratum, DATE(l.applied_at, 'America/Los_Angeles') AS change_day,
         l.applied_at, l.change_id, l.source, l.action
  FROM asg0 h
  JOIN (SELECT campaign_id, applied_at, change_id, source, action FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
        UNION ALL
        SELECT campaign_id, applied_at, change_id, source, action FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
        WHERE source = 'OBSERVED') l
    ON l.campaign_id = h.unit_id
  WHERE h.arm = 'HOLDOUT'
    AND DATE(l.applied_at, 'America/Los_Angeles') >= DATE(h.assigned_at, 'America/Los_Angeles')
    AND DATE(l.applied_at, 'America/Los_Angeles') < h.eligible_from;
CREATE TEMP TABLE obs0 AS
  SELECT COUNT(*) AS n FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` WHERE source = 'OBSERVED';
-- the deployed readout, every row (no FACT_AMAZON_ADS before 2027-01-05: the estimate is gated off)
CREATE TEMP TABLE ro AS
  SELECT state, unit_id, arm, stratum, contaminated_on, censored_from, pre_window_change_on,
         (holdout_n IS NOT NULL OR treated_n IS NOT NULL OR holdout_dollars_14d IS NOT NULL
          OR treated_dollars_14d IS NOT NULL OR holdout_pre_dollars_14d IS NOT NULL
          OR treated_pre_dollars_14d IS NOT NULL OR diff_raw_14d IS NOT NULL
          OR diff_adjusted_14d IS NOT NULL OR band_95_14d IS NOT NULL OR mde_ex_ante_14d IS NOT NULL) AS has_number
  FROM `onyga-482313.OI.V_HOLDOUT_READOUT`;
-- the deployed board's row (filtering on check_name prunes every other check: measured 2026-10-03)
CREATE TEMP TABLE board AS
  SELECT check_name, measured, threshold, status, detail
  FROM `onyga-482313.OI.V_ENGINE_HEALTH` WHERE check_name = 'holdout_unit_changed';

-- ---- the picks ----
CREATE TEMP TABLE pick AS
SELECT
  (SELECT AS STRUCT unit_id, censored_from FROM ro
   WHERE state = 'CENSORED' AND contaminated_on IS NOT NULL
   ORDER BY contaminated_on, unit_id LIMIT 1) AS contam_row,
  (SELECT AS STRUCT unit_id, censored_from FROM ro
   WHERE state = 'CENSORED' AND arm = 'TREATED'
   ORDER BY censored_from, unit_id LIMIT 1) AS mate_row,
  (SELECT AS STRUCT a.unit_id, a.arm, a.stratum FROM asg0 a
   WHERE a.unit_id NOT IN (SELECT unit_id FROM ro WHERE state = 'CENSORED' AND unit_id IS NOT NULL)
   ORDER BY a.unit_id LIMIT 1) AS free_unit,
  (SELECT AS STRUCT a.unit_id, a.unit_name, a.stratum, a.eligible_from,
          COALESCE(DATE_SUB(c.censored_from, INTERVAL 1 DAY),
                   LEAST(CURRENT_DATE('America/Los_Angeles'), a.trial_end)) AS day
   FROM asg0 a
   LEFT JOIN (SELECT unit_id, censored_from FROM ro WHERE state = 'CENSORED') c USING (unit_id)
   WHERE a.arm = 'HOLDOUT'
   ORDER BY c.censored_from IS NOT NULL, c.censored_from DESC, a.unit_id LIMIT 1) AS new_change,
  (SELECT AS STRUCT unit_id, pre_window_change_on FROM ro
   WHERE state = 'PRE_WINDOW_CHANGE'
   ORDER BY pre_window_change_on, unit_id LIMIT 1) AS pre_row,
  (SELECT AS STRUCT a.unit_id, a.unit_name, a.stratum, DATE(a.assigned_at, 'America/Los_Angeles') AS asg_day,
          DATE_SUB(a.eligible_from, INTERVAL 1 DAY) AS day
   FROM asg0 a
   WHERE a.arm = 'HOLDOUT' AND a.unit_id NOT IN (SELECT unit_id FROM pre)
   ORDER BY a.unit_id LIMIT 1) AS pre_new;

-- ---- the copies of the inputs ----
CREATE TEMP TABLE copies AS
SELECT copy FROM UNNEST(['LIVE', 'NC_DROP_ONE', 'NC_LATE', 'NC_DROP_MATE', 'HC_EXTRA', 'NC_NEW_CHANGE',
                         'NC_NO_HOLDOUT', 'NC_NO_OBSERVED', 'NC_EMPTY_RO', 'NC_NUMBER',
                         'NC_PRE_DROP', 'NC_PRE_LATE', 'HC_PRE_CLEAN', 'NC_PRE_NEW', 'NC_NUMBER_PRE']) AS copy;

CREATE TEMP TABLE cp_asg AS
SELECT c.copy, a.* FROM copies c CROSS JOIN asg0 a
WHERE NOT (c.copy = 'NC_NO_HOLDOUT' AND a.arm = 'HOLDOUT');

CREATE TEMP TABLE cp_led AS
SELECT c.copy, l.unit_id, l.unit_name, l.stratum, l.change_day, l.source
FROM copies c CROSS JOIN led l
WHERE NOT (c.copy = 'NC_NO_HOLDOUT')
  AND NOT (c.copy = 'NC_NO_OBSERVED' AND l.source = 'OBSERVED')
UNION ALL
SELECT 'NC_NEW_CHANGE', p.new_change.unit_id, p.new_change.unit_name, p.new_change.stratum,
       p.new_change.day, 'OBSERVED'
FROM pick p
WHERE p.new_change.day >= p.new_change.eligible_from;

CREATE TEMP TABLE cp_pre AS
SELECT c.copy, r.unit_id, r.unit_name, r.stratum, r.change_day, r.source
FROM copies c CROSS JOIN pre r
WHERE NOT (c.copy = 'NC_NO_HOLDOUT')
  AND NOT (c.copy = 'NC_NO_OBSERVED' AND r.source = 'OBSERVED')
  AND NOT (c.copy = 'HC_PRE_CLEAN')
UNION ALL
SELECT 'NC_PRE_NEW', p.pre_new.unit_id, p.pre_new.unit_name, p.pre_new.stratum, p.pre_new.day, 'OBSERVED'
FROM pick p
WHERE p.pre_new.day >= p.pre_new.asg_day;

CREATE TEMP TABLE cp_obs AS
SELECT c.copy, IF(c.copy = 'NC_NO_OBSERVED', 0, o.n) AS n FROM copies c CROSS JOIN obs0 o;

CREATE TEMP TABLE cp_ro AS
SELECT c.copy, r.state, r.unit_id, r.arm, r.contaminated_on,
       IF(c.copy = 'NC_LATE' AND r.state = 'CENSORED' AND r.unit_id = p.contam_row.unit_id,
          DATE_ADD(r.censored_from, INTERVAL 1 DAY), r.censored_from) AS censored_from,
       IF(c.copy = 'NC_PRE_LATE' AND r.state = 'PRE_WINDOW_CHANGE' AND r.unit_id = p.pre_row.unit_id,
          DATE_ADD(r.pre_window_change_on, INTERVAL 1 DAY), r.pre_window_change_on) AS pre_window_change_on,
       IF((c.copy = 'NC_NUMBER' AND r.state = 'CENSORED'
           AND r.unit_id = (SELECT MIN(unit_id) FROM ro WHERE state = 'CENSORED'))
          OR (c.copy = 'NC_NUMBER_PRE' AND r.state = 'PRE_WINDOW_CHANGE' AND r.unit_id = p.pre_row.unit_id),
          TRUE, r.has_number) AS has_number
FROM copies c CROSS JOIN ro r CROSS JOIN pick p
WHERE c.copy != 'NC_EMPTY_RO'
  AND NOT (c.copy = 'NC_DROP_ONE'  AND r.state = 'CENSORED' AND r.unit_id = p.contam_row.unit_id)
  AND NOT (c.copy = 'NC_DROP_MATE' AND r.state = 'CENSORED' AND r.unit_id = p.mate_row.unit_id)
  AND NOT (c.copy = 'NC_PRE_DROP'  AND r.state = 'PRE_WINDOW_CHANGE' AND r.unit_id = p.pre_row.unit_id)
  AND NOT (c.copy = 'HC_PRE_CLEAN' AND r.state = 'PRE_WINDOW_CHANGE')
UNION ALL
SELECT 'HC_EXTRA', 'CENSORED', p.free_unit.unit_id, p.free_unit.arm, CAST(NULL AS DATE),
       CURRENT_DATE('America/Los_Angeles'), CAST(NULL AS DATE), FALSE
FROM pick p WHERE p.free_unit.unit_id IS NOT NULL;

-- ---- H1: per copy, the CENSORED rows against the rule re-derived from that copy's ledger ----
CREATE TEMP TABLE h1 AS
WITH
exp AS (
  SELECT a.copy, a.unit_id, c.contaminated_on, s.censored_from, q.pre_window_change_on
  FROM cp_asg a
  LEFT JOIN (SELECT copy, unit_id, MIN(change_day) AS contaminated_on FROM cp_led GROUP BY 1, 2) c
         ON c.copy = a.copy AND c.unit_id = a.unit_id
  LEFT JOIN (SELECT copy, stratum, MIN(change_day) AS censored_from FROM cp_led GROUP BY 1, 2) s
         ON s.copy = a.copy AND s.stratum = a.stratum
  LEFT JOIN (SELECT copy, unit_id, MIN(change_day) AS pre_window_change_on FROM cp_pre GROUP BY 1, 2) q
         ON q.copy = a.copy AND q.unit_id = a.unit_id
),
act AS (  -- the readout's unit rows: CENSORED and PRE_WINDOW_CHANGE, one key per (copy, state, unit)
  SELECT copy, state, unit_id, COUNT(*) AS n_rows, MIN(censored_from) AS censored_from,
         MIN(contaminated_on) AS contaminated_on, MIN(pre_window_change_on) AS pre_window_change_on
  FROM cp_ro WHERE state IN ('CENSORED', 'PRE_WINDOW_CHANGE') GROUP BY 1, 2, 3
),
per_unit AS (  -- every trial unit of the copy against its CENSORED row and its PRE_WINDOW_CHANGE row (absent = NULL)
  SELECT e.copy,
         COUNTIF(e.censored_from IS DISTINCT FROM x.censored_from) AS v_censored_from,
         COUNTIF(e.contaminated_on IS DISTINCT FROM x.contaminated_on) AS v_contaminated_on,
         COUNTIF(e.pre_window_change_on IS DISTINCT FROM xp.pre_window_change_on) AS v_pre_window,
         COUNTIF(e.censored_from IS NOT NULL) AS n_expected_censored,
         COUNTIF(e.pre_window_change_on IS NOT NULL) AS n_expected_pre
  FROM exp e
  LEFT JOIN act x  ON x.copy = e.copy  AND x.unit_id = e.unit_id  AND x.state = 'CENSORED'
  LEFT JOIN act xp ON xp.copy = e.copy AND xp.unit_id = e.unit_id AND xp.state = 'PRE_WINDOW_CHANGE'
  GROUP BY 1
),
per_row AS (  -- CENSORED / PRE_WINDOW_CHANGE rows: duplicated, or naming no trial unit of the copy
  SELECT x.copy, COUNTIF(x.n_rows > 1) AS v_duplicate, COUNTIF(a.unit_id IS NULL) AS v_alien
  FROM act x LEFT JOIN (SELECT DISTINCT copy, unit_id FROM cp_asg) a ON a.copy = x.copy AND a.unit_id = x.unit_id
  GROUP BY 1
),
empt AS (  -- the emptiness terms
  SELECT c.copy,
         IF(COALESCE(ah.n_holdout, 0) = 0, 1, 0) + IF(COALESCE(o.n, 0) = 0, 1, 0)
           + IF(COALESCE(re.n_est, 0) = 0, 1, 0) AS v_empty
  FROM copies c
  LEFT JOIN (SELECT copy, COUNTIF(arm = 'HOLDOUT') AS n_holdout FROM cp_asg GROUP BY 1) ah ON ah.copy = c.copy
  LEFT JOIN cp_obs o ON o.copy = c.copy
  LEFT JOIN (SELECT copy, COUNTIF(state IN ('NOT_YET', 'READY')) AS n_est FROM cp_ro GROUP BY 1) re ON re.copy = c.copy
)
SELECT c.copy,
       COALESCE(u.v_censored_from, 0) AS v_censored_from,
       COALESCE(u.v_contaminated_on, 0) AS v_contaminated_on,
       COALESCE(u.v_pre_window, 0) AS v_pre_window,
       COALESCE(r.v_duplicate, 0) AS v_duplicate,
       COALESCE(r.v_alien, 0) AS v_alien,
       e.v_empty,
       COALESCE(u.n_expected_censored, 0) AS n_expected_censored,
       COALESCE(u.n_expected_pre, 0) AS n_expected_pre
FROM copies c
LEFT JOIN per_unit u ON u.copy = c.copy
LEFT JOIN per_row r ON r.copy = c.copy
LEFT JOIN empt e ON e.copy = c.copy;

-- ---- H2: the board's own text, run on each copy ----
CREATE TEMP TABLE twin (copy STRING, check_name STRING, measured FLOAT64, threshold STRING, status STRING, detail STRING);
FOR cp IN (SELECT copy FROM copies WHERE copy NOT IN ('NC_NUMBER', 'NC_NUMBER_PRE') ORDER BY copy) DO
  CREATE OR REPLACE TEMP TABLE hu_asg AS
    SELECT unit_id, unit_name, arm, stratum, eligible_from, trial_end, assigned_at FROM cp_asg WHERE copy = cp.copy;
  CREATE OR REPLACE TEMP TABLE hu_led AS
    SELECT unit_id, unit_name, stratum, change_day FROM cp_led WHERE copy = cp.copy;
  CREATE OR REPLACE TEMP TABLE hu_pre AS
    SELECT unit_id, unit_name, stratum, change_day FROM cp_pre WHERE copy = cp.copy;
  CREATE OR REPLACE TEMP TABLE hu_cens AS
    SELECT unit_id, censored_from FROM cp_ro WHERE copy = cp.copy AND state = 'CENSORED';
  CREATE OR REPLACE TEMP TABLE hu_pre_ro AS
    SELECT unit_id, pre_window_change_on FROM cp_ro WHERE copy = cp.copy AND state = 'PRE_WINDOW_CHANGE';
  CREATE OR REPLACE TEMP TABLE hu_obs AS
    SELECT n FROM cp_obs WHERE copy = cp.copy;
  INSERT INTO twin (copy, check_name, measured, threshold, status, detail)
  WITH
hu_gap AS (  -- trial units, either arm, that the readout does not censor from a change in their stratum on
  SELECT m.unit_id, m.unit_name, m.arm, m.stratum,
         MIN(t.change_day) AS first_change_day, MIN(c.censored_from) AS censored_from
  FROM hu_led t
  JOIN hu_asg m ON m.stratum = t.stratum
  LEFT JOIN hu_cens c ON c.unit_id = m.unit_id
  WHERE c.censored_from IS NULL OR c.censored_from > t.change_day
  GROUP BY 1, 2, 3, 4
),
hu_pre_gap AS (  -- HOLDOUT units changed before their window that the readout does not publish from that day on
  SELECT p.unit_id, p.unit_name, p.stratum,
         MIN(p.change_day) AS first_change_day, MIN(r.pre_window_change_on) AS published_on
  FROM hu_pre p
  LEFT JOIN hu_pre_ro r ON r.unit_id = p.unit_id
  GROUP BY 1, 2, 3
  HAVING MIN(r.pre_window_change_on) IS NULL OR MIN(r.pre_window_change_on) > MIN(p.change_day)
),
c33 AS (  -- R9 / fix #27: a change on a HOLDOUT campaign inside its window is censored with its stratum; a change between its assignment and its window start is published, and AMBER while Ori has not ruled on it
  SELECT 'holdout_unit_changed',
    CAST((SELECT COUNT(*) FROM hu_gap) + (SELECT COUNT(*) FROM hu_pre_gap) AS FLOAT64),
    'trial campaigns (either arm) sharing a stratum with a HOLDOUT campaign that changed inside its trial window (a change-log row applied, or a change observed on Amazon), which V_HOLDOUT_READOUT does not censor from that day on, + HOLDOUT campaigns changed between their assignment and their window start that the readout does not publish (PRE_WINDOW_CHANGE) · red > 0 (P-23 / R9, audit fix #27); red when no HOLDOUT unit or no observed-change row is read; amber while a HOLDOUT campaign changed between its assignment and its window start, which R9 does not censor (a ruling for Ori, HOLDOUT.md §6)',
    CASE WHEN (SELECT COUNTIF(arm = 'HOLDOUT') FROM hu_asg) = 0 THEN 'RED'
         WHEN (SELECT n FROM hu_obs) = 0 THEN 'RED'
         WHEN (SELECT COUNT(*) FROM hu_gap) + (SELECT COUNT(*) FROM hu_pre_gap) > 0 THEN 'RED'
         WHEN (SELECT COUNT(*) FROM hu_pre) > 0 THEN 'AMBER'
         ELSE 'GREEN' END,
    CONCAT(
      CASE WHEN (SELECT COUNTIF(arm = 'HOLDOUT') FROM hu_asg) = 0 THEN 'no HOLDOUT unit read from DE_HOLDOUT_ASSIGNMENT · '
           WHEN (SELECT n FROM hu_obs) = 0 THEN 'the observed-change ledger is empty, so a console change on a HOLDOUT campaign would be invisible · '
           ELSE '' END,
      IF((SELECT COUNT(*) FROM hu_gap) > 0,
         CONCAT('NOT CENSORED: ',
                (SELECT STRING_AGG(FORMAT('%s (%s, %s, %s): its stratum changed on %t, the readout censors it %s',
                                          unit_name, unit_id, arm, stratum, first_change_day,
                                          IF(censored_from IS NULL, 'never', FORMAT('from %t', censored_from))),
                                   '; ' ORDER BY first_change_day, unit_id) FROM hu_gap),
                ' · '),
         ''),
      IF((SELECT COUNT(*) FROM hu_pre_gap) > 0,
         CONCAT('NOT PUBLISHED: ',
                (SELECT STRING_AGG(FORMAT('%s (%s, %s): changed on %t before its window start, the readout publishes it %s',
                                          unit_name, unit_id, stratum, first_change_day,
                                          IF(published_on IS NULL, 'never', FORMAT('from %t', published_on))),
                                   '; ' ORDER BY first_change_day, unit_id) FROM hu_pre_gap),
                ' · '),
         ''),
      IF((SELECT COUNT(*) FROM hu_pre) > 0,
         CONCAT('A RULING FOR ORI: ', CAST((SELECT COUNT(DISTINCT unit_id) FROM hu_pre) AS STRING), ' of ',
                CAST((SELECT COUNTIF(arm = 'HOLDOUT') FROM hu_asg) AS STRING),
                ' HOLDOUT campaign(s) changed between their assignment and their window start, which R9 does not censor, so the readout scores them and their stratum-mates as untouched from the window start (first day): ',
                (SELECT STRING_AGG(FORMAT('%s %t', unit_name, d), ', ' ORDER BY d, unit_id)
                 FROM (SELECT unit_id, unit_name, MIN(change_day) AS d FROM hu_pre GROUP BY 1, 2)),
                ' · '),
         ''),
      CAST((SELECT COUNT(DISTINCT unit_id) FROM hu_led) AS STRING), ' of ',
      CAST((SELECT COUNTIF(arm = 'HOLDOUT') FROM hu_asg) AS STRING),
      ' HOLDOUT campaign(s) changed inside the trial window',
      COALESCE((SELECT CONCAT(' (first day): ', STRING_AGG(FORMAT('%s %t', unit_name, d), ', ' ORDER BY d, unit_id))
                FROM (SELECT unit_id, unit_name, MIN(change_day) AS d FROM hu_led GROUP BY 1, 2)), ''),
      ' · the readout censors ', CAST((SELECT COUNT(DISTINCT unit_id) FROM hu_cens) AS STRING), ' of ',
      CAST((SELECT COUNT(*) FROM hu_asg) AS STRING),
      ' trial campaigns, both arms, each from the first change in its stratum (R9, HOLDOUT.md §6)')
)
  SELECT cp.copy, * FROM c33;
END FOR;

-- ---- H3: the gate, per copy ----
CREATE TEMP TABLE h3 AS
SELECT c.copy,
  IF(CURRENT_DATE('America/Los_Angeles') < DATE '2027-01-05',
     IF(COALESCE(g.n_not_yet, 0) = 1, 0, 1) + COALESCE(g.n_ready, 0), 0)
  + COALESCE(g.n_number, 0) + COALESCE(g.n_bad_censored, 0) + COALESCE(g.n_bad_pre, 0)
  + COALESCE(g.n_bad_state, 0) AS v_gate
FROM copies c
LEFT JOIN (
  SELECT copy,
         COUNTIF(state = 'NOT_YET') AS n_not_yet,
         COUNTIF(state = 'READY') AS n_ready,
         COUNTIF(has_number AND state IN ('NOT_YET', 'CENSORED', 'PRE_WINDOW_CHANGE')) AS n_number,
         COUNTIF(state = 'CENSORED' AND (unit_id IS NULL OR censored_from IS NULL)) AS n_bad_censored,
         COUNTIF(state = 'PRE_WINDOW_CHANGE' AND (unit_id IS NULL OR pre_window_change_on IS NULL)) AS n_bad_pre,
         COUNTIF(state NOT IN ('NOT_YET', 'READY', 'CENSORED', 'PRE_WINDOW_CHANGE')) AS n_bad_state
  FROM cp_ro GROUP BY 1) g ON g.copy = c.copy;

-- ---- the result ----
WITH
p AS (SELECT * FROM pick),
x AS (
  SELECT
    p.contam_row.unit_id IS NOT NULL AS has_contam,
    p.mate_row.unit_id IS NOT NULL AS has_mate,
    p.free_unit.unit_id IS NOT NULL AS has_free,
    p.new_change.day >= p.new_change.eligible_from AS has_new,
    p.pre_row.unit_id IS NOT NULL AS has_pre_row,
    (SELECT COUNT(*) FROM pre) > 0 AS has_pre_led,
    COALESCE(p.pre_new.day >= p.pre_new.asg_day, FALSE) AS has_pre_new,
    -- the board's status on a copy whose inputs agree: AMBER while a change before the window stands
    IF((SELECT COUNT(*) FROM pre) > 0, 'AMBER', 'GREEN') AS hold_status
  FROM p
),
h AS (
  SELECT copy, v_censored_from + v_contaminated_on + v_pre_window + v_duplicate + v_alien + v_empty AS v,
         FORMAT('censored_from %d, contaminated_on %d, pre_window_change_on %d, duplicate %d, alien %d, emptiness %d · %d unit(s) the rule censors, %d HOLDOUT unit(s) changed before the window, on this copy',
                v_censored_from, v_contaminated_on, v_pre_window, v_duplicate, v_alien, v_empty,
                n_expected_censored, n_expected_pre) AS d
  FROM h1
),
t AS (SELECT * FROM twin),
-- per copy: the vacuity suffix (a copy whose pick does not exist says so and passes)
vac AS (
  SELECT c.copy,
         CASE c.copy WHEN 'NC_DROP_ONE' THEN IF(x.has_contam, '', ' (vacuous: no contaminated unit)')
                     WHEN 'NC_LATE' THEN IF(x.has_contam, '', ' (vacuous: no contaminated unit)')
                     WHEN 'NC_DROP_MATE' THEN IF(x.has_mate, '', ' (vacuous: no censored TREATED unit)')
                     WHEN 'HC_EXTRA' THEN IF(x.has_free, '', ' (vacuous: every trial unit is censored)')
                     WHEN 'NC_NEW_CHANGE' THEN IF(x.has_new, '', ' (vacuous: no day inside a HOLDOUT window before its censoring)')
                     WHEN 'NC_PRE_DROP' THEN IF(x.has_pre_row, '', ' (vacuous: no PRE_WINDOW_CHANGE row)')
                     WHEN 'NC_PRE_LATE' THEN IF(x.has_pre_row, '', ' (vacuous: no PRE_WINDOW_CHANGE row)')
                     WHEN 'NC_NUMBER_PRE' THEN IF(x.has_pre_row, '', ' (vacuous: no PRE_WINDOW_CHANGE row)')
                     WHEN 'NC_PRE_NEW' THEN IF(x.has_pre_new, '', ' (vacuous: no HOLDOUT unit unchanged before its window with a day between its assignment and its window start)')
                     WHEN 'HC_PRE_CLEAN' THEN IF(x.has_pre_led, '', ' (vacuous: no change before the window, the copy equals LIVE)')
                     ELSE '' END AS suffix,
         CASE c.copy WHEN 'NC_DROP_ONE' THEN NOT x.has_contam
                     WHEN 'NC_LATE' THEN NOT x.has_contam
                     WHEN 'NC_DROP_MATE' THEN NOT x.has_mate
                     WHEN 'HC_EXTRA' THEN NOT x.has_free
                     WHEN 'NC_NEW_CHANGE' THEN NOT x.has_new
                     WHEN 'NC_PRE_DROP' THEN NOT x.has_pre_row
                     WHEN 'NC_PRE_LATE' THEN NOT x.has_pre_row
                     WHEN 'NC_NUMBER_PRE' THEN NOT x.has_pre_row
                     WHEN 'NC_PRE_NEW' THEN NOT x.has_pre_new
                     WHEN 'HC_PRE_CLEAN' THEN NOT x.has_pre_led
                     ELSE FALSE END AS is_vacuous
  FROM copies c CROSS JOIN x
),
res AS (
  -- H1
  SELECT 'H1_LIVE every censoring the rule makes is a CENSORED row, every HOLDOUT unit changed before its window is a PRE_WINDOW_CHANGE row, and nothing else is' AS check_name,
         'violations 0' AS expected, CAST(h.v AS STRING) AS measured, h.v = 0 AS ok, h.d AS detail
  FROM h WHERE copy = 'LIVE'
  UNION ALL
  SELECT FORMAT('H1_%s %s%s', h.copy, IF(h.copy = 'HC_PRE_CLEAN', 'holds', 'fires'), v.suffix),
         IF(h.copy = 'HC_PRE_CLEAN', 'violations 0', 'violations >= 1'), CAST(h.v AS STRING),
         IF(h.copy = 'HC_PRE_CLEAN', h.v = 0, h.v >= 1) OR v.is_vacuous,
         h.d
  FROM h JOIN vac v USING (copy) WHERE h.copy NOT IN ('LIVE', 'NC_NUMBER', 'NC_NUMBER_PRE')
  UNION ALL
  -- H2
  SELECT FORMAT('H2a the deployed board row holdout_unit_changed is %s with measured 0', x.hold_status),
         FORMAT('one row, %s, 0', x.hold_status),
         COALESCE((SELECT FORMAT('%d row(s), %s, %g', COUNT(*), MAX(status), MAX(measured)) FROM board), 'none'),
         (SELECT COUNT(*) = 1 AND LOGICAL_AND(status = x.hold_status AND measured = 0) FROM board),
         COALESCE((SELECT MAX(detail) FROM board), 'no row')
  FROM x
  UNION ALL
  SELECT 'H2b the pasted hu_gap / hu_pre_gap / c33 text on the live inputs equals the deployed row (measured, status, threshold, detail)',
         'equal',
         IF(COUNT(*) = 1 AND LOGICAL_AND(b.measured = t.measured AND b.status = t.status
                                          AND b.threshold = t.threshold AND b.detail = t.detail), 'equal', 'different'),
         COUNT(*) = 1 AND LOGICAL_AND(b.measured = t.measured AND b.status = t.status
                                      AND b.threshold = t.threshold AND b.detail = t.detail),
         ANY_VALUE(t.detail)
  FROM board b JOIN t ON t.copy = 'LIVE' AND t.check_name = b.check_name
  UNION ALL
  SELECT FORMAT('H2_%s %s%s', t.copy,
                CASE t.copy WHEN 'HC_EXTRA' THEN 'holds (the board counts what is NOT censored)'
                            WHEN 'HC_PRE_CLEAN' THEN 'holds GREEN (the AMBER is the change before the window)'
                            WHEN 'LIVE' THEN 'holds' ELSE 'fires' END,
                v.suffix),
         CASE t.copy WHEN 'LIVE' THEN FORMAT('%s, 0', x.hold_status)
                     WHEN 'HC_EXTRA' THEN FORMAT('%s, 0', x.hold_status)
                     WHEN 'HC_PRE_CLEAN' THEN 'GREEN, 0'
                     WHEN 'NC_DROP_ONE' THEN 'RED, 1'
                     WHEN 'NC_LATE' THEN 'RED, 1'
                     WHEN 'NC_DROP_MATE' THEN 'RED, 1'
                     WHEN 'NC_PRE_DROP' THEN 'RED, 1'
                     WHEN 'NC_PRE_LATE' THEN 'RED, 1'
                     WHEN 'NC_PRE_NEW' THEN 'RED, 1'
                     WHEN 'NC_EMPTY_RO' THEN 'RED, the units the rule censors + the HOLDOUT units changed before the window'
                     ELSE 'RED' END,
         FORMAT('%s, %g', t.status, t.measured),
         CASE t.copy WHEN 'LIVE' THEN t.status = x.hold_status AND t.measured = 0
                     WHEN 'HC_EXTRA' THEN (t.status = x.hold_status AND t.measured = 0) OR v.is_vacuous
                     WHEN 'HC_PRE_CLEAN' THEN (t.status = 'GREEN' AND t.measured = 0) OR v.is_vacuous
                     WHEN 'NC_NEW_CHANGE' THEN (t.status = 'RED' AND t.measured >= 1) OR v.is_vacuous
                     WHEN 'NC_EMPTY_RO' THEN t.status = 'RED'
                                             AND t.measured = (SELECT n_expected_censored + n_expected_pre FROM h1 WHERE copy = 'NC_EMPTY_RO')
                     WHEN 'NC_NO_HOLDOUT' THEN t.status = 'RED'
                     WHEN 'NC_NO_OBSERVED' THEN t.status = 'RED'
                     ELSE (t.status = 'RED' AND t.measured = 1) OR v.is_vacuous END,
         t.detail
  FROM t JOIN vac v USING (copy) CROSS JOIN x
  UNION ALL
  -- H3
  SELECT 'H3_LIVE the gate holds: one NOT_YET row before 2027-01-05, no READY row, no number on any row',
         'violations 0', CAST(v_gate AS STRING), v_gate = 0,
         FORMAT('%d CENSORED row(s), %d PRE_WINDOW_CHANGE row(s), %d estimate row(s)',
                (SELECT COUNTIF(state = 'CENSORED') FROM ro), (SELECT COUNTIF(state = 'PRE_WINDOW_CHANGE') FROM ro),
                (SELECT COUNTIF(state NOT IN ('CENSORED', 'PRE_WINDOW_CHANGE')) FROM ro))
  FROM h3 WHERE copy = 'LIVE'
  UNION ALL
  SELECT 'H3_NC_NUMBER fires (a CENSORED row carrying a number)', 'violations >= 1', CAST(v_gate AS STRING),
         v_gate >= 1, 'holdout_n set on one CENSORED row'
  FROM h3 WHERE copy = 'NC_NUMBER'
  UNION ALL
  SELECT CONCAT('H3_NC_NUMBER_PRE fires (a PRE_WINDOW_CHANGE row carrying a number)', v.suffix), 'violations >= 1',
         CAST(h3.v_gate AS STRING), h3.v_gate >= 1 OR v.is_vacuous, 'holdout_n set on one PRE_WINDOW_CHANGE row'
  FROM h3 JOIN vac v USING (copy) WHERE h3.copy = 'NC_NUMBER_PRE'
)
SELECT check_name, expected, measured, IF(ok, 'PASS', 'FAIL') AS result, detail
FROM res
ORDER BY check_name;
