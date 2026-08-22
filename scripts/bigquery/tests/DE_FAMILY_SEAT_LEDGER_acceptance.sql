-- =============================================================================================
-- ACCEPTANCE — DE_FAMILY_SEAT_LEDGER + SP_MAINTAIN_FAMILY_SEATS (family seat register, Task 1).
-- Runs against the DEPLOYED table and the latest FACT_KEYWORD_STATE snapshot in one pass. Every
-- row must read PASS. Before the table exists this query ERRORS (table not found) — that is the
-- TDD "fails first" evidence. Run:
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
--
-- WHAT EACH CHECK PROTECTS:
--   A1  One open row per occupant: every ladder occupant (REPRICE / FLOOR_PROBATION / LOSER /
--       REVIVED_SETTLING / PENDING_SETTLE) in a working family has exactly one open ledger row.
--       A seat without a number is a seat nobody can name; two rows is two numbers for one keyword.
--   A2  No open row without an occupant: the ledger never keeps a seat for a keyword that left —
--       the register would show a phantom occupant and its cost would reconcile to nothing.
--   A3  One keyword per number: among OPEN rows, (family, seat_no) is unique.
--   A4  Numbers start at 1 and are never NULL or negative.
--   A5  No launch-family row, ever (open or closed): only HARVEST-book families are seated.
--   A6  Every closed row carries one of the four reasons; every open row carries none.
--   A7  Probe rows are TRIAL keywords: an open 'probe' seat's keyword reads TRIAL on the ladder
--       (it may have stopped spending today — then A2 closes it on the next run, not this one).
--   A8  Key uniqueness: (family, campaign_id, keyword_id, opened_on) appears once.
--   A9  Idempotence evidence is external (two runs, identical fingerprint — see the SOP); here we
--       assert the necessary condition that no keyword holds two open rows anywhere.
-- =============================================================================================
WITH
run_day AS (SELECT MAX(snapshot_date) AS d FROM `onyga-482313.OI.FACT_KEYWORD_STATE`),
working AS (SELECT family FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'HARVEST'),
ladder_occ AS (
  SELECT s.family, s.campaign_id, s.keyword_id
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
  JOIN working w ON w.family = s.family
  CROSS JOIN run_day
  WHERE s.snapshot_date = run_day.d
    AND s.state IN ('REPRICE', 'FLOOR_PROBATION', 'LOSER', 'REVIVED_SETTLING', 'PENDING_SETTLE')),
ledger AS (SELECT * FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`),
open_rows AS (SELECT * FROM ledger WHERE closed_on IS NULL),
today AS (SELECT s.family, s.campaign_id, s.keyword_id, s.state
          FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s CROSS JOIN run_day WHERE s.snapshot_date = run_day.d),
checks AS (
  SELECT 'A1 every ladder occupant has exactly one open row' AS check_name,
         (SELECT COUNT(*) FROM ladder_occ o
          WHERE (SELECT COUNT(*) FROM open_rows r
                 WHERE r.family = o.family AND r.campaign_id = o.campaign_id AND r.keyword_id = o.keyword_id) != 1) AS violations
  UNION ALL
  SELECT 'A2 no open row whose keyword is not an occupant today',
         (SELECT COUNT(*) FROM open_rows r
          LEFT JOIN today t ON t.campaign_id = r.campaign_id AND t.keyword_id = r.keyword_id AND t.family = r.family
          WHERE t.campaign_id IS NULL
             OR NOT (t.state IN ('REPRICE', 'FLOOR_PROBATION', 'LOSER', 'REVIVED_SETTLING', 'PENDING_SETTLE')
                     OR (t.state = 'TRIAL' AND r.occupant_kind_at_open = 'probe')))
  UNION ALL
  SELECT 'A3 one keyword per open seat number within a family',
         (SELECT COUNT(*) FROM (SELECT family, seat_no FROM open_rows GROUP BY 1, 2 HAVING COUNT(*) > 1))
  UNION ALL
  SELECT 'A4 seat numbers are positive integers',
         (SELECT COUNT(*) FROM ledger WHERE seat_no IS NULL OR seat_no < 1)
  UNION ALL
  SELECT 'A5 no launch-family row (HARVEST book only)',
         (SELECT COUNT(*) FROM ledger l LEFT JOIN working w ON w.family = l.family WHERE w.family IS NULL)
  UNION ALL
  SELECT 'A6 closed rows carry one of four reasons; open rows carry none',
         (SELECT COUNT(*) FROM ledger
          WHERE (closed_on IS NOT NULL AND closed_reason NOT IN ('TO_GOOD_SIDE', 'KILLED', 'PAUSED', 'LEFT_FAMILY'))
             OR (closed_on IS NULL AND closed_reason IS NOT NULL))
  UNION ALL
  SELECT 'A7 open probe seats hold TRIAL keywords',
         (SELECT COUNT(*) FROM open_rows r
          JOIN today t ON t.campaign_id = r.campaign_id AND t.keyword_id = r.keyword_id
          WHERE r.occupant_kind_at_open = 'probe' AND t.state != 'TRIAL')
  UNION ALL
  SELECT 'A8 occupancy key is unique',
         (SELECT COUNT(*) FROM (SELECT family, campaign_id, keyword_id, opened_on FROM ledger GROUP BY 1, 2, 3, 4 HAVING COUNT(*) > 1))
  UNION ALL
  SELECT 'A9 no keyword holds two open rows anywhere',
         (SELECT COUNT(*) FROM (SELECT campaign_id, keyword_id FROM open_rows GROUP BY 1, 2 HAVING COUNT(*) > 1))
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM checks
ORDER BY check_name;
