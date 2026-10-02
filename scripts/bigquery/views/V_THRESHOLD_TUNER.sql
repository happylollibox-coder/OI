-- =============================================
-- V_THRESHOLD_TUNER — scorecard verdicts become threshold proposals (2026-08-16, Task 3.2).
-- Spec: architecture/THRESHOLD_TUNER.md.
--
-- ADVISORY ONLY, by doctrine: the tuner PROPOSES; Ori PROMOTES (DE_COACH_THRESHOLDS carries a
-- suggestion channel — suggested_value / suggested_at / suggestion_reason — and the SQL engines
-- read only threshold_value). Promotion bar, non-negotiable: >= 20 graded changes per cell, and
-- a proposal must hold in TWO separate eras before it touches a rule (one bad fortnight must not
-- become doctrine) — the era split is published so the reader can check it.
--
-- write_target maps a proposal to a DE_COACH_THRESHOLDS key WHERE ONE EXISTS; the live keys are
-- coach-grain (WASTED_SPEND / PROFITABLE_ROAS / SCALE_UP_ROAS ... per strategy) while most
-- proposals here are LADDER-grain (step sizes), so most rows are ADVISORY_ONLY until a matching
-- key is added — stated per row, never silently. SP_WRITE_THRESHOLD_SUGGESTIONS writes ONLY
-- matched rows.
--
-- SIGNAL DISCOVERY (the task's second half — "when checking engine performance that will bring
-- more signals to check if the decision should be decided differently"): needs the signal panel
-- as-of change dates, which accumulates from 2026-08-16 (FACT_KEYWORD_STATE) and grades from
-- ~2026-08-29. The first question is queued in the SOP: did family context separate good raises
-- from bad. NOT computable yet — absent here, not faked.
--
-- HAND CHANGES ARE EVIDENCE, LABELLED AS ORI'S (Ori ruled 2026-10-02). The scorecard grades the
-- changes SP_RECORD_OBSERVED_CHANGES reads off the DIM SCD2 trail (source = 'OBSERVED': bid, state
-- and budget changes made by hand on Amazon). From 2026-10-01 to 10-02 they were held out of this
-- view pending that ruling; without them the tuner had no new evidence after 2026-08-24, the last
-- day OI's own tooling logged a change. They now count in every cell, and every cell says how many
-- of its graded changes were Ori's (era_split carries `hand H/N`, the proposal sentence names H), so
-- a proposal resting mostly on hand changes reads as such. The brief, the health board and the
-- engines' own clocks still leave them out; that was not part of the ruling.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_THRESHOLD_TUNER` AS
WITH graded AS (
  SELECT action_group, verdict, change_date, source,
    -- era split: two halves of the graded history, for the two-era promotion bar
    IF(change_date < DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 21 DAY), 'ERA_1', 'ERA_2') AS era,
    CASE WHEN ABS(COALESCE(pct_change, 0)) <= 7.5 THEN 'step ≤5%'
         WHEN ABS(COALESCE(pct_change, 0)) <= 12.5 THEN 'step ~10%'
         WHEN ABS(COALESCE(pct_change, 0)) <= 20 THEN 'step ~15%'
         ELSE 'step >20%' END AS step_bucket
  FROM `onyga-482313.OI.V_CHANGE_SCORECARD`
  WHERE verdict IS NOT NULL AND verdict != 'INSUFFICIENT'
),
cells AS (
  SELECT action_group, step_bucket,
    COUNT(*) AS n,
    ROUND(SAFE_DIVIDE(COUNTIF(verdict = 'CONFIRMED'), COUNT(*)), 2) AS confirm_rate,
    ROUND(SAFE_DIVIDE(COUNTIF(verdict = 'REVERSED'), COUNT(*)), 2) AS reversed_rate,
    -- the era split, published so the two-era bar is checkable at a glance
    CONCAT('era1 ', CAST(COUNTIF(era = 'ERA_1' AND verdict = 'REVERSED') AS STRING), '/',
           CAST(COUNTIF(era = 'ERA_1') AS STRING), ' rev · era2 ',
           CAST(COUNTIF(era = 'ERA_2' AND verdict = 'REVERSED') AS STRING), '/',
           CAST(COUNTIF(era = 'ERA_2') AS STRING),
           ' · hand ', CAST(COUNTIF(source = 'OBSERVED') AS STRING), '/', CAST(COUNT(*) AS STRING)) AS era_split,
    COUNTIF(source = 'OBSERVED') AS n_hand,
    IF(COUNTIF(source = 'OBSERVED') > 0,
       CONCAT(' (', CAST(COUNTIF(source = 'OBSERVED') AS STRING), " of them Ori's own changes on Amazon)"),
       '') AS hand_note
  FROM graded
  GROUP BY 1, 2
  HAVING COUNT(*) >= 20
),
proposals AS (
  SELECT
    CONCAT(action_group, ' @ ', step_bucket) AS scope,
    n, confirm_rate, reversed_rate, era_split,
    CASE
      WHEN reversed_rate > 0.40 THEN
        CONCAT('REVERSED at ', CAST(CAST(reversed_rate * 100 AS INT64) AS STRING), '% of ',
               CAST(n AS STRING), ' graded', hand_note, ' — propose the next-GENTLER step for this action class ',
               '(a false cut kills a winner forever; a false gentle step costs a day)')
      WHEN confirm_rate > 0.70 AND action_group IN ('BID_UP', 'BUDGET_UP') THEN
        CONCAT('CONFIRMED at ', CAST(CAST(confirm_rate * 100 AS INT64) AS STRING), '% of ',
               CAST(n AS STRING), ' graded raises', hand_note, ' — propose widening the raise gate one notch ',
               '(evidence says this raise class pays)')
      ELSE NULL END AS proposal,
    CAST(NULL AS STRING) AS write_target  -- no coach-grain key matches a ladder-step proposal yet
  FROM cells
)
SELECT scope, n, confirm_rate, reversed_rate, era_split, proposal,
       COALESCE(write_target, 'ADVISORY_ONLY — no DE_COACH_THRESHOLDS key at this grain') AS write_target
FROM proposals WHERE proposal IS NOT NULL
UNION ALL
-- the FIRST seeded suggestion, from a completed measurement (park calibration, 2026-08-12 study):
-- the OFF-only park shape measured +$2,020 vs the shipped shape. Static citation, not recomputed.
SELECT 'PARK calibration (measured study, 2026-08-12)', 0, NULL, NULL,
       'single study — needs its second era after the v27.45-v27.70 overhaul settles',
       'park re-verdict calibration measured the OFF-only shape at +$2,020 over the shipped shape; re-run the study after the August overhaul settles (~Sep 01), then promote or drop',
       'ADVISORY_ONLY — ladder-grain, no matching key';
