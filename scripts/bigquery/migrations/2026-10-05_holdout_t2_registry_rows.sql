-- =============================================
-- 2026-10-05 — holdout trial 2: the registry rows (plan docs/superpowers/plans/2026-10-03-holdout-restart.md,
-- Task 2 Step 3; deploy step 1 of Task 8). Runs AFTER scripts/bigquery/tables/DE_HOLDOUT_TRIAL.sql and
-- BEFORE the founding script (2026-10-05_holdout_t2_founding.sql, whose second ASSERT needs trial 2
-- registered as live) and before any reader switches to V_HOLDOUT_ARM.
--
-- Three rows:
--   trial 1 OPENED   — back-filled from the SP_ASSIGN_HOLDOUT v27.83 constants (seed, eligible_from
--                      2026-09-01, trial_end 2026-12-22) and V_HOLDOUT_READOUT's k (first_readout
--                      2027-01-05, t_mult 3.27, MDE 2261); interim look = eligible_from + 70.
--   trial 1 ARCHIVED — effective 2026-10-05 = trial 2's gate_from, so exactly one trial binds on any day.
--   trial 2 OPENED   — gate_from / assigned_on 2026-10-05, window 2026-10-06 .. 2027-01-26, interim
--                      2026-12-15, first readout 2027-02-09. Ori's OK of 2026-10-04 in his words.
--
-- APPEND-ONLY AND RE-RUNNABLE. Each row is inserted only when DE_HOLDOUT_TRIAL holds no row with the
-- same (trial_id, event), so a second run appends nothing. Nothing is updated or deleted.
-- Rehearsed on TMP_HT2_ copies 2026-10-04: first run appended 3 rows, second run appended 0.
-- =============================================
INSERT INTO `onyga-482313.OI.DE_HOLDOUT_TRIAL`
  (trial_id, event, effective_on, recorded_at, seed, assigned_on, win_start, win_end,
   interim_look, first_readout, t_mult, mde_ex_ante_14d, ruling, note)
SELECT r.trial_id, r.event, r.effective_on, CURRENT_TIMESTAMP(), r.seed, r.assigned_on, r.win_start,
       r.win_end, r.interim_look, r.first_readout, r.t_mult, r.mde_ex_ante_14d, r.ruling, r.note
FROM UNNEST(ARRAY<STRUCT<trial_id STRING, event STRING, effective_on DATE, seed STRING, assigned_on DATE,
  win_start DATE, win_end DATE, interim_look DATE, first_readout DATE, t_mult FLOAT64,
  mde_ex_ante_14d FLOAT64, ruling STRING, note STRING>>[
  ('HOLDOUT-2026Q4-CAMPAIGN', 'OPENED', DATE '2026-09-01', 'OI-HOLDOUT-v1|14',
   DATE '2026-08-19', DATE '2026-09-01', DATE '2026-12-22', DATE '2026-11-10', DATE '2027-01-05', 3.27, 2261.0,
   'Ori 2026-08-18: "start the holdout." (v27.83)',
   'Back-filled 2026-10-05 from the SP_ASSIGN_HOLDOUT v27.83 constants; the 69 rows are unchanged.'),
  ('HOLDOUT-2026Q4-CAMPAIGN', 'ARCHIVED', DATE '2026-10-05', NULL, NULL, NULL, NULL,
   NULL, NULL, NULL, NULL,
   'Ori 2026-10-03: the holdout trial restarts (option (c)); keep the old trial on record, archived, with its contamination stated.',
   'CONTAMINATED. Since the assignment on 2026-08-19, 10 of the 14 HOLDOUT campaigns changed on Amazon: 7 between the assignment and the window start (25 ledger rows: the 08-21 pauses of 135553284530895 and 39989090923480, the 08-23 reprice book on 279837860088128, 446868628489343 and 75834491759416, unlogged changes on 200171414843593 and 488973733209950) and 8 inside the window (25 observed rows, none logged, first days 2026-09-10 .. 2026-09-27, among them the two pauses Ori made himself on 2026-09-27, 75834491759416 and 76054744633802). R9 as built censors 61 of 69 units (13 of 14 HOLDOUT, 48 of 55 TREATED). No estimate was read. Arms bound 2026-09-01 .. 2026-10-04. The 69 rows stay in DE_HOLDOUT_ASSIGNMENT unchanged (fingerprint 7298956708089075507). Record: architecture/HOLDOUT.md §6.'),
  ('HOLDOUT-2026Q4-CAMPAIGN-T2', 'OPENED', DATE '2026-10-05', 'OI-HOLDOUT-v2|5',
   DATE '2026-10-05', DATE '2026-10-06', DATE '2027-01-26', DATE '2026-12-15', DATE '2027-02-09', 3.27, 2089.0,
   'Ori 2026-10-03: restart from 2026-10-06 with a fresh draw by the same method. List approved by Ori on 2026-10-04: "ok seed 5, deploy it".',
   NULL)]) r
WHERE NOT EXISTS (
  SELECT 1 FROM `onyga-482313.OI.DE_HOLDOUT_TRIAL` e
  WHERE e.trial_id = r.trial_id AND e.event = r.event);
