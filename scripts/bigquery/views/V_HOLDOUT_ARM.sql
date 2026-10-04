-- =============================================
-- V_HOLDOUT_ARM — the gate: one row per HOLDOUT campaign whose arm binds today or later, any trial.
-- Spec: architecture/HOLDOUT.md §4. Plan: docs/superpowers/plans/2026-10-03-holdout-restart.md
-- (§2.1, Task 2 Step 2).
--
-- Every reader that keeps the engine off a control reads this view, never DE_HOLDOUT_ASSIGNMENT
-- directly (plan §1, Task 5). The gate readers test CURRENT_DATE('America/Los_Angeles') >= gate_from
-- (and <= gate_to where they need it).
--
-- MIN(gate_from) / MAX(gate_to) per campaign: one trial's gate_to is the day before the next one's
-- gate_from (trial 1 archived from 2026-10-05 = trial 2's gate_from), so a campaign that is a
-- control in both trials has one unbroken interval. trial_id is the trial with the latest gate_from.
-- A trial with no OPENED row in DE_HOLDOUT_TRIAL is not in V_HOLDOUT_TRIAL, so its controls are not
-- here.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_HOLDOUT_ARM` AS
-- one row per HOLDOUT campaign whose arm binds today or later, any trial. The gate readers test
-- CURRENT_DATE('America/Los_Angeles') >= gate_from (and <= gate_to where they need it).
SELECT a.unit_id AS campaign_id,
       MIN(t.gate_from) AS gate_from,
       MAX(t.gate_to)   AS gate_to,
       ARRAY_AGG(a.trial_id ORDER BY t.gate_from DESC LIMIT 1)[OFFSET(0)] AS trial_id
FROM `onyga-482313.OI.DE_HOLDOUT_ASSIGNMENT` a
JOIN `onyga-482313.OI.V_HOLDOUT_TRIAL` t USING (trial_id)
WHERE a.unit_type = 'CAMPAIGN' AND a.arm = 'HOLDOUT'
  AND CURRENT_DATE('America/Los_Angeles') <= t.gate_to
GROUP BY 1;
