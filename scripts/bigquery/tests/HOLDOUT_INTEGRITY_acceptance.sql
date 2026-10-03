-- =============================================================================================
-- HOLDOUT_INTEGRITY acceptance — v27.162 (2026-10-03), piece-1 plan Task 8: ruling R9 (spec P-23)
-- and audit fix #27. EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^[[:space:]]*--' FILE)"
-- Objects: scripts/bigquery/views/V_HOLDOUT_READOUT.sql (the CENSORED rows),
--          scripts/bigquery/views/V_ENGINE_HEALTH.sql (c33 holdout_unit_changed).
-- SOP: architecture/HOLDOUT.md §6 "Contamination"; architecture/ENGINE_HEALTH.md.
--
-- THE RULE UNDER TEST (R9, Ori 2026-10-02, option (a); HOLDOUT.md §6 #2). A HOLDOUT campaign that
-- changed inside its trial window [eligible_from, trial_end] — a change-log row that was applied
-- (V_PPC_CHANGE_LOG_APPLIED) or a change the observed-change ledger saw on Amazon (FACT_PPC_CHANGE_LOG
-- source OBSERVED) — is contaminated from the Los Angeles day of its first such change; it AND its
-- stratum-mates in both arms are censored from the earliest such day in the stratum.
--   H1  the readout's CENSORED rows are exactly that: every unit the rule censors carries one
--       CENSORED row with that censored_from (and its own contaminated_on when it is a contaminated
--       HOLDOUT unit), and no other unit carries one. The expectation is re-derived HERE from the
--       ledger — the readout's derivation is what is under test. Emptiness terms: no HOLDOUT unit, no
--       observed-change row at all, or no estimate row (NOT_YET / READY) in the readout reads as a
--       violation, so an empty input can never pass.
--   H2  V_ENGINE_HEALTH holdout_unit_changed is GREEN on the live board after the censoring, and its
--       own text (hu_gap and c33, pasted below VERBATIM from V_ENGINE_HEALTH.sql) reads RED on every
--       doctored copy that leaves a change uncensored or empties an input. H2b ties the pasted text
--       to the deployed row on the live inputs: measured, status, threshold and the whole detail.
--   H3  the readout's gate still holds: before 2027-01-05 exactly one estimate row (NOT_YET), no
--       READY row, and no number on any row — the CENSORED rows carry dates and a reason only.
-- THE COPIES. Each copy is a full set of the four inputs the check reads (hu_asg = the trial's units,
-- hu_led = the changes on HOLDOUT units inside the window, hu_obs = the observed ledger's size,
-- hu_cens / the readout rows). Picks are deterministic (first by date, then unit_id):
--   LIVE              everything as read.                            H1 0      H2 GREEN, 0
--   NC_DROP_ONE       the first contaminated HOLDOUT unit's CENSORED row removed (the plan's NC).
--                                                                    H1 >= 1   H2 RED, 1
--   NC_LATE           that row's censored_from one day later.        H1 >= 1   H2 RED, 1
--   NC_DROP_MATE      the first censored TREATED unit's row removed (a stratum-mate).
--                                                                    H1 >= 1   H2 RED, 1
--   HC_EXTRA          a CENSORED row added for an uncensored unit (over-censoring): H1 is two-sided
--                     and fires; the board counts only what is NOT censored and must hold.
--                                                                    H1 >= 1   H2 GREEN, 0
--   NC_NEW_CHANGE     the next console change: an observed change added on the HOLDOUT unit that is
--                     uncensored (else the latest censored), dated today (else the day before its
--                     censoring); the readout as read does not censor it. H1 >= 1   H2 RED, >= 1
--   NC_NO_HOLDOUT     the HOLDOUT rows of the assignment removed.     H1 >= 1   H2 RED (emptiness)
--   NC_NO_OBSERVED    the observed ledger empty (its rows out of hu_led, hu_obs 0).
--                                                                    H1 >= 1   H2 RED (emptiness)
--   NC_EMPTY_RO       the readout returns no row.                    H1 >= 1   H2 RED, every censored unit
--   NC_NUMBER         (H3 only) a CENSORED row carrying holdout_n 1. H3 >= 1
-- A copy whose pick does not exist (no contaminated unit, no censored TREATED unit, no uncensored
-- unit) says '(vacuous ...)' in its name and passes: a clean trial is a legitimate state, and LIVE,
-- NC_NO_HOLDOUT, NC_NO_OBSERVED and NC_EMPTY_RO are exercised on every input.
-- TEXT IDENTITY: the hu_gap / c33 block below must equal V_ENGINE_HEALTH.sql's byte for byte, and the
-- deployed definition must carry it (whitespace-normalised). Check both with:
--   python3 -c "import re,json,subprocess;b=lambda t:t[t.index('\nhu_gap AS ('):t.index('\n)\n',t.index('\nc33 AS ('))+2];v=open('scripts/bigquery/views/V_ENGINE_HEALTH.sql').read();a=open('scripts/bigquery/tests/HOLDOUT_INTEGRITY_acceptance.sql').read();d=json.loads(subprocess.check_output(['bq','query','--project_id=onyga-482313','--use_legacy_sql=false','--format=json',\"SELECT view_definition FROM \`onyga-482313.OI.INFORMATION_SCHEMA.VIEWS\` WHERE table_name='V_ENGINE_HEALTH'\"]))[0]['view_definition'];n=lambda s:re.sub(r'\s+',' ',s);print('file==acceptance',b(v)==b(a),'deployed carries it',n(b(v)) in n(d))"
--
-- RUN 2026-10-03 after deploying V_HOLDOUT_READOUT and V_ENGINE_HEALTH v27.162 (job
-- bqjob_r5628fe341cbbaa3e_000001a1002f5b71_1, 66 statements, 249 s, 179.2 slot-s, 12.3 MB, no
-- FACT_AMAZON_ADS): 22 rows, every one PASS, every control exercised (none vacuous). Readings:
--   H1 violations: LIVE 0 (61 units the rule censors) · NC_DROP_ONE 2 · NC_LATE 1 · NC_DROP_MATE 1 ·
--      HC_EXTRA 1 · NC_NEW_CHANGE 7 (67 units on that copy: SB|CAP|LNC's 6 added) · NC_NO_HOLDOUT 62 ·
--      NC_NO_OBSERVED 70 · NC_EMPTY_RO 70.
--   H2 (status, measured): LIVE GREEN 0 · NC_DROP_ONE RED 1 · NC_LATE RED 1 · NC_DROP_MATE RED 1 ·
--      HC_EXTRA GREEN 0 · NC_NEW_CHANGE RED 6 · NC_NO_HOLDOUT RED 0 (emptiness) · NC_NO_OBSERVED RED 0
--      (emptiness) · NC_EMPTY_RO RED 61. H2a the deployed row GREEN 0; H2b equal on measured, status,
--      threshold and the whole detail.
--   H3 LIVE 0 (61 CENSORED rows, 1 estimate row) · NC_NUMBER 1.
-- The first run (job bqjob_r740ea0939f232cc6_000001a100292209_1) also read 22 PASS and showed the
-- board's RED detail printing "censors it from NULL" (FORMAT('%t', NULL) is the string 'NULL', so
-- the COALESCE never fell through); both texts now test IS NULL, the board was redeployed and the
-- text identity re-checked: file==acceptance True, deployed carries it True.
-- =============================================================================================

-- ---- the live inputs, each read once ----
CREATE TEMP TABLE asg0 AS
  SELECT unit_id, unit_name, arm, stratum, eligible_from, trial_end
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
CREATE TEMP TABLE obs0 AS
  SELECT COUNT(*) AS n FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG` WHERE source = 'OBSERVED';
-- the deployed readout, every row (no FACT_AMAZON_ADS before 2027-01-05: the estimate is gated off)
CREATE TEMP TABLE ro AS
  SELECT state, unit_id, arm, stratum, contaminated_on, censored_from,
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
   ORDER BY c.censored_from IS NOT NULL, c.censored_from DESC, a.unit_id LIMIT 1) AS new_change;

-- ---- the copies of the four inputs ----
CREATE TEMP TABLE copies AS
SELECT copy FROM UNNEST(['LIVE', 'NC_DROP_ONE', 'NC_LATE', 'NC_DROP_MATE', 'HC_EXTRA', 'NC_NEW_CHANGE',
                         'NC_NO_HOLDOUT', 'NC_NO_OBSERVED', 'NC_EMPTY_RO', 'NC_NUMBER']) AS copy;

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

CREATE TEMP TABLE cp_obs AS
SELECT c.copy, IF(c.copy = 'NC_NO_OBSERVED', 0, o.n) AS n FROM copies c CROSS JOIN obs0 o;

CREATE TEMP TABLE cp_ro AS
SELECT c.copy, r.state, r.unit_id, r.arm, r.contaminated_on,
       IF(c.copy = 'NC_LATE' AND r.state = 'CENSORED' AND r.unit_id = p.contam_row.unit_id,
          DATE_ADD(r.censored_from, INTERVAL 1 DAY), r.censored_from) AS censored_from,
       IF(c.copy = 'NC_NUMBER' AND r.state = 'CENSORED'
          AND r.unit_id = (SELECT MIN(unit_id) FROM ro WHERE state = 'CENSORED'), TRUE, r.has_number) AS has_number
FROM copies c CROSS JOIN ro r CROSS JOIN pick p
WHERE c.copy != 'NC_EMPTY_RO'
  AND NOT (c.copy = 'NC_DROP_ONE'  AND r.state = 'CENSORED' AND r.unit_id = p.contam_row.unit_id)
  AND NOT (c.copy = 'NC_DROP_MATE' AND r.state = 'CENSORED' AND r.unit_id = p.mate_row.unit_id)
UNION ALL
SELECT 'HC_EXTRA', 'CENSORED', p.free_unit.unit_id, p.free_unit.arm, CAST(NULL AS DATE),
       CURRENT_DATE('America/Los_Angeles'), FALSE
FROM pick p WHERE p.free_unit.unit_id IS NOT NULL;

-- ---- H1: per copy, the CENSORED rows against the rule re-derived from that copy's ledger ----
CREATE TEMP TABLE h1 AS
WITH
exp AS (
  SELECT a.copy, a.unit_id, c.contaminated_on, s.censored_from
  FROM cp_asg a
  LEFT JOIN (SELECT copy, unit_id, MIN(change_day) AS contaminated_on FROM cp_led GROUP BY 1, 2) c
         ON c.copy = a.copy AND c.unit_id = a.unit_id
  LEFT JOIN (SELECT copy, stratum, MIN(change_day) AS censored_from FROM cp_led GROUP BY 1, 2) s
         ON s.copy = a.copy AND s.stratum = a.stratum
),
act AS (
  SELECT copy, unit_id, COUNT(*) AS n_rows, MIN(censored_from) AS censored_from,
         MIN(contaminated_on) AS contaminated_on
  FROM cp_ro WHERE state = 'CENSORED' GROUP BY 1, 2
),
per_unit AS (  -- every trial unit of the copy against its CENSORED row (absent = NULL)
  SELECT e.copy,
         COUNTIF(e.censored_from IS DISTINCT FROM x.censored_from) AS v_censored_from,
         COUNTIF(e.contaminated_on IS DISTINCT FROM x.contaminated_on) AS v_contaminated_on,
         COUNTIF(e.censored_from IS NOT NULL) AS n_expected_censored
  FROM exp e LEFT JOIN act x ON x.copy = e.copy AND x.unit_id = e.unit_id
  GROUP BY 1
),
per_row AS (  -- CENSORED rows: duplicated, or naming no trial unit of the copy
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
       COALESCE(r.v_duplicate, 0) AS v_duplicate,
       COALESCE(r.v_alien, 0) AS v_alien,
       e.v_empty,
       COALESCE(u.n_expected_censored, 0) AS n_expected_censored
FROM copies c
LEFT JOIN per_unit u ON u.copy = c.copy
LEFT JOIN per_row r ON r.copy = c.copy
LEFT JOIN empt e ON e.copy = c.copy;

-- ---- H2: the board's own text, run on each copy ----
CREATE TEMP TABLE twin (copy STRING, check_name STRING, measured FLOAT64, threshold STRING, status STRING, detail STRING);
FOR cp IN (SELECT copy FROM copies ORDER BY copy) DO
  CREATE OR REPLACE TEMP TABLE hu_asg AS
    SELECT unit_id, unit_name, arm, stratum, eligible_from, trial_end FROM cp_asg WHERE copy = cp.copy;
  CREATE OR REPLACE TEMP TABLE hu_led AS
    SELECT unit_id, unit_name, stratum, change_day FROM cp_led WHERE copy = cp.copy;
  CREATE OR REPLACE TEMP TABLE hu_cens AS
    SELECT unit_id, censored_from FROM cp_ro WHERE copy = cp.copy AND state = 'CENSORED';
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
c33 AS (  -- R9 / fix #27: no change on a HOLDOUT campaign goes uncensored
  SELECT 'holdout_unit_changed',
    CAST((SELECT COUNT(*) FROM hu_gap) AS FLOAT64),
    'trial campaigns (either arm) sharing a stratum with a HOLDOUT campaign that changed inside its trial window (a change-log row applied, or a change observed on Amazon), which V_HOLDOUT_READOUT does not censor from that day on · red > 0 (P-23 / R9, audit fix #27); red when no HOLDOUT unit or no observed-change row is read',
    CASE WHEN (SELECT COUNTIF(arm = 'HOLDOUT') FROM hu_asg) = 0 THEN 'RED'
         WHEN (SELECT n FROM hu_obs) = 0 THEN 'RED'
         WHEN (SELECT COUNT(*) FROM hu_gap) > 0 THEN 'RED'
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
  + COALESCE(g.n_number, 0) + COALESCE(g.n_bad_censored, 0) + COALESCE(g.n_bad_state, 0) AS v_gate
FROM copies c
LEFT JOIN (
  SELECT copy,
         COUNTIF(state = 'NOT_YET') AS n_not_yet,
         COUNTIF(state = 'READY') AS n_ready,
         COUNTIF(has_number AND state IN ('NOT_YET', 'CENSORED')) AS n_number,
         COUNTIF(state = 'CENSORED' AND (unit_id IS NULL OR censored_from IS NULL)) AS n_bad_censored,
         COUNTIF(state NOT IN ('NOT_YET', 'READY', 'CENSORED')) AS n_bad_state
  FROM cp_ro GROUP BY 1) g ON g.copy = c.copy;

-- ---- the result ----
WITH
p AS (SELECT * FROM pick),
x AS (
  SELECT
    p.contam_row.unit_id IS NOT NULL AS has_contam,
    p.mate_row.unit_id IS NOT NULL AS has_mate,
    p.free_unit.unit_id IS NOT NULL AS has_free,
    p.new_change.day >= p.new_change.eligible_from AS has_new
  FROM p
),
h AS (
  SELECT copy, v_censored_from + v_contaminated_on + v_duplicate + v_alien + v_empty AS v,
         FORMAT('censored_from %d, contaminated_on %d, duplicate %d, alien %d, emptiness %d · %d unit(s) the rule censors on this copy',
                v_censored_from, v_contaminated_on, v_duplicate, v_alien, v_empty, n_expected_censored) AS d
  FROM h1
),
t AS (SELECT * FROM twin),
res AS (
  -- H1
  SELECT 'H1_LIVE every censoring the rule makes is a CENSORED row, and nothing else is' AS check_name,
         'violations 0' AS expected, CAST(h.v AS STRING) AS measured, h.v = 0 AS ok, h.d AS detail
  FROM h WHERE copy = 'LIVE'
  UNION ALL
  SELECT FORMAT('H1_%s fires%s', h.copy,
                CASE h.copy WHEN 'NC_DROP_ONE' THEN IF(x.has_contam, '', ' (vacuous: no contaminated unit)')
                            WHEN 'NC_LATE' THEN IF(x.has_contam, '', ' (vacuous: no contaminated unit)')
                            WHEN 'NC_DROP_MATE' THEN IF(x.has_mate, '', ' (vacuous: no censored TREATED unit)')
                            WHEN 'HC_EXTRA' THEN IF(x.has_free, '', ' (vacuous: every trial unit is censored)')
                            WHEN 'NC_NEW_CHANGE' THEN IF(x.has_new, '', ' (vacuous: no day inside a HOLDOUT window before its censoring)')
                            ELSE '' END),
         'violations >= 1', CAST(h.v AS STRING),
         h.v >= 1 OR (h.copy IN ('NC_DROP_ONE', 'NC_LATE') AND NOT x.has_contam)
                  OR (h.copy = 'NC_DROP_MATE' AND NOT x.has_mate)
                  OR (h.copy = 'HC_EXTRA' AND NOT x.has_free)
                  OR (h.copy = 'NC_NEW_CHANGE' AND NOT x.has_new),
         h.d
  FROM h CROSS JOIN x WHERE h.copy NOT IN ('LIVE', 'NC_NUMBER')
  UNION ALL
  -- H2
  SELECT 'H2a the deployed board row holdout_unit_changed is GREEN with measured 0',
         'one row, GREEN, 0',
         COALESCE((SELECT FORMAT('%d row(s), %s, %g', COUNT(*), MAX(status), MAX(measured)) FROM board), 'none'),
         (SELECT COUNT(*) = 1 AND LOGICAL_AND(status = 'GREEN' AND measured = 0) FROM board),
         COALESCE((SELECT MAX(detail) FROM board), 'no row')
  UNION ALL
  SELECT 'H2b the pasted hu_gap / c33 text on the live inputs equals the deployed row (measured, status, threshold, detail)',
         'equal',
         IF(COUNT(*) = 1 AND LOGICAL_AND(b.measured = t.measured AND b.status = t.status
                                          AND b.threshold = t.threshold AND b.detail = t.detail), 'equal', 'different'),
         COUNT(*) = 1 AND LOGICAL_AND(b.measured = t.measured AND b.status = t.status
                                      AND b.threshold = t.threshold AND b.detail = t.detail),
         ANY_VALUE(t.detail)
  FROM board b JOIN t ON t.copy = 'LIVE' AND t.check_name = b.check_name
  UNION ALL
  SELECT FORMAT('H2_%s %s%s', t.copy,
                CASE t.copy WHEN 'HC_EXTRA' THEN 'holds (the board counts what is NOT censored)' WHEN 'LIVE' THEN 'holds' ELSE 'fires' END,
                CASE t.copy WHEN 'NC_DROP_ONE' THEN IF(x.has_contam, '', ' (vacuous: no contaminated unit)')
                            WHEN 'NC_LATE' THEN IF(x.has_contam, '', ' (vacuous: no contaminated unit)')
                            WHEN 'NC_DROP_MATE' THEN IF(x.has_mate, '', ' (vacuous: no censored TREATED unit)')
                            WHEN 'HC_EXTRA' THEN IF(x.has_free, '', ' (vacuous: every trial unit is censored)')
                            WHEN 'NC_NEW_CHANGE' THEN IF(x.has_new, '', ' (vacuous: no day inside a HOLDOUT window before its censoring)')
                            ELSE '' END),
         CASE t.copy WHEN 'LIVE' THEN 'GREEN, 0'
                     WHEN 'HC_EXTRA' THEN 'GREEN, 0'
                     WHEN 'NC_DROP_ONE' THEN 'RED, 1'
                     WHEN 'NC_LATE' THEN 'RED, 1'
                     WHEN 'NC_DROP_MATE' THEN 'RED, 1'
                     WHEN 'NC_EMPTY_RO' THEN 'RED, the units the rule censors'
                     ELSE 'RED' END,
         FORMAT('%s, %g', t.status, t.measured),
         CASE t.copy WHEN 'LIVE' THEN t.status = 'GREEN' AND t.measured = 0
                     WHEN 'HC_EXTRA' THEN (t.status = 'GREEN' AND t.measured = 0) OR NOT x.has_free
                     WHEN 'NC_DROP_ONE' THEN (t.status = 'RED' AND t.measured = 1) OR NOT x.has_contam
                     WHEN 'NC_LATE' THEN (t.status = 'RED' AND t.measured = 1) OR NOT x.has_contam
                     WHEN 'NC_DROP_MATE' THEN (t.status = 'RED' AND t.measured = 1) OR NOT x.has_mate
                     WHEN 'NC_NEW_CHANGE' THEN (t.status = 'RED' AND t.measured >= 1) OR NOT x.has_new
                     WHEN 'NC_EMPTY_RO' THEN t.status = 'RED'
                                             AND t.measured = (SELECT n_expected_censored FROM h1 WHERE copy = 'NC_EMPTY_RO')
                     ELSE t.status = 'RED' END,
         t.detail
  FROM t CROSS JOIN x WHERE t.copy != 'NC_NUMBER'
  UNION ALL
  -- H3
  SELECT 'H3_LIVE the gate holds: one NOT_YET row before 2027-01-05, no READY row, no number on any row',
         'violations 0', CAST(v_gate AS STRING), v_gate = 0,
         FORMAT('%d CENSORED row(s), %d estimate row(s)',
                (SELECT COUNTIF(state = 'CENSORED') FROM ro), (SELECT COUNTIF(state != 'CENSORED') FROM ro))
  FROM h3 WHERE copy = 'LIVE'
  UNION ALL
  SELECT 'H3_NC_NUMBER fires (a CENSORED row carrying a number)', 'violations >= 1', CAST(v_gate AS STRING),
         v_gate >= 1, 'holdout_n set on one CENSORED row'
  FROM h3 WHERE copy = 'NC_NUMBER'
)
SELECT check_name, expected, measured, IF(ok, 'PASS', 'FAIL') AS result, detail
FROM res
ORDER BY check_name;
