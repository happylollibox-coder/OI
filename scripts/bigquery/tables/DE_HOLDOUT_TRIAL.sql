-- =============================================
-- DE_HOLDOUT_TRIAL — which holdout trial is live. Append-only registry, one row per event.
-- Spec: architecture/HOLDOUT.md §4, §9. Plan: docs/superpowers/plans/2026-10-03-holdout-restart.md
-- (§2.1, Task 2 Step 1).
--
-- WHY A REGISTRY. DE_HOLDOUT_ASSIGNMENT already carries trial_id, but a trial's status cannot live
-- on its rows: marking trial 1's 69 rows archived would be an UPDATE, and that table is append-only
-- (HOLDOUT.md §6 #1). So the status lives here, as events:
--   OPENED   — effective_on = gate_from, the first LA day the trial's arm blocks exports; the row
--              carries the trial's dates and design constants.
--   ARCHIVED — effective_on = the first LA day the trial no longer binds; note says why.
--
-- APPEND-ONLY. Never UPDATE, DELETE, MERGE ... WHEN MATCHED or CREATE OR REPLACE TABLE. A trial is
-- archived by appending a row. V_HOLDOUT_TRIAL reads the latest OPENED row per trial (by
-- recorded_at) and the earliest ARCHIVED effective_on.
--
-- A trial with no OPENED row is invisible to V_HOLDOUT_TRIAL and so to the gate (V_HOLDOUT_ARM).
-- Its rows are written by scripts/bigquery/migrations/2026-10-05_holdout_t2_registry_rows.sql,
-- before any reader switches to V_HOLDOUT_ARM (plan Task 8).
-- =============================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_HOLDOUT_TRIAL` (
  trial_id         STRING    NOT NULL,  -- = DE_HOLDOUT_ASSIGNMENT.trial_id
  event            STRING    NOT NULL,  -- 'OPENED' | 'ARCHIVED'
  effective_on     DATE      NOT NULL,  -- OPENED: gate_from, the LA day the arm starts to block exports; ARCHIVED: first LA day the trial no longer binds
  recorded_at      TIMESTAMP NOT NULL,
  seed             STRING,              -- OPENED: the seed its rows carry
  assigned_on      DATE,                -- OPENED: LA day of the founding insert
  win_start        DATE,                -- OPENED: = eligible_from of its rows (the estimate and R9 start here)
  win_end          DATE,                -- OPENED: = trial_end of its rows
  interim_look     DATE,                -- OPENED: the one-time safety look (HOLDOUT.md §8)
  first_readout    DATE,                -- OPENED: win_end + 14, never pulled forward
  t_mult           FLOAT64,             -- OPENED: the readout's band multiplier
  mde_ex_ante_14d  FLOAT64,             -- OPENED: the design's MDE per 14 days
  ruling           STRING,              -- who decided, when, in their words
  note             STRING               -- ARCHIVED: why, with the contamination numbers
)
OPTIONS (description = 'Which holdout trial is live, append-only: one row per event (OPENED / ARCHIVED). Never UPDATE or DELETE — a trial is archived by appending a row. Read by V_HOLDOUT_TRIAL. Spec: architecture/HOLDOUT.md §9; plan docs/superpowers/plans/2026-10-03-holdout-restart.md.');
