-- =============================================
-- REPEAT_VETO_RUNS — is the "one-day" veto actually one day? (v27.98, 2026-08-21)
--
-- THE QUESTION IT ANSWERS, and it needs no experiment. The last-day veto (v27.75/v27.76) is
-- STATELESS by design: there is no "held since" flag, because the daily re-run IS the day-after
-- recheck. That design has one failure mode — a keyword whose filling day reads poorly most days
-- can be held again, and again, and the same one-day wait becomes a standing block wearing a
-- one-day costume. Nothing could ask this before, because a vetoed row was ERASED from
-- FACT_ENGINE_PROPOSALS instead of labelled. v27.98 labels it (hold_source / held_action /
-- held_bid, verdict EXCLUDE with the veto's own sentence), and labelling is what makes the
-- question a query.
--
-- THE UNIT IS CONSECUTIVE SNAPSHOTS, NOT CONSECUTIVE CALENDAR DAYS. The veto is re-decided once
-- per snapshot; a day on which the orchestrator did not run is not a day on which the veto
-- released. So the run index is built over the distinct snapshot dates that EXIST.
--
-- READ THE ARM. The two arms are not equally strong and a run means different things in each:
--   LAST_DAY_VETO_CUT   — a filling day already at/above the cut bar. Under-attribution can only
--                         make a day look WORSE, so this reading is conservative proof and a run
--                         here is the veto working: the cut keeps not being justified.
--   LAST_DAY_VETO_RAISE — a filling day reading poorly, and about half of at-volume rows read
--                         exactly 0.00x on a filling day. A LONG RUN HERE IS THE ALARM: it is the
--                         raise that never comes, on a keyword that is busy every day.
--
-- HOW TO READ THE RESULT: run 1 = the single day Ori specified, and needs no attention. Runs of 2
-- are ordinary (two poor days). A run that keeps growing on the RAISE arm is the defect the
-- stateless design was always exposed to, and the remedy is a release rule, not a longer wait.
-- =============================================
WITH days AS (
  -- dense index over the snapshots that actually exist, so a missed orchestrator run does not
  -- read as a released veto
  SELECT snapshot_date, DENSE_RANK() OVER (ORDER BY snapshot_date) AS d_ix
  FROM (SELECT DISTINCT snapshot_date FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS`)
),
held AS (
  SELECT p.snapshot_date, d.d_ix, p.engine, p.hold_source,
         p.campaign_id, p.campaign_name, COALESCE(p.keyword_id, '') AS keyword_id, p.target_text,
         p.held_action, p.held_bid, p.current_bid
  FROM `onyga-482313.OI.FACT_ENGINE_PROPOSALS` p
  JOIN days d USING (snapshot_date)
  WHERE p.hold_source IS NOT NULL
),
runs AS (
  -- the island trick: index minus rank is constant exactly while the snapshots are consecutive.
  -- The partition deliberately EXCLUDES hold_source — a keyword flipping between the raise and
  -- cut arms on consecutive days is still a keyword nothing has been allowed to do anything to.
  SELECT h.*,
    h.d_ix - ROW_NUMBER() OVER (
      PARTITION BY h.engine, h.campaign_id, h.keyword_id ORDER BY h.d_ix) AS run_key
  FROM held h
)
SELECT
  engine,
  campaign_name,
  target_text,
  keyword_id,
  MIN(snapshot_date)                                   AS run_start,
  MAX(snapshot_date)                                   AS run_end,
  COUNT(*)                                             AS consecutive_snapshots_held,
  STRING_AGG(DISTINCT hold_source ORDER BY hold_source) AS arms,
  MIN(current_bid)                                     AS bid_low,
  MAX(current_bid)                                     AS bid_high,
  MIN(held_bid)                                        AS held_bid_low,
  MAX(held_bid)                                        AS held_bid_high
FROM runs
GROUP BY engine, campaign_id, campaign_name, target_text, keyword_id, run_key
ORDER BY consecutive_snapshots_held DESC, run_start, engine, campaign_name;
