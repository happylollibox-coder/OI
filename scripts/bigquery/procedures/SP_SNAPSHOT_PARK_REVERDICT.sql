-- =============================================
-- SP_SNAPSHOT_PARK_REVERDICT — materializes V_PARK_REVERDICT into FACT_PARK_REVERDICT
-- (v27.48 part 1, 2026-08-09). Spec: architecture/SEASON_CONTEXT_LEDGER.md §7.
--
-- WHY A SNAPSHOT: the ENGINES (V_OOB_KEYWORD seat ordering + ACTIVATE_REVIVE / settle veto /
-- CONFIRM_PARK block; V_KEYWORD_LIFT output-layer mirrors) consume the reverdict — but
-- V_OOB_KEYWORD sits at the BQ planner ceiling and re-plans V_KEYWORD_LIFT via lift_probes, so
-- the reverdict view's FACT + context-gate subtree must never enter either engine plan (the
-- V_KEYWORD_CONTEXT_GATE plan-cost lesson: ~25s -> ~176s). The engines LEFT JOIN this small
-- table (~600 rows, (campaign_id, keyword_id) grain) instead.
--
-- Fully derived, idempotent: CREATE OR REPLACE TABLE from the view. Stale-snapshot direction is
-- SAFE: engine_immune persists (more protection), and a stale REVIVE that was already uploaded
-- is caught by the engines' APPLIED_HOLD (applied bid != stale config mirror).
--
-- Called by SP_ORCHESTRATE_DAILY_REFRESH Task 20.5e — AFTER SP_SNAPSHOT_SEASON_VERDICT (20.5d):
-- the reverdict reads season verdicts (the 0.8x season-WIN relaxation) and the context gate.
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SNAPSHOT_PARK_REVERDICT`()
OPTIONS (
  description = "Park-reverdict snapshot (v27.48). CREATE OR REPLACE TABLE FACT_PARK_REVERDICT AS SELECT * FROM V_PARK_REVERDICT — settled re-judgment of every parked/STOPped/recently-revived SP keyword: reverdict REVIVE / CONFIRM_PARK / PENDING_SETTLE / INSUFFICIENT, calibrated revive_bid, post-revival settle veto (engine_immune) and manual holds. Engines read the TABLE (planner-ceiling doctrine). Task 20.5e, after SP_SNAPSHOT_SEASON_VERDICT. Spec: architecture/SEASON_CONTEXT_LEDGER.md §7."
)
BEGIN
  CREATE OR REPLACE TABLE `onyga-482313.OI.FACT_PARK_REVERDICT` AS
  SELECT * FROM `onyga-482313.OI.V_PARK_REVERDICT`;
END;
