-- SP_REFRESH_COACH_LOOP — the SQL half of the coacher loop, daily. Coacher D/E/C.
-- Idempotent; safe to run daily (the review only resolves a week once it completes).
-- NOTE: the Python generators (tools/strategy_profile, tools/weekly_plan, derive_tos_targets)
-- are NOT here — they can't run inside a BQ SP and need a Cloud runner (see deferred infra).
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_REFRESH_COACH_LOOP`()
BEGIN
  -- 1. write last completed week's plan-vs-actual status back (so V_PLAN_LEARNINGS accumulates)
  CALL `onyga-482313.OI.SP_REVIEW_WEEKLY_PLAN`();
  -- 2. advance the probe decision budgets (start/accumulate/graduate/exhaust)
  CALL `onyga-482313.OI.SP_REFRESH_PROBE_LOG`();
END;
