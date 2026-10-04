-- =============================================================================================
-- HOLDOUT_RESTART acceptance — holdout trial 2 (plan docs/superpowers/plans/2026-10-03-holdout-restart.md
-- §5). EVERY ROW MUST READ violations = 0.
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache --format=prettyjson \
--     "$(grep -v '^[[:space:]]*--' FILE)"
-- Each statement returns one row (check_name, violations, detail); parse the multi-statement output
-- by regex over the {"check_name"...} objects.
-- This file holds K1-K6 (plan Tasks 2-3). K7-K12 are added by plan Task 7.
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
