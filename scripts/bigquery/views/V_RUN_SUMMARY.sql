-- =============================================
-- V_RUN_SUMMARY — the Weekly Run front page as one small-table query (2026-08-16, Phase 6 Task 2).
-- Spec: architecture/WEEKLY_RUN_UX.md. One row per summary cell; three sections:
--   CHANGES   today's GO instructions by direction ($/day on BUDGET moves ONLY — bid-level $/day
--             would be invented precision)
--   HELD      what the gate excluded / flagged, by class
--   UNCHANGED the rest of the account, from the STATE MACHINE (FACT_KEYWORD_STATE supersedes the
--             plan's interim guard-based taxonomy — built the day before this view)
--   SEATS     the 80/20 doctrine status of each WORKING family (v27.123, family seat register
--             Task 4) — where the account's money is standing, beside what moved today.
-- Reads ONLY snapshot tables. Target: renders in seconds.
--
-- ##########################################################################
-- # v27.123 — SEATS, and no label in this view may render blank any more.  #
-- ##########################################################################
-- (2026-08-23, family seat register Task 4. Spec: architecture/FAMILY_SEAT_REGISTER.md.)
--
-- SEATS is one row per WORKING family: its doctrine status in plain words, the number of numbered
-- seats its 20% side holds, and the open capacity in $/day (negative when the side is over its
-- allowance). It reads T_FAMILY_SEAT_REGISTER — the same image the SEATS section of V_DAILY_BRIEF
-- and the SeatRegister cube read, so the three surfaces cannot disagree — and it judges nothing
-- itself: a launch family is published by the register as a REFERENCE row rather than a FAMILY
-- row, so filtering on row_type is what keeps the house rule that a launch family is never judged
-- on profit. No name list to forget to update.
--
-- THE FALL-THROUGH THAT COULD PUBLISH AN EMPTY LABEL. The UNCHANGED arm ended in
-- `ELSE LOWER(ks.state)`, which is a plain word for every state the ladder has today and NULL for
-- a row the snapshot ever writes with no state at all — an empty cell on the front page, with
-- nothing to tell a reader whether it means "none" or "unnamed". Both label CASEs in this view now
-- end in a sentence rather than a value, and the acceptance suite asserts no label in any section
-- is blank (SEAT_SURFACE_acceptance.sql, C06).
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_RUN_SUMMARY` AS
WITH pf AS (SELECT * FROM `onyga-482313.OI.T_ENGINE_PREFLIGHT`),
changes AS (
  SELECT 'CHANGES' AS section,
    -- v27.72: NEGATE before the bid arms — a negate has NULL values, and NULL < NULL is NULL,
    -- so without its own arm every block lands in the ELSE and inflates "bid raises"
    CASE WHEN lever = 'NEGATE' THEN 'search terms blocked'
         WHEN lever = 'BUDGET' AND suggested_budget < current_budget THEN 'budget cuts'
         WHEN lever = 'BUDGET' THEN 'budget raises'
         WHEN grain = 'REVIVE' THEN 'revivals'
         WHEN suggested_bid < current_bid THEN 'bid cuts'
         ELSE 'bid raises' END AS label,
    COUNT(*) AS n,
    ROUND(SUM(IF(lever = 'BUDGET', suggested_budget - current_budget, 0)), 2) AS dollars_per_day,
    CAST(NULL AS STRING) AS detail
  FROM pf WHERE verdict = 'GO'
  GROUP BY 2
),
held AS (
  SELECT 'HELD' AS section,
    -- class label: strip the per-row numbers so REVIEW rows GROUP (the '(' split) — the row
    -- detail keeps one full example reason
    CONCAT(LOWER(verdict), ' — ',
           COALESCE(SPLIT(SPLIT(verdict_reason, ' (')[SAFE_OFFSET(0)], ' — ')[SAFE_OFFSET(0)], 'other')) AS label,
    COUNT(*) AS n, CAST(NULL AS FLOAT64) AS dollars_per_day,
    ANY_VALUE(verdict_reason) AS detail
  FROM pf WHERE verdict != 'GO'
  GROUP BY 2
),
instructed AS (SELECT DISTINCT campaign_id, COALESCE(keyword_id, '') AS kid FROM pf),
unchanged AS (
  SELECT 'UNCHANGED' AS section,
    CASE ks.state
      WHEN 'WINNER' THEN 'winners holding'
      WHEN 'PACED_WINNER' THEN 'winners holding'   -- paced ones with no live instruction today
      WHEN 'TRIAL' THEN 'trial — gathering evidence'
      WHEN 'PARKED' THEN 'parked at minimum bid'
      WHEN 'DEAD' THEN 'tested losers (closed)'
      -- v27.103 bar/SE ladder states (LOSER_BLEED kept for safety; superseded by the ladder);
      -- v27.104: FLOOR_PROBATION added, LOSER now means "probation at the floor elapsed"
      WHEN 'AT_BAR' THEN 'at their family bar — holding within noise'
      WHEN 'REPRICE' THEN 'priced above their record — in the reprice book'
      WHEN 'FLOOR_PROBATION' THEN 'on probation at their floor — re-judged once clicks settle there'
      WHEN 'LOSER' THEN 'failed at their floor after probation — kill candidates (reprice book)'
      WHEN 'LAUNCH_CONTAINED' THEN 'launch — contained, never judged on profit'
      WHEN 'LOSER_BLEED' THEN 'proven losers still spending'
      WHEN 'REVIVED_SETTLING' THEN 'revived — waiting for final sales data'
      WHEN 'PENDING_SETTLE' THEN 'just parked — verdict when sales data completes'
      -- v27.123: never NULL. A state the ladder gains reads as itself; a row written with no
      -- state at all says so, instead of printing an empty cell on the front page.
      ELSE COALESCE(LOWER(ks.state), 'no ladder state on the row — the snapshot wrote it blank')
      END AS label,
    COUNT(*) AS n, CAST(NULL AS FLOAT64) AS dollars_per_day,
    ANY_VALUE(ks.next_check_what) AS detail
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE` ks
  LEFT JOIN instructed i
    ON i.campaign_id = ks.campaign_id AND i.kid = COALESCE(ks.keyword_id, '')
  WHERE i.campaign_id IS NULL   -- anti-join by equality only
  GROUP BY 2
),

-- v27.123 SEATS — where the money is STANDING, beside what moved. One row per working family.
seat_reg AS (SELECT * FROM `onyga-482313.OI.T_FAMILY_SEAT_REGISTER`),
seat_counts AS (
  SELECT family,
         COUNTIF(row_type = 'SEAT' AND side = '20') AS n_seats,
         COUNTIF(row_type = 'LEAK')                 AS n_leaks,
         COUNTIF(row_type = 'GAP')                  AS n_gaps
  FROM seat_reg GROUP BY 1
),
seats AS (
  SELECT 'SEATS' AS section,
    CONCAT(f.family, ' — ',
      CASE f.doctrine_status
        WHEN 'IN'        THEN 'passes the 80/20 line'
        WHEN 'AT_LINE'   THEN 'at the 80/20 line, inside its own spend noise'
        WHEN 'OUT'       THEN 'below the 80/20 line: the 20% side is over its allowance'
        WHEN 'NO_SPEND'  THEN 'no judged spend on this window'
        WHEN 'REFERENCE' THEN 'launch family — never judged on profit'
        ELSE 'a doctrine status this summary has not learned — read the register'
      END) AS label,
    COALESCE(c.n_seats, 0) AS n,
    -- open capacity: positive is room a new probe could take, negative is the overspend. This is
    -- the register's own column, not a second arithmetic.
    ROUND(f.open_capacity_per_day, 2) AS dollars_per_day,
    FORMAT('%d numbered seat%s cost $%.2f/day against an allowance of $%.2f/day; %d leak%s ($%.2f/day) and %d untracked keyword%s ($%.2f/day) sit on the same side. Keyword snapshot %s — the seat-by-seat read, and every move, is V_FAMILY_SEAT_REGISTER.',
           COALESCE(c.n_seats, 0), IF(COALESCE(c.n_seats, 0) = 1, '', 's'),
           COALESCE(f.seats_cost_per_day, 0), COALESCE(f.allowance_per_day, 0),
           COALESCE(c.n_leaks, 0), IF(COALESCE(c.n_leaks, 0) = 1, '', 's'), COALESCE(f.leak_per_day, 0),
           COALESCE(c.n_gaps,  0), IF(COALESCE(c.n_gaps,  0) = 1, '', 's'), COALESCE(f.gap_per_day, 0),
           FORMAT_DATE('%b %d', f.as_of)) AS detail
  FROM seat_reg f LEFT JOIN seat_counts c ON c.family = f.family
  WHERE f.row_type = 'FAMILY' AND f.horizon = 'today'
)
SELECT * FROM changes UNION ALL SELECT * FROM held UNION ALL SELECT * FROM unchanged
UNION ALL SELECT * FROM seats;
