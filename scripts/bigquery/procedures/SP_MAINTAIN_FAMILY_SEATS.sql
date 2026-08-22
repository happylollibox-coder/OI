-- =============================================
-- SP_MAINTAIN_FAMILY_SEATS — keeps DE_FAMILY_SEAT_LEDGER honest, once per keyword-state snapshot.
-- Spec: architecture/FAMILY_SEAT_REGISTER.md (Task 1 of the family seat register).
--
-- WHAT IT DOES, in order:
--   1. OCCUPANTS  — today's occupant set, read from FACT_KEYWORD_STATE's latest snapshot for the
--                   WORKING families only (V_BOOK_ASSIGNMENT.book = 'HARVEST'; a launch family is
--                   never seated). A keyword occupies a seat when its state is REPRICE (repair),
--                   FLOOR_PROBATION (probation), LOSER (failed), REVIVED_SETTLING or PENDING_SETTLE
--                   (settling), or when it is a TRIAL keyword the ENGINE lists as a probe
--                   (V_KEYWORD_LIFT probing / PROBE_START — the same set V_OOB_KEYWORD calls
--                   is_lift_probe) AND it spent in the basis window (the k_basis_days complete
--                   days ending at the ads watermark − 1, the register's spend basis).
--   2. CLOSE      — every OPEN ledger row whose (family, campaign, keyword) is not in today's
--                   occupant set is closed on the snapshot date with one reason:
--                     LEFT_FAMILY   the keyword is still tracked but under another family, or its
--                                   family is no longer in the HARVEST book
--                     KILLED        the ladder now reads DEAD, or a seat that held a FAILED keyword
--                                   finds the keyword gone from the snapshot (the book paused it)
--                     PAUSED        the ladder reads PARKED, or the keyword is gone from the snapshot
--                     TO_GOOD_SIDE  anything else still tracked — winning, at its bar, or waiting
--                                   with volume (the 80% side)
--   3. REOPEN     — a row closed on THIS snapshot date whose key is an occupant again is reopened
--                   (closed_on / closed_reason cleared) so a same-day flip keeps its number and
--                   the key (family, campaign, keyword, opened_on) stays unique.
--   4. ADMIT      — occupants without an open row get the LOWEST seat number not held by an open
--                   row of their family. Several admissions in one run are ordered totally
--                   (kind, spend DESC, campaign_id, keyword_id) and take the free numbers in
--                   ascending order, so the run is deterministic.
--
-- IDEMPOTENT: every write is keyed on the snapshot date and on set differences, so a second run
-- on the same snapshot finds nothing to close, reopen or admit and writes nothing. A continuing
-- occupant is never touched — its number is stable for as long as it stays seated, even if its
-- kind changes (repair → probation → failed is the ladder doing its job, not a new seat).
--
-- NOT THIS PROCEDURE'S JOB: costs, sides, the 80/20 read, moves — V_FAMILY_SEAT_REGISTER derives
-- those from the snapshots every morning. No engine reads the ledger.
-- Orchestrator: Task 20.8b, immediately after SP_SNAPSHOT_KEYWORD_STATE (20.8).
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_MAINTAIN_FAMILY_SEATS`()
OPTIONS (
  description = "Maintains DE_FAMILY_SEAT_LEDGER from the latest FACT_KEYWORD_STATE snapshot for the WORKING families (V_BOOK_ASSIGNMENT book = HARVEST; launches never seated). Occupants: REPRICE (repair), FLOOR_PROBATION (probation), LOSER (failed), REVIVED_SETTLING / PENDING_SETTLE (settling), and TRIAL keywords the engine lists as probes (V_KEYWORD_LIFT probing / PROBE_START) that spent in the basis window (7 complete days ending at the ads watermark - 1). Steps: CLOSE open rows that left the occupant set, dated on the snapshot, reason LEFT_FAMILY (tracked under another family or family left the HARVEST book) > KILLED (DEAD, or a failed seat whose keyword is gone from the snapshot) > PAUSED (PARKED or gone from the snapshot) > TO_GOOD_SIDE (still tracked: winning, at bar, waiting with volume); REOPEN a row closed on the same snapshot date whose key is an occupant again (keeps its number, keeps the key unique); ADMIT new occupants at the LOWEST seat number not held by an open row of the family, several admissions ordered totally (kind, spend DESC, campaign_id, keyword_id). Idempotent on the same snapshot; continuing occupants are never touched, so a number is stable for as long as the keyword stays seated whatever its kind becomes. Orchestrator Task 20.8b, right after SP_SNAPSHOT_KEYWORD_STATE. No engine reads the ledger. Spec: architecture/FAMILY_SEAT_REGISTER.md."
)
BEGIN
  -- Declared constant: the spend basis is the k_basis_days complete days ending at the ads
  -- watermark − 1 (the window the design was validated on). Mirrored in V_FAMILY_SEAT_REGISTER.
  DECLARE k_basis_days INT64 DEFAULT 7;
  DECLARE run_day DATE;

  SET run_day = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`);
  IF run_day IS NULL THEN
    SELECT 'SP_MAINTAIN_FAMILY_SEATS: no keyword-state snapshot — nothing to do' AS log_message;
    RETURN;
  END IF;

  -- ── 1. OCCUPANTS ──────────────────────────────────────────────────────────────────────────
  CREATE TEMP TABLE occupants AS
  WITH
  wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
         FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
  working AS (SELECT family FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'HARVEST'),
  -- the engine's own probe list — the set V_OOB_KEYWORD reads as is_lift_probe
  probes AS (SELECT DISTINCT CAST(keyword_id AS STRING) AS kid
             FROM `onyga-482313.OI.V_KEYWORD_LIFT`
             WHERE probing OR action = 'PROBE_START'),
  sp AS (SELECT CAST(f.campaign_id AS STRING) AS cid, CAST(f.keyword_id AS STRING) AS kid,
                SUM(f.Ads_cost) AS spend_basis
         FROM `onyga-482313.OI.FACT_AMAZON_ADS` f CROSS JOIN wm
         WHERE f.date BETWEEN DATE_SUB(wm.d, INTERVAL k_basis_days DAY)
                          AND DATE_SUB(wm.d, INTERVAL 1 DAY)
         GROUP BY 1, 2),
  s AS (SELECT s.family, s.campaign_id, s.keyword_id, s.state
        FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
        JOIN working w ON w.family = s.family
        WHERE s.snapshot_date = run_day)
  SELECT s.family, s.campaign_id, s.keyword_id,
         CASE s.state
           WHEN 'REPRICE'          THEN 'repair'
           WHEN 'FLOOR_PROBATION'  THEN 'probation'
           WHEN 'LOSER'            THEN 'failed'
           WHEN 'REVIVED_SETTLING' THEN 'settling'
           WHEN 'PENDING_SETTLE'   THEN 'settling'
           WHEN 'TRIAL'            THEN 'probe'
         END AS occupant_kind,
         COALESCE(sp.spend_basis, 0) AS spend_basis
  FROM s
  LEFT JOIN sp ON sp.cid = s.campaign_id AND sp.kid = s.keyword_id
  LEFT JOIN probes p ON p.kid = s.keyword_id
  WHERE s.state IN ('REPRICE', 'FLOOR_PROBATION', 'LOSER', 'REVIVED_SETTLING', 'PENDING_SETTLE')
     OR (s.state = 'TRIAL' AND p.kid IS NOT NULL AND COALESCE(sp.spend_basis, 0) > 0);

  -- ── 2. CLOSE ──────────────────────────────────────────────────────────────────────────────
  CREATE TEMP TABLE leaving AS
  WITH
  working AS (SELECT family FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'HARVEST'),
  -- where the keyword is today, any family — one row per (campaign, keyword) on the snapshot
  today AS (SELECT s.campaign_id, s.keyword_id, s.family, s.state,
                   s.family IN (SELECT family FROM working) AS in_working
            FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
            WHERE s.snapshot_date = run_day)
  SELECT l.family, l.campaign_id, l.keyword_id, l.opened_on,
         CASE
           WHEN t.campaign_id IS NULL
             THEN IF(l.occupant_kind_at_open = 'failed', 'KILLED', 'PAUSED')
           WHEN t.family IS DISTINCT FROM l.family OR NOT t.in_working THEN 'LEFT_FAMILY'
           WHEN t.state = 'DEAD'   THEN 'KILLED'
           WHEN t.state = 'PARKED' THEN 'PAUSED'
           ELSE 'TO_GOOD_SIDE'
         END AS closed_reason
  FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
  LEFT JOIN occupants o
    ON o.family = l.family AND o.campaign_id = l.campaign_id AND o.keyword_id = l.keyword_id
  LEFT JOIN today t
    ON t.campaign_id = l.campaign_id AND t.keyword_id = l.keyword_id
  WHERE l.closed_on IS NULL AND o.campaign_id IS NULL;

  UPDATE `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
  SET closed_on = run_day, closed_reason = x.closed_reason
  FROM leaving x
  WHERE l.family = x.family AND l.campaign_id = x.campaign_id AND l.keyword_id = x.keyword_id
    AND l.opened_on = x.opened_on AND l.closed_on IS NULL;

  -- ── 3. REOPEN (same-day flip keeps its number and keeps the key unique) ──────────────────
  UPDATE `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
  SET closed_on = NULL, closed_reason = NULL
  FROM occupants o
  WHERE l.family = o.family AND l.campaign_id = o.campaign_id AND l.keyword_id = o.keyword_id
    AND l.closed_on = run_day
    AND NOT EXISTS (SELECT 1 FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` z
                    WHERE z.family = l.family AND z.campaign_id = l.campaign_id
                      AND z.keyword_id = l.keyword_id AND z.closed_on IS NULL);

  -- ── 4. ADMIT at the lowest free number ────────────────────────────────────────────────────
  INSERT INTO `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`
    (family, campaign_id, keyword_id, seat_no, opened_on, closed_on, closed_reason, occupant_kind_at_open)
  WITH
  open_seats AS (SELECT family, seat_no FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` WHERE closed_on IS NULL),
  open_seats_keys AS (SELECT family, campaign_id, keyword_id
                      FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` WHERE closed_on IS NULL),
  admits AS (
    SELECT o.*
    FROM occupants o
    LEFT JOIN open_seats_keys l
      ON l.family = o.family AND l.campaign_id = o.campaign_id AND l.keyword_id = o.keyword_id
    WHERE l.campaign_id IS NULL),
  need AS (
    SELECT n.family, COUNT(*) AS n_new,
           (SELECT COUNT(*) FROM open_seats s WHERE s.family = n.family) AS n_open
    FROM admits n GROUP BY n.family),
  -- among 1..(open + new) at least n_new numbers are free (pigeonhole); take them in order
  free AS (
    SELECT c.family, cand AS seat_no,
           ROW_NUMBER() OVER (PARTITION BY c.family ORDER BY cand) AS rk
    FROM need c, UNNEST(GENERATE_ARRAY(1, c.n_open + c.n_new)) AS cand
    LEFT JOIN open_seats s ON s.family = c.family AND s.seat_no = cand
    WHERE s.seat_no IS NULL),
  ranked AS (
    SELECT n.*,
           ROW_NUMBER() OVER (PARTITION BY n.family
             ORDER BY CASE n.occupant_kind WHEN 'repair' THEN 1 WHEN 'probation' THEN 2
                                           WHEN 'failed' THEN 3 WHEN 'settling' THEN 4 ELSE 5 END,
                      n.spend_basis DESC, n.campaign_id, n.keyword_id) AS rk
    FROM admits n)
  SELECT r.family, r.campaign_id, r.keyword_id, f.seat_no, run_day,
         CAST(NULL AS DATE), CAST(NULL AS STRING), r.occupant_kind
  FROM ranked r
  JOIN free f ON f.family = r.family AND f.rk = r.rk;

  SELECT FORMAT('SP_MAINTAIN_FAMILY_SEATS: snapshot %s — %d occupants, %d seats closed',
                CAST(run_day AS STRING),
                (SELECT COUNT(*) FROM occupants),
                (SELECT COUNT(*) FROM leaving)) AS log_message;
END;
