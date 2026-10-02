-- =============================================================================================
-- DE_PLAN_CONFIG + FN_PLAN_CALENDAR_STATE acceptance — v27.132 (2026-08-23), v27.155 (2026-10-01).
-- EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md P-13, §3.
-- SOP: architecture/NEXT_WEEK_MONEY.md
--
-- Checks:
--   C01 exactly one ACTIVE row per calendar state, and all three states are present
--   C02 settings in range: window_days 1..28, allowance_share in (0,1], live_plan A|B,
--       ramp_steps >= 1, min_orders >= 1, and a description a person can actually read; v27.155:
--       strong_day_mult present and >= 1.0 (a "very good" last day that need not even reach the
--       bar is not a test), strong_day_min_orders present and >= 1; and at least one active row
--   C03 the function reads the LIVE calendar on declared dates, and PEAK WINS over a BOOST that
--       overlaps it (2026-10-15 sits inside Halloween's peak AND inside Christmas's run-up)
--   C04 the function never returns NULL or an unknown state over a two-year sweep
--   C05 the three states the config declares are exactly the states the function can return
--       (a state the function emits with no config row would leave the plan with no window)
--   C06 every seed row carries the DECLARED SENTINEL updated_at, never a deploy-time clock —
--       so re-running the DDL can never out-rank, by recency, a row Ori entered by hand. This
--       is the check that failed on v27.130, where the seed carried CURRENT_TIMESTAMP().
--   C07 where a state carries a row someone entered by hand, that row is the ACTIVE WINNER: no
--       plan_seed row may win a state Ori has ruled on.
--   C08 the plan's window agrees with the house's OLDER window authority for today's state.
--       V_PEAK_WINDOW_RULE + DE_PEAK_WINDOW_OVERRIDE already answer "3 or 7 in a peak" on Ori's
--       evidence discipline, and their re-measure clocks can grant a 7. P-11 says one engine, so
--       DE_PLAN_CONFIG is the plan's authority — but the two must not disagree silently. When
--       this check goes red, someone rules; it is not a bug to be patched away in the view.
--   C09 every ACTIVE seed row still carries the SETTINGS the DDL declares. This is the alarm for
--       the v27.131 defect: that guard keyed on updated_by, so an UPDATE IN PLACE of a seeded
--       row (`SET allowance_share = 0.33 WHERE calendar_state = 'PEAK' AND is_active`) left
--       updated_by = 'plan_seed' and the next re-deploy silently reverted it. v27.132 keys the
--       DELETE on the VALUES, so the edit now survives — and this check makes it VISIBLE rather
--       than silent: a plan_seed row whose settings no longer match the declaration is a hand
--       change wearing the seed's label, and the fix is to retire it and insert an owned row
--       (the SOP's recipe). The seed values below are DECLARED CONSTANTS copied from the DDL,
--       not measurements (Standing Rule 0 exempt); if the DDL's declared seed changes, change
--       them here in the same commit. v27.155: the declaration includes strong_day_mult 1.5 and
--       strong_day_min_orders 1, so a seed row whose P-14c settings were edited in place, or are
--       still NULL (the DDL has not been re-run since the columns were added), is counted.
--   C10 (v27.155) the judge carries NO LITERAL for the P-14c settings: V_PLAN_WINDOW_JUDGMENT's
--       deployed definition has no "<number> AS strong_day_mult" / "<number> AS
--       strong_day_min_orders", and still names both (it publishes them on every row). A literal
--       is a second copy of the rule that a retire-then-insert here would not move.
--
-- v27.155: EVERY CHECK HAS A STANDING NEGATIVE CONTROL. Each check is written once over copies of
-- its input — LIVE, and doctored TEMP copies — and each control asserts that its doctored copy
-- FIRES (the row reads PASS when it fired). The doctored copies add or change rows of whatever is
-- live, so a control does not depend on which rows Ori has written. C03 now counts a NULL from
-- the function as a miss (it read COUNTIF(NOT ok), which skips a NULL); C04 already did.
-- RUN LOG: at the end of this header.
--
-- C03 dates are DECLARED CALENDAR DATES read off DIM_US_HOLIDAYS, not measurements (Standing
-- Rule 0 exempt). If Ori edits the live calendar these dates move with it and this check is the
-- first thing that says so — which is the point of asserting against the live table.
--
-- RUN LOG — dated; re-run the file rather than trusting a figure here.
-- RUN 2026-10-01 (LA; 2026-10-02 ~03:45 UTC), BEFORE v27.155 WAS DEPLOYED: the deploy of
-- DE_PLAN_CONFIG.sql was refused by the session's permission system, so the file was run by a
-- scratch harness with DE_PLAN_CONFIG swapped for TMP_ stand-ins, three ways:
--   * the live table converted by the v27.155 DDL on a TMP_ copy, and the judge's definition taken
--     from V_PLAN_WINDOW_JUDGMENT.sql v27.155 (what it will read once both are deployed):
--     24 rows, every one PASS, 38.1 slot-seconds. LIVE read 0 on C01-C10. The controls fired with:
--     NC_C01 1; NC_C02_MULT 1, NC_C02_MIN 1, NC_C02_NULL 1, NC_C02_EMPTY 1; NC_C03 1; NC_C04 1;
--     NC_C05 1; NC_C06 1; NC_C07 1; NC_C08 1; NC_C09 1, NC_C09_NULL 1; NC_C10 2.
--   * the same table against the DEPLOYED (v27.154) judge: 23 PASS, C10 FAIL 2 — the two k CTE
--     literals, C10 firing on the real thing it guards.
--   * the live table with the three columns added and the seed NOT yet re-run (NULL in the new
--     columns): C02 FAIL 3, C09 FAIL 3 (every seed row), C10 FAIL 2; the other 21 PASS. That is
--     the state between the ALTERs and the seed; the DDL file runs both in one script.
-- Before any edit, the v27.132 file run against the live table read 9 PASS (11.2 slot-seconds).
-- =============================================================================================
DECLARE today_state STRING DEFAULT `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(CURRENT_DATE('America/New_York'));

CREATE TEMP TABLE cfg_live AS
  SELECT * FROM `onyga-482313.OI.DE_PLAN_CONFIG`;
-- one active row to doctor, whatever is live (the first state in order)
CREATE TEMP TABLE one_active AS
  SELECT * FROM cfg_live WHERE is_active
  QUALIFY ROW_NUMBER() OVER (ORDER BY calendar_state, updated_at DESC) = 1;

CREATE TEMP TABLE cfg_copies AS
            SELECT 'LIVE' AS copy, * FROM cfg_live
  -- C01: a second active row for a state
  UNION ALL SELECT 'NC_C01', * FROM cfg_live
  UNION ALL SELECT 'NC_C01', * FROM one_active
  -- C02: the multiplier under the bar; no order minimum; no multiplier at all
  UNION ALL SELECT 'NC_C02_MULT', * FROM cfg_live WHERE NOT is_active OR calendar_state != (SELECT calendar_state FROM one_active)
  UNION ALL SELECT 'NC_C02_MULT', * REPLACE (0.9 AS strong_day_mult) FROM cfg_live
            WHERE is_active AND calendar_state = (SELECT calendar_state FROM one_active)
  UNION ALL SELECT 'NC_C02_MIN', * FROM cfg_live WHERE NOT is_active OR calendar_state != (SELECT calendar_state FROM one_active)
  UNION ALL SELECT 'NC_C02_MIN', * REPLACE (0 AS strong_day_min_orders) FROM cfg_live
            WHERE is_active AND calendar_state = (SELECT calendar_state FROM one_active)
  UNION ALL SELECT 'NC_C02_NULL', * FROM cfg_live WHERE NOT is_active OR calendar_state != (SELECT calendar_state FROM one_active)
  UNION ALL SELECT 'NC_C02_NULL', * REPLACE (CAST(NULL AS FLOAT64) AS strong_day_mult) FROM cfg_live
            WHERE is_active AND calendar_state = (SELECT calendar_state FROM one_active)
  -- C02 emptiness: NC_C02_EMPTY has no row at all (listed in copies below)
  -- C05: every row of PEAK gone (the function emits PEAK)
  UNION ALL SELECT 'NC_C05', * FROM cfg_live WHERE calendar_state != 'PEAK'
  -- C06: a seed row stamped with a deploy clock
  UNION ALL SELECT 'NC_C06', * FROM cfg_live
  UNION ALL SELECT 'NC_C06', * REPLACE ('plan_seed' AS updated_by, TIMESTAMP '2026-10-01 00:00:00 UTC' AS updated_at) FROM one_active
  -- C07: a hand row for a state, and a seed row out-ranking it by recency
  UNION ALL SELECT 'NC_C07', * FROM cfg_live
  UNION ALL SELECT 'NC_C07', * REPLACE ('nc_hand' AS updated_by, TIMESTAMP '2026-09-01 00:00:00 UTC' AS updated_at) FROM one_active
  UNION ALL SELECT 'NC_C07', * REPLACE ('plan_seed' AS updated_by, TIMESTAMP '2099-01-01 00:00:00 UTC' AS updated_at) FROM one_active
  -- C08: today's window four days longer than the house rule's
  UNION ALL SELECT 'NC_C08', * REPLACE (IF(is_active AND calendar_state = today_state, window_days + 4, window_days) AS window_days) FROM cfg_live
  -- C09: an active seed row whose P-14c multiplier was edited in place; and one where it is still NULL
  UNION ALL SELECT 'NC_C09', * FROM cfg_live
  UNION ALL SELECT 'NC_C09', * REPLACE ('plan_seed' AS updated_by, 1.3 AS strong_day_mult) FROM one_active
  UNION ALL SELECT 'NC_C09_NULL', * FROM cfg_live
  UNION ALL SELECT 'NC_C09_NULL', * REPLACE ('plan_seed' AS updated_by, CAST(NULL AS FLOAT64) AS strong_day_mult) FROM one_active;
-- the copies, listed explicitly: a copy that came back EMPTY is still judged
CREATE TEMP TABLE copies AS
  SELECT copy FROM UNNEST(['LIVE', 'NC_C01', 'NC_C02_MULT', 'NC_C02_MIN', 'NC_C02_NULL', 'NC_C02_EMPTY',
                           'NC_C05', 'NC_C06', 'NC_C07', 'NC_C08', 'NC_C09', 'NC_C09_NULL']) AS copy;

-- the seed the DDL declares (DECLARED CONSTANTS, the twin of _plan_config_seed)
CREATE TEMP TABLE seed_decl AS
  SELECT * FROM UNNEST([
    STRUCT('OFF_PEAK' AS calendar_state, 7 AS window_days, 0.20 AS allowance_share,
           'B' AS live_plan, 3 AS ramp_steps, 2 AS min_orders,
           1.5 AS strong_day_mult, 1 AS strong_day_min_orders),
    STRUCT('BOOST', 3, 0.50, 'B', 3, 2, 1.5, 1),
    STRUCT('PEAK',  3, 0.20, 'B', 3, 2, 1.5, 1)
  ]);

-- C10's input: the judge's deployed definition, and a copy carrying the v27.154 k CTE literals
CREATE TEMP TABLE view_copies AS
            SELECT 'LIVE' AS copy, view_definition AS def
            FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS` WHERE table_name = 'V_PLAN_WINDOW_JUDGMENT'
  UNION ALL SELECT 'NC_C10', CONCAT(view_definition, '\n         1.5    AS strong_day_mult,\n         1      AS strong_day_min_orders')
            FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS` WHERE table_name = 'V_PLAN_WINDOW_JUDGMENT';

CREATE TEMP TABLE v (copy STRING, chk STRING, n INT64);
-- C01 exactly one active row per state, all three present
INSERT INTO v
SELECT k.copy, 'C01',
       COUNTIF(a.n_active != 1)
     + 3 - COUNT(DISTINCT IF(a.calendar_state IN ('OFF_PEAK', 'BOOST', 'PEAK'), a.calendar_state, NULL))
FROM copies k
LEFT JOIN (SELECT copy, calendar_state, COUNT(*) AS n_active FROM cfg_copies WHERE is_active GROUP BY 1, 2) a
  USING (copy)
GROUP BY k.copy;
-- C02 every active row in range, readable, carrying both P-14c settings; and some active row at all
INSERT INTO v
SELECT k.copy, 'C02',
       COUNTIF(c.is_active AND (c.window_days NOT BETWEEN 1 AND 28
                                OR c.allowance_share <= 0 OR c.allowance_share > 1
                                OR c.live_plan NOT IN ('A', 'B')
                                OR c.ramp_steps < 1
                                OR c.min_orders < 1
                                OR c.description IS NULL OR LENGTH(TRIM(c.description)) < 20
                                OR c.strong_day_mult IS NULL OR c.strong_day_mult < 1.0
                                OR c.strong_day_min_orders IS NULL OR c.strong_day_min_orders < 1))
     + IF(COUNTIF(c.is_active) = 0, 1, 0)
FROM copies k
LEFT JOIN cfg_copies c USING (copy)
GROUP BY k.copy;
-- C05 every state the function emits has an active row
INSERT INTO v
SELECT k.copy, 'C05', COUNTIF(a.calendar_state IS NULL)
FROM copies k
CROSS JOIN (SELECT DISTINCT `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(d) AS s
            FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2025-01-01', DATE '2026-12-31')) d) e
LEFT JOIN (SELECT DISTINCT copy, calendar_state FROM cfg_copies WHERE is_active) a
  ON a.copy = k.copy AND a.calendar_state = e.s
GROUP BY k.copy;
-- C06 seed rows carry the declared sentinel
INSERT INTO v
SELECT k.copy, 'C06',
       COUNTIF(c.updated_by = 'plan_seed' AND c.updated_at IS DISTINCT FROM TIMESTAMP '2026-08-23 00:00:00 UTC')
FROM copies k
LEFT JOIN cfg_copies c USING (copy)
GROUP BY k.copy;
-- C07 a hand-entered row always wins its state
INSERT INTO v
SELECT k.copy, 'C07', COUNTIF(w.updated_by = 'plan_seed' AND h.calendar_state IS NOT NULL)
FROM copies k
LEFT JOIN (SELECT copy, calendar_state, updated_by FROM cfg_copies WHERE is_active
           QUALIFY ROW_NUMBER() OVER (PARTITION BY copy, calendar_state ORDER BY updated_at DESC) = 1) w
  USING (copy)
LEFT JOIN (SELECT DISTINCT copy, calendar_state FROM cfg_copies
           WHERE updated_by IS DISTINCT FROM 'plan_seed') h
  ON h.copy = w.copy AND h.calendar_state = w.calendar_state
GROUP BY k.copy;
-- C08 today's window agrees with V_PEAK_WINDOW_RULE, and today's state has a window at all
INSERT INTO v
SELECT k.copy, 'C08', COUNTIF(t.window_days IS DISTINCT FROM r.w_days)
FROM copies k
CROSS JOIN (SELECT w_days FROM `onyga-482313.OI.V_PEAK_WINDOW_RULE`) r
LEFT JOIN (SELECT copy, window_days FROM cfg_copies
           WHERE is_active AND calendar_state = today_state
           QUALIFY ROW_NUMBER() OVER (PARTITION BY copy ORDER BY updated_at DESC) = 1) t
  USING (copy)
GROUP BY k.copy;
-- C09 every active seed row carries the declared settings, the P-14c pair included (NULL is a miss)
INSERT INTO v
SELECT k.copy, 'C09', COUNTIF(c.updated_by = 'plan_seed' AND c.is_active AND sd.calendar_state IS NULL)
FROM copies k
LEFT JOIN cfg_copies c USING (copy)
LEFT JOIN seed_decl sd
  ON  sd.calendar_state        = c.calendar_state
  AND sd.window_days           = c.window_days
  AND sd.allowance_share       = c.allowance_share
  AND sd.live_plan             = c.live_plan
  AND sd.ramp_steps            = c.ramp_steps
  AND sd.min_orders            = c.min_orders
  AND sd.strong_day_mult       = c.strong_day_mult
  AND sd.strong_day_min_orders = c.strong_day_min_orders
GROUP BY k.copy;
-- C10 the judge holds no literal for either P-14c setting, and still names both; and it exists
INSERT INTO v
SELECT vc.copy, 'C10',
       IF(REGEXP_CONTAINS(vc.def, r'(?i)[0-9]+(\.[0-9]+)?\s+AS\s+strong_day_mult\b'), 1, 0)
     + IF(REGEXP_CONTAINS(vc.def, r'(?i)[0-9]+(\.[0-9]+)?\s+AS\s+strong_day_min_orders\b'), 1, 0)
     + IF(STRPOS(vc.def, 'strong_day_mult') = 0 OR STRPOS(vc.def, 'strong_day_min_orders') = 0, 1, 0)
FROM view_copies vc;
INSERT INTO v
SELECT 'LIVE', 'C10', IF(COUNTIF(copy = 'LIVE') = 0, 1, 0) FROM view_copies;

-- C03 and C04 test the function on declared dates; their controls are doctored expectations
CREATE TEMP TABLE c03_cases AS
  SELECT * FROM UNNEST([
    -- Christmas peak (peak_start 2026-11-03 .. cooldown_end 2026-12-28)
    STRUCT('LIVE' AS copy, DATE '2026-12-20' AS d, 'PEAK' AS expect),
    -- Back to School run-up (boost_start 2026-08-01 .. peak_start 2026-08-10)
    ('LIVE', DATE '2026-08-05', 'BOOST'),
    -- Back to School peak (peak_start 2026-08-10 .. holiday_date 2026-09-14 + 3, cooldown NULL)
    ('LIVE', DATE '2026-08-23', 'PEAK'),
    -- between seasons: after Prime Day's cooldown, before Back to School's boost
    ('LIVE', DATE '2026-07-15', 'OFF_PEAK'),
    -- Christmas run-up (boost_start 2026-10-01), still ahead of Halloween's peak_start 2026-10-10
    ('LIVE', DATE '2026-10-05', 'BOOST'),
    -- PEAK WINS: 2026-10-15 is inside Halloween's peak AND inside Christmas's run-up
    ('LIVE', DATE '2026-10-15', 'PEAK'),
    -- control: a declared date expected in the wrong state must be counted
    ('NC_C03', DATE '2026-07-15', 'PEAK')
  ]);
INSERT INTO v
SELECT copy, 'C03', COUNTIF(NOT COALESCE(`onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(d) = expect, FALSE))
FROM c03_cases GROUP BY copy;
INSERT INTO v
SELECT copy, 'C04', COUNTIF(s IS NULL OR s NOT IN ('OFF_PEAK', 'BOOST', 'PEAK'))
FROM (
  SELECT 'LIVE' AS copy, `onyga-482313.OI.FN_PLAN_CALENDAR_STATE`(d) AS s
  FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2025-01-01', DATE '2026-12-31')) d
  UNION ALL
  -- control: one NULL among the outputs must be counted
  SELECT 'NC_C04', s FROM UNNEST([CAST(NULL AS STRING), 'PEAK']) s
)
GROUP BY copy;

-- what each copy measured, printed so a PASS can be told from a vacuous one
SELECT copy, chk, n FROM v ORDER BY chk, copy;

WITH f AS (SELECT copy, chk, SUM(n) AS n FROM v GROUP BY 1, 2),
checks AS (
  -- A STATE WITH TWO ACTIVE ROWS OR NONE: the judge and the builder read a window that nobody chose, or none.
  SELECT 'C01 one active row per state, three states' AS check_name, (SELECT n FROM f WHERE copy = 'LIVE' AND chk = 'C01') AS violations
  -- A SETTING OUT OF RANGE OR MISSING MOVES MONEY ON A TYPO: a 0.9 last-day bar holds keywords that did not even reach the family bar; a NULL stops the judge.
  UNION ALL SELECT 'C02 settings in range, the P-14c pair present (strong_day_mult >= 1.0, strong_day_min_orders >= 1), a readable description', (SELECT n FROM f WHERE copy = 'LIVE' AND chk = 'C02')
  -- THE PLAN WOULD JUDGE ON THE WRONG WINDOW AND SHARE FOR THE SEASON: the calendar function misreads the house calendar.
  UNION ALL SELECT 'C03 calendar reads PEAK / BOOST / OFF_PEAK on declared dates', (SELECT n FROM f WHERE copy = 'LIVE' AND chk = 'C03')
  -- A DAY WITH NO STATE HAS NO SETTINGS: the judge returns no window that day.
  UNION ALL SELECT 'C04 never NULL, never an unknown state (2025-01-01 .. 2026-12-31)', (SELECT n FROM f WHERE copy = 'LIVE' AND chk = 'C04')
  -- THE FUNCTION CAN NAME A STATE WITH NO ACTIVE ROW: on such a day the plan has no window and writes nothing.
  UNION ALL SELECT 'C05 every state the function emits has an active config row', (SELECT n FROM f WHERE copy = 'LIVE' AND chk = 'C05')
  -- A RE-DEPLOY COULD OUT-RANK ORI'S ROW BY RECENCY (the v27.130 defect).
  UNION ALL SELECT 'C06 seed rows carry the declared sentinel updated_at', (SELECT n FROM f WHERE copy = 'LIVE' AND chk = 'C06')
  -- A SEED ROW WINS A STATE ORI HAS RULED ON: his setting is in the table and nobody reads it.
  UNION ALL SELECT 'C07 a hand-entered row always wins its state', (SELECT n FROM f WHERE copy = 'LIVE' AND chk = 'C07')
  -- TWO AUTHORITIES ON THE WINDOW DISAGREE SILENTLY: someone must rule which one stands.
  UNION ALL SELECT 'C08 plan window agrees with V_PEAK_WINDOW_RULE today', (SELECT n FROM f WHERE copy = 'LIVE' AND chk = 'C08')
  -- A HAND CHANGE WEARING THE SEED'S LABEL, OR A SEED ROW THE DDL HAS NOT CONVERTED: retire it and insert an owned row.
  UNION ALL SELECT 'C09 active seed rows still carry the declared seed settings, the P-14c pair included', (SELECT n FROM f WHERE copy = 'LIVE' AND chk = 'C09')
  -- A SECOND COPY OF THE LAST-DAY RULE IN THE JUDGE: Ori's retire-then-insert would change the table and not the verdicts.
  UNION ALL SELECT 'C10 V_PLAN_WINDOW_JUDGMENT holds no literal for strong_day_mult / strong_day_min_orders', (SELECT SUM(n) FROM f WHERE copy = 'LIVE' AND chk = 'C10')
  -- the negative controls: each doctored copy must FIRE its check (0 = it fired)
  UNION ALL SELECT 'C01a NEGATIVE CONTROL C01 FIRES: a second active row for one state', IF((SELECT n FROM f WHERE copy = 'NC_C01' AND chk = 'C01') >= 1, 0, 1)
  UNION ALL SELECT 'C02a NEGATIVE CONTROL C02 FIRES: strong_day_mult 0.9 on one active row', IF((SELECT n FROM f WHERE copy = 'NC_C02_MULT' AND chk = 'C02') >= 1, 0, 1)
  UNION ALL SELECT 'C02b NEGATIVE CONTROL C02 FIRES: strong_day_min_orders 0 on one active row', IF((SELECT n FROM f WHERE copy = 'NC_C02_MIN' AND chk = 'C02') >= 1, 0, 1)
  UNION ALL SELECT 'C02c NEGATIVE CONTROL C02 FIRES: strong_day_mult NULL on one active row', IF((SELECT n FROM f WHERE copy = 'NC_C02_NULL' AND chk = 'C02') >= 1, 0, 1)
  UNION ALL SELECT 'C02d NEGATIVE CONTROL C02 FIRES: no row at all', IF((SELECT n FROM f WHERE copy = 'NC_C02_EMPTY' AND chk = 'C02') >= 1, 0, 1)
  UNION ALL SELECT 'C03a NEGATIVE CONTROL C03 FIRES: a declared date expected in the wrong state', IF((SELECT n FROM f WHERE copy = 'NC_C03' AND chk = 'C03') >= 1, 0, 1)
  UNION ALL SELECT 'C04a NEGATIVE CONTROL C04 FIRES: a NULL among the outputs', IF((SELECT n FROM f WHERE copy = 'NC_C04' AND chk = 'C04') >= 1, 0, 1)
  UNION ALL SELECT 'C05a NEGATIVE CONTROL C05 FIRES: every PEAK row gone', IF((SELECT n FROM f WHERE copy = 'NC_C05' AND chk = 'C05') >= 1, 0, 1)
  UNION ALL SELECT 'C06a NEGATIVE CONTROL C06 FIRES: a seed row stamped 2026-10-01', IF((SELECT n FROM f WHERE copy = 'NC_C06' AND chk = 'C06') >= 1, 0, 1)
  UNION ALL SELECT 'C07a NEGATIVE CONTROL C07 FIRES: a seed row out-ranking a hand row by recency', IF((SELECT n FROM f WHERE copy = 'NC_C07' AND chk = 'C07') >= 1, 0, 1)
  UNION ALL SELECT 'C08a NEGATIVE CONTROL C08 FIRES: today\'s window four days longer than the house rule', IF((SELECT n FROM f WHERE copy = 'NC_C08' AND chk = 'C08') >= 1, 0, 1)
  UNION ALL SELECT 'C09a NEGATIVE CONTROL C09 FIRES: an active seed row at strong_day_mult 1.3', IF((SELECT n FROM f WHERE copy = 'NC_C09' AND chk = 'C09') >= 1, 0, 1)
  UNION ALL SELECT 'C09b NEGATIVE CONTROL C09 FIRES: an active seed row with strong_day_mult still NULL', IF((SELECT n FROM f WHERE copy = 'NC_C09_NULL' AND chk = 'C09') >= 1, 0, 1)
  UNION ALL SELECT 'C10a NEGATIVE CONTROL C10 FIRES: the judge carrying the v27.154 k CTE literals', IF((SELECT SUM(n) FROM f WHERE copy = 'NC_C10' AND chk = 'C10') >= 1, 0, 1)
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM checks
ORDER BY check_name;
