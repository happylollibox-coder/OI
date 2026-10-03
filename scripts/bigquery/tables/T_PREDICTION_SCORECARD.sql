-- =============================================================================================
-- T_PREDICTION_SCORECARD — v27.173 (2026-10-03, learning-contract piece 2, Task 5): the report
-- card of the plan's predictions. REBUILT, never accumulated: SP_GRADE_PREDICTIONS replaces it
-- (CREATE OR REPLACE TABLE, the same columns in the same order as below) at the end of every run,
-- from the current grades of FACT_PREDICTION_GRADE (the highest regrade_seq of each prediction;
-- predictor 'FIXTURE' excluded) and, for YOUNG and NEXT_WEEK, from V_PREDICTION_LEDGER.
-- This file creates it empty (CREATE TABLE IF NOT EXISTS) so its readers can compile before the
-- grader's first run. A column added here is added to the procedure's final SELECT in the same
-- position; architecture/LEARNING.md §10 "Task 5" prints the query that compares the two.
--
-- GRAIN: predictor x variant x family x calendar_state x level x row_type (+ scenario on ACCURACY
-- rows, + bucket on CURVE rows, + the week on WINDOW rows). family = 'ALL' and calendar_state =
-- 'ALL' are the predictor's rollup (ACCURACY, MONEY, HONESTY, YOUNG, NEXT_WEEK); CURVE and LINE are
-- per family x calendar_state only, the grain the minimum-investment line is set on.
-- LEVELS: WINDOW (one Sunday-start week of as_of, the house week WEEK(SUNDAY), pooling every graded
-- night in it), TRAILING_3 (the group's three most recent graded windows), SINCE_START; YOUNG is
-- SINCE_START; NEXT_WEEK is TONIGHT (the latest night of the ledger).
-- An UNGRADABLE row is counted on HONESTY rows and enters no other aggregate.
--
-- ROW TYPES (architecture/LEARNING.md §5):
--   ACCURACY   scenario APPLIED (the scenario that applied, is_applied), DO_NOTHING or ACT (every
--              graded row of that scenario, applied or not: accuracy only): n_rows, keywords, the
--              predicted and realised sums, mae_net_usd = SUM|err_net|, mae_net_share = SUM|err_net|
--              / SUM real_spend, bias_share = SUM err_net / SUM real_spend, side_accuracy (spend-
--              weighted), rule_versions, builder_versions
--   MONEY      per plan row: dn_net_per_dollar (DO_NOTHING-applied), act_net_per_pred_dollar
--              (ACT-applied: realised net / predicted spend), counterfactual_net_per_alloc =
--              SUM(alloc_spend x realised net per ad dollar, 0 where nothing was spent) /
--              SUM(alloc_spend) (FN_PLAN_SCORECARD's GRADE metric), alloc_spend, alloc_unrealized,
--              pred_lift and realised_lift over ACT-applied plan rows (ACT pred_net - DO_NOTHING
--              pred_net; realised net - DO_NOTHING pred_net), lift_rows, pred_lift_all (every
--              graded plan row), lift_control = 'DO_NOTHING_PREDICTION', and that control's own
--              accuracy (control_mae_net_share, control_bias_share)
--   CURVE      per bucket (0, 1-5, 6-10, 11-20, 21-40, 41-80, 81+ realised clicks): bucket_rows,
--              bucket_spend, bucket_accuracy; cum_rows, cum_spend, cum_accuracy over the rows at or
--              above bucket_floor (NULL on bucket 0, which never sets the line)
--   LINE       min_clicks = the smallest floor whose cum_accuracy >= MIN_INVEST_SIDE_ACCURACY with
--              cum_rows >= MIN_INVEST_MIN_ROWS (NULL = no line), settled_cpc = SUM real_spend / SUM
--              real_clicks, min_dollars = min_clicks x settled_cpc, the two bars used, and a sentence
--   HONESTY    per plan row: n_rows, n_right, n_wrong, n_inconclusive, n_ungradable,
--              n_act_no_matching_action (a non-no-op ACT whose row applied as DO_NOTHING),
--              n_other_action, n_placement_changed, n_predicted_but_zero_clicks (bucket 0 with window
--              clicks)
--   YOUNG      per predictor x variant x family: ledger_rows, graded_rows, waiting_rows,
--              next_due_watermark (the watermark at which the next waiting row becomes gradable)
--              and a sentence
--   NEXT_WEEK  per family, the live plan of the latest night: dn_pred_net, act_pred_net,
--              dn_pred_spend, act_pred_spend and the sentence "do nothing $X; upload the plan $Y"
-- Every row: watermark (the house watermark of the run), grader_version, scored_at.
--
-- Written by:  SP_GRADE_PREDICTIONS (orchestrator Task 20.8f from piece-2 Task 6)
-- Read by:     the brief's "do nothing / upload the plan" line and the Learning panel (piece 7);
--              architecture/LEARNING.md §8 "How to read the report card in one query"
-- SOP:         architecture/LEARNING.md §5
-- =============================================================================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.T_PREDICTION_SCORECARD` (
  predictor                    STRING,
  variant                      STRING,
  family                       STRING,
  calendar_state               STRING,
  level                        STRING,   -- WINDOW | TRAILING_3 | SINCE_START | TONIGHT
  row_type                     STRING,   -- ACCURACY | MONEY | CURVE | LINE | HONESTY | YOUNG | NEXT_WEEK
  scenario                     STRING,   -- ACCURACY: APPLIED | DO_NOTHING | ACT
  bucket                       STRING,   -- CURVE: 0 | 1-5 | 6-10 | 11-20 | 21-40 | 41-80 | 81+
  bucket_floor                 INT64,
  window_from                  DATE,
  window_to                    DATE,
  n_windows                    INT64,
  n_nights                     INT64,
  n_rows                       INT64,
  keywords                     INT64,
  pred_clicks                  FLOAT64,
  real_clicks                  FLOAT64,
  pred_spend                   FLOAT64,
  real_spend                   FLOAT64,
  pred_orders                  FLOAT64,
  real_orders                  FLOAT64,
  pred_gp                      FLOAT64,
  real_gp                      FLOAT64,
  pred_net                     FLOAT64,
  real_net                     FLOAT64,
  mae_net_usd                  FLOAT64,
  mae_net_share                FLOAT64,
  bias_share                   FLOAT64,
  side_accuracy                FLOAT64,
  dn_net_per_dollar            FLOAT64,
  act_net_per_pred_dollar      FLOAT64,
  counterfactual_net_per_alloc FLOAT64,
  alloc_spend                  FLOAT64,
  alloc_unrealized             FLOAT64,
  pred_lift                    FLOAT64,
  realised_lift                FLOAT64,
  lift_rows                    INT64,
  pred_lift_all                FLOAT64,
  lift_control                 STRING,
  control_mae_net_share        FLOAT64,
  control_bias_share           FLOAT64,
  bucket_rows                  INT64,
  bucket_spend                 FLOAT64,
  bucket_accuracy              FLOAT64,
  cum_rows                     INT64,
  cum_spend                    FLOAT64,
  cum_accuracy                 FLOAT64,
  min_clicks                   INT64,
  min_dollars                  FLOAT64,
  settled_cpc                  FLOAT64,
  bar_side_accuracy            FLOAT64,
  bar_min_rows                 INT64,
  n_right                      INT64,
  n_wrong                      INT64,
  n_inconclusive               INT64,
  n_ungradable                 INT64,
  n_act_no_matching_action     INT64,
  n_other_action               INT64,
  n_placement_changed          INT64,
  n_predicted_but_zero_clicks  INT64,
  ledger_rows                  INT64,
  graded_rows                  INT64,
  waiting_rows                 INT64,
  next_due_watermark           DATE,
  dn_pred_net                  FLOAT64,
  act_pred_net                 FLOAT64,
  dn_pred_spend                FLOAT64,
  act_pred_spend               FLOAT64,
  rule_versions                STRING,
  builder_versions             STRING,
  detail                       STRING,
  watermark                    DATE,
  grader_version               STRING,
  scored_at                    TIMESTAMP
)
OPTIONS (description = "v27.173 (2026-10-03, learning-contract piece 2 Task 5): the report card of the plan's predictions, rebuilt (CREATE OR REPLACE) by SP_GRADE_PREDICTIONS at the end of every run from the current grades of FACT_PREDICTION_GRADE (predictor FIXTURE excluded) and, for YOUNG and NEXT_WEEK, from V_PREDICTION_LEDGER. Grain predictor x variant x family x calendar_state x level x row_type (+ scenario on ACCURACY, + bucket on CURVE, + the week on WINDOW); family/calendar_state 'ALL' = the predictor's rollup. Levels WINDOW (Sunday-start week of as_of), TRAILING_3 (the group's three most recent graded windows), SINCE_START; TONIGHT for NEXT_WEEK. Row types ACCURACY (applied / DO_NOTHING / ACT: mae_net_usd, mae_net_share, bias_share, spend-weighted side_accuracy), MONEY (dn_net_per_dollar, act_net_per_pred_dollar, counterfactual_net_per_alloc = FN_PLAN_SCORECARD's GRADE metric, pred_lift / realised_lift over ACT-applied rows, lift_control DO_NOTHING_PREDICTION), CURVE (per click bucket and cumulative side accuracy), LINE (min_clicks at MIN_INVEST_SIDE_ACCURACY with MIN_INVEST_MIN_ROWS rows, min_dollars), HONESTY (ungradable, ACT with no matching action, other action, placement changed, predicted but zero clicks), YOUNG (what waits and when it becomes gradable), NEXT_WEEK (tonight's live plan per family: do nothing vs upload the plan, predicted net). UNGRADABLE rows enter HONESTY only. SOP: architecture/LEARNING.md 5.");
