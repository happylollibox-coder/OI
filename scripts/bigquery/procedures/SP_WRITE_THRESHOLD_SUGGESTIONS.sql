-- =============================================
-- SP_WRITE_THRESHOLD_SUGGESTIONS — the tuner's write half (2026-08-16, Task 3.2).
-- Spec: architecture/THRESHOLD_TUNER.md.
--
-- Writes V_THRESHOLD_TUNER proposals into DE_COACH_THRESHOLDS' suggestion channel
-- (suggested_value / suggested_at / suggestion_reason) — ONLY rows whose write_target names a
-- real threshold_key. The engines read threshold_value alone, so nothing changes behavior until
-- Ori promotes a suggestion by hand. TODAY every proposal is ladder-grain (ADVISORY_ONLY — the
-- live keys are coach-grain), so this SP is a deliberate no-op that exists so the pipe is
-- plumbed the day a matching key is added; it logs its affected-row count either way.
-- NOT in the orchestrator: suggestion-writing is a weekly deliberate act, not a daily reflex —
-- run it by hand alongside the weekly review until the cadence earns automation.
-- =============================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_WRITE_THRESHOLD_SUGGESTIONS`()
OPTIONS (
  description = "Tuner write-half (Task 3.2, 2026-08-16): copies V_THRESHOLD_TUNER proposals whose write_target names a real DE_COACH_THRESHOLDS key into that row's suggestion channel (suggested_value/suggested_at/suggestion_reason). Engines read threshold_value only — Ori promotes by hand. Currently a deliberate no-op (all proposals ladder-grain, ADVISORY_ONLY). Run by hand at the weekly review, not scheduled. Spec: architecture/THRESHOLD_TUNER.md."
)
BEGIN
  UPDATE `onyga-482313.OI.DE_COACH_THRESHOLDS` t
  SET t.suggested_at = CURRENT_DATETIME('America/Los_Angeles'),
      t.suggestion_reason = p.proposal
  FROM `onyga-482313.OI.V_THRESHOLD_TUNER` p
  WHERE p.write_target = t.threshold_key;  -- matches nothing while every row is ADVISORY_ONLY

  SELECT CONCAT('SP_WRITE_THRESHOLD_SUGGESTIONS: ', CAST(@@row_count AS STRING),
                ' suggestion(s) written (ADVISORY_ONLY rows are never written)') AS log_message;
END;
