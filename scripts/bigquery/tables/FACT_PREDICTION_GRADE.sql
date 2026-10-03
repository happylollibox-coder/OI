-- =============================================================================================
-- FACT_PREDICTION_GRADE — v27.173 (2026-10-03, learning-contract piece 2, Task 5): one row per
-- graded ledger row of V_PREDICTION_LEDGER (one scenario of one prediction; a prediction is a plan
-- row) set against what happened over its horizon once that horizon has settled.
--
-- WRITTEN ONLY BY SP_GRADE_PREDICTIONS, and only by INSERT. APPEND-ONLY: never updated, never
-- deleted from (house rule for FACT_ tables). A prediction is graded once: the grader inserts a
-- row only for a ledger row with no grade (NOT EXISTS on the key), so a second run inserts
-- nothing. Outcomes restate for days after; a grade moves only under an explicit
-- SP_GRADE_PREDICTIONS(regrade_from, reason) call, which APPENDS a new row per prediction of the
-- nights as_of >= regrade_from, with regrade_seq one higher and regrade_reason = reason. The
-- CURRENT grade of a prediction is its row with the highest regrade_seq; the first grade is 0.
--
-- KEY: (predictor, variant, as_of, campaign_id, keyword_id, scenario, regrade_seq).
--
-- FROZEN COPIES. The five predicted numbers, pred_side, built_at and the plan's ask (bids, budgets,
-- move) are copied from the ledger at grading, so a grade can be read without re-running the view
-- and the contract suite (Task 7) fails if a graded ledger row ever reads differently from its copy.
--
-- THE COLUMNS (architecture/LEARNING.md §4 says how each is decided):
--   the ledger's copy     family .. move, horizon_from/to, built_at, builder_version, rule_version,
--                         response_model_version, basis_*, alloc_spend, pred_*, act_is_noop
--   which scenario        applied_scenario (ACT | DO_NOTHING | OTHER_ACTION, the same on both rows
--                         of a plan row), is_applied (this row's scenario is the applied one; FALSE
--                         on both rows of an OTHER_ACTION), matched_change_ids / other_change_ids
--                         (V_PPC_CHANGE_LOG_LANDED change_id), placement_changed with its two
--                         readings placement_m_from / placement_m_to (the keyword-state history's
--                         m_effective on or before as_of and on or before horizon_to)
--   what happened         real_clicks, real_spend, real_orders, real_gp, real_net over horizon_from
--                         .. horizon_to from FACT_AMAZON_ADS as read at graded_at (no row = 0),
--                         real_side (the judge's test), side_correct
--   the grade             err_net = pred_net - real_net, abs_err_net, click_bucket (realised clicks:
--                         0, 1-5, 6-10, 11-20, 21-40, 41-80, 81+), min_clicks_at_grade (the
--                         minimum-investment line in force when the row was graded; NULL = none),
--                         grade (RIGHT | WRONG | INCONCLUSIVE | UNGRADABLE), ungradable_reason
--                         (KEYWORD_ARCHIVED | CAMPAIGN_ARCHIVED)
--   the run               graded_at, watermark (the house watermark the run used:
--                         LEAST(MAX(FACT_AMAZON_ADS.date), FN_ADS_ANCHOR_CAP())), grader_version,
--                         regrade_reason
--
-- Partitioned by as_of (the night), clustered by predictor, family (the report card's grouping).
-- CREATE TABLE IF NOT EXISTS: re-running this file never drops a grade. A column added later is
-- ALTER TABLE ADD COLUMN IF NOT EXISTS, one per statement, mirrored here.
--
-- Written by:  SP_GRADE_PREDICTIONS (orchestrator Task 20.8f from piece-2 Task 6)
-- Read by:     SP_GRADE_PREDICTIONS (current grades, the minimum-investment curve, the report card
--              T_PREDICTION_SCORECARD); V_ENGINE_HEALTH prediction_grades_fresh (Task 6);
--              scripts/bigquery/tests/PREDICTION_CONTRACT_acceptance.sql (Task 7)
-- Spec:        docs/superpowers/specs/2026-10-01-learning-contract-design.md §7, §11
-- SOP:         architecture/LEARNING.md §4, §10 "Task 5"
-- =============================================================================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.FACT_PREDICTION_GRADE` (
  -- the key
  predictor               STRING    NOT NULL,  -- 'PLAN_A' | 'PLAN_B' (later any engine; 'FIXTURE' = contract fixtures)
  variant                 STRING    NOT NULL,  -- plan: the letter
  as_of                   DATE      NOT NULL,  -- the night the prediction was made
  campaign_id             STRING    NOT NULL,
  keyword_id              STRING    NOT NULL,
  scenario                STRING    NOT NULL,  -- DO_NOTHING | ACT
  regrade_seq             INT64     NOT NULL,  -- 0 = first grade; +1 per regrade_from run
  -- the ledger's copy, frozen at grading
  family                  STRING,
  channel                 STRING,
  calendar_state          STRING,
  window_days             INT64,
  is_live_plan            BOOL,
  holdout                 BOOL,
  family_bar              FLOAT64,
  min_orders              INT64,
  move                    STRING,              -- ACT rows only (the ledger's)
  current_bid             FLOAT64,
  planned_bid             FLOAT64,
  campaign_current_budget FLOAT64,
  campaign_planned_budget FLOAT64,
  horizon_from            DATE,
  horizon_to              DATE,
  built_at                TIMESTAMP,
  builder_version         STRING,
  rule_version            STRING,
  response_model_version  STRING,
  basis_clicks            INT64,
  basis_spend             FLOAT64,
  alloc_spend             FLOAT64,
  act_is_noop             BOOL,
  pred_clicks             FLOAT64,
  pred_spend              FLOAT64,
  pred_orders             FLOAT64,
  pred_gp                 FLOAT64,
  pred_net                FLOAT64,
  pred_side               INT64,
  -- which scenario applied
  applied_scenario        STRING,              -- ACT | DO_NOTHING | OTHER_ACTION
  is_applied              BOOL,
  matched_change_ids      ARRAY<STRING>,
  other_change_ids        ARRAY<STRING>,
  placement_changed       BOOL,                -- placement_m_to differs from placement_m_from beyond 1e-6; NULL when either is NULL
  placement_m_from        FLOAT64,             -- FACT_KEYWORD_STATE_HISTORY.m_effective, latest snapshot on or before as_of
  placement_m_to          FLOAT64,             -- the same, latest snapshot on or before horizon_to
  -- what happened
  real_clicks             INT64,
  real_spend              FLOAT64,
  real_orders             INT64,
  real_gp                 FLOAT64,
  real_net                FLOAT64,
  real_side               INT64,
  side_correct            BOOL,
  -- the grade
  err_net                 FLOAT64,
  abs_err_net             FLOAT64,
  click_bucket            STRING,
  min_clicks_at_grade     INT64,
  grade                   STRING,              -- RIGHT | WRONG | INCONCLUSIVE | UNGRADABLE
  ungradable_reason       STRING,
  -- the run
  graded_at               TIMESTAMP,
  watermark               DATE,
  grader_version          STRING,
  regrade_reason          STRING
)
PARTITION BY as_of
CLUSTER BY predictor, family
OPTIONS (description = "v27.173 (2026-10-03, learning-contract piece 2 Task 5): one row per graded ledger row of V_PREDICTION_LEDGER (one scenario of one prediction; a prediction is a plan row), written by SP_GRADE_PREDICTIONS once the row's horizon_to + SETTLE_HORIZON_DAYS is at or before the house watermark LEAST(MAX(FACT_AMAZON_ADS.date), FN_ADS_ANCHOR_CAP()). Carries frozen copies of the ledger row (the five predicted numbers, pred_side, built_at, rule_version, the plan's ask), the scenario that applied (from V_PPC_CHANGE_LOG_LANDED: ACT, DO_NOTHING or OTHER_ACTION; is_applied on the matching row), the realised clicks, spend, orders, gross profit and net over horizon_from..horizon_to from FACT_AMAZON_ADS (no row = 0), the realised side (the judge's test: orders >= min_orders and gross profit per ad dollar >= family_bar), the net error, the click bucket, the minimum-investment line in force (min_clicks_at_grade) and the label RIGHT / WRONG / INCONCLUSIVE / UNGRADABLE (UNGRADABLE only for a keyword or campaign archived within the horizon). APPEND-ONLY, never updated or deleted from: a prediction is graded once; SP_GRADE_PREDICTIONS(regrade_from, reason) appends a re-grade of the nights as_of >= regrade_from with regrade_seq + 1. The current grade is the highest regrade_seq. Partitioned by as_of, clustered by predictor, family. SOP: architecture/LEARNING.md 4.");
