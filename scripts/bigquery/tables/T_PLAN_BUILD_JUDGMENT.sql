-- =============================================================================================
-- T_PLAN_BUILD_JUDGMENT — v27.171 (2026-10-03): the judgement each plan night was built on, saved by
-- SP_BUILD_NEXT_WEEK_PLAN with the night (learning-contract piece 2, Task 3 follow-up 2; Ori's ruling
-- D2 (c) of 2026-10-03).
--
-- WHY IT EXISTS. FACT_PLAN_NEXT_WEEK_acceptance.sql C13 asserts that the live plan reproduces the
-- judgement row for row (side, verdict, candidacy). Until v27.170 it compared the latest night with
-- the LIVE V_PLAN_WINDOW_JUDGMENT, which was sound while the 07:35 and 16:00 UTC passes rewrote the
-- night on the view's current window. The freeze (v27.170) stops those rewrites: a night is now
-- written by the 05:00 UTC pass, on the Los Angeles day before its as_of, on a window ending three
-- days before as_of, and at Los Angeles midnight the view's fence moves a day while the night stays.
-- On the 2026-10-03 night (BigQuery time travel) the 05:36:35 UTC write and the 16:34:13 UTC write
-- differ on 47 of 356 live rows in side, verdict or is_candidate, with the same row population (job
-- bqjob_r56dc7b535d3baa1b_000001a102f2de7b_1). So C13 against the view could pass only between the
-- night's write and Los Angeles midnight. C13 now reads this table: the judgement the night was
-- actually built on, whatever hour the check runs.
--
-- GRAIN. One row per (as_of, campaign_id, keyword_id): the builder's one read of the judgement view
-- (its temp table `j`), as_of the night, built_at the night's built_at (the same value as the plan
-- rows of that write, MAX(built_at) of the builder's `final`). Only the columns C13 compares are kept
-- (side_b, verdict, is_candidate, window_from, window_to, calendar_state) — named, not SELECT *, so a
-- column added to the view never breaks the builder's INSERT.
--
-- WRITTEN WITH THE NIGHT. SP_BUILD_NEXT_WEEK_PLAN v27.171 DELETEs this table's as_of partition and
-- INSERTs it right after it writes the plan partition, past both freeze readings and R11's guard: a
-- frozen pass, a refused rewrite or a failed assertion writes neither. A night rewritten before its
-- Los Angeles midnight rewrites both. Nights written before v27.171 have no row here, and C13 reads
-- them as "not on record" (1).
--
-- ACCUMULATES: CREATE TABLE IF NOT EXISTS, never replaced — replacing it erases the record C13 reads.
-- Partitioned by as_of: the builder deletes and C13 reads by it.
--
-- Written by:  SP_BUILD_NEXT_WEEK_PLAN (orchestrator Task 20.8c), v27.171 on
-- Read by:     scripts/bigquery/tests/FACT_PLAN_NEXT_WEEK_acceptance.sql (C13) and its control
--              harnesses (check_plan_clock_controls.py, check_plan_seat_controls.py,
--              check_plan_money_controls.py: --build-judge-table)
-- SOP:         architecture/LEARNING.md §1 "The freeze"; architecture/NEXT_WEEK_MONEY.md §3
-- =============================================================================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.T_PLAN_BUILD_JUDGMENT` (
  as_of           DATE      NOT NULL,  -- the night (FACT_PLAN_NEXT_WEEK.as_of, the New York date)
  built_at        TIMESTAMP NOT NULL,  -- the night's built_at: the plan rows of the same write carry it
  builder_version STRING,              -- the SP_BUILD_NEXT_WEEK_PLAN version that saved it
  campaign_id     STRING,              -- V_PLAN_WINDOW_JUDGMENT.campaign_id
  keyword_id      STRING,              -- V_PLAN_WINDOW_JUDGMENT.keyword_id
  side_b          STRING,              -- rule B's side, as the judge published it
  verdict         STRING,              -- the judge's verdict
  is_candidate    BOOL,                -- the judge's candidacy
  window_from     DATE,                -- the window the judge read
  window_to       DATE,
  calendar_state  STRING               -- the calendar state the judge read
)
PARTITION BY as_of
CLUSTER BY campaign_id, keyword_id
OPTIONS (description = "v27.171 (2026-10-03, learning piece 2 Task 3 follow-up 2, ruling D2 (c)): the judgement each plan night was built on -- one row per (as_of, campaign_id, keyword_id) of SP_BUILD_NEXT_WEEK_PLAN's one read of V_PLAN_WINDOW_JUDGMENT (its temp table j), with the night's as_of and built_at (the plan rows of the same write carry that built_at) and the columns FACT_PLAN_NEXT_WEEK_acceptance C13 compares: side_b, verdict, is_candidate, window_from, window_to, calendar_state. Written by the builder right after the plan partition (DELETE + INSERT of the as_of partition), past both freeze readings and R11's guard, so a frozen, refused or failed pass writes neither. Under the freeze a night is written by the 05:00 UTC pass on a window ending as_of - 3, and the live view's fence moves at Los Angeles midnight; C13 reads this table so it compares the night with the judgement it was built on at any hour. Nights written before v27.171 have no row. ACCUMULATES: CREATE TABLE IF NOT EXISTS, never replaced. SOP: architecture/LEARNING.md 1 'The freeze'.");
