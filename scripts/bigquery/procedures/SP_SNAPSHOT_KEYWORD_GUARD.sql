-- =============================================
-- SP_SNAPSHOT_KEYWORD_GUARD — materializes V_KEYWORD_GUARD into FACT_KEYWORD_GUARD
-- (v27.48 part 2, 2026-08-09). Spec: architecture/SEASON_CONTEXT_LEDGER.md §7.6-7.9.
--
-- WHY A SNAPSHOT: BOTH engines consume the guard signals (general settle veto, probe record
-- caps, MANUAL_HOLD, PACE_RAISE, settled-first seat ordering) — but V_OOB_KEYWORD sits at the
-- BQ planner ceiling and re-plans V_KEYWORD_LIFT via lift_probes, so the guard view's FACT
-- subtrees must never enter either engine plan (same doctrine as FACT_PARK_REVERDICT). The
-- engines LEFT JOIN this small table (~1.4k rows, (campaign_id, keyword_id) grain) instead.
--
-- Fully derived, idempotent: CREATE OR REPLACE TABLE from the view. Stale-snapshot directions:
--   settle veto  — a stale last_click can look settled one day early on a row that clicked
--                  today; the engines' own 1-day cooldown + APPLIED_HOLD bound the exposure.
--   manual hold  — a manual change made TODAY appears tomorrow; day-0 is covered by the
--                  engines' 'changed today' cooldown + APPLIED_HOLD.
--   pace         — a stale pace_flag re-emission after an upload is caught by APPLIED_HOLD.
--
-- Called by SP_ORCHESTRATE_DAILY_REFRESH Task 20.5f — AFTER SP_SNAPSHOT_PARK_REVERDICT (20.5e):
-- both snapshots read the same settled frames and the engines read them side by side.
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SNAPSHOT_KEYWORD_GUARD`()
OPTIONS (
  description = "Keyword-guard snapshot (v27.48 part 2). CREATE OR REPLACE TABLE FACT_KEYWORD_GUARD AS SELECT * FROM V_KEYWORD_GUARD — per-instance guard signals for both engines: channel-aware settled 90d record + settle_ok/settle_due (general settle veto, Cause 1), scope lifetime record + LY conv CPC (probe record caps, Cause 2), MANUAL 7d hold with catastrophic escape (Cause 3), LY-pacing raise flags + calibrated target (Cause 4). Engines read the TABLE (planner-ceiling doctrine). Task 20.5f, after SP_SNAPSHOT_PARK_REVERDICT. Spec: architecture/SEASON_CONTEXT_LEDGER.md §7.6-7.9."
)
BEGIN
  CREATE OR REPLACE TABLE `onyga-482313.OI.FACT_KEYWORD_GUARD` AS
  SELECT * FROM `onyga-482313.OI.V_KEYWORD_GUARD`;
END;
