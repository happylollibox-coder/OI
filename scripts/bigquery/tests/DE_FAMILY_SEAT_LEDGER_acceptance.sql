-- =============================================================================================
-- DE_FAMILY_SEAT_LEDGER acceptance — every row must read PASS.
-- Run after SP_MAINTAIN_FAMILY_SEATS on the latest FACT_KEYWORD_STATE snapshot:
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Spec: architecture/FAMILY_SEAT_REGISTER.md.
--
-- Checks:
--   A1  One open row per occupant: every ladder occupant (REPRICE / FLOOR_PROBATION / LOSER /
--       REVIVED_SETTLING / PENDING_SETTLE in a HARVEST family, not brand defense) holds exactly
--       one open row.
--   A2  No open row without an occupant: the ledger never keeps a seat for a keyword that left —
--       an open row's keyword is a ladder occupant today or a probe (TRIAL, on the engine's probe
--       list T_LIFT_PROBES or at the ladder's floor).
--   A3  One keyword per number: among OPEN rows, (family, seat_no) is unique.
--   A4  Numbers start at 1 and are never NULL or negative.
--   A5  No launch-family row, ever (open or closed): only HARVEST-book families are seated.
--   A6  Every closed row carries one of the six reasons; every open row carries none.
--   A7  Probe rows are TRIAL keywords: an open 'probe' seat's keyword reads TRIAL on the ladder.
--   A8  Key uniqueness: (family, campaign_id, keyword_id, opened_on) appears once.
--   A9  Idempotence evidence is external (two runs, identical fingerprint — see the SOP); here we
--       assert the necessary condition that no keyword holds two open rows anywhere.
--   A10 No brand-defense keyword holds an open seat (defense is never judged on profit).
--   A11 Every open probe seat is at an entry or park bid: on T_LIFT_PROBES, or at_floor on the
--       ladder — a TRIAL keyword at neither is waiting (80% side) and must not be seated.
-- =============================================================================================
WITH
run_day AS (SELECT MAX(snapshot_date) AS d FROM `onyga-482313.OI.FACT_KEYWORD_STATE`),
working AS (SELECT family FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'HARVEST'),
probes AS (SELECT DISTINCT CAST(keyword_id AS STRING) AS kid FROM `onyga-482313.OI.T_LIFT_PROBES`),
ladder_occ AS (
  SELECT s.family, s.campaign_id, s.keyword_id
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
  JOIN working w ON w.family = s.family
  CROSS JOIN run_day
  WHERE s.snapshot_date = run_day.d
    AND NOT COALESCE(s.is_brand_defense, FALSE)
    AND s.state IN ('REPRICE', 'FLOOR_PROBATION', 'LOSER', 'REVIVED_SETTLING', 'PENDING_SETTLE')),
ledger AS (SELECT * FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`),
open_rows AS (SELECT * FROM ledger WHERE closed_on IS NULL),
today AS (SELECT s.family, s.campaign_id, s.keyword_id, s.state,
                 COALESCE(s.is_brand_defense, FALSE) AS is_brand_defense,
                 COALESCE(s.at_floor, FALSE) AS at_floor,
                 p.kid IS NOT NULL AS engine_probe
          FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s CROSS JOIN run_day
          LEFT JOIN probes p ON p.kid = s.keyword_id
          WHERE s.snapshot_date = run_day.d),
checks AS (
  SELECT 'A01 every ladder occupant has exactly one open row' AS check_name,
         (SELECT COUNT(*) FROM ladder_occ o
          WHERE (SELECT COUNT(*) FROM open_rows r
                 WHERE r.family = o.family AND r.campaign_id = o.campaign_id AND r.keyword_id = o.keyword_id) != 1) AS violations
  UNION ALL
  SELECT 'A02 no open row whose keyword is not an occupant today',
         (SELECT COUNT(*) FROM open_rows r
          LEFT JOIN today t ON t.campaign_id = r.campaign_id AND t.keyword_id = r.keyword_id AND t.family = r.family
          WHERE t.campaign_id IS NULL
             OR t.is_brand_defense
             OR NOT (t.state IN ('REPRICE', 'FLOOR_PROBATION', 'LOSER', 'REVIVED_SETTLING', 'PENDING_SETTLE')
                     OR (t.state = 'TRIAL' AND (t.engine_probe OR t.at_floor))))
  UNION ALL
  SELECT 'A03 one keyword per open seat number within a family',
         (SELECT COUNT(*) FROM (SELECT family, seat_no FROM open_rows GROUP BY 1, 2 HAVING COUNT(*) > 1))
  UNION ALL
  SELECT 'A04 seat numbers are positive integers',
         (SELECT COUNT(*) FROM ledger WHERE seat_no IS NULL OR seat_no < 1)
  UNION ALL
  SELECT 'A05 no launch-family row (HARVEST book only)',
         (SELECT COUNT(*) FROM ledger l LEFT JOIN working w ON w.family = l.family WHERE w.family IS NULL)
  UNION ALL
  SELECT 'A06 closed rows carry one of six reasons; open rows carry none',
         (SELECT COUNT(*) FROM ledger
          WHERE (closed_on IS NOT NULL AND closed_reason NOT IN
                   ('TO_GOOD_SIDE', 'TO_WAITING', 'KILLED', 'PAUSED', 'LEFT_FAMILY', 'DEFENSE_EXEMPT'))
             OR (closed_on IS NULL AND closed_reason IS NOT NULL))
  UNION ALL
  SELECT 'A07 open probe seats hold TRIAL keywords',
         (SELECT COUNT(*) FROM open_rows r
          JOIN today t ON t.campaign_id = r.campaign_id AND t.keyword_id = r.keyword_id
          WHERE r.occupant_kind_at_open = 'probe' AND t.state != 'TRIAL')
  UNION ALL
  SELECT 'A08 occupancy key is unique',
         (SELECT COUNT(*) FROM (SELECT family, campaign_id, keyword_id, opened_on FROM ledger GROUP BY 1, 2, 3, 4 HAVING COUNT(*) > 1))
  UNION ALL
  SELECT 'A09 no keyword holds two open rows anywhere',
         (SELECT COUNT(*) FROM (SELECT campaign_id, keyword_id FROM open_rows GROUP BY 1, 2 HAVING COUNT(*) > 1))
  UNION ALL
  SELECT 'A10 no brand-defense keyword holds an open seat',
         (SELECT COUNT(*) FROM open_rows r
          JOIN today t ON t.campaign_id = r.campaign_id AND t.keyword_id = r.keyword_id
          WHERE t.is_brand_defense)
  UNION ALL
  SELECT 'A11 every open probe seat is at an entry (engine probe) or park (floor) bid',
         (SELECT COUNT(*) FROM open_rows r
          JOIN today t ON t.campaign_id = r.campaign_id AND t.keyword_id = r.keyword_id
          WHERE t.state = 'TRIAL' AND NOT (t.engine_probe OR t.at_floor))
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM checks
ORDER BY check_name;
