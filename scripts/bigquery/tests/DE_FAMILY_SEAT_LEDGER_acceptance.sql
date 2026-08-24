-- =============================================================================================
-- DE_FAMILY_SEAT_LEDGER acceptance — every row must read PASS.
-- Run after SP_MAINTAIN_FAMILY_SEATS on the latest FACT_KEYWORD_STATE snapshot and the latest
-- FACT_PLAN_NEXT_WEEK partitions:
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^--' FILE)"
-- Spec: architecture/FAMILY_SEAT_REGISTER.md (ruling R-o), v27.139 (2026-08-24).
--
-- v27.139 REWRITE. The occupant set moved from FACT_KEYWORD_STATE alone to FACT_PLAN_NEXT_WEEK
-- plan='B''s own SEATED keywords (seat_no IS NOT NULL) at the most recent as_of, joined to
-- plan='A' on (family, campaign_id, keyword_id) for the agreement_tier. Every check below re-reads
-- this truth from the SAME plan partitions SP_MAINTAIN_FAMILY_SEATS itself read (MAX(as_of) at the
-- time the file runs) — a file run any later than the procedure, after a NEW plan partition has
-- landed, will legitimately show A01/A02-style drift until the next SP run catches up; that is not
-- a defect in either object, it is the one-pass lag the procedure's own header documents.
--
-- Checks:
--   A01 One open row per plan-B-seated keyword: every (family, campaign_id, keyword_id) with
--       seat_no IS NOT NULL on the latest plan='B' partition holds exactly one open ledger row.
--   A02 No open row without a reason: every open row's key is EITHER in today's plan-B seated set,
--       OR correctly HELD (held_reason = 'HELD_DISPUTED', and plan A genuinely still calls it
--       not-good while the key is absent from the seated set — see A18).
--   A03 One keyword per number: among OPEN rows, (family, seat_no) is unique.
--   A04 Numbers start at 1 and are never NULL or negative.
--   A05 No launch-family row, ever (open or closed): only HARVEST-book families are seated.
--   A06 Every closed row carries one of the mapped reasons; every open row carries none.
--   A07 occupant_kind_at_open is one of the known values (repair | probation | failed | settling |
--       probe | stalled probe | parked — awaiting re-verdict | parked | disputed) — the domain
--       check for the new 'disputed' value (v27.139): never an overload of an existing code.
--   A08 Key uniqueness: (family, campaign_id, keyword_id, opened_on) appears once.
--   A09 No keyword holds two open rows anywhere.
--   A10 SAFETY CHECK, not a filter (v27.139): no open seat's keyword is brand defense by the
--       three-way test (ladder flag, campaign name, DIM_BRAND_PHRASES) — the ledger no longer
--       re-derives this filter itself (it would break exact reconciliation with the plan's own
--       seated set), so this is a standing measurement of whether the plan's own (narrower) filter
--       ever lets one through. Zero today; a violation here is a signal to fix the ladder's
--       is_brand_defense flag or V_PLAN_WINDOW_JUDGMENT, never to patch it in this procedure.
--   A11 Memory: every open row carries last_observed_kind and last_observed_state.
--   A12 Plain words: every closed row carries closed_reason_text mapped to its code; every open
--       row carries none.
--   A13 held_reason / held_reason_text move together: both NULL, or both carrying the mapped
--       sentence for the code — never one without the other.
--   A14 held_reason domain: only NULL or 'HELD_DISPUTED' — the new value is never an overload of
--       closed_reason and never appears anywhere else.
--   A15 agreement_tier is published on every OPEN row (CONFIRMED or DISPUTED, never NULL).
--   A16 CONFIRMED-only closure (P-4/P-5 spirit): every row closed ON TODAY's run reads
--       agreement_tier = 'CONFIRMED' at close — a DISPUTED occupant is never closed, only held.
--   A17 Admission order: within one family's admissions opened on today's run, no DISPUTED
--       candidate holds a LOWER seat number than a CONFIRMED candidate admitted in the same run.
--   A18 HELD_DISPUTED correctness: every row carrying held_reason = 'HELD_DISPUTED' is genuinely
--       disputed — its key is absent from today's plan-B seated set AND plan A's side for that key
--       is still NOT_GOOD.
--   A19 No held row is also closed, and no closed row also carries a held_reason (the two states
--       are mutually exclusive by construction).
-- =============================================================================================
WITH
mx AS (SELECT MAX(as_of) AS d FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE plan = 'B'),
run_day AS (SELECT MAX(snapshot_date) AS d FROM `onyga-482313.OI.FACT_KEYWORD_STATE`),
working AS (SELECT family FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'HARVEST'),
plan_b AS (SELECT p.family, p.campaign_id, p.keyword_id, p.ladder_state, p.rank_score
           FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p CROSS JOIN mx
           WHERE p.plan = 'B' AND p.as_of = mx.d AND p.seat_no IS NOT NULL),
plan_a AS (SELECT p.family, p.campaign_id, p.keyword_id, p.side AS side_a
           FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p CROSS JOIN mx
           WHERE p.plan = 'A' AND p.as_of = mx.d),
occ AS (
  SELECT b.family, b.campaign_id, b.keyword_id, b.ladder_state, b.rank_score,
         IF(COALESCE(a.side_a, 'GOOD') = 'NOT_GOOD', 'CONFIRMED', 'DISPUTED') AS agreement_tier
  FROM plan_b b LEFT JOIN plan_a a
    ON a.family = b.family AND a.campaign_id = b.campaign_id AND a.keyword_id = b.keyword_id),
brand_hit AS (
  SELECT DISTINCT s.campaign_id, s.keyword_id FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
  JOIN (SELECT DISTINCT CONCAT(r'\b', REGEXP_REPLACE(TRIM(LOWER(phrase), ' |,'), r'([.*+?^${}()|\[\]\\])', r'\\\1'), r'\b') AS rx
        FROM `onyga-482313.OI.DIM_BRAND_PHRASES` WHERE phrase_type = 'BRAND' AND TRIM(LOWER(phrase), ' |,') != '') b
    ON REGEXP_CONTAINS(LOWER(s.target_text), b.rx)),
today AS (
  SELECT s.campaign_id, s.keyword_id,
         (COALESCE(s.is_brand_defense, FALSE)
          OR REGEXP_CONTAINS(UPPER(COALESCE(s.campaign_name, '')), r'BRAND DEFENSE')
          OR bh.keyword_id IS NOT NULL) AS is_brand_defense
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s CROSS JOIN run_day
  LEFT JOIN brand_hit bh ON bh.campaign_id = s.campaign_id AND bh.keyword_id = s.keyword_id
  WHERE s.snapshot_date = run_day.d),
ledger AS (SELECT * FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`),
open_rows AS (SELECT * FROM ledger WHERE closed_on IS NULL),
reason_text AS (
  SELECT 'KILLED' AS code, 'The keyword is gone from the snapshot after its last verdict was failed or dead, or the ladder now reads dead: the book paused a failed keyword. The seat is free.' AS text UNION ALL
  SELECT 'PAUSED', 'The keyword is gone from the snapshot, or the ladder now reads parked, without a failed verdict first. The seat is free.' UNION ALL
  SELECT 'PARK_LAPSED', 'The keyword reads parked on the ladder but is no longer a parked seat: it has no spend on the basis window, or its re-verdict appointment has passed. A parked keyword that still spends past its appointment is a leak (pause row). The seat is free.' UNION ALL
  SELECT 'LEFT_FAMILY', 'The keyword is still tracked but now belongs to another family, or its family left the working (HARVEST) book. The seat is free.' UNION ALL
  SELECT 'DEFENSE_EXEMPT', 'The keyword is now brand defense. Defense is never judged on profit, so it is never seated. The seat is free.' UNION ALL
  SELECT 'TO_GOOD_SIDE', 'The keyword is now winning or at its bar: it moved to the 80% side. The seat is free.' UNION ALL
  SELECT 'TO_WAITING', 'The keyword is still a trial but is no longer bought at an entry or park bid and is not a stalled probe: it is back to waiting for clicks on the 80% side, no verdict yet. The seat is free.' UNION ALL
  SELECT 'STATE_CHANGED', 'The keyword left the seat set — it now reads '),
held_text AS (
  SELECT 'HELD_DISPUTED' AS code,
         'Held — the two judges disagree about this keyword: the 90-day ladder record still calls it not-good but this week\'s window no longer seats it (or never judged it a candidate). It keeps its seat until the next window\'s plan resolves the disagreement — nobody cuts a keyword on one judge\'s word alone.' AS text),
checks AS (
  SELECT 'A01 every plan-B-seated keyword has exactly one open row' AS check_name,
         (SELECT COUNT(*) FROM occ o
          WHERE (SELECT COUNT(*) FROM open_rows r
                 WHERE r.family = o.family AND r.campaign_id = o.campaign_id AND r.keyword_id = o.keyword_id) != 1) AS violations
  UNION ALL
  SELECT 'A02 every open row is a plan-B occupant or a genuinely HELD_DISPUTED row',
         (SELECT COUNT(*) FROM open_rows r
          LEFT JOIN occ o ON o.family = r.family AND o.campaign_id = r.campaign_id AND o.keyword_id = r.keyword_id
          WHERE o.campaign_id IS NULL AND r.held_reason IS DISTINCT FROM 'HELD_DISPUTED')
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
  SELECT 'A06 closed rows carry one of the mapped reasons; open rows carry none',
         (SELECT COUNT(*) FROM ledger
          WHERE (closed_on IS NOT NULL AND closed_reason NOT IN
                   ('TO_GOOD_SIDE', 'TO_WAITING', 'KILLED', 'PAUSED', 'PARK_LAPSED', 'LEFT_FAMILY', 'DEFENSE_EXEMPT', 'STATE_CHANGED'))
             OR (closed_on IS NULL AND closed_reason IS NOT NULL))
  UNION ALL
  SELECT 'A07 occupant_kind_at_open is one of the known values',
         (SELECT COUNT(*) FROM ledger
          WHERE occupant_kind_at_open NOT IN
            ('repair', 'probation', 'failed', 'settling', 'probe', 'stalled probe',
             'parked — awaiting re-verdict', 'parked', 'disputed'))
  UNION ALL
  SELECT 'A08 occupancy key is unique',
         (SELECT COUNT(*) FROM (SELECT family, campaign_id, keyword_id, opened_on FROM ledger GROUP BY 1, 2, 3, 4 HAVING COUNT(*) > 1))
  UNION ALL
  SELECT 'A09 no keyword holds two open rows anywhere',
         (SELECT COUNT(*) FROM (SELECT campaign_id, keyword_id FROM open_rows GROUP BY 1, 2 HAVING COUNT(*) > 1))
  UNION ALL
  SELECT 'A10 SAFETY CHECK: no open seat is brand defense by the three-way test',
         (SELECT COUNT(*) FROM open_rows r
          JOIN today t ON t.campaign_id = r.campaign_id AND t.keyword_id = r.keyword_id
          WHERE t.is_brand_defense)
  UNION ALL
  SELECT 'A11 every open row remembers its last observed kind and state',
         (SELECT COUNT(*) FROM open_rows WHERE last_observed_kind IS NULL OR last_observed_state IS NULL)
  UNION ALL
  SELECT 'A12 every closed row carries the plain sentence mapped to its reason; open rows carry none',
         (SELECT COUNT(*) FROM ledger l LEFT JOIN reason_text x ON x.code = l.closed_reason
          WHERE (l.closed_on IS NOT NULL AND (l.closed_reason_text IS NULL
                                              OR IF(l.closed_reason = 'STATE_CHANGED',
                                                    NOT STARTS_WITH(l.closed_reason_text, x.text) OR NOT ENDS_WITH(l.closed_reason_text, '. The seat is free.'),
                                                    l.closed_reason_text != x.text)))
             OR (l.closed_on IS NULL AND l.closed_reason_text IS NOT NULL))
  UNION ALL
  SELECT 'A13 held_reason and held_reason_text move together and match the mapped sentence',
         (SELECT COUNT(*) FROM ledger l LEFT JOIN held_text x ON x.code = l.held_reason
          WHERE (l.held_reason IS NULL) != (l.held_reason_text IS NULL)
             OR (l.held_reason IS NOT NULL AND l.held_reason_text != x.text))
  UNION ALL
  SELECT 'A14 held_reason domain is NULL or HELD_DISPUTED only',
         (SELECT COUNT(*) FROM ledger WHERE held_reason IS NOT NULL AND held_reason != 'HELD_DISPUTED')
  UNION ALL
  SELECT 'A15 agreement_tier is published (CONFIRMED or DISPUTED) on every open row',
         (SELECT COUNT(*) FROM open_rows WHERE COALESCE(agreement_tier, '') NOT IN ('CONFIRMED', 'DISPUTED'))
  UNION ALL
  -- scoped to agreement_tier IS NOT NULL: a row closed on run_day's calendar date by a PRIOR pass
  -- of the OLD (pre-v27.139) procedure, before this column existed, legitimately carries a NULL
  -- tier forever (no retroactive backfill — the column describes standing going forward). The
  -- precise before/after version of this check (every row THIS RUN closed reads CONFIRMED) lives
  -- in the drift suite (D-suite), which can actually tell old closures from new ones.
  SELECT 'A16 CONFIRMED-only closure: every row closed today with a tier reads agreement_tier = CONFIRMED',
         (SELECT COUNT(*) FROM ledger, run_day
          WHERE closed_on = run_day.d AND agreement_tier IS NOT NULL AND agreement_tier != 'CONFIRMED')
  UNION ALL
  SELECT 'A17 admission order: no DISPUTED candidate seated lower than a CONFIRMED one co-admitted today',
         (SELECT COUNT(*) FROM open_rows d
          JOIN open_rows c
            ON c.family = d.family AND c.opened_on = d.opened_on
          , run_day
          WHERE d.opened_on = run_day.d AND d.agreement_tier = 'DISPUTED'
            AND c.agreement_tier = 'CONFIRMED' AND c.seat_no > d.seat_no)
  UNION ALL
  SELECT 'A18 every HELD_DISPUTED row is genuinely disputed (absent from plan B seated set, plan A still NOT_GOOD)',
         (SELECT COUNT(*) FROM open_rows r
          LEFT JOIN occ o ON o.family = r.family AND o.campaign_id = r.campaign_id AND o.keyword_id = r.keyword_id
          LEFT JOIN plan_a a ON a.family = r.family AND a.campaign_id = r.campaign_id AND a.keyword_id = r.keyword_id
          WHERE r.held_reason = 'HELD_DISPUTED'
            AND (o.campaign_id IS NOT NULL OR COALESCE(a.side_a, 'GOOD') != 'NOT_GOOD'))
  UNION ALL
  SELECT 'A19 held and closed are mutually exclusive',
         (SELECT COUNT(*) FROM ledger WHERE held_reason IS NOT NULL AND closed_on IS NOT NULL)
)
SELECT check_name, violations, IF(violations = 0, 'PASS', 'FAIL') AS result
FROM checks
ORDER BY check_name;
