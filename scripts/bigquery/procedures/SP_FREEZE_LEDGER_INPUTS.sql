-- =============================================================================================
-- SP_FREEZE_LEDGER_INPUTS(caller STRING) — v27.177 (2026-10-04, learning piece 2 fix L1): freeze the
-- keyword-state inputs of every plan night not yet frozen, once.
--
-- WHAT IT WRITES. FACT_PREDICTION_LEDGER_INPUTS (append-only): for every (as_of, built_at) of
-- FACT_PLAN_NEXT_WEEK with no row there yet, one row per keyword of the night's plan rows (both
-- plans), with
--   * the night's snapshot pick, the rule V_PREDICTION_LEDGER v27.172 applied at query time: the
--     latest snapshot_date of FACT_KEYWORD_STATE_HISTORY before DATE(built_at, 'America/Los_Angeles')
--     among copies captured at or before built_at; of that date, the newest copy captured at or
--     before built_at (snapshot_captured_at). v27.172 took the newest copy of the date with no
--     captured_at filter; the history held one copy per date when this ran (2026-10-04), so the two
--     read the same rows on every stored night;
--   * the keyword's settled_clk90 / settled_ord90 / settled_gp90 in that copy (in_snapshot FALSE and
--     NULLs when the copy has no row for it, or the night has no snapshot);
--   * the night's builder_version and rule_builder_tag = COALESCE(builder_version, 'pre-v27.170').
-- All of one call's nights go in ONE INSERT, so a night is frozen whole or not at all.
--
-- WHEN. SP_BUILD_NEXT_WEEK_PLAN v27.177 CALLs it ('SP_BUILD_NEXT_WEEK_PLAN v27.177') right after it
-- writes the night, so the night is frozen seconds after built_at, from the history as it stood at
-- the build. Any night an earlier call missed is frozen by the next call (the NOT EXISTS below).
-- The nights stored before v27.177 were frozen by one hand CALL on 2026-10-04.
--
-- WHY THE BUILDER AND NOT THE GRADER OR A NEW ORCHESTRATOR STEP: the builder is the one writer that
-- runs at built_at; its CALL follows the night's INSERT in the same script. The grader (Task 20.8f)
-- or a new step would run later in the pass, and a pass whose step failed would leave the night
-- unfrozen until the next pass, a gap in which a re-capture or prune could reach it.
--
-- Idempotent: a second call inserts nothing for a night already here. Never updates or deletes.
-- Asserts one builder_version per night (a night is one builder run).
-- Reads: FACT_PLAN_NEXT_WEEK, FACT_KEYWORD_STATE_HISTORY, FACT_PREDICTION_LEDGER_INPUTS.
-- Read by: V_PREDICTION_LEDGER (each night's first freeze).
-- Acceptance: scripts/bigquery/tests/PREDICTION_CONTRACT_acceptance.sql L5;
-- controls scripts/bigquery/tests/check_ledger_freeze_controls.py.
-- SOP: architecture/LEARNING.md §1, §3, §10 "Fix L1".
-- =============================================================================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_FREEZE_LEDGER_INPUTS`(caller STRING)
OPTIONS (description = "v27.177 (2026-10-04, learning piece 2 fix L1): freezes the keyword-state inputs of every FACT_PLAN_NEXT_WEEK night (as_of, built_at) not yet in FACT_PREDICTION_LEDGER_INPUTS, in one INSERT: per keyword of the night's plan rows, the night's snapshot pick (the latest FACT_KEYWORD_STATE_HISTORY snapshot_date before the Los Angeles date of built_at among copies captured at or before built_at, and that date's newest such copy), the keyword's settled_clk90 / settled_ord90 / settled_gp90 in it, and the night's builder_version with rule_builder_tag = COALESCE(builder_version, 'pre-v27.170'); frozen_at = now, frozen_by = caller. CALLed by SP_BUILD_NEXT_WEEK_PLAN right after it writes a night, so a night is frozen at its build; a night a call missed is frozen by the next. Idempotent, append-only, never updates or deletes; asserts one builder_version per night. Read by V_PREDICTION_LEDGER. SOP: architecture/LEARNING.md.")
BEGIN
  DECLARE run_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

  CREATE OR REPLACE TEMP TABLE _fli_nights AS
  SELECT p.as_of, p.built_at,
         COUNT(DISTINCT IFNULL(p.builder_version, '<NULL>')) AS n_versions,
         ANY_VALUE(p.builder_version) AS builder_version
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p
  WHERE NOT EXISTS (SELECT 1 FROM `onyga-482313.OI.FACT_PREDICTION_LEDGER_INPUTS` f
                    WHERE f.as_of = p.as_of AND f.built_at = p.built_at)
  GROUP BY p.as_of, p.built_at;

  ASSERT NOT EXISTS (SELECT 1 FROM _fli_nights WHERE n_versions != 1)
    AS 'SP_FREEZE_LEDGER_INPUTS: a night carries more than one builder_version; not frozen';

  INSERT INTO `onyga-482313.OI.FACT_PREDICTION_LEDGER_INPUTS`
    (as_of, built_at, builder_version, rule_builder_tag, family, channel, campaign_id, keyword_id,
     in_snapshot, snapshot_date, snapshot_captured_at, settled_clk90, settled_ord90, settled_gp90,
     frozen_at, frozen_by)
  WITH
  snap_night AS (   -- the latest snapshot_date before the Los Angeles date of built_at, final at built_at
    SELECT n.as_of, n.built_at, MAX(h.snapshot_date) AS snap_date
    FROM _fli_nights n
    JOIN `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY` h
      ON h.snapshot_date < DATE(n.built_at, 'America/Los_Angeles') AND h.captured_at <= n.built_at
    GROUP BY n.as_of, n.built_at
  ),
  snap_copy AS (    -- that date's newest copy captured at or before built_at
    SELECT s.as_of, s.built_at, s.snap_date, MAX(h.captured_at) AS snap_captured_at
    FROM snap_night s
    JOIN `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY` h
      ON h.snapshot_date = s.snap_date AND h.captured_at <= s.built_at
    GROUP BY s.as_of, s.built_at, s.snap_date
  ),
  night_keys AS (
    SELECT DISTINCT p.as_of, p.built_at, p.family, p.channel, p.campaign_id, p.keyword_id
    FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p
    JOIN _fli_nights n ON n.as_of = p.as_of AND n.built_at = p.built_at
  ),
  ks AS (           -- the keyword's row in that copy (one: the same tie-break v27.172 used)
    SELECT k.as_of, k.built_at, k.campaign_id, k.keyword_id,
           h.settled_clk90, h.settled_ord90, h.settled_gp90
    FROM night_keys k
    JOIN snap_copy c ON c.as_of = k.as_of AND c.built_at = k.built_at
    JOIN `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY` h
      ON h.snapshot_date = c.snap_date AND h.captured_at = c.snap_captured_at
     AND h.campaign_id = k.campaign_id AND h.keyword_id = k.keyword_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY k.as_of, k.built_at, k.campaign_id, k.keyword_id
                               ORDER BY h.settled_clk90 DESC, h.settled_ord90 DESC, h.settled_gp90 DESC) = 1
  )
  SELECT k.as_of, k.built_at, n.builder_version, COALESCE(n.builder_version, 'pre-v27.170'),
         k.family, k.channel, k.campaign_id, k.keyword_id,
         s.as_of IS NOT NULL, c.snap_date, c.snap_captured_at,
         s.settled_clk90, s.settled_ord90, s.settled_gp90,
         run_ts, IFNULL(caller, 'UNNAMED CALL')
  FROM night_keys k
  JOIN _fli_nights n ON n.as_of = k.as_of AND n.built_at = k.built_at
  LEFT JOIN snap_copy c ON c.as_of = k.as_of AND c.built_at = k.built_at
  LEFT JOIN ks s ON s.as_of = k.as_of AND s.built_at = k.built_at
                AND s.campaign_id = k.campaign_id AND s.keyword_id = k.keyword_id;
END;
