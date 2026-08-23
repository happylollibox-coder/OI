-- =============================================================================================
-- THE MORNING SURFACE acceptance — family seat register Task 4. Every row must read PASS.
--
-- WHAT THIS SUITE GUARDS. Task 4 puts the 80/20 doctrine in front of a person in three places
-- that are not the register: the SEATS section of V_DAILY_BRIEF, the SEATS section of
-- V_RUN_SUMMARY, and the SeatRegister cube (which reads T_FAMILY_SEAT_REGISTER). A surface that
-- disagrees with the register is worse than no surface, because the reader has no way to know
-- which of the two is lying. So every check here RE-DERIVES the figure from the register's own
-- rows and compares — it never asks a surface to confirm itself, and it never reads a number out
-- of the sentence it is testing except to compare that number against an independent derivation.
--
-- Run it after SP_REFRESH_CUBE_TABLES (the T_ the surfaces read is built there, step 0c):
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
--
-- TDD record: run BEFORE Task 4 shipped, C07 dies on "Not found: Table T_FAMILY_SEAT_REGISTER"
-- and, with that table hand-built to get past it, C01/C02/C03/C04/C05/C09/C10 all read FAIL
-- because neither view has a SEATS section yet. After the deploy every check reads PASS.
--
-- THE TWO CLOCKS (the same caveat B04 carries in the register suite, in a new place). The
-- surfaces read T_FAMILY_SEAT_REGISTER, an image of the register taken when SP_REFRESH_CUBE_TABLES
-- last ran; the register itself is live. Between an ads-watermark advance and the next pass the
-- two differ, and C07 reports that drift as violations. That is the pipeline's ordinary mid-day
-- state, not a defect: check LOG_PIPELINE_RUNS for the last SP_REFRESH_CUBE_TABLES and re-run
-- after the next pass before treating a C07 failure as a bug. C01–C05 compare each surface with
-- the SAME image the surface read, so they are immune to it.
--
-- Checks:
--   C01 One line per working family, and only those: the brief's SEATS section has exactly one
--       row per FAMILY row of the register on the today horizon, no launch family, no duplicates.
--   C02 The brief line reconciles to the register's FAMILY row: from_value is the family's
--       bad_side_per_day, to_value its allowance_per_day, status its doctrine_status — to the cent.
--   C03 The brief SENTENCE reconciles too, and is re-derived from the register's OWN PER-ROW
--       costs, never from the family aggregate the sentence was built from: the seat / leak /
--       untracked counts equal the count of SEAT (20% side) / LEAK / GAP rows for that family, and
--       the dollars printed beside each equal the SUM of those rows' cost_per_day. Tolerance $0.02
--       on the dollars, and the reason is on the check: the sentence renders one aggregate to two
--       decimals while this re-derivation adds up per-row costs that were each rounded on their own
--       row (ruling R-m). Counts are exact — a count has no rounding.
--   C04 Nothing falls through to blank: every SEATS row has a non-empty section, source, family,
--       item, action, status and detail, and no row wears the CASE's unlearned-status wording.
--   C05 The run summary's SEATS section: one row per working family, a label that names the family
--       and a learned doctrine phrase, n = the family's 20%-side seat count re-derived from the
--       register, dollars_per_day = its open capacity to the cent, a non-empty detail.
--   C06 No label anywhere in V_RUN_SUMMARY is blank or NULL — including the UNCHANGED section's
--       fall-through arm, which used to hand back LOWER(state) and would have published an empty
--       label for a row the snapshot wrote with no state at all.
--   C07 The cube reads the register: T_FAMILY_SEAT_REGISTER agrees with V_FAMILY_SEAT_REGISTER row
--       for row on sort_key, every FAMILY figure to the cent, and sort_key is unique in the table —
--       the precondition for using it as the cube's primary key.
--   C08 Every category a person reads on the cube is a non-empty plain word, on every row that
--       carries one; and no row that carries a category carries a blank side.
--   C09 No launch family is judged on either surface: zero SEATS rows for a family the register
--       publishes as REFERENCE, in the brief and in the run summary.
--   C10 The brief's SEATS row names no campaign and no keyword — which is why the holdout rule has
--       nothing to mark on it — and section_rank 6 belongs to SEATS and to nothing else.
--
-- The cube's own shape (a dimension for every column a person reads, and the doctrine label CASEs
-- naming every status the register can emit) is asserted by the file checker that SQL cannot run:
--   python3 scripts/bigquery/tests/check_seat_surface_labels.py
-- =============================================================================================

CREATE TEMP TABLE reg AS SELECT * FROM `onyga-482313.OI.V_FAMILY_SEAT_REGISTER`;
CREATE TEMP TABLE tab AS SELECT * FROM `onyga-482313.OI.T_FAMILY_SEAT_REGISTER`;
CREATE TEMP TABLE brief AS
  SELECT * FROM `onyga-482313.OI.V_DAILY_BRIEF` WHERE section = 'SEATS';
CREATE TEMP TABLE runs AS SELECT * FROM `onyga-482313.OI.V_RUN_SUMMARY`;

CREATE TEMP TABLE brief_rank AS
  SELECT DISTINCT section, section_rank FROM `onyga-482313.OI.V_DAILY_BRIEF`;

WITH
famrow AS (
  SELECT * FROM tab WHERE row_type = 'FAMILY' AND horizon = 'today'),
refrow AS (
  SELECT DISTINCT family FROM tab WHERE row_type = 'REFERENCE'),
per_row AS (
  SELECT family,
         COUNTIF(row_type = 'SEAT' AND side = '20')                       AS n_seats,
         ROUND(SUM(IF(row_type = 'SEAT' AND side = '20', cost_per_day, 0)), 2) AS seat_cost,
         COUNTIF(row_type = 'LEAK')                                       AS n_leaks,
         ROUND(SUM(IF(row_type = 'LEAK', cost_per_day, 0)), 2)            AS leak_cost,
         COUNTIF(row_type = 'GAP')                                        AS n_gaps,
         ROUND(SUM(IF(row_type = 'GAP', cost_per_day, 0)), 2)             AS gap_cost
  FROM tab GROUP BY 1),
-- the figures the brief PRINTED, pulled back out of its own sentence so they can be compared
-- against per_row above. One capturing group per extract: BigQuery's REGEXP_EXTRACT allows only one.
said AS (
  SELECT b.campaign_name AS family,
         SAFE_CAST(REGEXP_EXTRACT(b.detail, r'([0-9]+) numbered seats?') AS INT64)          AS n_seats,
         SAFE_CAST(REGEXP_EXTRACT(b.detail, r'numbered seats? \(\$([0-9.]+)/day\)') AS FLOAT64) AS seat_cost,
         SAFE_CAST(REGEXP_EXTRACT(b.detail, r'([0-9]+) leaks? still spending') AS INT64)    AS n_leaks,
         SAFE_CAST(REGEXP_EXTRACT(b.detail, r'leaks? still spending \(\$([0-9.]+)/day\)') AS FLOAT64) AS leak_cost,
         SAFE_CAST(REGEXP_EXTRACT(b.detail, r'([0-9]+) untracked keywords?') AS INT64)      AS n_gaps,
         SAFE_CAST(REGEXP_EXTRACT(b.detail, r'untracked keywords? \(\$([0-9.]+)/day\)') AS FLOAT64) AS gap_cost
  FROM brief b),
rs AS (SELECT * FROM runs WHERE section = 'SEATS'),
-- NON-VACUITY. Every check below that reads only one of these populations counts an EMPTY
-- population as a violation of itself. Without this, a check that inspects the brief's SEATS rows
-- reports PASS the moment the section stops existing — which is precisely the failure it is there
-- to catch, and precisely how the first run of this suite reported five green checks against a
-- section that had not been written yet.
pop AS (
  SELECT (SELECT COUNT(*) FROM famrow) AS n_fam,
         (SELECT COUNT(*) FROM brief)  AS n_brief,
         (SELECT COUNT(*) FROM rs)     AS n_rs,
         (SELECT COUNT(*) FROM tab)    AS n_tab,
         (SELECT COUNT(*) FROM said WHERE n_seats IS NOT NULL) AS n_said),
checks AS (
  SELECT 'C01 one brief SEATS line per working family, no launch family, no duplicate' AS check_name,
         (SELECT ABS(COUNT(*) - (SELECT COUNT(*) FROM famrow)) FROM brief)
         + (SELECT COUNT(*) FROM (SELECT campaign_name FROM brief GROUP BY 1 HAVING COUNT(*) > 1))
         + (SELECT COUNT(*) FROM brief b LEFT JOIN famrow f ON f.family = b.campaign_name
            WHERE f.family IS NULL)
         + (SELECT COUNT(*) FROM famrow f LEFT JOIN brief b ON b.campaign_name = f.family
            WHERE b.campaign_name IS NULL) AS violations
  UNION ALL
  SELECT 'C02 every brief SEATS line reconciles to its register FAMILY row (bad side, allowance, doctrine status) to the cent',
         (SELECT COUNT(*) FROM brief b JOIN famrow f ON f.family = b.campaign_name
          WHERE ABS(COALESCE(b.from_value, -1) - COALESCE(f.bad_side_per_day, -2)) > 0.01
             OR ABS(COALESCE(b.to_value, -1) - COALESCE(f.allowance_per_day, -2)) > 0.01
             OR b.status IS DISTINCT FROM f.doctrine_status)
         + (SELECT IF(n_brief = 0 OR n_fam = 0, 1, 0) FROM pop)
  UNION ALL
  SELECT 'C03 the brief sentence agrees with the register re-derived from its OWN per-row costs (counts exact; dollars within $0.02 — a two-decimal aggregate against a sum of per-row rounded costs, R-m)',
         (SELECT COUNT(*) FROM said s JOIN per_row p ON p.family = s.family
          WHERE s.n_seats IS DISTINCT FROM p.n_seats
             OR s.n_leaks IS DISTINCT FROM p.n_leaks
             OR s.n_gaps  IS DISTINCT FROM p.n_gaps
             OR ABS(COALESCE(s.seat_cost, -1) - COALESCE(p.seat_cost, 0)) > 0.02
             OR ABS(COALESCE(s.leak_cost, -1) - COALESCE(p.leak_cost, 0)) > 0.02
             OR ABS(COALESCE(s.gap_cost,  -1) - COALESCE(p.gap_cost,  0)) > 0.02)
         + (SELECT COUNTIF(n_seats IS NULL OR n_leaks IS NULL OR n_gaps IS NULL
                           OR seat_cost IS NULL OR leak_cost IS NULL OR gap_cost IS NULL) FROM said)
         + (SELECT IF(n_said = 0 OR n_said != n_fam, 1, 0) FROM pop)
  UNION ALL
  SELECT 'C04 nothing blank on a brief SEATS row, and no row wears the unlearned-doctrine-status wording',
         (SELECT COUNTIF(COALESCE(section, '') = '' OR COALESCE(source, '') = ''
                      OR COALESCE(campaign_name, '') = '' OR COALESCE(item, '') = ''
                      OR COALESCE(action, '') = '' OR COALESCE(status, '') = ''
                      OR COALESCE(detail, '') = '') FROM brief)
         + (SELECT COUNTIF(action LIKE '%has not learned%' OR action LIKE '%unlearned%'
                        OR detail LIKE '%has not learned%') FROM brief)
         + (SELECT IF(n_brief = 0 OR n_fam = 0, 1, 0) FROM pop)
  UNION ALL
  SELECT 'C05 the run summary SEATS section: one row per working family, family named in the label, seat count and open capacity re-derived from the register',
         (SELECT ABS(COUNT(*) - (SELECT COUNT(*) FROM famrow)) FROM rs)
         + (SELECT COUNT(*) FROM famrow f LEFT JOIN rs r ON r.label LIKE CONCAT(f.family, ' — %')
            WHERE r.label IS NULL)
         + (SELECT COUNT(*) FROM rs r JOIN famrow f ON r.label LIKE CONCAT(f.family, ' — %')
            LEFT JOIN per_row p ON p.family = f.family
            WHERE r.n IS DISTINCT FROM COALESCE(p.n_seats, 0)
               OR ABS(COALESCE(r.dollars_per_day, -1) - COALESCE(f.open_capacity_per_day, -2)) > 0.01
               OR COALESCE(r.detail, '') = ''
               OR r.label LIKE '%has not learned%')
         + (SELECT IF(n_rs = 0 OR n_fam = 0, 1, 0) FROM pop)
  UNION ALL
  SELECT 'C06 no V_RUN_SUMMARY label is blank or NULL, in any section',
         (SELECT COUNTIF(COALESCE(label, '') = '') FROM runs)
         + (SELECT IF((SELECT COUNT(*) FROM runs) = 0, 1, 0))
  UNION ALL
  SELECT 'C07 the cube table is the register: same rows by sort_key, FAMILY figures to the cent, sort_key unique',
         (SELECT ABS(COUNT(*) - (SELECT COUNT(*) FROM reg)) FROM tab)
         + (SELECT COUNT(*) FROM (SELECT sort_key FROM tab GROUP BY 1 HAVING COUNT(*) > 1))
         + (SELECT COUNT(*) FROM reg v FULL OUTER JOIN tab t ON t.sort_key = v.sort_key
            WHERE v.sort_key IS NULL OR t.sort_key IS NULL)
         + (SELECT COUNT(*) FROM reg v JOIN tab t ON t.sort_key = v.sort_key
            WHERE v.row_type = 'FAMILY'
              AND (ABS(COALESCE(v.bad_side_per_day, 0)  - COALESCE(t.bad_side_per_day, 0))  > 0.01
                OR ABS(COALESCE(v.allowance_per_day, 0) - COALESCE(t.allowance_per_day, 0)) > 0.01
                OR ABS(COALESCE(v.good_side_per_day, 0) - COALESCE(t.good_side_per_day, 0)) > 0.01
                OR v.doctrine_status IS DISTINCT FROM t.doctrine_status))
         + (SELECT IF(n_tab = 0, 1, 0) FROM pop)
  UNION ALL
  SELECT 'C08 every category on the cube is a non-empty plain word, and carries a side',
         (SELECT COUNTIF(category IS NOT NULL AND TRIM(category) = '') FROM tab)
         + (SELECT COUNTIF(row_type IN ('CATEGORY', 'SEAT', 'LEAK', 'GAP', 'NO_CLOCK')
                           AND COALESCE(category, '') = '') FROM tab)
         + (SELECT COUNTIF(row_type IN ('SEAT', 'LEAK', 'GAP', 'NO_CLOCK')
                           AND COALESCE(side, '') = '') FROM tab)
         + (SELECT IF(n_tab = 0, 1, 0) FROM pop)
  UNION ALL
  SELECT 'C09 no launch family is judged on either surface',
         (SELECT COUNT(*) FROM brief b JOIN refrow r ON r.family = b.campaign_name)
         + (SELECT COUNT(*) FROM rs x JOIN refrow r ON x.label LIKE CONCAT(r.family, ' — %'))
         + (SELECT IF(n_brief = 0 OR n_rs = 0 OR (SELECT COUNT(*) FROM refrow) = 0, 1, 0) FROM pop)
  UNION ALL
  SELECT 'C10 the brief SEATS row names no campaign and no keyword; section_rank 6 belongs to SEATS alone',
         (SELECT COUNTIF(campaign_id IS NOT NULL OR keyword_id IS NOT NULL) FROM brief)
         + (SELECT COUNTIF(section_rank != 6) FROM brief)
         + (SELECT COUNTIF(section != 'SEATS' AND section_rank = 6) FROM brief_rank)
         + (SELECT IF(n_brief = 0, 1, 0) FROM pop)
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM checks ORDER BY check_name;
