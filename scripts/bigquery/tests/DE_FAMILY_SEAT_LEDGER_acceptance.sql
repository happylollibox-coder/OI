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
--       an open row's keyword is a ladder occupant today, a probe (ruling R-a) or a stalled probe
--       (ruling R-b).
--   A3  One keyword per number: among OPEN rows, (family, seat_no) is unique.
--   A4  Numbers start at 1 and are never NULL or negative.
--   A5  No launch-family row, ever (open or closed): only HARVEST-book families are seated.
--   A6  Every closed row carries one of the six reasons; every open row carries none.
--   A7  Probe rows are TRIAL keywords: an open seat opened as 'probe' or 'stalled probe' reads
--       TRIAL on the ladder.
--   A8  Key uniqueness: (family, campaign_id, keyword_id, opened_on) appears once.
--   A9  Idempotence evidence is external (two runs, identical fingerprint — see the SOP); here we
--       assert the necessary condition that no keyword holds two open rows anywhere.
--   A10 No brand-defense keyword holds an open seat (defense is never judged on profit).
--   A11 Ruling R-a, negative half: every open TRIAL seat is an engine-listed probe (spend or not),
--       OR at the park bid WITH spend in the basis window, OR a stalled probe. A TRIAL keyword at
--       the park bid with NO spend, or at neither bid and not stalled, is waiting and must not be
--       seated.
--   A12 Ruling R-a, positive half: every engine-listed TRIAL keyword in a working family (spend or
--       no spend) and every at-floor TRIAL keyword with spend holds exactly one open row.
--   A13 Ruling R-b: every stalled probe — TRIAL, not engine-listed, not at the floor, still holding
--       the raised bid of its latest applied INCREASE_BID, that raise older than the engine's probe
--       window (k_probe_window_days) with fewer than the verdict's clicks (k_verdict_clicks) since —
--       holds exactly one open row, and the row's last_observed_kind reads 'stalled probe'.
--   A14 Memory: every open row carries last_observed_kind and last_observed_state, and
--       last_observed_state equals the keyword's ladder state today (the ledger is the only memory
--       of yesterday — FACT_KEYWORD_STATE holds one snapshot).
--   A15 Plain words: every closed row carries closed_reason_text, and the text is the sentence the
--       SOP maps to its code; every open row carries none.
-- =============================================================================================
WITH
k AS (SELECT 7 AS basis_days, 14 AS probe_window_days, 20 AS verdict_clicks),  -- mirrors SP_MAINTAIN_FAMILY_SEATS / V_KEYWORD_LIFT probing
run_day AS (SELECT MAX(snapshot_date) AS d FROM `onyga-482313.OI.FACT_KEYWORD_STATE`),
wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
working AS (SELECT family FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'HARVEST'),
probes AS (SELECT DISTINCT CAST(keyword_id AS STRING) AS kid FROM `onyga-482313.OI.T_LIFT_PROBES`),
lastchg AS (
  SELECT campaign_id, keyword_id, action, DATE(applied_at, 'America/Los_Angeles') AS chg_date, new_bid
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
  WHERE action IN ('INCREASE_BID', 'REDUCE_BID') AND new_bid IS NOT NULL
    AND keyword_id IS NOT NULL AND keyword_id != ''
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id ORDER BY applied_at DESC, change_id DESC) = 1),
sp AS (
  SELECT CAST(f.campaign_id AS STRING) AS cid, CAST(f.keyword_id AS STRING) AS kid,
         SUM(IF(f.date BETWEEN DATE_SUB(wm.d, INTERVAL k.basis_days DAY) AND DATE_SUB(wm.d, INTERVAL 1 DAY), f.Ads_cost, 0)) AS spend_basis,
         SUM(IF(lc.chg_date IS NOT NULL AND f.date > lc.chg_date, f.Ads_clicks, 0)) AS clicks_since_raise
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f CROSS JOIN wm CROSS JOIN k
  LEFT JOIN lastchg lc ON lc.campaign_id = CAST(f.campaign_id AS STRING) AND lc.keyword_id = CAST(f.keyword_id AS STRING)
  WHERE f.date > DATE_SUB(wm.d, INTERVAL 120 DAY)
  GROUP BY 1, 2),
today AS (
  SELECT s.family, s.campaign_id, s.keyword_id, s.state,
         COALESCE(s.is_brand_defense, FALSE) AS is_brand_defense,
         COALESCE(s.at_floor, FALSE) AS at_floor,
         p.kid IS NOT NULL AS engine_probe,
         COALESCE(sp.spend_basis, 0) > 0 AS has_spend,
         (p.kid IS NULL AND NOT COALESCE(s.at_floor, FALSE)
          AND lc.action = 'INCREASE_BID'
          AND ABS(s.current_bid - lc.new_bid) < 0.005
          AND lc.chg_date <= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL k.probe_window_days DAY)
          AND COALESCE(sp.clicks_since_raise, 0) < k.verdict_clicks) AS stalled,
         s.family IN (SELECT family FROM working) AS in_working
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s CROSS JOIN run_day CROSS JOIN k
  LEFT JOIN probes p ON p.kid = s.keyword_id
  LEFT JOIN sp ON sp.cid = s.campaign_id AND sp.kid = s.keyword_id
  LEFT JOIN lastchg lc ON lc.campaign_id = s.campaign_id AND lc.keyword_id = s.keyword_id
  WHERE s.snapshot_date = run_day.d),
ladder_occ AS (
  SELECT family, campaign_id, keyword_id FROM today
  WHERE in_working AND NOT is_brand_defense
    AND state IN ('REPRICE', 'FLOOR_PROBATION', 'LOSER', 'REVIVED_SETTLING', 'PENDING_SETTLE')),
probe_occ AS (
  SELECT family, campaign_id, keyword_id FROM today
  WHERE in_working AND NOT is_brand_defense AND state = 'TRIAL'
    AND (engine_probe OR (at_floor AND has_spend))),
stalled_occ AS (
  SELECT family, campaign_id, keyword_id FROM today
  WHERE in_working AND NOT is_brand_defense AND state = 'TRIAL' AND stalled),
ledger AS (SELECT * FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`),
open_rows AS (SELECT * FROM ledger WHERE closed_on IS NULL),
reason_text AS (
  SELECT 'KILLED' AS code, 'The keyword is gone from the snapshot after its last verdict was failed or dead, or the ladder now reads dead: the book paused a failed keyword. The seat is free.' AS text UNION ALL
  SELECT 'PAUSED', 'The keyword is gone from the snapshot, or the ladder now reads parked, without a failed verdict first. The seat is free.' UNION ALL
  SELECT 'LEFT_FAMILY', 'The keyword is still tracked but now belongs to another family, or its family left the working (HARVEST) book. The seat is free.' UNION ALL
  SELECT 'DEFENSE_EXEMPT', 'The keyword is now brand defense. Defense is never judged on profit, so it is never seated. The seat is free.' UNION ALL
  SELECT 'TO_GOOD_SIDE', 'The keyword is now winning or at its bar: it moved to the 80% side. The seat is free.' UNION ALL
  SELECT 'TO_WAITING', 'The keyword is still a trial but is no longer bought at an entry or park bid and is not a stalled probe: it is back to waiting for clicks on the 80% side, no verdict yet. The seat is free.'),
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
             OR NOT t.in_working
             OR t.is_brand_defense
             OR NOT (t.state IN ('REPRICE', 'FLOOR_PROBATION', 'LOSER', 'REVIVED_SETTLING', 'PENDING_SETTLE')
                     OR (t.state = 'TRIAL' AND (t.engine_probe OR (t.at_floor AND t.has_spend) OR t.stalled))))
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
  SELECT 'A07 open probe and stalled-probe seats hold TRIAL keywords',
         (SELECT COUNT(*) FROM open_rows r
          JOIN today t ON t.campaign_id = r.campaign_id AND t.keyword_id = r.keyword_id
          WHERE r.occupant_kind_at_open IN ('probe', 'stalled probe') AND t.state != 'TRIAL')
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
  SELECT 'A11 R-a: every open TRIAL seat is engine-listed, or at the park bid with spend, or stalled',
         (SELECT COUNT(*) FROM open_rows r
          JOIN today t ON t.campaign_id = r.campaign_id AND t.keyword_id = r.keyword_id
          WHERE t.state = 'TRIAL' AND NOT (t.engine_probe OR (t.at_floor AND t.has_spend) OR t.stalled))
  UNION ALL
  SELECT 'A12 R-a: every engine-listed TRIAL (spend or not) and every at-floor TRIAL with spend has one open row',
         (SELECT COUNT(*) FROM probe_occ o
          WHERE (SELECT COUNT(*) FROM open_rows r
                 WHERE r.family = o.family AND r.campaign_id = o.campaign_id AND r.keyword_id = o.keyword_id) != 1)
  UNION ALL
  SELECT 'A13 R-b: every stalled probe has one open row observed as stalled probe',
         (SELECT COUNT(*) FROM stalled_occ o
          WHERE (SELECT COUNT(*) FROM open_rows r
                 WHERE r.family = o.family AND r.campaign_id = o.campaign_id AND r.keyword_id = o.keyword_id
                   AND r.last_observed_kind = 'stalled probe') != 1)
  UNION ALL
  SELECT 'A14 every open row remembers its last observed kind and state, and the state matches the ladder today',
         (SELECT COUNT(*) FROM open_rows r
          LEFT JOIN today t ON t.campaign_id = r.campaign_id AND t.keyword_id = r.keyword_id AND t.family = r.family
          WHERE r.last_observed_kind IS NULL OR r.last_observed_state IS NULL
             OR r.last_observed_state IS DISTINCT FROM t.state)
  UNION ALL
  SELECT 'A15 every closed row carries the plain sentence mapped to its reason; open rows carry none',
         (SELECT COUNT(*) FROM ledger l LEFT JOIN reason_text x ON x.code = l.closed_reason
          WHERE (l.closed_on IS NOT NULL AND (l.closed_reason_text IS NULL OR l.closed_reason_text != x.text))
             OR (l.closed_on IS NULL AND l.closed_reason_text IS NOT NULL))
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM checks
ORDER BY check_name;
