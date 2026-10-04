-- =============================================
-- V_HOLDOUT_TRIAL — one row per holdout trial, read from the append-only registry DE_HOLDOUT_TRIAL.
-- Spec: architecture/HOLDOUT.md §4, §9. Plan: docs/superpowers/plans/2026-10-03-holdout-restart.md
-- (§2.1, Task 2 Step 2).
--
-- COLUMNS (beyond the OPENED row's own):
--   gate_from    = the OPENED row's effective_on: the first LA day the arm blocks exports.
--   gate_to      = LEAST(win_end, archived_from - 1): the last LA day the arm binds.
--   archived_from / archive_note = the earliest ARCHIVED event, if any.
--   is_live      = not archived as of today (LA). Readers that need ONE trial (the readout, c33,
--                  SP_ASSIGN_HOLDOUT) take the live row and break ties on the newest assigned_on.
--   status_today = ARCHIVED | ASSIGNED (before gate_from) | RUNNING (to win_end) | SETTLING (to
--                  first_readout) | READ_OUT.
--
-- A trial with no OPENED row does not appear here, so it is invisible to V_HOLDOUT_ARM.
-- An empty registry empties this view and the gate.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_HOLDOUT_TRIAL` AS
WITH
opened AS (
  SELECT * FROM `onyga-482313.OI.DE_HOLDOUT_TRIAL` WHERE event = 'OPENED'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY trial_id ORDER BY recorded_at DESC) = 1),
archived AS (
  SELECT trial_id, MIN(effective_on) AS archived_from,
         ARRAY_AGG(note ORDER BY recorded_at LIMIT 1)[OFFSET(0)] AS archive_note
  FROM `onyga-482313.OI.DE_HOLDOUT_TRIAL` WHERE event = 'ARCHIVED' GROUP BY 1),
today AS (SELECT CURRENT_DATE('America/Los_Angeles') AS d)
SELECT o.trial_id, o.seed, o.assigned_on, o.win_start, o.win_end, o.interim_look, o.first_readout,
       o.t_mult, o.mde_ex_ante_14d, o.ruling,
       o.effective_on AS gate_from,
       IF(a.archived_from IS NULL, o.win_end,
          LEAST(o.win_end, DATE_SUB(a.archived_from, INTERVAL 1 DAY))) AS gate_to,
       a.archived_from, a.archive_note,
       (a.archived_from IS NULL OR t.d < a.archived_from) AS is_live,
       CASE WHEN a.archived_from IS NOT NULL AND t.d >= a.archived_from THEN 'ARCHIVED'
            WHEN t.d < o.effective_on   THEN 'ASSIGNED'
            WHEN t.d <= o.win_end       THEN 'RUNNING'
            WHEN t.d < o.first_readout  THEN 'SETTLING'
            ELSE 'READ_OUT' END AS status_today
FROM opened o
LEFT JOIN archived a USING (trial_id)
CROSS JOIN today t;
