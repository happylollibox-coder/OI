-- =============================================================================================
-- 2026-10-03 — learning-contract piece 2, Task 2: seed the LEARNING settings.
--
-- WHAT. Twelve rows in DE_COACH_THRESHOLDS under strategy_id = 'LEARNING', coach_mode =
-- 'GUARDIAN', product_family = NULL, source = 'SEED', updated_by = 'learning-piece2': the
-- constants of response model RM1 (V_PREDICTION_LEDGER, Task 4), of the grader
-- (SP_GRADE_PREDICTIONS, Task 5) and of the health checks (V_ENGINE_HEALTH, Task 6). Each row's
-- description names where its value comes from. Every one is a DECLARED CONSTANT (Ori's rulings
-- D1-D6 of 2026-10-03, "all recommended"); where a value came from a measurement, the description
-- names the query that measured it, and the dated record is architecture/LEARNING.md §10 (Task 2)
-- and the learning-contract spec §14.
--
-- WHY THIS SCOPE. The spec (§4) puts every learning setting under strategy_id = 'LEARNING',
-- coach_mode = 'GUARDIAN', product_family = NULL, and its readers read exactly that scope. A row
-- landing under any other coach_mode or family is invisible to them and the setting resolves NULL.
-- scripts/bigquery/tests/LEARNING_SETTINGS_acceptance.sql S1 checks the scope.
--
-- RE-RUNNABLE, AND NEVER DESTRUCTIVE. Inserts only the keys that do not already exist under that
-- exact scope (threshold_key x strategy_id x coach_mode x product_family, the resolution key
-- FACT_THRESHOLD_HISTORY keys on). It never deletes or updates a row, so a value the grader's
-- proposals or Ori later move (piece 6) is never put back by a re-run.
--
-- THEN THE HISTORY. The CALL at the end runs SP_SNAPSHOT_THRESHOLDS once, so FACT_THRESHOLD_HISTORY
-- records the new rows (ADDED) before the next orchestrator pass and the ledger can cite their
-- history_id (response_model_version). On a re-run it writes only what changed since the last pass.
--
-- Deploy:
--   bq query --project_id=onyga-482313 --use_legacy_sql=false --nouse_cache "$(grep -v '^[[:space:]]*--' FILE)"
-- Check: scripts/bigquery/tests/LEARNING_SETTINGS_acceptance.sql.
-- Spec: docs/superpowers/specs/2026-10-01-learning-contract-design.md §4, §6, §7, §9, §14.
-- Plan: docs/superpowers/plans/2026-10-03-learning-piece2-ledger-grader.md Task 2.
-- SOP:  architecture/LEARNING.md §3 "The settings".
-- =============================================================================================

INSERT INTO `onyga-482313.OI.DE_COACH_THRESHOLDS`
  (threshold_key, strategy_id, product_family, threshold_value, description, peak_multiplier,
   boost_peak_multiplier, source, updated_at, updated_by, coach_mode)
SELECT s.threshold_key, 'LEARNING', CAST(NULL AS STRING), s.threshold_value, s.description,
       1.0, 1.0, 'SEED', CURRENT_DATETIME(), 'learning-piece2', 'GUARDIAN'
FROM UNNEST([
  STRUCT('CLICK_BID_ELASTICITY' AS threshold_key, 1.0 AS threshold_value,
    "epsilon of response model RM1 (V_PREDICTION_LEDGER, the ACT scenario): with r = new_bid / current_bid, predicted clicks, orders and gross profit are the DO_NOTHING numbers x r^epsilon, spend x r^(epsilon + gamma). Seeded 2026-10-03 at 1.0, the learning-contract spec seed (spec §6; ruling D3); the repo holds no measured value. The grader proposes moves to it (piece 6, spec §8 rule 4); Ori decides." AS description),
  STRUCT('CPC_BID_EXPONENT', 1.0,
    "gamma of response model RM1: the price per click follows the bid as r^gamma, so ACT spend is DO_NOTHING spend x r^(epsilon + gamma). Seeded 2026-10-03 at 1.0, which the spec's CPC = bid x ratio implies (spec §6; ruling D3). The measured alternative is the gamma 0.778 (0.638-0.872) declared in V_BID_CPC_TRANSFER's params CTE."),
  STRUCT('BID_TO_CPC_RATIO_FALLBACK', 0.974,
    "CPC / bid that RM1 uses only for a zero-basis OPEN_PROBE (no window clicks): predicted clicks = the seat's spend / (planned_bid x this). Seeded 2026-10-03 (ruling D3) at the account's SUM(cost) / SUM(clicks x FACT_KEYWORD_STATE_HISTORY.current_bid) over 2026-09-02..09-29, joined on snapshot_date = date: learning-contract spec §14 E4, query Q3 (piece-2 brief §3). Replaces the spec's 1.17, which has no source. Re-measure with Q3."),
  STRUCT('OWN_CVR_MIN_CLICKS', 30.0,
    "Settled 90-day clicks (FACT_KEYWORD_STATE_HISTORY.settled_clk90, the latest snapshot with captured_at <= built_at) a zero-basis OPEN_PROBE needs before RM1 prices its orders and gross profit from its own settled rate; below it RM1 uses the family x channel pooled settled rate. Seeded 2026-10-03 at 30 (piece-2 brief §3: the plan keywords that reach it; the count per stored night and its query are in architecture/LEARNING.md §10, Task 2)."),
  STRUCT('SETTLE_HORIZON_DAYS', 14.0,
    "Days after a prediction's horizon_to before SP_GRADE_PREDICTIONS grades it: gradable when horizon_to + this <= LEAST(MAX(FACT_AMAZON_ADS.date), FN_ADS_ANCHOR_CAP()), the house watermark; prediction_grades_fresh allows one night more. Seeded 2026-10-03 at 14 (spec §7): the first age at which V_PLAN_SETTLE_COMPLETION's sales_completion reads 1.0 on both channels (query in architecture/LEARNING.md §10, Task 2)."),
  STRUCT('MATCH_WINDOW_DAYS', 3.0,
    "Days after as_of within which a change in V_PPC_CHANGE_LOG_LANDED (Los Angeles dates as_of .. as_of + this) can count as the plan's move when SP_GRADE_PREDICTIONS decides which scenario applied. Seeded 2026-10-03 at 3, spec §7 (within 3 days after as_of)."),
  STRUCT('MATCH_BID_TOL', 0.005,
    "Dollars. A bid change matches the plan when it lands within this of planned_bid, and the plan has a bid component only when ABS(planned_bid - current_bid) >= this (SP_GRADE_PREDICTIONS). Seeded 2026-10-03 at 0.005, spec §7 (bid +/- $0.005)."),
  STRUCT('MATCH_BUDGET_TOL', 0.01,
    "Dollars a day. A campaign budget change matches the plan when it lands within this of campaign_planned_budget, and the plan has a budget component only when ABS(campaign_planned_budget - campaign_current_budget) >= this (SP_GRADE_PREDICTIONS). Seeded 2026-10-03 at 0.01, spec §7 (budget +/- $0.01)."),
  STRUCT('MIN_INVEST_SIDE_ACCURACY', 0.80,
    "A RATIO. The cumulative spend-weighted side accuracy a click-bucket floor must reach to set the minimum-investment line, per predictor x family x calendar_state (SP_GRADE_PREDICTIONS); a grade below the line, or with no line, is INCONCLUSIVE. Seeded 2026-10-03 at 0.80, spec §7, kept by ruling D4."),
  STRUCT('MIN_INVEST_MIN_ROWS', 20.0,
    "Graded plan rows a click-bucket floor needs at or above it before it can set the minimum-investment line; bucket 0 never sets it. Seeded 2026-10-03 at 20, ruling D4 (the same count as FN_PLAN_SCORECARD's declared min_guard_rows)."),
  STRUCT('MIN_GRADED_WINDOWS', 3.0,
    "Windows (the Sunday-start week of as_of, ruling D5) on each side of prediction_regression's comparison: the trailing this many against the this many before them; the check reads YOUNG until twice this many are graded. Seeded 2026-10-03 at 3, spec §8-§9 (trailing 3 against the previous 3)."),
  STRUCT('REGRESSION_MAX', 0.10,
    "A RATIO. prediction_regression is RED when a predictor's trailing MIN_GRADED_WINDOWS windows are worse than the ones before them by more than this, on mae_net_share or counterfactual_net_per_alloc. Seeded 2026-10-03 at 0.10, spec §9.")
]) AS s
WHERE NOT EXISTS (
  SELECT 1
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS` t
  WHERE t.threshold_key = s.threshold_key
    AND t.strategy_id = 'LEARNING'
    AND t.coach_mode = 'GUARDIAN'
    AND t.product_family IS NULL
);

CALL `onyga-482313.OI.SP_SNAPSHOT_THRESHOLDS`();
