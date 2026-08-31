CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SCORE_INTENT_INDEXES`()
BEGIN
  -- ===========================================================================================
  -- SP_SCORE_INTENT_INDEXES
  -- Materialises the walk-forward evidence layer for the intent CVR index registry:
  --   T_INTENT_INDEX_SCORECARD  <- V_INTENT_INDEX_SCORECARD  (index verdicts, 18 months)
  --   T_INTENT_BASE_TUNING      <- V_INTENT_BASE_TUNING       (recency shape x k_base grid)
  --
  -- WHY THE TABLES EXIST AT ALL. Both source views walk 18 target months across the whole
  -- observation set. Reading them live costs enough that this chain has already hit the
  -- on-demand CPU cap once -- V_INTENT_CVR_CURVE ran ~27k CPU-seconds per scan and every
  -- consumer had to be repointed at T_INTENT_CVR_CURVE, 50s -> 1.4s -- and the Task 4 acceptance
  -- file was outright REJECTED by BigQuery at 97,066 CPU-seconds against a 33,500 ceiling.
  -- Measured 2026-08-31 the two views cost 6,215 and 942 slot-seconds per scan. Acceptance
  -- checks R12/R13/R14/R16 therefore read THESE TABLES, not the views. Do not repoint them.
  --
  -- PROMOTES NOTHING. This procedure does not write DE_INTENT_INDEX_REGISTRY and must never be
  -- given permission to: is_active is set by a human, the same contract as DE_SEARCH_TERM_INTENT,
  -- because the Coacher has twice made unreviewed bid changes that lost money.
  --
  -- CADENCE. R16 fails the suite when either table is more than 8 days old, so this wants to run
  -- at least weekly, and MUST be re-run after any change to the index views, the thresholds, or
  -- the curve -- otherwise a promotion decision is made against evidence from before the change.
  --
  -- scored_at is stamped per table by its own CURRENT_TIMESTAMP(), so a partial run (the first
  -- statement succeeding and the second failing) leaves the two tables with different stamps and
  -- R16, which checks BOTH, reports it. That is deliberate: one shared timestamp variable would
  -- hide exactly that failure.
  -- ===========================================================================================

  CREATE OR REPLACE TABLE `onyga-482313.OI.T_INTENT_INDEX_SCORECARD` AS
  SELECT CURRENT_TIMESTAMP() AS scored_at, *
  FROM `onyga-482313.OI.V_INTENT_INDEX_SCORECARD`;

  CREATE OR REPLACE TABLE `onyga-482313.OI.T_INTENT_BASE_TUNING` AS
  SELECT CURRENT_TIMESTAMP() AS scored_at, *
  FROM `onyga-482313.OI.V_INTENT_BASE_TUNING`;
END;
