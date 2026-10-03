-- =============================================================================================
-- V_PREDICTION_LEDGER — v27.172 (2026-10-03, learning piece 2, Task 4): the next-week money plan's
-- predictions in the learning contract's shape. ONE ROW PER (as_of, predictor, campaign_id,
-- keyword_id, scenario): every row of FACT_PLAN_NEXT_WEEK, every stored night including August
-- (ruling D1), twice — scenario DO_NOTHING (leave tonight's bids and budgets as they are) and
-- scenario ACT (upload the plan's move). No new writing: a view over stored columns and two
-- append-only histories.
--
-- THE HORIZON (ruling D2 (c)). horizon_from = GREATEST(as_of, the first full Los Angeles day after
-- built_at); horizon_to = horizon_from + window_days - 1. A forecast exists before any day it
-- forecasts; a night written after Los Angeles midnight of its as_of (every night stored before the
-- v27.170 freeze) has its horizon start a day later instead.
--
-- DO_NOTHING = the window the plan judged: clicks w_clk, spend w_sp, orders w_ord /
-- settle_factor_eff, gross profit w_gp_corrected, net w_gp_corrected - w_sp.
--
-- ACT = RM1, anchored on DO_NOTHING (ruling D3 (b)):
--   r = new_bid / current_bid on REPRICE, OPEN_PROBE (planned_bid) and PARK
--       (ROUND(COALESCE(bid_park, bid_floor, current_bid), 2)); r = 1 on NONE, NONE_HOLDOUT,
--       HOLD_AT_PRICE, HOLD_AT_PARK; any other move has no r and its ACT row is NULL (acceptance L1).
--   clicks w_clk x r^eps; spend w_sp x r^(eps+gamma); orders (w_ord / settle_factor_eff) x r^eps;
--   gross profit w_gp_corrected x r^eps; net = gross profit - spend. PAUSE: all five 0.
--   A keyword with no window clicks predicts 0 on ACT, except an OPEN_PROBE, priced from its seat:
--   spend seat_cost_per_day x window_days; clicks spend / (planned_bid x BID_TO_CPC_RATIO_FALLBACK);
--   orders clicks x CVR; gross profit orders x GP per order; CVR and GP per order the keyword's own
--   settled 90-day record (settled_ord90 / settled_clk90, settled_gp90 / settled_ord90) when
--   settled_clk90 >= OWN_CVR_MIN_CLICKS, else the pooled record of the night's plan keywords of the
--   same family and channel; both from FACT_KEYWORD_STATE_HISTORY's latest snapshot_date BEFORE the
--   Los Angeles date of built_at, among copies captured at or before built_at (a snapshot_date is
--   re-captured, and its earlier copy pruned, by every pass on that Los Angeles date, so only an
--   earlier date is final when the night is written).
--   THE CAMPAIGN BUDGET (ruled 2026-10-03, the recommended form; architecture/LEARNING.md §3): where
--   campaign_planned_budget < campaign_current_budget, every ACT row of the campaign (that night,
--   that plan) is multiplied by
--     LEAST(1, GREATEST(planned x H, SUM(DO_NOTHING spend) x planned / current) / SUM(ACT spend))
--   (H = window_days; 1 where the campaign's ACT spend is 0): a cap at the new budget x H, falling
--   back to the proportional cut where DO_NOTHING already overdelivers the current budget. A raise
--   has no effect (RM1 limitation).
--
-- THE SETTINGS are DE_COACH_THRESHOLDS rows (strategy_id 'LEARNING', coach_mode 'GUARDIAN', family
-- NULL), read from their history FACT_THRESHOLD_HISTORY, never as literals: per night and key the
-- latest event with snapshot_at <= built_at; a night built before a key's first event takes that
-- first event (every night stored before 2026-10-03 17:05:15 UTC, when the seeds were first
-- recorded). The history is append-only, so the value that priced a night never changes.
-- response_model_version names the four that price ACT: 'RM1:' + their history ids in key order
-- (BID_TO_CPC_RATIO_FALLBACK, CLICK_BID_ELASTICITY, CPC_BID_EXPONENT, OWN_CVR_MIN_CLICKS);
-- DO_NOTHING is 'RUN_RATE'. MATCH_BID_TOL and MATCH_BUDGET_TOL decide act_is_noop.
--
-- rule_version = the history_id of the DE_PLAN_CONFIG row for the night's calendar_state in force at
-- built_at, || ':' || builder_version ('pre-v27.170' where the row has none). In force = the config
-- row's latest event at built_at is active and not REMOVED, and among such rows of the state the
-- latest; an event counts from its snapshot_at, except a SEEDED event, which counts from its
-- source_updated_at (the history began 2026-10-02; the seed rows' updated_at, 2026-08-23, is when
-- they took force). min_orders is read from the same event.
--
-- act_is_noop = no bid component (|planned_bid - current_bid| >= MATCH_BID_TOL), no state component
-- (PAUSE) and no budget component (|planned - current budget| >= MATCH_BUDGET_TOL).
-- Diagnostic columns on ACT rows: act_bid_ratio (r), act_budget_factor, act_basis (ANCHORED |
-- PAUSE | ZERO_BASIS | SEAT_PROBE_OWN | SEAT_PROBE_POOLED).
--
-- Reads FACT_PLAN_NEXT_WEEK, FACT_THRESHOLD_HISTORY, FACT_KEYWORD_STATE_HISTORY. No catalog table
-- (rulings D3 (b), D6), no FACT_AMAZON_ADS, no CURRENT_* clock.
-- Spec: docs/superpowers/specs/2026-10-01-learning-contract-design.md §5, §6, §14.
-- Plan: docs/superpowers/plans/2026-10-03-learning-piece2-ledger-grader.md Task 4.
-- SOP:  architecture/LEARNING.md §1-§3, §10 "Task 4".
-- Acceptance: scripts/bigquery/tests/PREDICTION_CONTRACT_acceptance.sql (L1-L4).
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PREDICTION_LEDGER`
OPTIONS (description = "v27.172 (2026-10-03, learning piece 2 Task 4, rulings D1-D3): the next-week money plan's predictions, one row per (as_of, predictor = 'PLAN_' || plan, campaign_id, keyword_id, scenario), every stored night of FACT_PLAN_NEXT_WEEK twice: DO_NOTHING (the judged window: w_clk, w_sp, w_ord / settle_factor_eff, w_gp_corrected, net = w_gp_corrected - w_sp) and ACT (RM1 anchored on DO_NOTHING: r = new_bid / current_bid on REPRICE / OPEN_PROBE / PARK, 1 on NONE / NONE_HOLDOUT / HOLD_AT_PRICE / HOLD_AT_PARK; clicks, orders, gross profit x r^eps, spend x r^(eps+gamma); PAUSE 0; a zero-click row 0 except an OPEN_PROBE priced from its seat at the keyword's own settled 90-day rate or the night's family x channel pool from FACT_KEYWORD_STATE_HISTORY; on a campaign whose budget the plan cuts every ACT row x LEAST(1, GREATEST(planned x H, sum DO_NOTHING spend x planned / current) / sum ACT spend), the recommended form ruled 2026-10-03). horizon_from = GREATEST(as_of, the Los Angeles date of built_at + 1), horizon_to = horizon_from + window_days - 1 (ruling D2). Settings from FACT_THRESHOLD_HISTORY (LEARNING scope), the event in force at built_at or a key's first event for a night built before it; response_model_version 'RM1:' + their history ids, 'RUN_RATE' on DO_NOTHING; rule_version = the DE_PLAN_CONFIG history_id in force at built_at || ':' || builder_version ('pre-v27.170' where NULL); min_orders from the same event. Carries alloc_spend (the seat: planned_spend_per_day x window_days, not a forecast), act_is_noop, pred_side, basis_clicks / basis_spend. Reads no catalog table, no FACT_AMAZON_ADS, no clock. Acceptance: scripts/bigquery/tests/PREDICTION_CONTRACT_acceptance.sql. SOP: architecture/LEARNING.md.")
AS
WITH
plan_rows AS (
  SELECT p.*
  FROM `onyga-482313.OI.FACT_PLAN_NEXT_WEEK` p
),
nights AS (
  SELECT DISTINCT as_of, built_at, calendar_state
  FROM plan_rows
),

-- ---- the plan config in force at built_at: rule_version and min_orders ------------------------
cfg_ev AS (
  SELECT history_id, row_key, key_ordinal, change_kind, calendar_state, min_orders, is_active,
         snapshot_at,
         IF(change_kind = 'SEEDED', COALESCE(source_updated_at, snapshot_at), snapshot_at) AS in_force_from
  FROM `onyga-482313.OI.FACT_THRESHOLD_HISTORY`
  WHERE source_table = 'DE_PLAN_CONFIG'
),
cfg_row_at AS (   -- each config row's latest event at the night's built_at
  SELECT n.as_of, n.built_at, n.calendar_state AS night_state, e.*
  FROM nights n
  JOIN cfg_ev e ON e.in_force_from <= n.built_at
  QUALIFY ROW_NUMBER() OVER (PARTITION BY n.as_of, n.built_at, e.row_key, e.key_ordinal
                             ORDER BY e.in_force_from DESC, e.snapshot_at DESC, e.history_id) = 1
),
cfg AS (          -- the active row of the night's state; the latest of them if two overlap
  SELECT as_of, built_at, history_id AS cfg_history_id, min_orders
  FROM cfg_row_at
  WHERE change_kind <> 'REMOVED' AND is_active AND calendar_state = night_state
  QUALIFY ROW_NUMBER() OVER (PARTITION BY as_of, built_at
                             ORDER BY in_force_from DESC, snapshot_at DESC, history_id) = 1
),

-- ---- the LEARNING settings in force at built_at -----------------------------------------------
lrn_ev AS (
  SELECT threshold_key, history_id, snapshot_at, threshold_value
  FROM `onyga-482313.OI.FACT_THRESHOLD_HISTORY`
  WHERE source_table = 'DE_COACH_THRESHOLDS'
    AND strategy_id = 'LEARNING' AND coach_mode = 'GUARDIAN' AND product_family IS NULL
    AND threshold_key IN ('CLICK_BID_ELASTICITY', 'CPC_BID_EXPONENT', 'BID_TO_CPC_RATIO_FALLBACK',
                          'OWN_CVR_MIN_CLICKS', 'MATCH_BID_TOL', 'MATCH_BUDGET_TOL')
),
lrn_pick AS (     -- the latest event at built_at; for a night built before a key's first event, that first event
  SELECT n.as_of, n.built_at, e.threshold_key, e.history_id, e.threshold_value
  FROM (SELECT DISTINCT as_of, built_at FROM nights) n
  CROSS JOIN lrn_ev e
  QUALIFY ROW_NUMBER() OVER (PARTITION BY n.as_of, n.built_at, e.threshold_key
                             ORDER BY (e.snapshot_at <= n.built_at) DESC,
                                      IF(e.snapshot_at <= n.built_at, e.snapshot_at, NULL) DESC,
                                      e.snapshot_at, e.history_id) = 1
),
lrn AS (
  SELECT as_of, built_at,
         MAX(IF(threshold_key = 'CLICK_BID_ELASTICITY', threshold_value, NULL))      AS eps,
         MAX(IF(threshold_key = 'CPC_BID_EXPONENT', threshold_value, NULL))          AS gamma,
         MAX(IF(threshold_key = 'BID_TO_CPC_RATIO_FALLBACK', threshold_value, NULL)) AS cpc_ratio,
         MAX(IF(threshold_key = 'OWN_CVR_MIN_CLICKS', threshold_value, NULL))        AS own_min_clk,
         MAX(IF(threshold_key = 'MATCH_BID_TOL', threshold_value, NULL))             AS bid_tol,
         MAX(IF(threshold_key = 'MATCH_BUDGET_TOL', threshold_value, NULL))          AS budget_tol,
         IF(COUNTIF(threshold_key IN ('BID_TO_CPC_RATIO_FALLBACK', 'CLICK_BID_ELASTICITY',
                                      'CPC_BID_EXPONENT', 'OWN_CVR_MIN_CLICKS')) = 4,
            CONCAT('RM1:', STRING_AGG(IF(threshold_key IN ('BID_TO_CPC_RATIO_FALLBACK', 'CLICK_BID_ELASTICITY',
                                                           'CPC_BID_EXPONENT', 'OWN_CVR_MIN_CLICKS'),
                                         history_id, NULL), ',' ORDER BY threshold_key)),
            NULL) AS rm_version
  FROM lrn_pick
  GROUP BY as_of, built_at
),

-- ---- the keyword-state snapshot final at built_at (zero-click OPEN_PROBE pricing) ----------------
snap_night AS (
  SELECT n.as_of, n.built_at, MAX(h.snapshot_date) AS snap_date
  FROM (SELECT DISTINCT as_of, built_at FROM nights) n
  JOIN `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY` h
    ON h.snapshot_date < DATE(n.built_at, 'America/Los_Angeles') AND h.captured_at <= n.built_at
  GROUP BY n.as_of, n.built_at
),
night_keys AS (
  SELECT DISTINCT as_of, built_at, family, channel, campaign_id, keyword_id
  FROM plan_rows
),
ks AS (           -- the night's plan keywords in that snapshot
  SELECT k.as_of, k.built_at, k.family, k.channel, k.campaign_id, k.keyword_id,
         h.settled_clk90, h.settled_ord90, h.settled_gp90
  FROM night_keys k
  JOIN snap_night s ON s.as_of = k.as_of AND s.built_at = k.built_at
  JOIN `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY` h
    ON h.snapshot_date = s.snap_date AND h.campaign_id = k.campaign_id AND h.keyword_id = k.keyword_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY k.as_of, k.built_at, k.campaign_id, k.keyword_id
                             ORDER BY h.captured_at DESC, h.settled_clk90 DESC, h.settled_ord90 DESC,
                                      h.settled_gp90 DESC) = 1
),
pool AS (
  SELECT as_of, built_at, family, channel,
         SAFE_DIVIDE(SUM(settled_ord90), SUM(settled_clk90)) AS pool_cvr,
         SAFE_DIVIDE(SUM(settled_gp90), SUM(settled_ord90))  AS pool_gpo
  FROM ks
  GROUP BY as_of, built_at, family, channel
),

-- ---- one row per plan row, with everything a scenario needs ------------------------------------
base AS (
  SELECT
    p.*,
    c.cfg_history_id, c.min_orders,
    l.eps, l.gamma, l.cpc_ratio, l.own_min_clk, l.bid_tol, l.budget_tol, l.rm_version,
    GREATEST(p.as_of, DATE_ADD(DATE(p.built_at, 'America/Los_Angeles'), INTERVAL 1 DAY)) AS horizon_from,
    CASE
      WHEN p.move IN ('REPRICE', 'OPEN_PROBE') THEN SAFE_DIVIDE(p.planned_bid, p.current_bid)
      WHEN p.move = 'PARK' THEN SAFE_DIVIDE(ROUND(COALESCE(p.bid_park, p.bid_floor, p.current_bid), 2), p.current_bid)
      WHEN p.move IN ('NONE', 'NONE_HOLDOUT', 'HOLD_AT_PRICE', 'HOLD_AT_PARK') THEN 1.0
      ELSE NULL                                  -- PAUSE needs none; an unknown move gets none (L1)
    END AS r,
    (p.w_clk = 0 AND p.move = 'OPEN_PROBE') AS seat_probe,
    (k.settled_clk90 >= l.own_min_clk) AS own_rate,
    IF(k.settled_clk90 >= l.own_min_clk, SAFE_DIVIDE(k.settled_ord90, k.settled_clk90), pl.pool_cvr) AS probe_cvr,
    IF(k.settled_clk90 >= l.own_min_clk, SAFE_DIVIDE(k.settled_gp90, k.settled_ord90), pl.pool_gpo)  AS probe_gpo
  FROM plan_rows p
  LEFT JOIN cfg c  ON c.as_of = p.as_of AND c.built_at = p.built_at
  LEFT JOIN lrn l  ON l.as_of = p.as_of AND l.built_at = p.built_at
  LEFT JOIN ks k   ON k.as_of = p.as_of AND k.built_at = p.built_at
                  AND k.campaign_id = p.campaign_id AND k.keyword_id = p.keyword_id
  LEFT JOIN pool pl ON pl.as_of = p.as_of AND pl.built_at = p.built_at
                   AND pl.family = p.family AND pl.channel = p.channel
),
act0 AS (         -- ACT before the campaign budget
  SELECT b.*,
    CASE
      WHEN b.move = 'PAUSE' THEN 'PAUSE'
      WHEN b.seat_probe     THEN IF(b.own_rate, 'SEAT_PROBE_OWN', 'SEAT_PROBE_POOLED')
      WHEN b.w_clk = 0      THEN 'ZERO_BASIS'
      ELSE 'ANCHORED'
    END AS act_basis,
    CASE
      WHEN b.move = 'PAUSE' THEN 0.0
      WHEN b.seat_probe     THEN SAFE_DIVIDE(b.seat_cost_per_day * b.window_days, b.planned_bid * b.cpc_ratio)
      WHEN b.w_clk = 0      THEN 0.0
      ELSE b.w_clk * POW(b.r, b.eps)
    END AS a_clicks,
    CASE
      WHEN b.move = 'PAUSE' THEN 0.0
      WHEN b.seat_probe     THEN b.seat_cost_per_day * b.window_days
      WHEN b.w_clk = 0      THEN 0.0
      ELSE b.w_sp * POW(b.r, b.eps + b.gamma)
    END AS a_spend,
    CASE
      WHEN b.move = 'PAUSE' THEN 0.0
      WHEN b.seat_probe     THEN SAFE_DIVIDE(b.seat_cost_per_day * b.window_days, b.planned_bid * b.cpc_ratio) * b.probe_cvr
      WHEN b.w_clk = 0      THEN 0.0
      ELSE SAFE_DIVIDE(b.w_ord, b.settle_factor_eff) * POW(b.r, b.eps)
    END AS a_orders,
    CASE
      WHEN b.move = 'PAUSE' THEN 0.0
      WHEN b.seat_probe     THEN IF(b.probe_cvr = 0, 0.0,
                                    SAFE_DIVIDE(b.seat_cost_per_day * b.window_days, b.planned_bid * b.cpc_ratio)
                                    * b.probe_cvr * b.probe_gpo)
      WHEN b.w_clk = 0      THEN 0.0
      ELSE b.w_gp_corrected * POW(b.r, b.eps)
    END AS a_gp
  FROM base b
),
camp AS (         -- the campaign budget clause, per night, plan and campaign
  SELECT as_of, plan, campaign_id,
         CASE
           WHEN MAX(campaign_planned_budget) < MAX(campaign_current_budget) THEN
             COALESCE(LEAST(1.0, SAFE_DIVIDE(
               GREATEST(MAX(campaign_planned_budget) * MAX(window_days),
                        SAFE_DIVIDE(SUM(w_sp) * MAX(campaign_planned_budget), MAX(campaign_current_budget))),
               SUM(a_spend))), 1.0)
           ELSE 1.0
         END AS budget_factor
  FROM act0
  GROUP BY as_of, plan, campaign_id
),
act AS (
  SELECT a.*, m.budget_factor,
         a.a_clicks * m.budget_factor AS act_clicks,
         a.a_spend  * m.budget_factor AS act_spend,
         a.a_orders * m.budget_factor AS act_orders,
         a.a_gp     * m.budget_factor AS act_gp
  FROM act0 a
  JOIN camp m ON m.as_of = a.as_of AND m.plan = a.plan AND m.campaign_id = a.campaign_id
)
SELECT
  CONCAT('PLAN_', a.plan)                                              AS predictor,
  a.plan                                                               AS variant,
  scenario,
  a.as_of,
  a.built_at,
  a.builder_version,
  a.horizon_from,
  DATE_ADD(a.horizon_from, INTERVAL a.window_days - 1 DAY)             AS horizon_to,
  a.window_days,
  a.family,
  a.campaign_id,
  a.keyword_id,
  a.channel,
  a.calendar_state,
  a.is_live_plan,
  a.holdout,
  a.family_bar,
  a.min_orders,
  a.current_bid,
  a.planned_bid,
  a.campaign_current_budget,
  a.campaign_planned_budget,
  IF(scenario = 'ACT', a.move, NULL)                                 AS move,
  a.planned_spend_per_day * a.window_days                              AS alloc_spend,
  NOT (COALESCE(ABS(a.planned_bid - a.current_bid) >= a.bid_tol, FALSE)
       OR a.move = 'PAUSE'
       OR COALESCE(ABS(a.campaign_planned_budget - a.campaign_current_budget) >= a.budget_tol, FALSE))
                                                                       AS act_is_noop,
  IF(a.side = 'GOOD', 1, 0)                                            AS pred_side,
  a.w_clk                                                              AS basis_clicks,
  a.w_sp                                                               AS basis_spend,
  a.settle_factor_eff,
  IF(scenario = 'ACT', a.act_clicks, CAST(a.w_clk AS FLOAT64))                       AS pred_clicks,
  IF(scenario = 'ACT', a.act_spend,  a.w_sp)                                         AS pred_spend,
  IF(scenario = 'ACT', a.act_orders, SAFE_DIVIDE(a.w_ord, a.settle_factor_eff))      AS pred_orders,
  IF(scenario = 'ACT', a.act_gp,     a.w_gp_corrected)                               AS pred_gp,
  IF(scenario = 'ACT', a.act_gp - a.act_spend, a.w_gp_corrected - a.w_sp)            AS pred_net,
  IF(scenario = 'ACT', a.r, NULL)                                    AS act_bid_ratio,
  IF(scenario = 'ACT', a.budget_factor, NULL)                        AS act_budget_factor,
  IF(scenario = 'ACT', a.act_basis, NULL)                            AS act_basis,
  CONCAT(a.cfg_history_id, ':', COALESCE(a.builder_version, 'pre-v27.170')) AS rule_version,
  IF(scenario = 'ACT', a.rm_version, 'RUN_RATE')                     AS response_model_version
FROM act a
CROSS JOIN UNNEST(['DO_NOTHING', 'ACT']) AS scenario;
