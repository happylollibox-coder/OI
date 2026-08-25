-- =============================================================================================
-- FACT_SEAT_REQUEST — the Brain's ledger of what it ASKED FOR. v27.147 (2026-08-25). Plan step 5.
-- Doctrine: architecture/THREE_LAYERS.md §6.0. Ruled by Ori 2026-08-25:
--   "Brain should also save his request and results and report if the catalog and pacing performed
--    like expected... by doing so we can examine what need to get better."
--
-- WHY IT MUST EXIST SEPARATELY FROM THE PLAN. Step 4 put the request on FACT_PLAN_NEXT_WEEK, and
-- that partition is DELETEd and rewritten every night. A request written tonight is gone tomorrow.
-- This is the same shape as the Catalog-memory problem (violation 6) and takes the same fix: an
-- append-only table that accumulates what a replaced table can only hold for a day. Without it,
-- §6.0's grading has nothing to grade against — by the time a window closes on 2026-09-08, every
-- partition that carried the promise has been overwritten thirteen times.
--
-- ONE ROW PER (requested_on, plan, campaign, keyword). The plan re-asks every night until the
-- verdict date, and each night's ask is kept rather than collapsed: an ask that KEEPS CHANGING is
-- itself a finding, and a ledger that silently overwrote yesterday's promise could not show it.
-- BOTH PLANS are recorded — the shadow plan is graded too (P-9), and grading only the live arm
-- would make the counterfactual unmeasurable, which is the whole point of running it.
--
-- IT CARRIES THE CATALOG CLAIM THE SEAT WAS BOUGHT ON. §6.0 grades the Catalog on whether its
-- recommendation performed as it said it would, and a verdict stripped of the claim behind it can
-- be counted but not graded — the same argument that made FACT_KEYWORD_STATE_HISTORY carry the
-- whole ladder row rather than a (date, subject, state) triple.
--
-- NOTHING READS IT YET and nothing here decides anything. It records what was already decided by
-- SP_BUILD_NEXT_WEEK_PLAN, and it can move no bid, budget or pause.
-- =============================================================================================

CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_SEAT_REQUEST`
(
  -- WHEN THE PROMISE WAS MADE
  requested_on        DATE    OPTIONS (description = "The plan's as_of — the day the Brain made this request. Partition key."),
  captured_at         TIMESTAMP OPTIONS (description = "When this row was written HERE, which is not when the Brain decided. Provenance, never a business date."),
  source              STRING  OPTIONS (description = "ORCHESTRATOR | MANUAL — how this row arrived."),
  source_detail       STRING  OPTIONS (description = "Exactly what was read and when, so any row can be re-derived."),

  -- WHOSE PROMISE
  plan                STRING  OPTIONS (description = "A or B. Both are recorded — the shadow plan is graded too (P-9)."),
  is_live_plan        BOOL    OPTIONS (description = "Whether this plan arm was the live one on the night it was written."),
  family              STRING,
  campaign_id         STRING,
  campaign_name       STRING,
  keyword_id          STRING,
  ad_group_id         STRING,
  target_text         STRING,
  match_type          STRING,
  channel             STRING,
  seat_no             INT64   OPTIONS (description = "The numbered, dollar-sized seat this request occupies."),

  -- THE QUESTION (§3.0 step 2) — a click count and a date, which is the only form that can be graded
  clicks_requested    INT64   OPTIONS (description = "How many clicks this seat is buying. EXACT: an ordinary seat asks for last window's clicks at a repaired price; a probe asks click_goal_day x window_days."),
  clicks_due_date     DATE    OPTIONS (description = "The date they are due — the seat's own verdict_date (P-12). NOT the judged window's end, which is in the past."),
  request_basis       STRING  OPTIONS (description = "WINDOW_CLICKS or PROBE_GOAL — how clicks_requested was derived, so the row explains its own arithmetic."),
  expected_cpc        FLOAT64 OPTIONS (description = "The price the seat expects to pay per click."),
  implied_daily_spend FLOAT64 OPTIONS (description = "What this seat demands of its campaign's budget each day."),
  window_days         INT64,

  -- WHICH CAMPAIGN MUST CARRY IT (§3.0 step 3) — so a grader can ask whether it could
  campaign_current_budget FLOAT64,
  campaign_planned_budget FLOAT64,

  -- THE CATALOG CLAIM IT WAS BOUGHT ON (§6.0) — without this the Catalog cannot be graded
  ladder_state        STRING  OPTIONS (description = "The Catalog's verdict on the night the seat was funded."),
  verdict             STRING  OPTIONS (description = "The Brain's own window verdict that made this a candidate."),
  family_bar          FLOAT64 OPTIONS (description = "The bar the claim was measured against."),
  ret_corrected       FLOAT64 OPTIONS (description = "The window return the seat was bought on, settle-corrected. THE CLAIM."),
  w_clk               INT64   OPTIONS (description = "Clicks in the judged window — the evidence the ask was sized from."),
  w_ord               INT64,
  w_sp                FLOAT64,

  -- THE PRICE THE SEAT WAS FUNDED AT
  current_bid         FLOAT64,
  planned_bid         FLOAT64,
  move                STRING,
  holdout             BOOL    OPTIONS (description = "A holdout campaign's request is recorded and never acted on — the counterfactual has to be gradeable too.")
)
PARTITION BY requested_on
CLUSTER BY keyword_id, campaign_id, plan, family
OPTIONS (description = "The Brain's ledger of what it ASKED FOR — architecture/THREE_LAYERS.md §6.0, ruled by Ori 2026-08-25. Append-only, one row per (requested_on, plan, campaign, keyword), written by SP_APPEND_SEAT_REQUEST at orchestrator Task 20.8d. EXISTS BECAUSE FACT_PLAN_NEXT_WEEK IS REPLACED NIGHTLY: step 4 put the click target on the plan partition, and that partition is deleted and rewritten every pass, so a request made tonight is gone tomorrow and a window closing on 2026-09-08 would have had every promise behind it overwritten thirteen times. Same shape as violation 6, same fix. Each night's ask is KEPT rather than collapsed, because an ask that keeps changing is itself a finding. Carries the Catalog claim the seat was bought on, because §6.0 grades the Catalog on whether its recommendation performed as claimed and a verdict stripped of its evidence can be counted but not graded. Both plan arms are recorded — grading only the live one would make the shadow plan's counterfactual unmeasurable. NOTHING READS IT YET; it records what SP_BUILD_NEXT_WEEK_PLAN already decided and can move no bid, budget or pause. Acceptance: scripts/bigquery/tests/SEAT_REQUEST_acceptance.sql.");
