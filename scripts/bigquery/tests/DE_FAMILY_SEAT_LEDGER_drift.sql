-- =============================================================================================
-- DE_FAMILY_SEAT_LEDGER drift acceptance — what a NEW pass must not break.
-- v27.139 REWRITE (2026-08-24, ruling R-o): the occupant set moved from FACT_KEYWORD_STATE alone
-- to FACT_PLAN_NEXT_WEEK plan='B''s own seated keywords, agreement-tier joined to plan='A'. Every
-- check below that reads "today's occupant set" now reads it from a PLAN snapshot copy
-- (TMP_FSR_PLAN), not a live table — same discipline the ledger images already followed.
--
-- WHY THIS FILE EXISTS. The A-suite (DE_FAMILY_SEAT_LEDGER_acceptance.sql) judges the ledger
-- against ONE snapshot: it cannot see whether a seat number survived the night, whether a
-- newly-closed row's tier is right (a pre-migration row closed on the same calendar date carries
-- no tier and would be a false positive there), or whether a DISPUTED occupant already open was
-- ever evicted. This file is the missing half: it compares a ledger AFTER a pass against the
-- ledger BEFORE it, and the plan snapshot the AFTER ledger was maintained against.
--
-- THE FOUR IMAGES IT READS. This file NEVER reads a live table. It reads four copies the operator
-- makes, so the BEFORE image can never silently be the same image as the AFTER one:
--   TMP_FSR_LEDGER_BEFORE  the ledger as it stood BEFORE the pass (or replay) under test
--   TMP_FSR_LEDGER_AFTER   the ledger as it stands AFTER it
--   TMP_FSR_STATE          the keyword snapshot the AFTER ledger was maintained against
--   TMP_FSR_PLAN           FACT_PLAN_NEXT_WEEK (both plans, the as_of the AFTER ledger read)
-- If any copy is missing the query ERRORS on the table name. That is deliberate — see D00.
--
-- HOW TO RUN IT AFTER A REAL PASS (house rule: copies only, dropped afterwards):
--   BEFORE the pass runs:
--     CREATE OR REPLACE TABLE `onyga-482313.OI.TMP_FSR_LEDGER_BEFORE` AS
--       SELECT * FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`;
--   AFTER it finishes:
--     CREATE OR REPLACE TABLE `onyga-482313.OI.TMP_FSR_LEDGER_AFTER` AS
--       SELECT * FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`;
--     CREATE OR REPLACE TABLE `onyga-482313.OI.TMP_FSR_STATE` AS
--       SELECT * FROM `onyga-482313.OI.FACT_KEYWORD_STATE`;
--     CREATE OR REPLACE TABLE `onyga-482313.OI.TMP_FSR_PLAN` AS
--       SELECT * FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
--       WHERE as_of = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE plan = 'B');
--   Then run this file; every row must read PASS. Then DROP the four copies.
--
-- Checks:
--   D00 THE TWO LEDGER IMAGES ARE DIFFERENT IMAGES. If BEFORE and AFTER are byte-identical, every
--       check below compares a table to itself and reads VACUOUS, not PASS.
--   D01 STABILITY — every keyword seated in BOTH images kept its seat number.
--   D02 PLAIN WORDS — every closed row carries closed_reason_text mapped to its code.
--   D03 CODE AND DATE — every closed row carries a mapped code; every row closed since BEFORE is
--       dated between BEFORE's newest date and the AFTER snapshot.
--   D04 THE INJECTED DEPARTURES closed with the code the case expects (edit `expected`).
--   D05 R-h — every parked keyword whose re-verdict appointment has passed and that this pass
--       actually released (closed, not held) closed PARK_LAPSED.
--   D06 REUSE — admissions took the LOWEST free numbers.
--   D07 one keyword per open seat number within a family; numbers >= 1.
--   D08 NO OVERWRITE — no admission took a number a still-seated keyword of the family holds.
--   D09 (v27.139) PLAN RECONCILIATION (Task 6): the AFTER ledger's open, non-held seat set for
--       plan B's seated keywords (TMP_FSR_PLAN, plan='B', seat_no IS NOT NULL) equals plan B's
--       seated set EXACTLY — one seat number per seated keyword, no orphans either direction.
--   D10 (v27.139) CONFIRMED-ONLY CLOSURE, PRECISE — every row THIS PASS closed (closed in AFTER,
--       not in BEFORE) reads agreement_tier = 'CONFIRMED'. Unlike the acceptance suite's A16 this
--       cannot be fooled by a pre-migration same-day closure, because it reads the true diff.
--   D11 (v27.139) NO EVICTION OF A DISPUTED OCCUPANT — no row held open (held_reason =
--       'HELD_DISPUTED') in BEFORE is CLOSED in AFTER while plan A (TMP_FSR_PLAN, plan='A') still
--       calls it NOT_GOOD. A held row may only close once plan A stops objecting (P-4/P-5 spirit:
--       never cut on one judge's word alone) or continue being held (or resume as an occupant).
--   D12 (v27.139) ADMISSION ORDER ACROSS THE PASS — among rows admitted (opened) on this pass, no
--       DISPUTED candidate took a lower seat number than a CONFIRMED one admitted in the same
--       family on the same pass (the before/after-precise version of A17).
-- =============================================================================================
WITH
run_day AS (SELECT MAX(snapshot_date) AS d FROM `onyga-482313.OI.TMP_FSR_STATE`),
before AS (SELECT family, campaign_id, keyword_id, seat_no
           FROM `onyga-482313.OI.TMP_FSR_LEDGER_BEFORE` WHERE closed_on IS NULL),
before_full AS (SELECT * FROM `onyga-482313.OI.TMP_FSR_LEDGER_BEFORE`),
after_open AS (SELECT family, campaign_id, keyword_id, seat_no, opened_on, agreement_tier, held_reason
               FROM `onyga-482313.OI.TMP_FSR_LEDGER_AFTER` WHERE closed_on IS NULL),
after_closed AS (SELECT * FROM `onyga-482313.OI.TMP_FSR_LEDGER_AFTER` WHERE closed_on IS NOT NULL),
plan_b AS (SELECT family, campaign_id, keyword_id FROM `onyga-482313.OI.TMP_FSR_PLAN` WHERE plan = 'B' AND seat_no IS NOT NULL),
plan_a AS (SELECT family, campaign_id, keyword_id, side AS side_a FROM `onyga-482313.OI.TMP_FSR_PLAN` WHERE plan = 'A'),
-- the rows THIS pass closed: closed in AFTER and not already closed in BEFORE
new_closed AS (
  SELECT c.* FROM after_closed c
  LEFT JOIN `onyga-482313.OI.TMP_FSR_LEDGER_BEFORE` b
    ON b.family = c.family AND b.campaign_id = c.campaign_id AND b.keyword_id = c.keyword_id
   AND b.opened_on = c.opened_on AND b.closed_on IS NOT NULL
  WHERE b.campaign_id IS NULL),
-- the same image, taken twice, is not a before-and-after pair (D00)
fp AS (
  SELECT
    (SELECT FARM_FINGERPRINT(STRING_AGG(TO_JSON_STRING(t), '|'
              ORDER BY family, campaign_id, keyword_id, opened_on))
     FROM `onyga-482313.OI.TMP_FSR_LEDGER_BEFORE` t) AS fp_before,
    (SELECT FARM_FINGERPRINT(STRING_AGG(TO_JSON_STRING(t), '|'
              ORDER BY family, campaign_id, keyword_id, opened_on))
     FROM `onyga-482313.OI.TMP_FSR_LEDGER_AFTER` t) AS fp_after),
sop AS (SELECT * FROM UNNEST([
  STRUCT('KILLED' AS code, 'The keyword is gone from the snapshot after its last verdict was failed or dead, or the ladder now reads dead: the book paused a failed keyword. The seat is free.' AS txt),
  ('PAUSED', 'The keyword is gone from the snapshot, or the ladder now reads parked, without a failed verdict first. The seat is free.'),
  ('PARK_LAPSED', 'The keyword reads parked on the ladder but is no longer a parked seat: it has no spend on the basis window, or its re-verdict appointment has passed. A parked keyword that still spends past its appointment is a leak (pause row). The seat is free.'),
  ('LEFT_FAMILY', 'The keyword is still tracked but now belongs to another family, or its family left the working (HARVEST) book. The seat is free.'),
  ('DEFENSE_EXEMPT', 'The keyword is now brand defense. Defense is never judged on profit, so it is never seated. The seat is free.'),
  ('TO_GOOD_SIDE', 'The keyword is now winning or at its bar: it moved to the 80% side. The seat is free.'),
  ('TO_WAITING', 'The keyword is still a trial but is no longer bought at an entry or park bid and is not a stalled probe: it is back to waiting for clicks on the 80% side, no verdict yet. The seat is free.')])),
-- the departures the run under test injected; edit for the case being proven
expected AS (SELECT * FROM UNNEST(ARRAY<STRUCT<cid STRING, kid STRING, code STRING>>[])),
fam_admits AS (SELECT family, MAX(seat_no) AS max_admit
               FROM after_open, run_day WHERE opened_on = run_day.d GROUP BY family),
fam_free AS (
  SELECT f.family, MIN(cand) AS min_free
  FROM (SELECT family, MAX(seat_no) AS mx FROM after_open GROUP BY family) f,
       UNNEST(GENERATE_ARRAY(1, f.mx)) AS cand
  LEFT JOIN after_open o ON o.family = f.family AND o.seat_no = cand
  WHERE o.seat_no IS NULL GROUP BY f.family),
checks AS (
  SELECT 'D00 the BEFORE and AFTER images are different images (else every check below is vacuous)' AS check_name,
         (SELECT COUNTIF(fp_before = fp_after) FROM fp) AS violations
  UNION ALL SELECT 'D01 every continuing occupant kept its seat number',
         (SELECT COUNT(*) FROM before b JOIN after_open a USING (family, campaign_id, keyword_id)
          WHERE a.seat_no != b.seat_no)
  UNION ALL SELECT 'D02 every closed row carries the SOP sentence mapped to its code',
         (SELECT COUNT(*) FROM after_closed c LEFT JOIN sop s ON s.code = c.closed_reason
          WHERE c.closed_reason_text IS NULL
             OR (c.closed_reason != 'STATE_CHANGED' AND c.closed_reason_text IS DISTINCT FROM s.txt)
             OR (c.closed_reason = 'STATE_CHANGED'
                 AND NOT (c.closed_reason_text LIKE 'The keyword left the seat set — it now reads %'
                          AND c.closed_reason_text LIKE '%. The seat is free.')))
  UNION ALL SELECT 'D03 every closed row carries a mapped reason code; every row closed since the BEFORE image is dated on a snapshot between that image and the AFTER snapshot',
         (SELECT COUNT(*) FROM after_closed c
          WHERE c.closed_reason NOT IN ('KILLED','PAUSED','PARK_LAPSED','LEFT_FAMILY','DEFENSE_EXEMPT','TO_GOOD_SIDE','TO_WAITING','STATE_CHANGED'))
         + (SELECT COUNT(*) FROM new_closed c, run_day,
                 (SELECT MAX(GREATEST(opened_on, COALESCE(closed_on, opened_on))) AS d
                  FROM `onyga-482313.OI.TMP_FSR_LEDGER_BEFORE`) bmax
            WHERE c.closed_on > run_day.d OR c.closed_on < bmax.d)
  UNION ALL SELECT 'D04 the injected departures closed with the expected code',
         (SELECT COUNT(*) FROM expected e
          LEFT JOIN after_closed c ON c.campaign_id = e.cid AND c.keyword_id = e.kid
          WHERE c.closed_reason IS DISTINCT FROM e.code)
  UNION ALL SELECT 'D05 R-h: every parked seat past its appointment that was actually released (closed, not held) closed PARK_LAPSED',
         (SELECT COUNT(*) FROM before b
          JOIN `onyga-482313.OI.TMP_FSR_STATE` s
            ON s.campaign_id = b.campaign_id AND s.keyword_id = b.keyword_id
          LEFT JOIN after_closed c
            ON c.campaign_id = b.campaign_id AND c.keyword_id = b.keyword_id, run_day
          LEFT JOIN after_open o2
            ON o2.campaign_id = b.campaign_id AND o2.keyword_id = b.keyword_id
          WHERE s.state = 'PARKED' AND s.next_check_date < run_day.d
            AND o2.campaign_id IS NULL  -- not held open this pass
            AND c.closed_reason IS DISTINCT FROM 'PARK_LAPSED')
  UNION ALL SELECT 'D06 admissions took the lowest free numbers (no free number below any admitted one)',
         (SELECT COUNT(*) FROM fam_admits a JOIN fam_free f USING (family) WHERE f.min_free < a.max_admit)
  UNION ALL SELECT 'D07 one keyword per open seat number within a family; numbers >= 1',
         (SELECT COUNT(*) FROM (SELECT family, seat_no FROM after_open GROUP BY 1, 2 HAVING COUNT(*) > 1))
         + (SELECT COUNTIF(seat_no IS NULL OR seat_no < 1) FROM after_open)
  UNION ALL SELECT 'D08 no admission took a number a still-seated keyword of the family holds',
         (SELECT COUNT(*) FROM after_open a, run_day WHERE a.opened_on = run_day.d
            AND EXISTS (SELECT 1 FROM before b
                        WHERE b.family = a.family AND b.seat_no = a.seat_no
                          AND NOT (b.campaign_id = a.campaign_id AND b.keyword_id = a.keyword_id)
                          AND EXISTS (SELECT 1 FROM after_open z
                                      WHERE z.family = b.family AND z.campaign_id = b.campaign_id
                                        AND z.keyword_id = b.keyword_id)))
  UNION ALL SELECT 'D09 (Task 6) the AFTER ledger\'s open non-held seat set for plan B\'s seated keywords equals plan B\'s seated set exactly, one number each, no orphans either direction',
         (SELECT COUNT(*) FROM plan_b p
          LEFT JOIN after_open o ON o.family = p.family AND o.campaign_id = p.campaign_id AND o.keyword_id = p.keyword_id
          WHERE o.campaign_id IS NULL OR o.held_reason IS NOT NULL)
         + (SELECT COUNT(*) FROM after_open o
            LEFT JOIN plan_b p ON p.family = o.family AND p.campaign_id = o.campaign_id AND p.keyword_id = o.keyword_id
            WHERE o.held_reason IS NULL AND p.campaign_id IS NULL)
         + (SELECT COUNT(*) FROM (SELECT family, seat_no FROM after_open WHERE held_reason IS NULL GROUP BY 1, 2 HAVING COUNT(*) > 1))
  UNION ALL SELECT 'D10 every row THIS PASS closed reads agreement_tier = CONFIRMED',
         (SELECT COUNT(*) FROM new_closed WHERE agreement_tier IS DISTINCT FROM 'CONFIRMED')
  UNION ALL SELECT 'D11 no HELD_DISPUTED occupant is evicted while plan A still says NOT_GOOD',
         (SELECT COUNT(*) FROM before_full b
          JOIN after_closed c
            ON c.family = b.family AND c.campaign_id = b.campaign_id AND c.keyword_id = b.keyword_id
           AND c.opened_on = b.opened_on
          JOIN plan_a a ON a.family = b.family AND a.campaign_id = b.campaign_id AND a.keyword_id = b.keyword_id
          WHERE b.closed_on IS NULL AND b.held_reason = 'HELD_DISPUTED' AND a.side_a = 'NOT_GOOD')
  UNION ALL SELECT 'D12 admission order across the pass: no DISPUTED candidate admitted this pass took a lower seat number than a CONFIRMED one admitted in the same family this pass',
         (SELECT COUNT(*) FROM after_open d
          JOIN after_open c ON c.family = d.family AND c.opened_on = d.opened_on, run_day
          WHERE d.opened_on = run_day.d AND d.agreement_tier = 'DISPUTED'
            AND c.agreement_tier = 'CONFIRMED' AND c.seat_no > d.seat_no)
)
SELECT check_name, violations,
       CASE WHEN violations = 0 THEN 'PASS'
            WHEN check_name LIKE 'D00%' THEN 'VACUOUS — the BEFORE copy is the AFTER copy; this run proves nothing'
            ELSE 'FAIL' END AS result
FROM checks ORDER BY check_name;
