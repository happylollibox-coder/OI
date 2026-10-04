-- =============================================================================================
-- HOLDOUT_RESTART acceptance — holdout trial 2 (plan docs/superpowers/plans/2026-10-03-holdout-restart.md
-- §5). EVERY ROW MUST READ violations = 0.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=prettyjson \
--     "$(grep -v '^[[:space:]]*--' FILE)"
-- Each statement returns one row (check_name, violations, detail); parse the multi-statement output
-- by regex over the {"check_name"...} objects.
-- This file holds K1-K6 (plan Tasks 2-3) and K7 (plan Task 5). K8-K12 are added by plan Task 7.
-- Objects: scripts/bigquery/tables/DE_HOLDOUT_TRIAL.sql, views/V_HOLDOUT_TRIAL.sql,
--          views/V_HOLDOUT_ARM.sql, migrations/2026-10-05_holdout_t2_registry_rows.sql,
--          migrations/2026-10-05_holdout_t2_founding.sql. SOP: architecture/HOLDOUT.md §4, §5, §9.
--
-- WHEN TO RUN: on 2026-10-05 (LA), straight after deploy steps 1-2 of plan Task 8. K1 and K6 read
-- CURRENT_DATE('America/Los_Angeles'): trial 1 is archived from 2026-10-05, so on 2026-10-04 both
-- trials are live (K1 reads 2) and trial 1's 14 controls still bind (K6 reads 26).
--
--   K1  one live trial and it is T2: ABS(COUNTIF(is_live) - 1) + COUNTIF(is_live AND trial_id != T2)
--       over V_HOLDOUT_TRIAL. An empty registry reads 1.
--   K2  trial 1's rows unchanged: 69 rows and FARM_FINGERPRINT over every column ordered by unit_id
--       = 7298956708089075507. An empty T1 reads 1.
--   K3  the founding cohort is the approved list: 59 FOUNDING rows, 12 HOLDOUT, fingerprint over
--       unit_id|arm|stratum|seq ordered by unit_id = 4171456845817687166. An empty cohort reads 1.
--   K4  T2's arms follow the rule from the stored columns (seed, stratum, seq_in_stratum), and each
--       stratum's sequence is whole (no duplicate seq, no seq >= the stratum's count); + 1 when T2
--       has no row.
--   K5  the seed is the first pass: on the founding rows, A1-A3 recomputed for OI-HOLDOUT-v2|0 .. |5.
--       Violations = (index 5 fails) + (indices 0-4 that pass). An empty cohort reads 1 (index 5 fails).
--   K6  the gate is T2's arm: the symmetric difference between today's binding rows of V_HOLDOUT_ARM
--       and T2's HOLDOUT rows, + 1 when T2 has no HOLDOUT row.
--   K7  no gate reader bypasses the arm: references to the table DE_HOLDOUT_ASSIGNMENT (any quoting,
--       with or without the project) in every deployed view and routine body of OI, comment text
--       removed, per object against its expected count: V_HOLDOUT_ARM 1, V_HOLDOUT_READOUT 1,
--       V_ENGINE_HEALTH 1 (c33 hu_asg), SP_ASSIGN_HOLDOUT 3 (the guard, assigned, INSERT INTO), every
--       other object 0. An expected object that is not deployed counts 0, so it is off its count.
--       Violations = objects off their count. TMP_HT2_ scratch objects are left out.
--       K7b (shell, the three tools have no deployed body), each must print 0:
--         for f in tools/build_reprice_bulksheet.py tools/build_seasonal_unpause_bulksheet.py \
--                  tools/build_seat_moves_bulksheet.py; do grep -c 'DE_HOLDOUT_ASSIGNMENT' $f; done
--       Run after Task 6 is deployed: until V_ENGINE_HEALTH reads V_HOLDOUT_ARM, K7 reads 1 (it
--       holds 3 references, expected 1). Comment text is removed from '--' to the end of the line,
--       so a reference on the same line after a '--' inside a string literal would not be counted.
--
-- MEASURED 2026-10-04 ~03:20-03:35 UTC (LA date 2026-10-03), rehearsal on TMP_HT2_ copies, all
-- dropped afterwards. Copies: DE_HOLDOUT_TRIAL from its DDL; DE_HOLDOUT_ASSIGNMENT by COPY of the
-- live table (69 T1 rows); both views from their files with the names sed-pointed at the copies.
-- Then the registry-rows file and the founding file ran on the copies (sed). "Pinned 10-05" = every
-- CURRENT_DATE('America/Los_Angeles') in the views and in this file rewritten to DATE '2026-10-05'.
--   deploy state, pinned 10-05:  K1 0 | K2 0 | K3 0 | K4 0 | K5 0 | K6 0
--   same, at CURRENT_DATE (LA 10-03): K1 2 (both trials live) and K6 26 (T1's 14 bind, T2's 12 do
--     not) as expected before 10-05; K2-K5 0
--   K2 on the live DE_HOLDOUT_ASSIGNMENT (read-only): 0 (69 rows, 7298956708089075507)
--   K5 detail: index 0 14 controls; 1 12 at 16.1%; 2 11; 3 11 at 24.4%; 4 14 on 4 of 5 families;
--     5 12 at 21.0% on 5 of 5 = PASS
--   negative controls (expected / measured):
--     K1 registry copy without T1's ARCHIVED row, pinned 10-05           2 / 2
--     K1 empty registry copy, pinned 10-05                                1 / 1
--     K2 copy with one T1 arm flipped                                     1 / 1
--     K2 copy with no T1 row                                              1 / 1
--     K3 copy minus one T2 founding row                                   1 / 1
--     K3 copy with two T2 arms swapped (still 12 HOLDOUT)                 1 / 1
--     K4 copy with one T2 arm flipped                                     1 / 1
--     K4 copy with one T2 seq duplicated (SP|UNC|LNC 3 -> 2)            >=1 / 1
--     K4 copy with no T2 row                                              1 / 1  (K3 1, K5 1 there too)
--     K5 A2 band set to [0.22, 0.26]                                      1 / 1
--     K6 registry copy without T1's ARCHIVED row, pinned 10-05           14 / 14
--     K6 copy with no T2 row, pinned 10-05                                1 / 1
--   gate_sim (V_HOLDOUT_ARM on the copies, date pinned; plan §2.1):
--     day         rows  binding  T2  T1
--     2026-10-04   26     14      0  14
--     2026-10-05   12     12     12   0
--     2026-10-06   12     12     12   0
--     2027-01-26   12     12     12   0
--     2027-01-27    0      0      0   0
--   slot time of one full read on the copies: V_HOLDOUT_ARM 5.46 s, V_HOLDOUT_TRIAL 4.88 s.
--
-- PLAN TASK 4 REHEARSAL, 2026-10-04 ~03:50-04:10 UTC (SP_ASSIGN_HOLDOUT and V_HOLDOUT_ELIGIBLE from
-- this branch, names sed-pointed at TMP_HT2_ copies, V_HOLDOUT_TRIAL / V_HOLDOUT_ARM and this file
-- pinned to 2026-10-05; all dropped afterwards). The deployed bodies matched the repo files before
-- the edit (procedure byte for byte; view apart from its comment lines).
--   after the founding file, then one extra eligible campaign (SB|UNC|GRD) and two CALLs:
--     K1 0 | K2 0 | K3 0 | K4 0 (T2 rows 60: one LATE ARRIVAL, seq 4, HOLDOUT) | K5 0 | K6 0 (13 bind)
--   K4 NC: that LATE ARRIVAL's seq moved 4 -> 5 (not continuing)               >=1 / 2
--   K2 NC = review fix 3's hazard: the deployed (trial-1) procedure body under this branch's
--     V_HOLDOUT_ELIGIBLE appended the 5 Bunny campaigns to trial 1                 1 / 1 (74 rows)
--     (the same body under the deployed view appended 0)
--
-- PLAN TASK 5 REHEARSAL, 2026-10-04 ~04:20-04:40 UTC (LA date 2026-10-03). SP_ENGINE_PREFLIGHT,
-- V_PLAN_WINDOW_JUDGMENT and V_FAMILY_SEAT_REGISTER from this branch, comment lines stripped, names
-- sed-pointed at TMP_HT2_ copies; all dropped afterwards (INFORMATION_SCHEMA: 0 TMP_HT2_ tables, 0
-- routines). Copies: registry from its DDL and the rows file (3 rows); assignment by COPY of the
-- live table plus the founding file (T1 69 rows / 14 HOLDOUT, T2 59 / 12); V_HOLDOUT_TRIAL and
-- V_HOLDOUT_ARM with CURRENT_DATE('America/Los_Angeles') pinned to 2026-10-05 (12 rows, all T2,
-- gate 2026-10-05 .. 2027-01-26). Before the edit the deployed bodies matched the repo files:
-- the procedure body and description byte for byte (the file adds the ';' after END), the two views
-- apart from their comment lines and the final ';'. Slot time is of one read of the view into a
-- temp table (CREATE TEMP TABLE AS SELECT *).
--   holdout campaigns returned (distinct campaign_id with holdout TRUE):
--     V_PLAN_WINDOW_JUDGMENT live            8, all T1 (eligible_from 2026-09-01); 6 T1 controls have no row
--       copy, arm pinned 10-05               holdout_member 10, all T2 (gate_from 2026-10-05); holdout 0,
--                                            because the view's own date (LA 10-03) is before the gate
--       copy, arm and d_la pinned 10-05      holdout 10 = holdout_member 10, all T2; T1-only 0
--     V_FAMILY_SEAT_REGISTER live            9, all T1 (2026-09-01); 5 T1 controls have no row
--       copy, arm pinned 10-05               9, all T2 (2026-10-05); T1-only 0
--     In every copy: no T1 control flagged, no non-control flagged, and every T2 control that has a
--     row is flagged. The T2 controls with no row (judgment 273898143987321, 27660342907703;
--     register 271009556929636, 273898143987321, 527422818407259) have no row in the live views
--     either: per-campaign row counts of all 26 controls are equal in the live and copied register.
--   the swap alone changes nothing: copies over an arm holding trial 1 only (TMP assignment
--     without the founding rows, registry date not pinned: 14 rows, gate 2026-09-01 .. 2026-10-04)
--     V_FAMILY_SEAT_REGISTER   346 = 346 rows, 0 / 0 rows differ, fingerprint 455831110707240095 both
--     V_PLAN_WINDOW_JUDGMENT   356 = 356 rows, 0 differing values in every column with FLOAT64
--       compared to 1e-6 relative; compared exactly, 69 rows differ from the live view, and 58 rows
--       differ between two reads of the live view itself (float last-bit noise)
--   register copy (arm pinned 10-05) vs live: CATEGORY rows 160 -> 159; 6 CATEGORY rows of Fresh and
--     Bottle (families of the released T1 controls 446868628489343, 227290137740434, 279837860088128)
--     move on the projection horizons; every other row_type count is unchanged.
--   slot time of one read (s):
--     V_PLAN_WINDOW_JUDGMENT  live 832, 902, 838, 714 | copies 789 (arm pinned), 808 (d_la pinned),
--                             726, 779 (trial-1 arm)
--     V_FAMILY_SEAT_REGISTER  live 9,013, 19,177, 6,085 | copies 26,784, 9,202 (arm pinned),
--                             15,793 (trial-1 arm). Reads of the same live view ranged 3x, so these
--                             samples show no difference either way.
--   SP_ENGINE_PREFLIGHT: TMP copy compiled (CREATE PROCEDURE validates the body) and CALLed; its
--     writes went to TMP_HT2_T_ENGINE_PREFLIGHT_NEW and a TMP_HT2_ copy of the 2026-10-03
--     FACT_ENGINE_PROPOSALS partition (413 rows); its CURRENT_DATE pinned to 2026-10-05. Nothing
--     wrote T_ENGINE_PREFLIGHT or FACT_ENGINE_PROPOSALS.
--     K8 (plan §5, against TMP assignment)  new body 0: 38 rows on 10 T2 controls, all EXCLUDE with
--       is_holdout, holdout_trial_id T2 only; 66 rows on 8 T1-only controls, none is_holdout; no
--       holdout row outside the controls. Slot 9.7 s (table) + 3.4 s (stamp).
--     K8 NC, the deployed body on the same copies and date: 102 (36 T2 rows not EXCLUDE: their
--       eligible_from is 2026-10-06, plan §2.3; 66 T1-only rows held). Live T_ENGINE_PREFLIGHT
--       (2026-10-03, before the deploy): 102 likewise.
--     the 309 rows on non-control campaigns: verdict and verdict_reason equal, new body vs deployed.
--     hold CTE at the real date (LA 10-03): deployed CTE on the live table 14 rows, new CTE on an
--       unpinned arm over T1+T2 copies 14 rows, 0 / 0 differences in (cid, trial_id); the arm held
--       26 rows (T2's 12 bind from 10-05).
--   K9 NC (latest FACT_PLAN_NEXT_WEEK, as_of 2026-10-03, 712 rows, before the deploy): 224
--     (94 T2-control rows not holdout + 130 T1-only rows holdout).
--   K7 on the deployed bodies today (= its NC, plan >= 6): 6 -- SP_ASSIGN_HOLDOUT 2 (expected 3);
--     SP_ENGINE_PREFLIGHT 1 (0); V_ENGINE_HEALTH 3 (1); V_FAMILY_SEAT_REGISTER 1 (0); V_HOLDOUT_ARM
--     0 (1, not deployed); V_PLAN_WINDOW_JUDGMENT 1 (0). V_HOLDOUT_READOUT 1 is on its count. Slot 3.1 s.
--     K7b on the tools before the edit: 2, 1, 2 (four hold CTEs and one docstring); after: 0, 0, 0.
--     The same count over this branch's bodies: V_HOLDOUT_ARM 1, SP_ASSIGN_HOLDOUT 3, the three
--     readers 0, V_HOLDOUT_READOUT 1, V_ENGINE_HEALTH 3 (plan Task 6 pending).
--   the tools' SQL with V_HOLDOUT_ARM pointed at the pinned copy: all four queries dry-run OK.
--     build_reprice_bulksheet: 78 rows, holdout_eligible_from on 7 campaigns, all T2, all 2026-10-05;
--     the 4 T1 controls with rows carry none. The pre-edit SQL on the live table: 78 rows, 4
--     campaigns, all T1, 2026-09-01. build_seat_moves_bulksheet LEAK 2 rows / NEGATE 0 rows, no
--     control among them. build_seasonal_unpause_bulksheet: dry run only (it needs keyword ids).
--   python3 -m pytest tools/tests -q: 225 passed before and after (test_seat_moves +
--     test_seasonal_unpause: 91).
--
-- PLAN TASK 6 REHEARSAL, 2026-10-04 ~05:00-06:05 UTC (LA date 2026-10-03). V_HOLDOUT_READOUT (k reads
-- the live trial) and V_ENGINE_HEALTH (c18 on V_HOLDOUT_ARM; c33 on the live trial, with the touch
-- alarm and feed liveness) from this branch, comment lines stripped, names pointed at TMP_HT2_ copies;
-- all dropped afterwards. Before the edit both deployed bodies matched the repo files apart from
-- comment lines and the final ';'; feat/campaign-first-strategy had no commit on either file after
-- 53326a5. The results, the H4/H5-style doctored inputs and the cost are in the two views' headers.
--   K7's count over this branch's bodies after the edit: V_ENGINE_HEALTH 1 (c33 hu_asg),
--     V_HOLDOUT_READOUT 1 (asg). The '(plan Task 6 pending)' 3 above is now 1.
--   V_ENGINE_HEALTH reads DE_HOLDOUT_BASELINE (c33 kind 4). That table's DDL and its founding insert
--     are not on this branch yet (plan Task 2 Step 3b, Task 3); the rehearsal used a copy with the
--     columns of Step 3b (trial_id, campaign_id, setting, recorded_at NOT NULL; value, source,
--     source_synced_at, ruling). The board cannot be created before the table exists.
-- =============================================================================================

-- K1 one live trial, and it is T2
SELECT 'K1_one_live_trial_is_t2' AS check_name,
       ABS(COUNTIF(is_live) - 1) + COUNTIF(is_live AND trial_id != 'HOLDOUT-2026Q4-CAMPAIGN-T2') AS violations,
       FORMAT('%d trial(s), live: %s', COUNT(*), IFNULL(STRING_AGG(IF(is_live, trial_id, NULL), ', ' ORDER BY trial_id), 'none')) AS detail
FROM `onyga-482313.OI.V_HOLDOUT_TRIAL`;

-- K2 trial 1's 69 rows unchanged
SELECT 'K2_t1_rows_unchanged' AS check_name,
       IF(COUNT(*) = 69 AND FARM_FINGERPRINT(STRING_AGG(FORMAT('%T', (trial_id, unit_type, unit_id, unit_name, arm, stratum, seq_in_stratum, seed, assigned_at, eligible_from, trial_end, channel, family, is_capped, is_launch, spend_28d_at_assign, gp_28d_at_assign, net_28d_at_assign, assignment_rule)), '|' ORDER BY unit_id)) = 7298956708089075507, 0, 1) AS violations,
       FORMAT('rows %d, fingerprint %s', COUNT(*), IFNULL(CAST(FARM_FINGERPRINT(STRING_AGG(FORMAT('%T', (trial_id, unit_type, unit_id, unit_name, arm, stratum, seq_in_stratum, seed, assigned_at, eligible_from, trial_end, channel, family, is_capped, is_launch, spend_28d_at_assign, gp_28d_at_assign, net_28d_at_assign, assignment_rule)), '|' ORDER BY unit_id)) AS STRING), 'none')) AS detail
FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
WHERE trial_id = 'HOLDOUT-2026Q4-CAMPAIGN';

-- K3 the founding cohort is the approved list
SELECT 'K3_founding_is_approved_list' AS check_name,
       IF(COUNT(*) = 59 AND COUNTIF(arm = 'HOLDOUT') = 12
          AND FARM_FINGERPRINT(STRING_AGG(FORMAT('%s|%s|%s|%d', unit_id, arm, stratum, seq_in_stratum), ',' ORDER BY unit_id)) = 4171456845817687166, 0, 1) AS violations,
       FORMAT('rows %d, HOLDOUT %d, fingerprint %s', COUNT(*), COUNTIF(arm = 'HOLDOUT'),
              IFNULL(CAST(FARM_FINGERPRINT(STRING_AGG(FORMAT('%s|%s|%s|%d', unit_id, arm, stratum, seq_in_stratum), ',' ORDER BY unit_id)) AS STRING), 'none')) AS detail
FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
WHERE trial_id = 'HOLDOUT-2026Q4-CAMPAIGN-T2' AND STARTS_WITH(assignment_rule, 'FOUNDING');

-- K4 T2's arms follow the rule from stored columns; each stratum's sequence is whole
WITH t2 AS (
  SELECT *, COUNT(*) OVER (PARTITION BY stratum) AS n_stratum
  FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
  WHERE trial_id = 'HOLDOUT-2026Q4-CAMPAIGN-T2'),
per_stratum AS (
  SELECT stratum, COUNT(*) - COUNT(DISTINCT seq_in_stratum) AS dup_seq,
         COUNTIF(seq_in_stratum >= n_stratum OR seq_in_stratum < 0) AS seq_out_of_range
  FROM t2 GROUP BY 1),
m AS (
  SELECT (SELECT COUNTIF(arm != IF(MOD(seq_in_stratum + MOD(ABS(FARM_FINGERPRINT(CONCAT(seed, '|', stratum))), 5), 5) = 0,
                                   'HOLDOUT', 'TREATED')) FROM t2) AS arm_mismatch,
         (SELECT IFNULL(SUM(dup_seq), 0) FROM per_stratum) AS dup_seq,
         (SELECT IFNULL(SUM(seq_out_of_range), 0) FROM per_stratum) AS seq_out_of_range,
         (SELECT COUNT(*) FROM t2) AS n_rows)
SELECT 'K4_arms_follow_rule' AS check_name,
       arm_mismatch + dup_seq + seq_out_of_range + IF(n_rows = 0, 1, 0) AS violations,
       FORMAT('T2 rows %d, arm mismatches %d, duplicate seq %d, seq out of range %d', n_rows, arm_mismatch, dup_seq, seq_out_of_range) AS detail
FROM m;

-- K5 seed index 5 is the first passing A1-A3 (A2 band below in k)
WITH k AS (SELECT 0.18 AS a2_lo, 0.22 AS a2_hi),
f AS (
  SELECT * FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
  WHERE trial_id = 'HOLDOUT-2026Q4-CAMPAIGN-T2' AND STARTS_WITH(assignment_rule, 'FOUNDING')),
pop AS (SELECT COUNT(*) AS n, COUNT(DISTINCT family) AS n_fam, SUM(spend_28d_at_assign) AS spend FROM f),
d AS (
  SELECT i, f.family, f.spend_28d_at_assign,
         MOD(f.seq_in_stratum + MOD(ABS(FARM_FINGERPRINT(CONCAT('OI-HOLDOUT-v2|', CAST(i AS STRING), '|', f.stratum))), 5), 5) = 0 AS is_holdout
  FROM UNNEST(GENERATE_ARRAY(0, 5)) AS i CROSS JOIN f),
per AS (
  SELECT i, COUNTIF(is_holdout) AS n_h, SUM(IF(is_holdout, spend_28d_at_assign, 0)) AS h_spend,
         COUNT(DISTINCT IF(is_holdout, family, NULL)) AS h_fam
  FROM d GROUP BY 1),
j AS (
  SELECT per.i, per.n_h, SAFE_DIVIDE(per.h_spend, pop.spend) AS share, per.h_fam, pop.n_fam,
         (per.n_h = CAST(ROUND(pop.n / 5) AS INT64)
          AND SAFE_DIVIDE(per.h_spend, pop.spend) BETWEEN k.a2_lo AND k.a2_hi
          AND per.h_fam = pop.n_fam) AS passes
  FROM per CROSS JOIN pop CROSS JOIN k)
SELECT 'K5_seed_is_first_pass' AS check_name,
       IF(COUNTIF(i = 5 AND passes) = 1, 0, 1) + COUNTIF(i < 5 AND passes) AS violations,
       IFNULL(STRING_AGG(FORMAT('index %d: %d controls, %.1f%%, %d of %d families%s', i, n_h, 100 * share, h_fam, n_fam,
                                IF(passes, ' PASS', '')), '; ' ORDER BY i), 'no founding rows') AS detail
FROM j;

-- K6 the gate is T2's arm
WITH gate AS (
  SELECT DISTINCT campaign_id, 1 AS g FROM `onyga-482313.OI.V_HOLDOUT_ARM`
  WHERE CURRENT_DATE('America/Los_Angeles') BETWEEN gate_from AND gate_to),
t2 AS (
  SELECT DISTINCT unit_id AS campaign_id, 1 AS h FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT`
  WHERE trial_id = 'HOLDOUT-2026Q4-CAMPAIGN-T2' AND unit_type = 'CAMPAIGN' AND arm = 'HOLDOUT'),
x AS (SELECT campaign_id, g IS NOT NULL AS in_gate, h IS NOT NULL AS in_t2 FROM gate FULL OUTER JOIN t2 USING (campaign_id))
SELECT 'K6_gate_is_t2_arm' AS check_name,
       COUNTIF(in_gate != in_t2) + IF(COUNTIF(in_t2) = 0, 1, 0) AS violations,
       FORMAT('binding today %d, T2 HOLDOUT %d, binding but not T2 %d, T2 not binding %d',
              COUNTIF(in_gate), COUNTIF(in_t2), COUNTIF(in_gate AND NOT in_t2), COUNTIF(in_t2 AND NOT in_gate)) AS detail
FROM x;

-- K7 no gate reader bypasses the arm (deployed bodies; comment text removed before counting)
WITH bodies AS (
  SELECT table_name AS object_name, view_definition AS body
  FROM `onyga-482313.OI.INFORMATION_SCHEMA.VIEWS`
  UNION ALL
  SELECT routine_name, routine_definition
  FROM `onyga-482313.OI.INFORMATION_SCHEMA.ROUTINES`),
n AS (
  SELECT object_name,
         ARRAY_LENGTH(REGEXP_EXTRACT_ALL(REGEXP_REPLACE(IFNULL(body, ''), r'--[^\n]*', ''),
                      r'(?i)(?:`?onyga-482313`?\.)?`?\bOI`?\.`?DE_HOLDOUT_ASSIGNMENT\b')) AS n_refs
  FROM bodies
  WHERE NOT STARTS_WITH(object_name, 'TMP_HT2_')),
expected AS (
  SELECT * FROM UNNEST([STRUCT('V_HOLDOUT_ARM' AS object_name, 1 AS n_expected),
                        ('V_HOLDOUT_READOUT', 1), ('V_ENGINE_HEALTH', 1), ('SP_ASSIGN_HOLDOUT', 3)])),
x AS (
  SELECT object_name, IFNULL(n.n_refs, 0) AS n_refs, IFNULL(e.n_expected, 0) AS n_expected
  FROM n FULL OUTER JOIN expected e USING (object_name))
SELECT 'K7_no_reader_bypasses_arm' AS check_name,
       COUNTIF(n_refs != n_expected) AS violations,
       IFNULL(STRING_AGG(IF(n_refs != n_expected, FORMAT('%s %d (expected %d)', object_name, n_refs, n_expected), NULL),
                         '; ' ORDER BY object_name), 'every object on its count') AS detail
FROM x;
