-- =============================================
-- SP_MAINTAIN_FAMILY_SEATS — keeps DE_FAMILY_SEAT_LEDGER honest, once per keyword-state snapshot.
-- Spec: architecture/FAMILY_SEAT_REGISTER.md (Task 1 of the family seat register; rulings R-a and
-- R-b of 2026-08-22 encoded in the occupant set below).
--
-- WHAT IT DOES, in order:
--   1. OCCUPANTS  — today's occupant set, read from FACT_KEYWORD_STATE (one snapshot) for the
--                   WORKING families only (V_BOOK_ASSIGNMENT.book = 'HARVEST'; a launch family is
--                   never seated) and NEVER a brand-defense keyword (is_brand_defense — defense is
--                   never judged on profit, and a seat is a profit judgment — tested three ways:
--                   the ladder's flag, the campaign-name rule its source uses, and the keyword
--                   text against the house brand phrases in DIM_BRAND_PHRASES). A keyword occupies a
--                   seat when its state is REPRICE (repair), FLOOR_PROBATION (probation), LOSER
--                   (failed), REVIVED_SETTLING or PENDING_SETTLE (settling), or when it is a TRIAL
--                   keyword in one of three probe positions, read from published engine columns
--                   and the applied change log only:
--                     probe, entry bid — the engine's probe list T_LIFT_PROBES (V_KEYWORD_LIFT
--                                 probing / PROBE_START: a bid raised within the engine's probe
--                                 window with fewer than the verdict's clicks since; the set
--                                 V_OOB_KEYWORD reads as is_lift_probe). Seated on the engine's
--                                 funding decision alone, SPEND OR NO SPEND (ruling R-a: a probe
--                                 seat costs $0 this week and still answers "what am I probing").
--                     probe, park bid — the ladder's own at_floor (the live bid observed at the
--                                 channel floor FN_BID_FLOOR publishes; never a literal) AND spend
--                                 in the basis window (ruling R-a: a floor-priced TRIAL that buys
--                                 nothing is idle, not a probe).
--                     stalled probe — ruling R-b: NOT on the engine's list and NOT at the floor,
--                                 whose latest applied bid change (V_PPC_CHANGE_LOG_APPLIED) is an
--                                 INCREASE_BID that still stands — the live bid is at or above the
--                                 logged new_bid and above the logged old_bid, i.e. never lowered
--                                 since (at or above, not equal: the generator's $1.00 activation
--                                 floor can lift a bid past the logged raise after the row is
--                                 written, and a keyword parked there is exactly the activation
--                                 entry R-b names) — that raise older than the engine's probe
--                                 window (k_probe_window_days) and fewer than the verdict's clicks
--                                 (k_verdict_clicks) bought since. The change log is the authority
--                                 for WHEN the raise happened; a bid raised with no applied log row
--                                 at all has no raise date and reads WAITING (the SOP says so).
--                                 A test that cannot produce a verdict at its pace is NOT "waiting
--                                 for results": it is a seat on the 20% side with a standing
--                                 proposal (re-price to the seat price, or park). The two
--                                 constants mirror the engine's own probing test in V_KEYWORD_LIFT
--                                 (raised within 14 days, under 20 episode clicks) — if the engine
--                                 changes them, change them here.
--                   A TRIAL keyword in none of the three positions is WAITING (80% side), never seated.
--                     parked — awaiting re-verdict — ruling R-h (2026-08-23): a PARKED keyword WITH
--                                 spend in the basis window whose re-verdict appointment
--                                 (next_check_date, the ladder's own) is on or after the snapshot
--                                 date. The ladder parks a keyword at the park bid WITH an
--                                 appointment: until that date it is being tested, not leaking.
--                                 Past the appointment, or without spend, it is not a seat (with
--                                 spend it is a LEAK — the register's pause row). Occupant kind
--                                 'parked — awaiting re-verdict', 20% side, cost = its spend.
--                   Basis window: the k_basis_days complete days ending at the ads watermark − 1.
--   2. CLOSE      — every OPEN ledger row whose (family, campaign, keyword) is not in today's
--                   occupant set is closed on the snapshot date with one reason code and the same
--                   reason as one plain sentence (closed_reason_text), first match wins:
--                     KILLED          the keyword is gone from the snapshot and the ledger's last
--                                     observed state for it was LOSER or DEAD (the book paused a
--                                     failed keyword); or the ladder now reads DEAD
--                     PAUSED          the keyword is gone from the snapshot with any other last
--                                     observed state
--                     PARK_LAPSED     the ladder reads PARKED but the keyword is no longer a parked
--                                     seat (R-h): no spend on the basis window, or its re-verdict
--                                     appointment has passed (with spend it is a leak)
--                     LEFT_FAMILY     still tracked but under another family, or its family is no
--                                     longer in the HARVEST book
--                     DEFENSE_EXEMPT  the keyword is now brand defense — never judged on profit,
--                                     never seated
--                     TO_GOOD_SIDE    winning or at its bar (WINNER, PACED_WINNER, AT_BAR — named
--                                     explicitly, never a catch-all)
--                     TO_WAITING      still TRIAL but in none of the three probe positions —
--                                     back to waiting for clicks on the 80% side, no verdict yet
--                     STATE_CHANGED   any other state: the sentence names it in plain words
--                                     ("left the seat set — it now reads <state>") so nothing
--                                     closes silently (P3)
--                   WHY THE LEDGER REMEMBERS: FACT_KEYWORD_STATE is CREATE OR REPLACE'd by
--                   SP_SNAPSHOT_KEYWORD_STATE and holds exactly ONE snapshot. A keyword still on
--                   it carries prior_state (the snapshot procedure reads the old table before
--                   replacing it), but a keyword that VANISHED from the snapshot has no row at
--                   all — and the vanish is precisely the KILLED-vs-PAUSED case. The ledger's
--                   last_observed_state (step 5) is the only memory for a vanished keyword; a row
--                   opened before that column existed (NULL) falls back to the kind it opened
--                   with (failed → KILLED).
--   3. REOPEN     — a row closed on THIS snapshot date whose key is an occupant again is reopened
--                   (closed_on / closed_reason / closed_reason_text cleared) so a same-day flip
--                   keeps its number and the key (family, campaign, keyword, opened_on) stays unique.
--   4. ADMIT      — occupants without an open row get the LOWEST seat number not held by an open
--                   row of their family. Several admissions in one run are ordered totally
--                   (kind: repair, probation, failed, settling, parked, probe, stalled probe; then
--                   spend DESC, campaign_id, keyword_id) and take the free numbers in ascending order,
--                   so the run is deterministic.
--   5. OBSERVE    — every OPEN row is stamped with last_observed_kind / last_observed_state from
--                   today's occupant set. A continuing occupant's NUMBER is never touched; only
--                   its memory is refreshed, and re-stamping the same snapshot writes the same
--                   values (idempotent).
--
-- IDEMPOTENT: every write is keyed on the snapshot date and on set differences, so a second run
-- on the same snapshot finds nothing to close, reopen or admit and re-stamps identical memory.
-- A continuing occupant's number is stable for as long as it stays seated, even if its kind
-- changes (repair → probation → failed is the ladder doing its job, not a new seat).
--
-- PROBE LIST FRESHNESS: T_LIFT_PROBES is rebuilt by SP_REFRESH_CUBE_TABLES (Task 21), which runs
-- AFTER this procedure (20.8b) in the same orchestrator pass, so the probe list read here is the
-- previous pass's. That is deliberate: inlining V_KEYWORD_LIFT here costs tens of seconds and
-- risks BigQuery's planning limit; the engine's probe window is two weeks, one pass of lag is
-- immaterial; and the register never reads a ceiling view (plan §Planner).
--
-- NOT THIS PROCEDURE'S JOB: costs, sides, the 80/20 read, moves — V_FAMILY_SEAT_REGISTER derives
-- those from the snapshots every morning. No engine reads the ledger.
-- Orchestrator: Task 20.8b, immediately after SP_SNAPSHOT_KEYWORD_STATE (20.8).
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_MAINTAIN_FAMILY_SEATS`()
OPTIONS (
  description = "Maintains DE_FAMILY_SEAT_LEDGER from the FACT_KEYWORD_STATE snapshot (the table holds one snapshot) for the WORKING families (V_BOOK_ASSIGNMENT book = HARVEST; launches never seated; brand-defense keywords never seated — the ladder's is_brand_defense, OR 'BRAND DEFENSE' in the campaign name, OR a house brand phrase from DIM_BRAND_PHRASES in the keyword text; defense is never judged on profit). The stalled-probe window is aged against the snapshot date (run_day), never the wall clock, and clicks since the raise are counted on complete days from the raise date itself, never a fixed window. Occupants: REPRICE (repair), FLOOR_PROBATION (probation), LOSER (failed), REVIVED_SETTLING / PENDING_SETTLE (settling), and three probe positions of a TRIAL keyword — probe at an entry bid (on the engine's probe list T_LIFT_PROBES, spend or no spend: ruling R-a), probe at the park bid (the ladder's at_floor, i.e. the live bid at the published channel floor, WITH spend in the basis window = 7 complete days ending at the ads watermark - 1: ruling R-a), and stalled probe (ruling R-b: not engine-listed, not at the floor, whose latest applied bid change in V_PPC_CHANGE_LOG_APPLIED is an INCREASE_BID that still stands — the live bid at or above the logged new_bid and above the logged old_bid, never lowered since; at-or-above because the generator's $1.00 activation floor can lift a bid past the logged raise — that raise older than the engine's probe window with fewer than the verdict's clicks since — a seat with a standing proposal, never 'waiting for results'; the change log is the authority for the raise date, a raise with no applied log row reads waiting). A TRIAL keyword in none of the three positions is waiting (80% side), never seated. Ruling R-h (2026-08-23): a PARKED keyword with spend in the basis window whose re-verdict appointment (next_check_date) is on or after the snapshot date is a seat of kind 'parked — awaiting re-verdict' (the ladder is testing it through its revive cycle); past its appointment or without spend it is not a seat (with spend it is a leak). Brand phrases are matched as WHOLE phrases on word boundaries (D9), never as bare substrings. Steps: CLOSE open rows that left the occupant set, dated on the snapshot, with a reason code and the same reason as a plain sentence (closed_reason_text), first-match KILLED (gone from the snapshot after a LOSER/DEAD last_observed_state in the ledger, or DEAD now) > PAUSED (gone otherwise) > PARK_LAPSED (reads PARKED but is no longer a parked seat: no spend, or its appointment passed) > LEFT_FAMILY (another family, or family left the HARVEST book) > DEFENSE_EXEMPT (now brand defense) > TO_GOOD_SIDE (WINNER / PACED_WINNER / AT_BAR, named explicitly) > TO_WAITING (still TRIAL, in no probe position) > STATE_CHANGED (any other state, named in plain words on the row); REOPEN a row closed on the same snapshot date whose key is an occupant again (keeps its number, keeps the key unique); ADMIT new occupants at the LOWEST seat number not held by an open row of the family, several admissions ordered totally (kind repair > probation > failed > settling > parked > probe > stalled probe, spend DESC, campaign_id, keyword_id); OBSERVE: stamp every open row with last_observed_kind / last_observed_state — the ledger's only memory of a keyword that has VANISHED from the snapshot (a keyword still on the snapshot carries prior_state; a vanished one has no row, and the vanish is the KILLED-vs-PAUSED case). Idempotent on the same snapshot; continuing occupants keep their number whatever their kind becomes. T_LIFT_PROBES is the previous pass's (Task 21 rebuilds it after 20.8b) — deliberate, the engine's probe window is two weeks. Orchestrator Task 20.8b, right after SP_SNAPSHOT_KEYWORD_STATE. No engine reads the ledger. Spec: architecture/FAMILY_SEAT_REGISTER.md."
)
BEGIN
  -- Declared constants. k_basis_days: the spend basis is the complete days ending at the ads
  -- watermark − 1 (the window the design was validated on; mirrored in V_FAMILY_SEAT_REGISTER).
  -- k_probe_window_days / k_verdict_clicks: the engine's own probing test (V_KEYWORD_LIFT:
  -- raised within 14 days, under 20 episode clicks) — a stalled probe is that test expired.
  DECLARE k_basis_days INT64 DEFAULT 7;
  DECLARE k_probe_window_days INT64 DEFAULT 14;
  DECLARE k_verdict_clicks INT64 DEFAULT 20;
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
  -- the engine's own probe list, materialised by Task 21 (the set V_OOB_KEYWORD reads as is_lift_probe)
  probes AS (SELECT DISTINCT CAST(keyword_id AS STRING) AS kid FROM `onyga-482313.OI.T_LIFT_PROBES`),
  -- the keyword's latest APPLIED bid change — the entry it was parked at, if that change was a raise
  lastchg AS (
    SELECT campaign_id, keyword_id, action, DATE(applied_at, 'America/Los_Angeles') AS chg_date, old_bid, new_bid
    FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_APPLIED`
    WHERE action IN ('INCREASE_BID', 'REDUCE_BID') AND new_bid IS NOT NULL
      AND keyword_id IS NOT NULL AND keyword_id != ''
    QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id ORDER BY applied_at DESC, change_id DESC) = 1),
  sp AS (SELECT CAST(f.campaign_id AS STRING) AS cid, CAST(f.keyword_id AS STRING) AS kid,
                SUM(IF(f.date BETWEEN DATE_SUB(wm.d, INTERVAL k_basis_days DAY)
                                  AND DATE_SUB(wm.d, INTERVAL 1 DAY), f.Ads_cost, 0)) AS spend_basis,
                -- clicks since the raise, on COMPLETE days (< the watermark). The scan starts at
                -- the basis window or the OLDEST standing raise, whichever is earlier, so the count
                -- is never truncated by an arbitrary window (P2; FACT_AMAZON_ADS is partitioned by
                -- year, so the dry-run byte bound is the same either way — only rows change).
                SUM(IF(lc.chg_date IS NOT NULL AND f.date > lc.chg_date AND f.date < wm.d, f.Ads_clicks, 0)) AS clicks_since_raise
         FROM `onyga-482313.OI.FACT_AMAZON_ADS` f CROSS JOIN wm
         LEFT JOIN lastchg lc
           ON lc.campaign_id = CAST(f.campaign_id AS STRING) AND lc.keyword_id = CAST(f.keyword_id AS STRING)
         WHERE f.date >= LEAST(DATE_SUB(wm.d, INTERVAL k_basis_days DAY),
                               COALESCE((SELECT MIN(chg_date) FROM lastchg), wm.d))
           AND f.date < wm.d
         GROUP BY 1, 2),
  -- brand defense, three ways: the ladder's flag, the campaign-name rule its source uses
  -- (V_BID_CPC_TRANSFER: 'BRAND DEFENSE' in the name), and the keyword text against the house
  -- brand phrases (DIM_BRAND_PHRASES, phrase_type BRAND) — the flag alone misses brand-word
  -- keywords in SB campaigns (the Bottle 'happy lolli truth or dare' trials). Never a literal list.
  brand_hit AS (SELECT DISTINCT s.campaign_id, s.keyword_id
                FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
                -- D9 (2026-08-23): a WHOLE phrase on word boundaries, never a bare substring — the
                -- house phrase 'lolli' as a substring would claim 'lolli pop' and 'lolli and pops'
                JOIN (SELECT DISTINCT CONCAT(r'\b', REGEXP_REPLACE(TRIM(LOWER(phrase), ' |,'), r'([.*+?^${}()|\[\]\\])', r'\\\1'), r'\b') AS rx
                      FROM `onyga-482313.OI.DIM_BRAND_PHRASES`
                      WHERE phrase_type = 'BRAND' AND TRIM(LOWER(phrase), ' |,') != '') b
                  ON REGEXP_CONTAINS(LOWER(s.target_text), b.rx)),
  s AS (SELECT s.family, s.campaign_id, s.keyword_id, s.state, s.at_floor, s.current_bid, s.next_check_date
        FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
        JOIN working w ON w.family = s.family
        LEFT JOIN brand_hit bh ON bh.campaign_id = s.campaign_id AND bh.keyword_id = s.keyword_id
        WHERE s.snapshot_date = run_day
          AND NOT COALESCE(s.is_brand_defense, FALSE)
          AND NOT REGEXP_CONTAINS(UPPER(COALESCE(s.campaign_name, '')), r'BRAND DEFENSE')
          AND bh.keyword_id IS NULL),
  pos AS (
    SELECT s.*,
           COALESCE(sp.spend_basis, 0) AS spend_basis,
           p.kid IS NOT NULL AS engine_probe,
           (COALESCE(s.at_floor, FALSE) AND COALESCE(sp.spend_basis, 0) > 0) AS park_probe,
           -- R-h (2026-08-23): a PARKED keyword that still spends and holds a re-verdict appointment
           -- (next_check_date on or after the snapshot date) is being TESTED by the ladder's revive
           -- cycle, not leaking: a seat. Past its appointment, or without spend, it is not a seat
           -- (with spend it is a leak — the register's pause row).
           (s.state = 'PARKED' AND COALESCE(sp.spend_basis, 0) > 0 AND s.next_check_date >= run_day) AS parked_seat,
           (p.kid IS NULL AND NOT COALESCE(s.at_floor, FALSE)
            AND lc.action = 'INCREASE_BID'
            -- the raise still stands: the live bid is AT OR ABOVE the logged new_bid and above the
            -- logged old_bid (never lowered since). At-or-above, not equal: the generator's $1.00
            -- activation floor can lift a bid past the logged raise AFTER the log row is written
            -- (a known defect), and a keyword parked there is exactly the population R-b names.
            AND s.current_bid >= lc.new_bid - 0.005 AND s.current_bid > lc.old_bid + 0.005
            AND lc.chg_date <= DATE_SUB(run_day, INTERVAL k_probe_window_days DAY)  -- aged against the SNAPSHOT date, never the wall clock (P1)
            AND COALESCE(sp.clicks_since_raise, 0) < k_verdict_clicks) AS stalled_probe
    FROM s
    LEFT JOIN sp ON sp.cid = s.campaign_id AND sp.kid = s.keyword_id
    LEFT JOIN probes p ON p.kid = s.keyword_id
    LEFT JOIN lastchg lc ON lc.campaign_id = s.campaign_id AND lc.keyword_id = s.keyword_id)
  SELECT family, campaign_id, keyword_id, state,
         CASE state
           WHEN 'REPRICE'          THEN 'repair'
           WHEN 'FLOOR_PROBATION'  THEN 'probation'
           WHEN 'LOSER'            THEN 'failed'
           WHEN 'REVIVED_SETTLING' THEN 'settling'
           WHEN 'PENDING_SETTLE'   THEN 'settling'
           WHEN 'TRIAL'            THEN IF(engine_probe OR park_probe, 'probe', 'stalled probe')
           WHEN 'PARKED'           THEN 'parked — awaiting re-verdict'
         END AS occupant_kind,
         spend_basis
  FROM pos
  WHERE state IN ('REPRICE', 'FLOOR_PROBATION', 'LOSER', 'REVIVED_SETTLING', 'PENDING_SETTLE')
     OR (state = 'TRIAL' AND (engine_probe OR park_probe OR COALESCE(stalled_probe, FALSE)))
     OR (state = 'PARKED' AND COALESCE(parked_seat, FALSE));

  -- ── 2. CLOSE ──────────────────────────────────────────────────────────────────────────────
  CREATE TEMP TABLE leaving AS
  WITH
  working AS (SELECT family FROM `onyga-482313.OI.V_BOOK_ASSIGNMENT` WHERE book = 'HARVEST'),
  -- where the keyword is today, any family — one row per (campaign, keyword) on the snapshot
  brand_hit AS (SELECT DISTINCT s.campaign_id, s.keyword_id
                FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
                -- D9 (2026-08-23): a WHOLE phrase on word boundaries, never a bare substring — the
                -- house phrase 'lolli' as a substring would claim 'lolli pop' and 'lolli and pops'
                JOIN (SELECT DISTINCT CONCAT(r'\b', REGEXP_REPLACE(TRIM(LOWER(phrase), ' |,'), r'([.*+?^${}()|\[\]\\])', r'\\\1'), r'\b') AS rx
                      FROM `onyga-482313.OI.DIM_BRAND_PHRASES`
                      WHERE phrase_type = 'BRAND' AND TRIM(LOWER(phrase), ' |,') != '') b
                  ON REGEXP_CONTAINS(LOWER(s.target_text), b.rx)),
  today AS (SELECT s.campaign_id, s.keyword_id, s.family, s.state,
                   (COALESCE(s.is_brand_defense, FALSE)
                    OR REGEXP_CONTAINS(UPPER(COALESCE(s.campaign_name, '')), r'BRAND DEFENSE')
                    OR bh.keyword_id IS NOT NULL) AS is_brand_defense,
                   s.family IN (SELECT family FROM working) AS in_working
            FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
            LEFT JOIN brand_hit bh ON bh.campaign_id = s.campaign_id AND bh.keyword_id = s.keyword_id
            WHERE s.snapshot_date = run_day),
  coded AS (
    SELECT l.family, l.campaign_id, l.keyword_id, l.opened_on,
           CASE
             WHEN t.campaign_id IS NULL
               THEN IF(COALESCE(l.last_observed_state IN ('LOSER', 'DEAD'),
                                l.occupant_kind_at_open = 'failed'), 'KILLED', 'PAUSED')
             WHEN t.family IS DISTINCT FROM l.family OR NOT t.in_working THEN 'LEFT_FAMILY'
             WHEN t.is_brand_defense THEN 'DEFENSE_EXEMPT'
             WHEN t.state = 'DEAD'   THEN 'KILLED'
             WHEN t.state = 'PARKED' THEN 'PARK_LAPSED'   -- R-h: no spend, or its re-verdict appointment passed
             WHEN t.state = 'TRIAL'  THEN 'TO_WAITING'
             WHEN t.state IN ('WINNER', 'PACED_WINNER', 'AT_BAR') THEN 'TO_GOOD_SIDE'
             -- P3: no silent catch-all — any other state is named, in plain words, on the row
             ELSE 'STATE_CHANGED'
           END AS closed_reason,
           CASE t.state
             WHEN 'LAUNCH_CONTAINED' THEN 'launch, contained by the launch controller'
             WHEN 'REVIVED_SETTLING' THEN 'revived, its verdict settling'
             WHEN 'PENDING_SETTLE'   THEN 'a verdict pending until its clicks settle'
             WHEN 'REPRICE'          THEN 'losing, being re-priced toward its bar'
             WHEN 'FLOOR_PROBATION'  THEN 'losing, on probation at its floor'
             WHEN 'LOSER'            THEN 'failed at its floor'
             ELSE CONCAT('an unmapped ladder state (', COALESCE(t.state, 'none'), ')')
           END AS state_words
    FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
    LEFT JOIN occupants o
      ON o.family = l.family AND o.campaign_id = l.campaign_id AND o.keyword_id = l.keyword_id
    LEFT JOIN today t
      ON t.campaign_id = l.campaign_id AND t.keyword_id = l.keyword_id
    WHERE l.closed_on IS NULL AND o.campaign_id IS NULL)
  -- every code mapped to one plain sentence — the same sentences the acceptance test and the SOP carry
  SELECT c.*,
         CASE c.closed_reason
           WHEN 'KILLED'         THEN 'The keyword is gone from the snapshot after its last verdict was failed or dead, or the ladder now reads dead: the book paused a failed keyword. The seat is free.'
           WHEN 'PAUSED'         THEN 'The keyword is gone from the snapshot, or the ladder now reads parked, without a failed verdict first. The seat is free.'
           WHEN 'PARK_LAPSED'    THEN 'The keyword reads parked on the ladder but is no longer a parked seat: it has no spend on the basis window, or its re-verdict appointment has passed. A parked keyword that still spends past its appointment is a leak (pause row). The seat is free.'
           WHEN 'LEFT_FAMILY'    THEN 'The keyword is still tracked but now belongs to another family, or its family left the working (HARVEST) book. The seat is free.'
           WHEN 'DEFENSE_EXEMPT' THEN 'The keyword is now brand defense. Defense is never judged on profit, so it is never seated. The seat is free.'
           WHEN 'TO_GOOD_SIDE'   THEN 'The keyword is now winning or at its bar: it moved to the 80% side. The seat is free.'
           WHEN 'TO_WAITING'     THEN 'The keyword is still a trial but is no longer bought at an entry or park bid and is not a stalled probe: it is back to waiting for clicks on the 80% side, no verdict yet. The seat is free.'
           WHEN 'STATE_CHANGED'  THEN CONCAT('The keyword left the seat set — it now reads ', c.state_words, '. The seat is free.')
         END AS closed_reason_text
  FROM coded c;

  UPDATE `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
  SET closed_on = run_day, closed_reason = x.closed_reason, closed_reason_text = x.closed_reason_text
  FROM leaving x
  WHERE l.family = x.family AND l.campaign_id = x.campaign_id AND l.keyword_id = x.keyword_id
    AND l.opened_on = x.opened_on AND l.closed_on IS NULL;

  -- ── 3. REOPEN (same-day flip keeps its number and keeps the key unique) ──────────────────
  UPDATE `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
  SET closed_on = NULL, closed_reason = NULL, closed_reason_text = NULL
  FROM occupants o
  WHERE l.family = o.family AND l.campaign_id = o.campaign_id AND l.keyword_id = o.keyword_id
    AND l.closed_on = run_day
    AND NOT EXISTS (SELECT 1 FROM `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` z
                    WHERE z.family = l.family AND z.campaign_id = l.campaign_id
                      AND z.keyword_id = l.keyword_id AND z.closed_on IS NULL);

  -- ── 4. ADMIT at the lowest free number ────────────────────────────────────────────────────
  INSERT INTO `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER`
    (family, campaign_id, keyword_id, seat_no, opened_on, closed_on, closed_reason, occupant_kind_at_open,
     last_observed_kind, last_observed_state, closed_reason_text)
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
                                           WHEN 'failed' THEN 3 WHEN 'settling' THEN 4
                                           WHEN 'parked — awaiting re-verdict' THEN 5
                                           WHEN 'probe' THEN 6 ELSE 7 END,
                      n.spend_basis DESC, n.campaign_id, n.keyword_id) AS rk
    FROM admits n)
  SELECT r.family, r.campaign_id, r.keyword_id, f.seat_no, run_day,
         CAST(NULL AS DATE), CAST(NULL AS STRING), r.occupant_kind,
         r.occupant_kind, r.state, CAST(NULL AS STRING)
  FROM ranked r
  JOIN free f ON f.family = r.family AND f.rk = r.rk;

  -- ── 5. OBSERVE — the ledger's only memory of yesterday ───────────────────────────────────
  UPDATE `onyga-482313.OI.DE_FAMILY_SEAT_LEDGER` l
  SET last_observed_kind = o.occupant_kind, last_observed_state = o.state
  FROM occupants o
  WHERE l.family = o.family AND l.campaign_id = o.campaign_id AND l.keyword_id = o.keyword_id
    AND l.closed_on IS NULL
    AND (l.last_observed_kind IS DISTINCT FROM o.occupant_kind
         OR l.last_observed_state IS DISTINCT FROM o.state);

  SELECT FORMAT('SP_MAINTAIN_FAMILY_SEATS: snapshot %s — %d occupants (%d stalled probes, %d parked awaiting re-verdict), %d seats closed',
                CAST(run_day AS STRING),
                (SELECT COUNT(*) FROM occupants),
                (SELECT COUNT(*) FROM occupants WHERE occupant_kind = 'stalled probe'),
                (SELECT COUNT(*) FROM occupants WHERE occupant_kind = 'parked — awaiting re-verdict'),
                (SELECT COUNT(*) FROM leaving)) AS log_message;
END;
