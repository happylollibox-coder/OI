CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_APPEND_SEAT_REQUEST`()
OPTIONS (description = "Appends today's funded seat requests from FACT_PLAN_NEXT_WEEK into FACT_SEAT_REQUEST (orchestrator Task 20.8d, immediately after Task 20.8c builds the plan). §6.0 / plan step 5. THE PLAN PARTITION IS REPLACED EVERY NIGHT, so without this step a request made tonight is gone tomorrow and a window closing three weeks out has had every promise behind it overwritten. APPEND-THEN-PRUNE, exactly as SP_APPEND_KEYWORD_STATE_HISTORY: it INSERTs the whole day stamped with this run's captured_at, then prunes any requested_on carrying more than one captured_at down to its newest stamp, keyed on the LEDGER'S OWN duplicate stamps rather than on the dates the plan happens to carry, and running before the append as well as after — so a strand left on any date is repaired by any later call including a manual one. The failure mode points the safe way: a crash between the two statements leaves a duplicate, never a lost promise. Only rows that TOOK A SEAT are recorded — a row with no seat asked no question, and writing one would invent an intention the Brain never had. Both plan arms are kept (P-9). Guarded so a missing or empty plan is a no-op rather than an emptied partition. It decides nothing, writes nothing any other task consults, and can move no bid, budget or pause. Acceptance: scripts/bigquery/tests/SEAT_REQUEST_acceptance.sql. Spec: architecture/THREE_LAYERS.md §6.0.")
BEGIN
  DECLARE run_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE plan_day DATE;
  DECLARE n_rows INT64;

  -- GUARD 0: no ledger, no work. A missing table is a no-op, not an error, so a pass that runs
  -- before the migration cannot fail on it.
  IF NOT EXISTS (SELECT 1 FROM `onyga-482313.OI.INFORMATION_SCHEMA.TABLES`
                 WHERE table_name = 'FACT_SEAT_REQUEST') THEN
    RETURN;
  END IF;

  -- PRUNE FIRST. The invariant is "one requested_on holds exactly one captured_at, newest wins",
  -- and it is repaired on entry as well as exit so a strand left by a crash on ANY date is healed
  -- by ANY later call — including a manual one, which is the universal remedy the SOP offers.
  DELETE FROM `onyga-482313.OI.FACT_SEAT_REQUEST` t
  WHERE t.captured_at < (SELECT MAX(x.captured_at) FROM `onyga-482313.OI.FACT_SEAT_REQUEST` x
                         WHERE x.requested_on = t.requested_on);

  SET plan_day = (SELECT MAX(as_of) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`);

  -- GUARD 1: an absent or empty plan is a no-op. Never empty a partition because the source was
  -- not built — a lost promise cannot be recovered by any later run.
  IF plan_day IS NULL THEN RETURN; END IF;

  SET n_rows = (SELECT COUNT(*) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
                WHERE as_of = plan_day AND seat_no IS NOT NULL AND clicks_requested IS NOT NULL);
  IF n_rows = 0 THEN RETURN; END IF;

  -- GUARD 2: refuse to re-record a plan build this ledger already holds. The plan is rebuilt
  -- several times a night; each rebuild that produces the SAME day should refresh the day's stamp,
  -- which the prune below does. What must not happen is a day being written from a plan partition
  -- OLDER than one already recorded — that would move a promise backwards. Compared on the plan's
  -- own built_at rather than on the calendar, for the reason v27.145 records: several passes share
  -- one date, so a date-only test is blind inside the day it runs in.
  IF (SELECT MAX(built_at) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = plan_day)
     < (SELECT MAX(plan_built_at) FROM (
          SELECT SAFE_CAST(REGEXP_EXTRACT(source_detail, r'built_at=([0-9T:\-\.]+Z)') AS TIMESTAMP)
                 AS plan_built_at
          FROM `onyga-482313.OI.FACT_SEAT_REQUEST` WHERE requested_on = plan_day))
  THEN
    RETURN;
  END IF;

  INSERT INTO `onyga-482313.OI.FACT_SEAT_REQUEST` (
    requested_on, captured_at, source, source_detail,
    plan, is_live_plan, family, campaign_id, campaign_name, keyword_id, ad_group_id,
    target_text, match_type, channel, seat_no,
    clicks_requested, clicks_due_date, request_basis, expected_cpc, implied_daily_spend, window_days,
    campaign_current_budget, campaign_planned_budget,
    ladder_state, verdict, family_bar, ret_corrected, w_clk, w_ord, w_sp,
    current_bid, planned_bid, move, holdout)
  SELECT
    p.as_of, run_ts, 'ORCHESTRATOR',
    FORMAT('SP_APPEND_SEAT_REQUEST read FACT_PLAN_NEXT_WEEK as_of=%t built_at=%s (%d seats)',
           p.as_of,
           FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%E3SZ',
             (SELECT MAX(built_at) FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` WHERE as_of = plan_day),
             'UTC'),
           n_rows),
    p.plan, p.is_live_plan, p.family, p.campaign_id, p.campaign_name, p.keyword_id, p.ad_group_id,
    p.target_text, p.match_type, p.channel, p.seat_no,
    p.clicks_requested, p.clicks_due_date, p.request_basis, p.expected_cpc, p.implied_daily_spend,
    p.window_days, p.campaign_current_budget, p.campaign_planned_budget,
    p.ladder_state, p.verdict, p.family_bar, p.ret_corrected, p.w_clk, p.w_ord, p.w_sp,
    p.current_bid, p.planned_bid, p.move, p.holdout
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p
  WHERE p.as_of = plan_day
    -- ONLY A ROW THAT TOOK A SEAT ASKED A QUESTION. A row without one has no promise to keep.
    AND p.seat_no IS NOT NULL
    AND p.clicks_requested IS NOT NULL;

  -- PRUNE AGAIN: two passes on one requested_on leave exactly one copy, the newest.
  DELETE FROM `onyga-482313.OI.FACT_SEAT_REQUEST` t
  WHERE t.captured_at < (SELECT MAX(x.captured_at) FROM `onyga-482313.OI.FACT_SEAT_REQUEST` x
                         WHERE x.requested_on = t.requested_on);
END;
