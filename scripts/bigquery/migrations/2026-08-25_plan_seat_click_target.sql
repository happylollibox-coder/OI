-- =============================================================================================
-- FACT_PLAN_NEXT_WEEK — the seat names its question. v27.146 (2026-08-25). Plan step 4.
--
-- VIOLATION 27: "a seat names no click target and no date, so no request can ever be graded."
-- §3.0 step 2 (Ori, 2026-08-25): the Brain must decide "what answers per keyword he is going to buy
-- with it (seats) and HOW MANY CLICKS he want to deliver in a SPECIFIC TIME WINDOW."
--
-- THE TABLE'S DDL IS `CREATE TABLE IF NOT EXISTS`, so editing the DDL file changes neither the live
-- columns nor the live description. Both must ship as an explicit ALTER here and be mirrored in
-- scripts/bigquery/tables/FACT_PLAN_NEXT_WEEK.sql.
--
-- NOTHING HERE IS AN ESTIMATE. The click target was always derivable and simply never written down
-- where anything could check it:
--
--   ORDINARY SEAT. seat_cost_per_day = (w_sp / window_days) * (planned_bid / current_bid), i.e.
--   last window's spend per day scaled by the price change. At the new price CPC scales by the SAME
--   ratio, so the ratio cancels:
--       clicks/day = seat_cost / CPC_new
--                  = [(w_sp/days) * (p/c)] / [CPC_old * (p/c)]
--                  = (w_sp/days) / CPC_old
--                  = w_clk / days
--   clicks_requested is therefore EXACTLY last window's clicks. An ordinary seat does not ask for
--   more clicks — it asks for THE SAME CLICKS AT A BETTER PRICE. That is worth saying plainly,
--   because a reader told only "the seat costs $0.93/day" cannot tell those two apart.
--
--   PROBE SEAT. seat_cost_per_day = seat_cpc * click_goal_day, and click_goal_day is already a
--   declared constant mirrored from V_FAMILY_SEAT_REGISTER. A PROBE HAS ALWAYS NAMED ITS QUESTION;
--   only the ordinary path was silent. Violation 27 is narrower than it was written.
--
-- expected_cpc is published beside them so the arithmetic can be re-derived by hand from the row
-- itself, without re-reading the view that produced it.
-- =============================================================================================

ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  ADD COLUMN IF NOT EXISTS clicks_requested   INT64
    OPTIONS (description = "§3.0 step 2 / violation 27. How many clicks this seat is buying over its window. EXACT, not estimated: an ordinary seat carries last window's clicks (w_clk), because the seat is that window's spend at a repaired price and the price ratio cancels; a probe carries click_goal_day x window_days from the seat register. NULL on every row that took no seat — a row with no seat asked no question."),
  ADD COLUMN IF NOT EXISTS clicks_due_date    DATE
    OPTIONS (description = "§3.0 step 2. The date by which those clicks were asked for — the end of the window the seat funds. A click count with no date cannot be graded, and 'soon' is not a date. NULL wherever clicks_requested is NULL."),
  ADD COLUMN IF NOT EXISTS expected_cpc       FLOAT64
    OPTIONS (description = "The price the seat expects to pay per click: seat_cost_per_day x window_days / clicks_requested. Published so the request re-derives from the row itself rather than from the view that produced it. For an ordinary seat this is last window's CPC scaled by the price change; for a probe it is the register's seat_cpc."),
  ADD COLUMN IF NOT EXISTS implied_daily_spend FLOAT64
    OPTIONS (description = "clicks_requested x expected_cpc / window_days — what this seat demands of its campaign's budget each day. Equal to seat_cost_per_day by construction; published separately because §3.0 step 3 asks whether the CAMPAIGN can carry the sum of these, and a check needs the number on the row rather than a derivation.");

-- A fifth column, added while writing the acceptance suite. The first cut tried to discriminate the
-- two derivations with `is_probe`, which lives on V_PLAN_WINDOW_JUDGMENT and NOT on this table — so
-- a grader reading the partition could not tell an exact click count from a declared goal. Rather
-- than copy a flag, the row now states HOW ITS OWN NUMBER WAS DERIVED, which is what a reader
-- actually needs and what makes the arithmetic checkable without the view.
ALTER TABLE `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
  ADD COLUMN IF NOT EXISTS request_basis STRING
    OPTIONS (description = "How clicks_requested was derived, so the row explains its own arithmetic. WINDOW_CLICKS = an ordinary seat asking for EXACTLY last window's clicks (w_clk) at a repaired price — the price ratio cancels, so this is arithmetic and not a forecast. PROBE_GOAL = a probe asking for click_goal_day x window_days from the seat register. NULL wherever no seat was taken.");
