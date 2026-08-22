-- =============================================================================================
-- DE_FAMILY_SEAT_LEDGER drift acceptance — what a NEW snapshot must not break.
--
-- WHY THIS FILE EXISTS. The A-suite (DE_FAMILY_SEAT_LEDGER_acceptance.sql) judges the ledger
-- against ONE snapshot: it cannot see whether a seat number survived the night, because the
-- number is a stored column and nothing in the live tables remembers what it was yesterday.
-- On the live ledger the closure checks (A06, A15) and the reuse of a freed number are also
-- VACUOUS while no row has ever closed. This file is the missing half: it compares a ledger
-- AFTER a pass against the ledger BEFORE it, and it is the file to run whenever the question is
-- "did last night's pass keep the numbers".
--
-- HOW TO RUN IT (the TMP_ recipe — house rule: synthetic rows only on TMP_ copies, never in a
-- production table; drop the copies afterwards):
--   1. TMP_FSR_STATE  = FACT_KEYWORD_STATE with snapshot_date advanced one day (plus whatever
--                       departures and arrivals the case under test needs).
--   2. TMP_FSR_LEDGER = a copy of DE_FAMILY_SEAT_LEDGER (this is the BEFORE image; the live
--                       table stays the BEFORE reference the checks below read).
--   3. TMP_SP_FSR_SEATS = SP_MAINTAIN_FAMILY_SEATS with the two table names swapped for the
--                       TMP_ pair, then CALL it.
--   4. Run this file. Every row must read PASS.
--   5. DROP the TMP_ objects.
-- After a REAL pass the same checks run with `before` pointed at an archive of the ledger; there
-- is no archive today (a Task 5 health-check item), which is why the TMP_ pair is the harness.
--
-- Checks:
--   D01 (a) STABILITY — every keyword that is seated in BOTH images kept its seat number. A
--       continuing occupant's number is never touched, whatever its kind became.
--   D02 (b) PLAIN WORDS — every closed row carries closed_reason_text, and the text is exactly
--       the sentence the SOP maps to its code (for STATE_CHANGED: the mapped prefix, the state
--       in plain words, and 'The seat is free.').
--   D03 (b) CODE AND DATE — every closed row carries one of the mapped codes and is closed on
--       the snapshot date, never the wall clock.
--   D04 (b) THE INJECTED DEPARTURES closed with the code the case expects. Edit the `expected`
--       CTE to the keys the run under test moved; an empty list makes this check vacuous, which
--       is honest — it then asserts nothing rather than pretending to.
--   D05 (b) R-h — every parked keyword whose re-verdict appointment has passed closed
--       PARK_LAPSED. This is the closure a plain date advance produces on its own.
--   D06 (c) REUSE — admissions took the LOWEST free numbers: in every family, no free number
--       sits below a number admitted on this run.
--   D07 (c) one keyword per open seat number within a family; numbers >= 1.
--   D08 (c) NO OVERWRITE — no row admitted on this run took a number that a still-seated
--       keyword of the same family holds.
-- =============================================================================================
WITH
run_day AS (SELECT MAX(snapshot_date) AS d FROM `onyga-482313.OI.TMP_FSR_STATE`),
before AS (SELECT family, campaign_id, keyword_id, seat_no
           FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` WHERE closed_on IS NULL),
after_open AS (SELECT family, campaign_id, keyword_id, seat_no, opened_on
               FROM `onyga-482313.OI.TMP_FSR_LEDGER` WHERE closed_on IS NULL),
after_closed AS (SELECT * FROM `onyga-482313.OI.TMP_FSR_LEDGER` WHERE closed_on IS NOT NULL),
-- the sentences the SOP and SP_MAINTAIN_FAMILY_SEATS both carry, verbatim
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
  SELECT 'D01 (a) every continuing occupant kept its seat number' AS check_name,
         (SELECT COUNT(*) FROM before b JOIN after_open a USING (family, campaign_id, keyword_id)
          WHERE a.seat_no != b.seat_no) AS violations
  UNION ALL SELECT 'D02 (b) every closed row carries the SOP sentence mapped to its code',
         (SELECT COUNT(*) FROM after_closed c LEFT JOIN sop s ON s.code = c.closed_reason
          WHERE c.closed_reason_text IS NULL
             OR (c.closed_reason != 'STATE_CHANGED' AND c.closed_reason_text IS DISTINCT FROM s.txt)
             OR (c.closed_reason = 'STATE_CHANGED'
                 AND NOT (c.closed_reason_text LIKE 'The keyword left the seat set — it now reads %'
                          AND c.closed_reason_text LIKE '%. The seat is free.')))
  UNION ALL SELECT 'D03 (b) every closed row carries a mapped reason code and closed_on = the snapshot date',
         (SELECT COUNT(*) FROM after_closed c, run_day
          WHERE c.closed_reason NOT IN ('KILLED','PAUSED','PARK_LAPSED','LEFT_FAMILY','DEFENSE_EXEMPT','TO_GOOD_SIDE','TO_WAITING','STATE_CHANGED')
             OR c.closed_on != run_day.d)
  UNION ALL SELECT 'D04 (b) the injected departures closed with the expected code',
         (SELECT COUNT(*) FROM expected e
          LEFT JOIN after_closed c ON c.campaign_id = e.cid AND c.keyword_id = e.kid
          WHERE c.closed_reason IS DISTINCT FROM e.code)
  UNION ALL SELECT 'D05 (b) R-h: every parked seat past its appointment closed PARK_LAPSED',
         (SELECT COUNT(*) FROM before b
          JOIN `onyga-482313.OI.TMP_FSR_STATE` s
            ON s.campaign_id = b.campaign_id AND s.keyword_id = b.keyword_id
          LEFT JOIN after_closed c
            ON c.campaign_id = b.campaign_id AND c.keyword_id = b.keyword_id, run_day
          WHERE s.state = 'PARKED' AND s.next_check_date < run_day.d
            AND c.closed_reason IS DISTINCT FROM 'PARK_LAPSED')
  UNION ALL SELECT 'D06 (c) admissions took the lowest free numbers (no free number below any admitted one)',
         (SELECT COUNT(*) FROM fam_admits a JOIN fam_free f USING (family) WHERE f.min_free < a.max_admit)
  UNION ALL SELECT 'D07 (c) one keyword per open seat number within a family; numbers >= 1',
         (SELECT COUNT(*) FROM (SELECT family, seat_no FROM after_open GROUP BY 1, 2 HAVING COUNT(*) > 1))
         + (SELECT COUNTIF(seat_no IS NULL OR seat_no < 1) FROM after_open)
  UNION ALL SELECT 'D08 (c) no admission took a number a still-seated keyword of the family holds',
         (SELECT COUNT(*) FROM after_open a, run_day WHERE a.opened_on = run_day.d
            AND EXISTS (SELECT 1 FROM before b
                        WHERE b.family = a.family AND b.seat_no = a.seat_no
                          AND NOT (b.campaign_id = a.campaign_id AND b.keyword_id = a.keyword_id)
                          AND EXISTS (SELECT 1 FROM after_open z
                                      WHERE z.family = b.family AND z.campaign_id = b.campaign_id
                                        AND z.keyword_id = b.keyword_id)))
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result FROM checks ORDER BY check_name;
