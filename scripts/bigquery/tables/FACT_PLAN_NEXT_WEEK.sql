-- =============================================================================================
-- FACT_PLAN_NEXT_WEEK — v27.133 (2026-08-23): the nightly plan for the working families, ONE ROW
-- PER (as_of, plan, campaign_id, keyword_id). Two plans are written every night (spec P-9):
--   plan 'B'  the LIVE plan — the window decides the side and the amount (rule B).
--   plan 'A'  the SHADOW plan — the ladder decides the side, the window decides the amount.
-- Nothing is ever deleted except today's own partition, which the builder rewrites when it re-runs
-- (idempotent on one pass). History is the scorecard's evidence and the P-14b guard's memory of
-- what the plan said last night.
--
-- Written by SP_BUILD_NEXT_WEEK_PLAN (orchestrator Task 20.8c, Task 2 of the plan). Read by
-- V_PLAN_WINDOW_JUDGMENT (last night's side, for P-14b), SP_SNAPSHOT_ENGINE_PROPOSALS (the PLAN
-- engine's rows), V_PLAN_SCORECARD (T+14 grading), tools/build_plan_bulksheet.py and the surfaces.
--
-- The table is created EMPTY here, by Task 1, because the judgement view reads it for the P-14b
-- guard and must not wait for the builder: on the first nights the prior-side read is empty by
-- design and the guard falls back to the declared bootstrap (the ladder's settled record).
-- CREATE TABLE IF NOT EXISTS — re-running this file can never drop a written plan.
-- Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md §4, §5, P-9, P-14.
-- SOP: architecture/NEXT_WEEK_MONEY.md §2.
-- =============================================================================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_PLAN_NEXT_WEEK`
(
  as_of                      DATE    NOT NULL,
  plan                       STRING  NOT NULL,
  is_live_plan               BOOL    NOT NULL,
  family                     STRING,
  book                       STRING,
  campaign_id                STRING,
  campaign_name              STRING,
  keyword_id                 STRING,
  ad_group_id                STRING,
  target_text                STRING,
  match_type                 STRING,
  channel                    STRING,
  is_auto                    BOOL,
  is_pt                      BOOL,
  calendar_state             STRING,
  window_days                INT64,
  window_from                DATE,
  window_to                  DATE,
  watermark                  DATE,
  w_clk                      INT64,
  w_ord                      INT64,
  w_sp                       FLOAT64,
  w_gp                       FLOAT64,
  w_gp_corrected             FLOAT64,
  settle_factor_min          FLOAT64,
  settle_factor_eff          FLOAT64,
  settle_curve_available     BOOL,
  settled                    BOOL,
  settle_due_on              DATE,
  settle_arm                 STRING,
  decided_by                 STRING,
  was_good                   BOOL,
  family_bar                 FLOAT64,
  ret_raw                    FLOAT64,
  ret_corrected              FLOAT64,
  ladder_state               STRING,
  side                       STRING,
  verdict                    STRING,
  is_candidate               BOOL,
  rank_score                 FLOAT64,
  rank_no                    INT64,
  seat_no                    INT64,
  seat_cost_per_day          FLOAT64,
  current_bid                FLOAT64,
  planned_bid                FLOAT64,
  bid_floor                  FLOAT64,
  move                       STRING,
  planned_spend_per_day      FLOAT64,
  verdict_date               DATE,
  pot_per_day                FLOAT64,
  allowance_target_per_day   FLOAT64,
  allowance_ramped_per_day   FLOAT64,
  notgood_today_per_day      FLOAT64,
  ramp_step                  INT64,
  ramp_steps                 INT64,
  allowance_share            FLOAT64,
  campaign_planned_budget    FLOAT64,
  campaign_current_budget    FLOAT64,
  holdout                    BOOL,
  holdout_eligible_from      DATE,
  sentence                   STRING,
  built_at                   TIMESTAMP
)
PARTITION BY as_of
CLUSTER BY plan, family, campaign_id
OPTIONS (description = "v27.133 (2026-08-23) the next-week money plan, one row per (as_of, plan, campaign, keyword) for the working families (HARVEST book). Two plans every night: 'B' is live (the window decides the side and the amount, rule B) and 'A' is shadow (the ladder decides the side, the window decides the amount) — spec P-9. Carries the window and its record raw AND corrected for settle completion, the arm that decided the side (settle_arm / decided_by, spec P-14), the family's pot / allowance / ramp step, the seat number and seat cost, the planned price and the executable move, the campaign budget the plan implies, and the plain sentence a person reads. Append-only; the builder rewrites only today's partition. Created empty by Task 1 because V_PLAN_WINDOW_JUDGMENT reads last night's side for the P-14b guard; written by SP_BUILD_NEXT_WEEK_PLAN (orchestrator 20.8c); read by SP_SNAPSHOT_ENGINE_PROPOSALS, V_PLAN_SCORECARD, tools/build_plan_bulksheet.py and T_PLAN_NEXT_WEEK. Spec: docs/superpowers/specs/2026-08-23-next-week-money-plan-design.md. SOP: architecture/NEXT_WEEK_MONEY.md");
