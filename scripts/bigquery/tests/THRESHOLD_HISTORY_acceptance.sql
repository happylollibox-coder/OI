-- =============================================================================================
-- THRESHOLD_HISTORY acceptance — v27.155 (2026-10-01), learning-contract piece 0 Task D.
-- FACT_THRESHOLD_HISTORY, written by SP_SNAPSHOT_THRESHOLDS -> SP_SNAPSHOT_THRESHOLDS_INTO.
-- EVERY ROW MUST READ PASS.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Objects: scripts/bigquery/tables/FACT_THRESHOLD_HISTORY.sql,
--          scripts/bigquery/procedures/SP_SNAPSHOT_THRESHOLDS_INTO.sql (the logic),
--          scripts/bigquery/procedures/SP_SNAPSHOT_THRESHOLDS.sql (the nightly call, Refresh Task 10.1).
-- SOP: architecture/NEXT_WEEK_MONEY.md §1 "The settings, and who may change them".
--
-- HOW IT TESTS THE NIGHTLY CODE WITHOUT TOUCHING A LIVE TABLE. SP_SNAPSHOT_THRESHOLDS_INTO takes
-- the three table names, so this file runs the SAME procedure on TMP_ copies of the live tables
-- (permanent TMP_THIST_* tables, because a procedure reads tables by name and cannot see this
-- script's temp tables; dropped at the end). Every write in this file is to a TMP_THIST_ table.
-- Runs, in order, each one's new rows kept under its label:
--   R_LIVE     today's coach thresholds and plan config, on a copy of today's history
--   R_LIVE_NC  the same, after one threshold_value in the coach copy moved by +0.5
--   R1         a fresh coach copy and the plan copy, on an EMPTY history (the first run)
--   R2         again, nothing changed
--   R3         one threshold_value moved by +0.5
--   R4         the SOP's retire-then-insert on the plan copy: PEAK retired, a hand PEAK row at
--              strong_day_mult 1.3 inserted with a change_reason
--   R5         the moved coach row deleted
--   R6         the same row inserted back
--   R7         again, nothing changed
--
-- THE CHECKS (violation counts, 0 = PASS):
--   C01 the first run on an empty history writes exactly one SEEDED row per source row, for both
--       sources, and nothing else
--   C02 a run with nothing changed writes nothing (R2, R7)
--   C03 one changed value writes exactly one row: CHANGED, on that key, carrying the new value (R3)
--   C04 a retire-then-insert writes exactly two rows: the retired row CHANGED with is_active FALSE
--       on its own key, the new row ADDED with its settings and its change_reason (R4)
--   C05 a removed row writes one REMOVED row with no values; put back, one ADDED row (R5, R6)
--   C06 every row of DE_COACH_THRESHOLDS and every ACTIVE row of DE_PLAN_CONFIG has an event in
--       the live history whose latest is not REMOVED
--   C07 the live history is current: the nightly code over today's tables writes nothing (R_LIVE)
--   C08 the live history is well formed: known kinds, a fingerprint on every row but REMOVED, one
--       history_id per row, no event repeating its key's previous values, no REMOVED twice
--       running, SEEDED only in a source's first snapshot
-- Every check also runs on a DOCTORED copy that must FIRE (the NC rows; PASS = it fired):
--   C01 R1 with one row dropped; C02 R3 judged as a second run (the changed value); C03 R2 (no row)
--   and R3 carrying the old value; C04 R4 without its ADDED row; C05 R5 written as CHANGED;
--   C06 the plan copy after R4 (one active row the live history has never seen) against the live
--   history; C07 R_LIVE_NC; C08 the live history plus one event repeating its key's last values.
-- Emptiness terms: C01 fails when either source copy is empty, C06 and C08 when the live history
-- is empty, and C03 / C04 / C05 count a missing row as a violation, so no check passes on nothing.
-- TWINS of SP_SNAPSHOT_THRESHOLDS_INTO kept in this file, which must change with it: the two key
-- formulas (C06; the coach key is also how R3 / R5 pick their row).
--
-- RUN LOG — the only place this file states a measurement; each entry is dated.
-- RUN 2026-10-01 (LA; 2026-10-02 03:2x-03:4x UTC), BEFORE ANY OF THESE OBJECTS WAS DEPLOYED. The
-- deploy of DE_PLAN_CONFIG's v27.155 DDL was refused by the session's permission system, so this
-- file was run by a scratch harness with three substitutions, and NOT as written:
--   DE_PLAN_CONFIG          -> a TMP_ copy of the live table converted by the v27.155 DDL (3 rows,
--                              1.5 / 1, the seed's sentinel updated_at);
--   FACT_THRESHOLD_HISTORY  -> a TMP_ table created from FACT_THRESHOLD_HISTORY.sql and seeded by
--                              SP_SNAPSHOT_THRESHOLDS_INTO's body (182 coach + 3 plan rows, all
--                              SEEDED, one snapshot; a second run of the body wrote 0 rows);
--   each CALL               -> the procedure file's body, unchanged, inlined in a BEGIN block with
--                              the three names declared as variables (9 calls).
-- 17 rows, every one PASS. Per copy (printed by the three SELECTs above the checks):
--   R_LIVE 0 rows; R_LIVE_NC 1 (CHANGED, the new value); R1 185 (182 + 3, all SEEDED, 185 keys);
--   R2 0; R3 1; R4 2 (the retired seed row CHANGED, the hand row ADDED at 1.3 with its reason);
--   R5 1 (REMOVED); R6 1 (ADDED, the value it had); R7 0. The coach row worked on was
--   {"threshold_key":"ACUTE_LOSS_NET","strategy_id":"GLOBAL","coach_mode":"GUARDIAN",
--   "product_family":null}, 0.0 -> 0.5.
--   Negative controls, each FIRED: NC_C01 c01 = 2; NC_C02 c02 = 1; NC_C03_NONE c03 = 2;
--   NC_C03_VALUE c03 = 1; NC_C04 c04 = 2; NC_C05 c05 = 1; NC_C06 1; R_LIVE_NC (C07) 1; NC_C08 1.
--   660.4 slot-seconds, 2.3 MB, 129 s (an earlier run of the same file: 439.5 slot-seconds). Reads
--   the two rule tables and the history only; no FACT_AMAZON_ADS.
-- THE SAME HARNESS WITH A BROKEN PROCEDURE (its change test "OR l.row_fingerprint IS DISTINCT FROM
-- c.row_fingerprint" replaced by "OR FALSE", so a changed row is never written): 4 rows FAIL —
-- C02a (the changed-value run wrote nothing, so the control could not fire) 1, C03 2, C04 2, C07a 1
-- — and the other 13 PASS. That is the suite catching a procedure that stopped recording changes.
-- Once the objects are deployed, run this file as written and add the entry here.
-- =============================================================================================
DECLARE t0 TIMESTAMP;
DECLARE n_coach INT64;
DECLARE n_plan INT64;
DECLARE pick_key STRING;       -- the coach row R3 / R5 / R6 work on (the first key in order)
DECLARE pick_old FLOAT64;
DECLARE pick_new FLOAT64;
DECLARE retired_at TIMESTAMP;  -- the plan row R4 retires (whatever is active for PEAK)
DECLARE retired_by STRING;

-- ---- copies of today's tables (TMP_THIST_*: the procedure reads tables by name) ----
CREATE OR REPLACE TABLE `onyga-482313.OI.TMP_THIST_COACH`    AS SELECT * FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`;
CREATE OR REPLACE TABLE `onyga-482313.OI.TMP_THIST_PLAN`     AS SELECT * FROM `onyga-482313.OI.DE_PLAN_CONFIG`;
CREATE OR REPLACE TABLE `onyga-482313.OI.TMP_THIST_LIVEHIST` AS SELECT * FROM `onyga-482313.OI.FACT_THRESHOLD_HISTORY`;
CREATE OR REPLACE TABLE `onyga-482313.OI.TMP_THIST_HIST`     AS SELECT * FROM `onyga-482313.OI.FACT_THRESHOLD_HISTORY` WHERE FALSE;

SET n_coach = (SELECT COUNT(*) FROM `onyga-482313.OI.TMP_THIST_COACH`);
SET n_plan  = (SELECT COUNT(*) FROM `onyga-482313.OI.TMP_THIST_PLAN`);
-- TWIN of the procedure's coach key
SET pick_key = (SELECT MIN(TO_JSON_STRING(STRUCT(threshold_key, strategy_id, coach_mode, product_family)))
                FROM `onyga-482313.OI.TMP_THIST_COACH`);
SET pick_old = (SELECT MAX(threshold_value) FROM `onyga-482313.OI.TMP_THIST_COACH`
                WHERE TO_JSON_STRING(STRUCT(threshold_key, strategy_id, coach_mode, product_family)) = pick_key);
SET pick_new = pick_old + 0.5;

CREATE TEMP TABLE run_rows AS
  SELECT CAST(NULL AS STRING) AS run, h.* FROM `onyga-482313.OI.TMP_THIST_HIST` h WHERE FALSE;

-- ---- R_LIVE: the nightly code over today's tables, on a copy of today's history ----
SET t0 = (SELECT IFNULL(MAX(snapshot_at), TIMESTAMP '1970-01-01') FROM `onyga-482313.OI.TMP_THIST_LIVEHIST`);
CALL `onyga-482313.OI.SP_SNAPSHOT_THRESHOLDS_INTO`('onyga-482313.OI.TMP_THIST_COACH', 'onyga-482313.OI.TMP_THIST_PLAN', 'onyga-482313.OI.TMP_THIST_LIVEHIST');
INSERT INTO run_rows SELECT 'R_LIVE', h.* FROM `onyga-482313.OI.TMP_THIST_LIVEHIST` h WHERE h.snapshot_at > t0;

-- ---- R_LIVE_NC: the same after one value moved (C07's negative control) ----
UPDATE `onyga-482313.OI.TMP_THIST_COACH` SET threshold_value = pick_new
WHERE TO_JSON_STRING(STRUCT(threshold_key, strategy_id, coach_mode, product_family)) = pick_key;
SET t0 = (SELECT IFNULL(MAX(snapshot_at), TIMESTAMP '1970-01-01') FROM `onyga-482313.OI.TMP_THIST_LIVEHIST`);
CALL `onyga-482313.OI.SP_SNAPSHOT_THRESHOLDS_INTO`('onyga-482313.OI.TMP_THIST_COACH', 'onyga-482313.OI.TMP_THIST_PLAN', 'onyga-482313.OI.TMP_THIST_LIVEHIST');
INSERT INTO run_rows SELECT 'R_LIVE_NC', h.* FROM `onyga-482313.OI.TMP_THIST_LIVEHIST` h WHERE h.snapshot_at > t0;

-- ---- R1: the first run, on an empty history (a fresh coach copy) ----
CREATE OR REPLACE TABLE `onyga-482313.OI.TMP_THIST_COACH` AS SELECT * FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`;
SET t0 = TIMESTAMP '1970-01-01';
CALL `onyga-482313.OI.SP_SNAPSHOT_THRESHOLDS_INTO`('onyga-482313.OI.TMP_THIST_COACH', 'onyga-482313.OI.TMP_THIST_PLAN', 'onyga-482313.OI.TMP_THIST_HIST');
INSERT INTO run_rows SELECT 'R1', h.* FROM `onyga-482313.OI.TMP_THIST_HIST` h WHERE h.snapshot_at > t0;

-- ---- R2: nothing changed ----
SET t0 = (SELECT IFNULL(MAX(snapshot_at), TIMESTAMP '1970-01-01') FROM `onyga-482313.OI.TMP_THIST_HIST`);
CALL `onyga-482313.OI.SP_SNAPSHOT_THRESHOLDS_INTO`('onyga-482313.OI.TMP_THIST_COACH', 'onyga-482313.OI.TMP_THIST_PLAN', 'onyga-482313.OI.TMP_THIST_HIST');
INSERT INTO run_rows SELECT 'R2', h.* FROM `onyga-482313.OI.TMP_THIST_HIST` h WHERE h.snapshot_at > t0;

-- ---- R3: one threshold_value moved by +0.5 ----
UPDATE `onyga-482313.OI.TMP_THIST_COACH` SET threshold_value = pick_new
WHERE TO_JSON_STRING(STRUCT(threshold_key, strategy_id, coach_mode, product_family)) = pick_key;
SET t0 = (SELECT IFNULL(MAX(snapshot_at), TIMESTAMP '1970-01-01') FROM `onyga-482313.OI.TMP_THIST_HIST`);
CALL `onyga-482313.OI.SP_SNAPSHOT_THRESHOLDS_INTO`('onyga-482313.OI.TMP_THIST_COACH', 'onyga-482313.OI.TMP_THIST_PLAN', 'onyga-482313.OI.TMP_THIST_HIST');
INSERT INTO run_rows SELECT 'R3', h.* FROM `onyga-482313.OI.TMP_THIST_HIST` h WHERE h.snapshot_at > t0;

-- ---- R4: the SOP's retire-then-insert on the plan copy ----
SET (retired_at, retired_by) = (SELECT AS STRUCT MAX(updated_at), MAX(updated_by)
                                FROM `onyga-482313.OI.TMP_THIST_PLAN` WHERE calendar_state = 'PEAK' AND is_active);
UPDATE `onyga-482313.OI.TMP_THIST_PLAN` SET is_active = FALSE WHERE calendar_state = 'PEAK' AND is_active;
INSERT INTO `onyga-482313.OI.TMP_THIST_PLAN`
  (calendar_state, window_days, allowance_share, live_plan, ramp_steps, min_orders,
   strong_day_mult, strong_day_min_orders, is_active, description, change_reason, updated_at, updated_by)
VALUES ('PEAK', 3, 0.20, 'B', 3, 2, 1.3, 1, TRUE,
        'acceptance: a hand row', 'acceptance: the retire-then-insert recipe', CURRENT_TIMESTAMP(), 'acceptance');
SET t0 = (SELECT IFNULL(MAX(snapshot_at), TIMESTAMP '1970-01-01') FROM `onyga-482313.OI.TMP_THIST_HIST`);
CALL `onyga-482313.OI.SP_SNAPSHOT_THRESHOLDS_INTO`('onyga-482313.OI.TMP_THIST_COACH', 'onyga-482313.OI.TMP_THIST_PLAN', 'onyga-482313.OI.TMP_THIST_HIST');
INSERT INTO run_rows SELECT 'R4', h.* FROM `onyga-482313.OI.TMP_THIST_HIST` h WHERE h.snapshot_at > t0;

-- ---- R5: the moved coach row deleted; R6: put back as it was; R7: nothing changed ----
CREATE TEMP TABLE picked AS
  SELECT * FROM `onyga-482313.OI.TMP_THIST_COACH`
  WHERE TO_JSON_STRING(STRUCT(threshold_key, strategy_id, coach_mode, product_family)) = pick_key;
DELETE FROM `onyga-482313.OI.TMP_THIST_COACH`
WHERE TO_JSON_STRING(STRUCT(threshold_key, strategy_id, coach_mode, product_family)) = pick_key;
SET t0 = (SELECT IFNULL(MAX(snapshot_at), TIMESTAMP '1970-01-01') FROM `onyga-482313.OI.TMP_THIST_HIST`);
CALL `onyga-482313.OI.SP_SNAPSHOT_THRESHOLDS_INTO`('onyga-482313.OI.TMP_THIST_COACH', 'onyga-482313.OI.TMP_THIST_PLAN', 'onyga-482313.OI.TMP_THIST_HIST');
INSERT INTO run_rows SELECT 'R5', h.* FROM `onyga-482313.OI.TMP_THIST_HIST` h WHERE h.snapshot_at > t0;

INSERT INTO `onyga-482313.OI.TMP_THIST_COACH` SELECT * FROM picked;
SET t0 = (SELECT IFNULL(MAX(snapshot_at), TIMESTAMP '1970-01-01') FROM `onyga-482313.OI.TMP_THIST_HIST`);
CALL `onyga-482313.OI.SP_SNAPSHOT_THRESHOLDS_INTO`('onyga-482313.OI.TMP_THIST_COACH', 'onyga-482313.OI.TMP_THIST_PLAN', 'onyga-482313.OI.TMP_THIST_HIST');
INSERT INTO run_rows SELECT 'R6', h.* FROM `onyga-482313.OI.TMP_THIST_HIST` h WHERE h.snapshot_at > t0;

SET t0 = (SELECT IFNULL(MAX(snapshot_at), TIMESTAMP '1970-01-01') FROM `onyga-482313.OI.TMP_THIST_HIST`);
CALL `onyga-482313.OI.SP_SNAPSHOT_THRESHOLDS_INTO`('onyga-482313.OI.TMP_THIST_COACH', 'onyga-482313.OI.TMP_THIST_PLAN', 'onyga-482313.OI.TMP_THIST_HIST');
INSERT INTO run_rows SELECT 'R7', h.* FROM `onyga-482313.OI.TMP_THIST_HIST` h WHERE h.snapshot_at > t0;

-- ---- the copies each check reads: real runs, and doctored copies that must FIRE ----
CREATE TEMP TABLE copies AS
            SELECT run AS copy, * EXCEPT (run) FROM run_rows
  -- C01: the first run with one row dropped
  UNION ALL SELECT 'NC_C01', * EXCEPT (run) FROM run_rows
            WHERE run = 'R1' AND history_id != (SELECT MIN(history_id) FROM run_rows WHERE run = 'R1')
  -- C02: the changed-value run judged as a second run
  UNION ALL SELECT 'NC_C02', * EXCEPT (run) FROM run_rows WHERE run = 'R3'
  -- C03: no row at all (R2's); the one row carrying the OLD value
  UNION ALL SELECT 'NC_C03_NONE', * EXCEPT (run) FROM run_rows WHERE run = 'R2'
  UNION ALL SELECT 'NC_C03_VALUE', * EXCEPT (run) REPLACE (pick_old AS threshold_value) FROM run_rows WHERE run = 'R3'
  -- C04: the retire-then-insert without its ADDED row
  UNION ALL SELECT 'NC_C04', * EXCEPT (run) FROM run_rows WHERE run = 'R4' AND change_kind != 'ADDED'
  -- C05: the removal written as a change
  UNION ALL SELECT 'NC_C05', * EXCEPT (run) REPLACE ('CHANGED' AS change_kind) FROM run_rows WHERE run = 'R5';

CREATE TEMP TABLE agg AS
  SELECT l.copy,
         COUNT(c.history_id)                                                      AS n,
         COUNTIF(c.change_kind = 'SEEDED')                                        AS n_seeded,
         COUNTIF(c.source_table = 'DE_COACH_THRESHOLDS')                          AS n_src_coach,
         COUNTIF(c.source_table = 'DE_PLAN_CONFIG')                               AS n_src_plan,
         COUNT(DISTINCT IF(c.history_id IS NULL, NULL,
                           FORMAT('%s|%s|%d', c.source_table, c.row_key, c.key_ordinal))) AS n_keys,
         COUNTIF(c.change_kind = 'CHANGED' AND c.source_table = 'DE_COACH_THRESHOLDS'
                 AND c.row_key = pick_key AND c.threshold_value = pick_new)      AS n_r3_ok,
         COUNTIF(c.change_kind = 'CHANGED' AND c.source_table = 'DE_PLAN_CONFIG'
                 AND c.calendar_state = 'PEAK' AND c.is_active = FALSE
                 AND c.source_updated_at = retired_at
                 AND c.source_updated_by IS NOT DISTINCT FROM retired_by)        AS n_r4_retired,
         COUNTIF(c.change_kind = 'ADDED' AND c.source_table = 'DE_PLAN_CONFIG'
                 AND c.calendar_state = 'PEAK' AND c.is_active
                 AND c.strong_day_mult = 1.3 AND c.strong_day_min_orders = 1
                 AND c.change_reason IS NOT NULL)                                 AS n_r4_added,
         COUNTIF(c.change_kind = 'REMOVED' AND c.row_key = pick_key AND c.row_fingerprint IS NULL
                 AND c.threshold_value IS NULL AND c.threshold_key IS NOT NULL)   AS n_r5_ok,
         COUNTIF(c.change_kind = 'ADDED' AND c.row_key = pick_key
                 AND c.threshold_value = pick_new)                                AS n_r6_ok
  FROM (SELECT copy FROM UNNEST(['R_LIVE', 'R_LIVE_NC', 'R1', 'R2', 'R3', 'R4', 'R5', 'R6', 'R7',
                                 'NC_C01', 'NC_C02', 'NC_C03_NONE', 'NC_C03_VALUE', 'NC_C04', 'NC_C05']) AS copy) l
  LEFT JOIN copies c ON c.copy = l.copy
  GROUP BY l.copy;

-- ---- C06 coverage and C08 form, on the live history and on a doctored copy ----
-- TWIN of the procedure's two key formulas
CREATE TEMP TABLE cur_keys AS
            SELECT 'LIVE' AS copy, 'DE_COACH_THRESHOLDS' AS source_table,
                   TO_JSON_STRING(STRUCT(threshold_key, strategy_id, coach_mode, product_family)) AS row_key
            FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  UNION ALL SELECT 'LIVE', 'DE_PLAN_CONFIG', TO_JSON_STRING(STRUCT(calendar_state, updated_by, updated_at))
            FROM `onyga-482313.OI.DE_PLAN_CONFIG` WHERE is_active
  UNION ALL SELECT 'NC_C06', 'DE_COACH_THRESHOLDS',
                   TO_JSON_STRING(STRUCT(threshold_key, strategy_id, coach_mode, product_family))
            FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  -- the plan copy after R4: its new active PEAK row was never seen by the live history
  UNION ALL SELECT 'NC_C06', 'DE_PLAN_CONFIG', TO_JSON_STRING(STRUCT(calendar_state, updated_by, updated_at))
            FROM `onyga-482313.OI.TMP_THIST_PLAN` WHERE is_active;
CREATE TEMP TABLE hist_copies AS
            SELECT 'LIVE' AS copy, h.* FROM `onyga-482313.OI.FACT_THRESHOLD_HISTORY` h
  UNION ALL SELECT 'NC_C06', h.* FROM `onyga-482313.OI.FACT_THRESHOLD_HISTORY` h
  UNION ALL SELECT 'NC_C08', h.* FROM `onyga-482313.OI.FACT_THRESHOLD_HISTORY` h
  -- one event repeating its key's last values, a minute after the last snapshot
  UNION ALL SELECT 'NC_C08', h.* REPLACE (GENERATE_UUID() AS history_id, 'CHANGED' AS change_kind,
                                          TIMESTAMP_ADD(h.snapshot_at, INTERVAL 1 MINUTE) AS snapshot_at)
            FROM `onyga-482313.OI.FACT_THRESHOLD_HISTORY` h
            WHERE h.change_kind != 'REMOVED'
            QUALIFY ROW_NUMBER() OVER (ORDER BY h.snapshot_at DESC, h.history_id) = 1;
CREATE TEMP TABLE latest AS
  SELECT copy, source_table, row_key, change_kind
  FROM hist_copies
  QUALIFY ROW_NUMBER() OVER (PARTITION BY copy, source_table, row_key
                             ORDER BY snapshot_at DESC, history_id DESC) = 1;
CREATE TEMP TABLE c06 AS
  WITH unc AS (
    SELECT k.copy, COUNTIF(t.row_key IS NULL OR t.change_kind = 'REMOVED') AS n_uncovered, COUNT(*) AS n_keys
    FROM cur_keys k
    LEFT JOIN latest t ON t.copy = k.copy AND t.source_table = k.source_table AND t.row_key = k.row_key
    GROUP BY k.copy
  ),
  hn AS (SELECT copy, COUNT(*) AS n_hist FROM hist_copies GROUP BY copy)
  SELECT l.copy,
         COALESCE(u.n_uncovered, 0)
       + IF(COALESCE(h.n_hist, 0) = 0, 1, 0)      -- an empty history covers nothing
       + IF(COALESCE(u.n_keys, 0) = 0, 1, 0) AS n  -- and empty sources are not "covered"
  FROM (SELECT 'LIVE' AS copy UNION ALL SELECT 'NC_C06') l
  LEFT JOIN unc u USING (copy)
  LEFT JOIN hn h USING (copy);
CREATE TEMP TABLE c08 AS
  WITH seq AS (
    SELECT h.*,
           LAG(row_fingerprint) OVER w AS prev_fp,
           LAG(change_kind)     OVER w AS prev_kind,
           MIN(snapshot_at) OVER (PARTITION BY copy, source_table) AS first_snap
    FROM hist_copies h
    WINDOW w AS (PARTITION BY copy, source_table, row_key, key_ordinal ORDER BY snapshot_at, history_id)
  )
  SELECT l.copy,
         COUNTIF(s.change_kind NOT IN ('SEEDED', 'ADDED', 'CHANGED', 'REMOVED'))
       + COUNTIF((s.change_kind = 'REMOVED') != (s.row_fingerprint IS NULL))
       + COUNTIF(s.prev_kind IS NOT NULL AND s.prev_kind != 'REMOVED' AND s.change_kind != 'REMOVED'
                 AND s.prev_fp = s.row_fingerprint)
       + COUNTIF(s.prev_kind = 'REMOVED' AND s.change_kind = 'REMOVED')
       + COUNTIF(s.change_kind = 'SEEDED' AND s.snapshot_at > s.first_snap)
       + (COUNT(s.history_id) - COUNT(DISTINCT s.history_id))
       + IF(COUNT(s.history_id) = 0, 1, 0) AS n
  FROM (SELECT 'LIVE' AS copy UNION ALL SELECT 'NC_C08') l
  LEFT JOIN seq s ON s.copy = l.copy
  GROUP BY l.copy;

-- ---- every check, and every negative control (0 = PASS; a control reads 0 when it FIRED) ----
CREATE TEMP TABLE v AS
  SELECT copy,
         -- C01 the first run seeds exactly one SEEDED row per source row, for both sources
         ABS(n - (n_coach + n_plan)) + (n - n_seeded) + (n - n_keys)
           + ABS(n_src_coach - n_coach) + ABS(n_src_plan - n_plan)
           + IF(n_coach = 0, 1, 0) + IF(n_plan = 0, 1, 0)                         AS c01,
         -- C02 nothing changed, nothing written
         n                                                                        AS c02,
         -- C03 one changed value, exactly one CHANGED row carrying it
         ABS(n - 1) + IF(n_r3_ok = 1, 0, 1)                                       AS c03,
         -- C04 retire-then-insert, exactly the retired row CHANGED and the new row ADDED
         ABS(n - 2) + IF(n_r4_retired = 1, 0, 1) + IF(n_r4_added = 1, 0, 1)      AS c04,
         -- C05 removed -> one REMOVED row with no values
         ABS(n - 1) + IF(n_r5_ok = 1, 0, 1)                                       AS c05r,
         -- C05 put back -> one ADDED row with the value it had
         ABS(n - 1) + IF(n_r6_ok = 1, 0, 1)                                       AS c05a
  FROM agg;

-- what each copy measured, printed so a PASS can be told from a vacuous one
SELECT 'runs' AS what, copy, n, n_seeded, n_src_coach, n_src_plan, n_keys, n_r3_ok, n_r4_retired, n_r4_added, n_r5_ok, n_r6_ok
FROM agg ORDER BY copy;
SELECT 'violations' AS what, copy, c01, c02, c03, c04, c05r, c05a FROM v ORDER BY copy;
SELECT 'live' AS what, 'C06' AS chk, copy, n FROM c06
UNION ALL SELECT 'live', 'C08', copy, n FROM c08 ORDER BY chk, copy;

WITH checks AS (
  -- A ROLLOUT OR A NEW RULE TABLE WOULD START WITHOUT ITS PAST: the first snapshot must hold every row it saw.
  SELECT FORMAT('C01 the first run on an empty history writes one SEEDED row per source row (%d coach thresholds + %d plan config rows)', n_coach, n_plan) AS check_name,
         (SELECT c01 FROM v WHERE copy = 'R1') AS violations
  -- THE HISTORY WOULD GROW EVERY PASS AND "THE VALUE IN FORCE ON DAY D" WOULD BE BURIED IN REPEATS.
  UNION ALL SELECT 'C02 a run with nothing changed writes nothing (R2, R7)',
         (SELECT c02 FROM v WHERE copy = 'R2') + (SELECT c02 FROM v WHERE copy = 'R7')
  -- A THRESHOLD COULD MOVE AND THE HISTORY WOULD NOT SAY SO, OR SAY IT WRONG: the grade of a rule change would read the wrong value.
  UNION ALL SELECT 'C03 one changed value writes exactly one CHANGED row on its key, carrying the new value (R3)',
         (SELECT c03 FROM v WHERE copy = 'R3')
  -- ORI'S RULE CHANGE WOULD LEAVE NO DATED RECORD OF WHEN THE OLD VALUE STOPPED AND THE NEW ONE STARTED.
  UNION ALL SELECT 'C04 a retire-then-insert writes the retired row CHANGED (is_active FALSE) and the new row ADDED with its change_reason (R4)',
         (SELECT c04 FROM v WHERE copy = 'R4')
  -- A DELETED THRESHOLD WOULD READ AS STILL IN FORCE FOREVER.
  UNION ALL SELECT 'C05 a removed row writes one REMOVED row; put back, one ADDED row (R5, R6)',
         (SELECT c05r FROM v WHERE copy = 'R5') + (SELECT c05a FROM v WHERE copy = 'R6')
  -- A SETTING THE PLAN READS TONIGHT WOULD HAVE NO RECORD: the snapshot step has not run, or failed.
  UNION ALL SELECT 'C06 every coach threshold and every active plan config row has a live history event, latest not REMOVED',
         (SELECT n FROM c06 WHERE copy = 'LIVE')
  -- A CHANGE SINCE THE LAST PASS IS NOT RECORDED YET; IF IT STAYS RED PAST THE NEXT ORCHESTRATOR PASS, THE HISTORY HAS STOPPED RECORDING.
  UNION ALL SELECT 'C07 the live history is current: the nightly code over today\'s tables writes nothing (R_LIVE)',
         (SELECT c02 FROM v WHERE copy = 'R_LIVE')
  -- THE HISTORY CANNOT BE READ AS "WHAT WAS IN FORCE WHEN": repeats, unlabelled rows or a second seed.
  UNION ALL SELECT 'C08 the live history is well formed (kinds, fingerprints, ids, no repeat, no second seed)',
         (SELECT n FROM c08 WHERE copy = 'LIVE')
  -- the negative controls: each doctored copy must FIRE its check (0 = it fired)
  UNION ALL SELECT 'C01a NEGATIVE CONTROL C01 FIRES: the first run with one row dropped',
         IF((SELECT c01 FROM v WHERE copy = 'NC_C01') >= 1, 0, 1)
  UNION ALL SELECT 'C02a NEGATIVE CONTROL C02 FIRES: a run after one value changed (R3) judged as a second run',
         IF((SELECT c02 FROM v WHERE copy = 'NC_C02') >= 1, 0, 1)
  UNION ALL SELECT 'C03a NEGATIVE CONTROL C03 FIRES: no row written',
         IF((SELECT c03 FROM v WHERE copy = 'NC_C03_NONE') >= 1, 0, 1)
  UNION ALL SELECT 'C03b NEGATIVE CONTROL C03 FIRES: the row carrying the old value',
         IF((SELECT c03 FROM v WHERE copy = 'NC_C03_VALUE') >= 1, 0, 1)
  UNION ALL SELECT 'C04a NEGATIVE CONTROL C04 FIRES: the retire-then-insert without its ADDED row',
         IF((SELECT c04 FROM v WHERE copy = 'NC_C04') >= 1, 0, 1)
  UNION ALL SELECT 'C05a NEGATIVE CONTROL C05 FIRES: the removal written as CHANGED',
         IF((SELECT c05r FROM v WHERE copy = 'NC_C05') >= 1, 0, 1)
  UNION ALL SELECT 'C06a NEGATIVE CONTROL C06 FIRES: an active plan config row the live history never saw',
         IF((SELECT n FROM c06 WHERE copy = 'NC_C06') >= 1, 0, 1)
  UNION ALL SELECT 'C07a NEGATIVE CONTROL C07 FIRES: today\'s tables with one threshold moved, on a copy of today\'s history (R_LIVE_NC)',
         IF((SELECT c02 FROM v WHERE copy = 'R_LIVE_NC') >= 1, 0, 1)
  UNION ALL SELECT 'C08a NEGATIVE CONTROL C08 FIRES: one event repeating its key\'s last values',
         IF((SELECT n FROM c08 WHERE copy = 'NC_C08') >= 1, 0, 1)
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM checks
ORDER BY check_name;

DROP TABLE IF EXISTS `onyga-482313.OI.TMP_THIST_COACH`;
DROP TABLE IF EXISTS `onyga-482313.OI.TMP_THIST_PLAN`;
DROP TABLE IF EXISTS `onyga-482313.OI.TMP_THIST_LIVEHIST`;
DROP TABLE IF EXISTS `onyga-482313.OI.TMP_THIST_HIST`;
