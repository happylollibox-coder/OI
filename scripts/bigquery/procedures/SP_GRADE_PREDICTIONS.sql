-- =============================================================================================
-- SP_GRADE_PREDICTIONS(regrade_from DATE, reason STRING) — v27.173 (2026-10-03, learning-contract
-- piece 2, Task 5): grade every prediction of V_PREDICTION_LEDGER whose horizon has settled, append
-- the grades to FACT_PREDICTION_GRADE, and rebuild the report card T_PREDICTION_SCORECARD.
-- Nightly: CALL `onyga-482313.OI.SP_GRADE_PREDICTIONS`(NULL, NULL) (orchestrator Task 20.8f, between
-- SP_APPEND_CATALOG_FORECAST and SP_REFRESH_CUBE_TABLES, from piece-2 Task 6).
-- Re-grade: CALL `onyga-482313.OI.SP_GRADE_PREDICTIONS`(DATE 'yyyy-mm-dd', 'why') appends a new grade,
-- regrade_seq + 1 and regrade_reason = why, for every currently graded prediction of the nights
-- as_of >= regrade_from that is still gradable, and grades nothing else differently.
--
-- STEP BY STEP (architecture/LEARNING.md §4 says why each rule is what it is):
--  0. SETTINGS from DE_COACH_THRESHOLDS (strategy_id 'LEARNING', coach_mode 'GUARDIAN',
--     product_family NULL), today's values, asserted present once each: SETTLE_HORIZON_DAYS,
--     MATCH_WINDOW_DAYS, MATCH_BID_TOL, MATCH_BUDGET_TOL, MIN_INVEST_SIDE_ACCURACY,
--     MIN_INVEST_MIN_ROWS. Never a literal.
--  1. GRADABLE: DATE_ADD(horizon_to, INTERVAL SETTLE_HORIZON_DAYS DAY) <= the house watermark
--     LEAST(MAX(date), FN_ADS_ANCHOR_CAP()) over FACT_AMAZON_ADS (V_PLAN_WINDOW_JUDGMENT's wm CTE),
--     and no grade yet (or, on a re-grade, a current grade on a night as_of >= regrade_from). The
--     MAX(date) term keeps a row ungraded while the table's newest day is short of it, so "no row
--     = 0" below is never read on a day the table has not reached.
--  2. WHAT HAPPENED: FACT_AMAZON_ADS on campaign_id + keyword_id, date BETWEEN horizon_from AND
--     horizon_to: SUM(Ads_clicks), SUM(Ads_cost), SUM(Ads_orders), SUM(GROSS_PROFIT); net = gross
--     profit - cost. No row = 0 (FACT holds clicked rows only).
--  3. UNGRADABLE only when the keyword (DIM_KEYWORD) or its campaign (DIM_CAMPAIGN) has a version
--     whose state is ARCHIVED, in any letter case, in force at any moment of the horizon (SCD2
--     effective_from / effective_to, the UTC wall clock, against the horizon's Los Angeles days).
--  4. WHICH SCENARIO APPLIED, from V_PPC_CHANGE_LOG_LANDED (landed_evidence other than
--     LOGGED_ONLY), changes on Los Angeles dates as_of .. as_of + MATCH_WINDOW_DAYS: the keyword's
--     changes (keyword_id) and its campaign's state and budget changes (keyword_id NULL, the same
--     campaign_id, a *BUDGET* or CAMPAIGN_* action). The plan row's expected components: bid when
--     |planned_bid - current_bid| >= MATCH_BID_TOL, state when the move is PAUSE, budget when
--     |campaign_planned_budget - campaign_current_budget| >= MATCH_BUDGET_TOL (the ledger's
--     act_is_noop test). A change matches a component: bid, new_bid within MATCH_BID_TOL of
--     planned_bid; state, KEYWORD_PAUSE or STOP_TARGET; budget, a *BUDGET* action whose new_budget
--     is within MATCH_BUDGET_TOL of campaign_planned_budget (SP_RECORD_OBSERVED_CHANGES' rules).
--     ACT = at least one component, every component matched, and no other change; DO_NOTHING = no
--     change at all (so a row whose plan asks for nothing, with nothing done, is DO_NOTHING);
--     OTHER_ACTION otherwise, a partial match included. placement_changed: the keyword's
--     FACT_KEYWORD_STATE_HISTORY.m_effective on its latest snapshot on or before as_of
--     (placement_m_from) differs, beyond float noise (1e-6), from the one on or before horizon_to
--     (placement_m_to); NULL when either is missing. m_effective is V_BID_CPC_TRANSFER's
--     click-weighted placement multiplier over a rolling window, read with the adjustments current
--     at each capture (that view's KNOWN DEFECT 1: no adjustment history exists), so it moves with
--     the click mix as well as with a setting; both readings are on the row
--     (architecture/LEARNING.md §9 and §10 "Task 5").
--  5. THE GRADE. realised side GOOD = orders >= min_orders AND COALESCE(gross profit / spend, -1)
--     >= family_bar (the judge's own test, V_PLAN_WINDOW_JUDGMENT `sided`); side_correct = the
--     ledger's pred_side came true. err_net = pred_net - real_net. click_bucket by realised clicks
--     0, 1-5, 6-10, 11-20, 21-40, 41-80, 81+. Then, per predictor x family x calendar_state, over
--     every current grade including tonight's (one row per plan row: its DO_NOTHING row; UNGRADABLE
--     left out): the spend-weighted side accuracy over the rows at or above each floor 1, 6, 11,
--     21, 41, 81; the LINE = the smallest floor with accuracy >= MIN_INVEST_SIDE_ACCURACY and >=
--     MIN_INVEST_MIN_ROWS rows (NULL when none). Then the label: UNGRADABLE; else INCONCLUSIVE in
--     bucket 0, below the line, or with no line; else RIGHT when side_correct, WRONG when not. Both
--     scenario rows of a plan row share side and outcome, so they carry the same label; the line in
--     force is stored as min_clicks_at_grade. Errors, then line, then labels: they cannot disagree.
--  6. INSERT, one row per due ledger row (both scenarios; is_applied on the applied one, neither on
--     OTHER_ACTION), with frozen copies of the ledger row. Append-only; asserted: the due keys are
--     unique and every one was inserted.
--  7. REBUILD T_PREDICTION_SCORECARD (CREATE OR REPLACE) from the current grades (FIXTURE excluded)
--     and the ledger; see scripts/bigquery/tables/T_PREDICTION_SCORECARD.sql for every column.
-- Returns a log_message row, then the rows inserted by night, scenario and label.
--
-- IDEMPOTENT: a second run inserts nothing (NOT EXISTS on the grade key); outcomes keep restating,
-- and a grade moves only under an explicit regrade_from call.
-- Reads V_PREDICTION_LEDGER, FACT_PREDICTION_GRADE, DE_COACH_THRESHOLDS, FACT_AMAZON_ADS,
-- DIM_KEYWORD, DIM_CAMPAIGN, V_PPC_CHANGE_LOG_LANDED, FACT_KEYWORD_STATE_HISTORY. No catalog table.
-- Spec: docs/superpowers/specs/2026-10-01-learning-contract-design.md §7, §11, §14.
-- Plan: docs/superpowers/plans/2026-10-03-learning-piece2-ledger-grader.md Task 5.
-- SOP:  architecture/LEARNING.md §4, §5, §10 "Task 5".
-- =============================================================================================
CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_GRADE_PREDICTIONS`(regrade_from DATE, reason STRING)
OPTIONS (description = "v27.173 (2026-10-03, learning-contract piece 2 Task 5): grades every prediction of V_PREDICTION_LEDGER whose horizon_to + SETTLE_HORIZON_DAYS is at or before the house watermark LEAST(MAX(FACT_AMAZON_ADS.date), FN_ADS_ANCHOR_CAP()) and that has no grade, appending one FACT_PREDICTION_GRADE row per ledger row (both scenarios), then rebuilds T_PREDICTION_SCORECARD. Realised numbers from FACT_AMAZON_ADS over horizon_from..horizon_to (no row = 0); UNGRADABLE only for a keyword or campaign archived (any case) within the horizon; the applied scenario from V_PPC_CHANGE_LOG_LANDED within as_of..as_of + MATCH_WINDOW_DAYS (ACT: every expected bid / state / budget component matched within MATCH_BID_TOL / MATCH_BUDGET_TOL and nothing else changed; DO_NOTHING: nothing changed on the keyword or its campaign's state or budget; else OTHER_ACTION); realised side = the judge's test (orders >= min_orders and gross profit per ad dollar >= family_bar); the minimum-investment line per predictor x family x calendar_state = the smallest click floor whose cumulative spend-weighted side accuracy over every current grade (tonight's included) is >= MIN_INVEST_SIDE_ACCURACY with >= MIN_INVEST_MIN_ROWS rows; labels UNGRADABLE, else INCONCLUSIVE (0 clicks, below the line or no line), else RIGHT / WRONG; the line stored as min_clicks_at_grade. Settings from DE_COACH_THRESHOLDS (LEARNING, GUARDIAN, family NULL), asserted. Idempotent: a second run inserts nothing. regrade_from (with a reason) appends a re-grade, regrade_seq + 1, of every current grade of the nights as_of >= regrade_from. CALL with (NULL, NULL) nightly. SOP: architecture/LEARNING.md 4-5.")
BEGIN
  DECLARE grader_version_d STRING DEFAULT 'v27.173';
  DECLARE graded_at_d TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE settle_days_d INT64;
  DECLARE match_days_d INT64;
  DECLARE bid_tol_d FLOAT64;
  DECLARE budget_tol_d FLOAT64;
  DECLARE min_acc_d FLOAT64;
  DECLARE min_rows_d INT64;
  DECLARE wm_d DATE;
  DECLARE d_from DATE;
  DECLARE d_to DATE;
  DECLARE n_due INT64 DEFAULT 0;
  DECLARE n_inserted INT64 DEFAULT 0;

  ASSERT regrade_from IS NULL OR COALESCE(TRIM(reason), '') <> ''
    AS 'SP_GRADE_PREDICTIONS: a re-grade (regrade_from set) needs a reason; it is stored as regrade_reason on every row the re-grade appends.';

  -- ── 0. the settings ───────────────────────────────────────────────────────────────────────────
  CREATE TEMP TABLE _set AS
  SELECT threshold_key, threshold_value
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id = 'LEARNING' AND coach_mode = 'GUARDIAN' AND product_family IS NULL
    AND threshold_key IN ('SETTLE_HORIZON_DAYS', 'MATCH_WINDOW_DAYS', 'MATCH_BID_TOL', 'MATCH_BUDGET_TOL',
                          'MIN_INVEST_SIDE_ACCURACY', 'MIN_INVEST_MIN_ROWS');

  ASSERT (SELECT COUNT(*) = 6 AND COUNT(DISTINCT threshold_key) = 6 AND COUNTIF(threshold_value IS NULL) = 0 FROM _set)
    AS 'SP_GRADE_PREDICTIONS: DE_COACH_THRESHOLDS must hold SETTLE_HORIZON_DAYS, MATCH_WINDOW_DAYS, MATCH_BID_TOL, MATCH_BUDGET_TOL, MIN_INVEST_SIDE_ACCURACY and MIN_INVEST_MIN_ROWS once each, non-NULL, under strategy_id LEARNING, coach_mode GUARDIAN, product_family NULL (migration 2026-10-03_learning_settings.sql).';

  SET settle_days_d = CAST((SELECT threshold_value FROM _set WHERE threshold_key = 'SETTLE_HORIZON_DAYS') AS INT64);
  SET match_days_d  = CAST((SELECT threshold_value FROM _set WHERE threshold_key = 'MATCH_WINDOW_DAYS') AS INT64);
  SET bid_tol_d     = (SELECT threshold_value FROM _set WHERE threshold_key = 'MATCH_BID_TOL');
  SET budget_tol_d  = (SELECT threshold_value FROM _set WHERE threshold_key = 'MATCH_BUDGET_TOL');
  SET min_acc_d     = (SELECT threshold_value FROM _set WHERE threshold_key = 'MIN_INVEST_SIDE_ACCURACY');
  SET min_rows_d    = CAST((SELECT threshold_value FROM _set WHERE threshold_key = 'MIN_INVEST_MIN_ROWS') AS INT64);

  -- ── 1. the watermark, the ledger, the current grades, what is due ──────────────────────────────
  SET wm_d = (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) FROM `onyga-482313.OI.FACT_AMAZON_ADS`);
  ASSERT wm_d IS NOT NULL
    AS 'SP_GRADE_PREDICTIONS: the house watermark is NULL (FACT_AMAZON_ADS holds no row); nothing can be graded.';

  CREATE TEMP TABLE _led AS
  SELECT * FROM `onyga-482313.OI.V_PREDICTION_LEDGER`;

  CREATE TEMP TABLE _cur0 AS
  SELECT predictor, variant, as_of, campaign_id, keyword_id, scenario, regrade_seq
  FROM `onyga-482313.OI.FACT_PREDICTION_GRADE`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY predictor, variant, as_of, campaign_id, keyword_id, scenario
                             ORDER BY regrade_seq DESC) = 1;

  CREATE TEMP TABLE _due AS
  SELECT l.*, c.regrade_seq AS prev_seq
  FROM _led l
  LEFT JOIN _cur0 c
    ON c.predictor = l.predictor AND c.variant = l.variant AND c.as_of = l.as_of
   AND c.campaign_id = l.campaign_id AND c.keyword_id = l.keyword_id AND c.scenario = l.scenario
  WHERE DATE_ADD(l.horizon_to, INTERVAL settle_days_d DAY) <= wm_d
    AND (c.predictor IS NULL OR (regrade_from IS NOT NULL AND l.as_of >= regrade_from));

  SET n_due = (SELECT COUNT(*) FROM _due);

  ASSERT (SELECT COUNT(*) = COUNT(DISTINCT FORMAT('%s|%s|%t|%s|%s|%s', predictor, variant, as_of,
                                                  campaign_id, keyword_id, scenario)) FROM _due)
    AS 'SP_GRADE_PREDICTIONS: V_PREDICTION_LEDGER has two rows for one prediction key; a grade appended now could never be told apart (PREDICTION_CONTRACT acceptance L1a).';
  ASSERT NOT EXISTS (SELECT 1 FROM _due WHERE min_orders IS NULL OR family_bar IS NULL OR pred_side IS NULL
                                           OR horizon_from IS NULL OR horizon_to IS NULL)
    AS 'SP_GRADE_PREDICTIONS: a gradable ledger row has no min_orders, family_bar, pred_side or horizon; its realised side cannot be tested (V_PREDICTION_LEDGER).';

  -- one row per plan row (both scenario rows of a plan row carry the same plan columns)
  CREATE TEMP TABLE _prow AS
  SELECT predictor, variant, as_of, campaign_id, keyword_id,
         MAX(horizon_from) AS horizon_from, MAX(horizon_to) AS horizon_to,
         MAX(IF(scenario = 'ACT', move, NULL)) AS move,
         MAX(current_bid) AS current_bid, MAX(planned_bid) AS planned_bid,
         MAX(campaign_current_budget) AS campaign_current_budget,
         MAX(campaign_planned_budget) AS campaign_planned_budget
  FROM _due
  GROUP BY predictor, variant, as_of, campaign_id, keyword_id;

  SET d_from = (SELECT MIN(horizon_from) FROM _prow);
  SET d_to   = (SELECT MAX(horizon_to) FROM _prow);

  -- ── 2. what happened over the horizon ─────────────────────────────────────────────────────────
  CREATE TEMP TABLE _real AS
  WITH k AS (SELECT DISTINCT campaign_id, keyword_id, horizon_from, horizon_to FROM _prow)
  SELECT k.campaign_id, k.keyword_id, k.horizon_from, k.horizon_to,
         SUM(f.Ads_clicks)    AS clk,
         SUM(f.Ads_cost)      AS sp,
         SUM(f.Ads_orders)    AS ord,
         SUM(f.GROSS_PROFIT)  AS gp
  FROM k
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` f
    ON f.campaign_id = k.campaign_id AND f.keyword_id = k.keyword_id
   AND f.date BETWEEN k.horizon_from AND k.horizon_to
  WHERE f.date BETWEEN d_from AND d_to
  GROUP BY k.campaign_id, k.keyword_id, k.horizon_from, k.horizon_to;

  -- ── 3. archived within the horizon ────────────────────────────────────────────────────────────
  CREATE TEMP TABLE _arch AS
  WITH k AS (SELECT DISTINCT campaign_id, keyword_id, horizon_from, horizon_to FROM _prow),
  kw AS (
    SELECT DISTINCT k.campaign_id, k.keyword_id, k.horizon_from, k.horizon_to
    FROM k
    JOIN `onyga-482313.OI.DIM_KEYWORD` d ON d.keyword_id = k.keyword_id
    WHERE UPPER(d.state) = 'ARCHIVED'
      AND TIMESTAMP(d.effective_from, 'UTC') < TIMESTAMP(DATE_ADD(k.horizon_to, INTERVAL 1 DAY), 'America/Los_Angeles')
      AND (d.effective_to IS NULL OR TIMESTAMP(d.effective_to, 'UTC') > TIMESTAMP(k.horizon_from, 'America/Los_Angeles'))
  ),
  ca AS (
    SELECT DISTINCT k.campaign_id, k.keyword_id, k.horizon_from, k.horizon_to
    FROM k
    JOIN `onyga-482313.OI.DIM_CAMPAIGN` d ON d.campaign_id = k.campaign_id
    WHERE UPPER(d.state) = 'ARCHIVED'
      AND TIMESTAMP(d.effective_from, 'UTC') < TIMESTAMP(DATE_ADD(k.horizon_to, INTERVAL 1 DAY), 'America/Los_Angeles')
      AND (d.effective_to IS NULL OR TIMESTAMP(d.effective_to, 'UTC') > TIMESTAMP(k.horizon_from, 'America/Los_Angeles'))
  )
  SELECT k.campaign_id, k.keyword_id, k.horizon_from, k.horizon_to,
         (kw.keyword_id IS NOT NULL) AS kw_arch,
         (ca.keyword_id IS NOT NULL) AS camp_arch
  FROM k
  LEFT JOIN kw ON kw.campaign_id = k.campaign_id AND kw.keyword_id = k.keyword_id
              AND kw.horizon_from = k.horizon_from AND kw.horizon_to = k.horizon_to
  LEFT JOIN ca ON ca.campaign_id = k.campaign_id AND ca.keyword_id = k.keyword_id
              AND ca.horizon_from = k.horizon_from AND ca.horizon_to = k.horizon_to;

  -- ── 4. which scenario applied ─────────────────────────────────────────────────────────────────
  CREATE TEMP TABLE _chg AS
  SELECT change_id, action, keyword_id, campaign_id, new_bid, new_budget,
         DATE(applied_at, 'America/Los_Angeles') AS la_date
  FROM `onyga-482313.OI.V_PPC_CHANGE_LOG_LANDED`
  WHERE landed_evidence <> 'LOGGED_ONLY'
    AND DATE(applied_at, 'America/Los_Angeles')
        BETWEEN (SELECT MIN(as_of) FROM _prow)
            AND DATE_ADD((SELECT MAX(as_of) FROM _prow), INTERVAL match_days_d DAY);

  CREATE TEMP TABLE _app AS
  WITH comp AS (
    SELECT p.*,
           COALESCE(ABS(p.planned_bid - p.current_bid) >= bid_tol_d, FALSE)                          AS has_bid,
           COALESCE(p.move = 'PAUSE', FALSE)                                                          AS has_state,
           COALESCE(ABS(p.campaign_planned_budget - p.campaign_current_budget) >= budget_tol_d, FALSE) AS has_budget
    FROM _prow p
  ),
  hits AS (
    -- the keyword's own changes
    SELECT c.predictor, c.variant, c.as_of, c.campaign_id, c.keyword_id, x.change_id,
           CASE
             WHEN c.has_bid AND x.new_bid IS NOT NULL
                  AND ABS(x.new_bid - c.planned_bid) <= bid_tol_d + 1e-9 THEN 'BID'
             WHEN c.has_state AND x.action IN ('KEYWORD_PAUSE', 'STOP_TARGET') THEN 'STATE'
           END AS matched
    FROM comp c
    JOIN _chg x
      ON x.keyword_id = c.keyword_id
     AND x.la_date BETWEEN c.as_of AND DATE_ADD(c.as_of, INTERVAL match_days_d DAY)
    UNION ALL
    -- its campaign's state and budget changes
    SELECT c.predictor, c.variant, c.as_of, c.campaign_id, c.keyword_id, x.change_id,
           CASE
             WHEN c.has_budget AND x.action LIKE '%BUDGET%' AND x.new_budget IS NOT NULL
                  AND ABS(x.new_budget - c.campaign_planned_budget) <= budget_tol_d + 1e-9 THEN 'BUDGET'
           END AS matched
    FROM comp c
    JOIN _chg x
      ON x.campaign_id = c.campaign_id
     AND x.keyword_id IS NULL
     AND (x.action LIKE '%BUDGET%' OR STARTS_WITH(x.action, 'CAMPAIGN_'))
     AND x.la_date BETWEEN c.as_of AND DATE_ADD(c.as_of, INTERVAL match_days_d DAY)
  ),
  agg AS (
    SELECT predictor, variant, as_of, campaign_id, keyword_id,
           COUNT(*)                                   AS n_changes,
           COUNTIF(matched IS NULL)                   AS n_other,
           LOGICAL_OR(COALESCE(matched = 'BID', FALSE))    AS bid_hit,
           LOGICAL_OR(COALESCE(matched = 'STATE', FALSE))  AS state_hit,
           LOGICAL_OR(COALESCE(matched = 'BUDGET', FALSE)) AS budget_hit,
           ARRAY_AGG(IF(matched IS NOT NULL, change_id, NULL) IGNORE NULLS ORDER BY change_id) AS matched_ids,
           ARRAY_AGG(IF(matched IS NULL, change_id, NULL) IGNORE NULLS ORDER BY change_id)     AS other_ids
    FROM hits
    GROUP BY predictor, variant, as_of, campaign_id, keyword_id
  )
  SELECT c.predictor, c.variant, c.as_of, c.campaign_id, c.keyword_id,
         CASE
           WHEN (c.has_bid OR c.has_state OR c.has_budget)
                AND (NOT c.has_bid    OR COALESCE(a.bid_hit, FALSE))
                AND (NOT c.has_state  OR COALESCE(a.state_hit, FALSE))
                AND (NOT c.has_budget OR COALESCE(a.budget_hit, FALSE))
                AND COALESCE(a.n_other, 0) = 0                       THEN 'ACT'
           WHEN COALESCE(a.n_changes, 0) = 0                         THEN 'DO_NOTHING'
           ELSE 'OTHER_ACTION'
         END AS applied_scenario,
         COALESCE(a.matched_ids, ARRAY<STRING>[]) AS matched_change_ids,
         COALESCE(a.other_ids, ARRAY<STRING>[])   AS other_change_ids
  FROM comp c
  LEFT JOIN agg a
    ON a.predictor = c.predictor AND a.variant = c.variant AND a.as_of = c.as_of
   AND a.campaign_id = c.campaign_id AND a.keyword_id = c.keyword_id;

  -- the placement multiplier on the keyword's latest snapshot on or before as_of, and on or before
  -- horizon_to (the latest copy of a snapshot_date); changed = the two readings differ beyond float noise
  CREATE TEMP TABLE _plc AS
  WITH hh AS (
    SELECT p.predictor, p.variant, p.as_of, p.campaign_id, p.keyword_id,
           h.snapshot_date, h.captured_at, h.m_effective
    FROM _prow p
    JOIN `onyga-482313.OI.FACT_KEYWORD_STATE_HISTORY` h
      ON h.campaign_id = p.campaign_id AND h.keyword_id = p.keyword_id
     AND h.snapshot_date <= p.horizon_to
  ),
  m0 AS (
    SELECT predictor, variant, as_of, campaign_id, keyword_id, m_effective AS m_from
    FROM hh
    WHERE snapshot_date <= as_of
    QUALIFY ROW_NUMBER() OVER (PARTITION BY predictor, variant, as_of, campaign_id, keyword_id
                               ORDER BY snapshot_date DESC, captured_at DESC) = 1
  ),
  m1 AS (
    SELECT predictor, variant, as_of, campaign_id, keyword_id, m_effective AS m_to
    FROM hh
    QUALIFY ROW_NUMBER() OVER (PARTITION BY predictor, variant, as_of, campaign_id, keyword_id
                               ORDER BY snapshot_date DESC, captured_at DESC) = 1
  )
  SELECT p.predictor, p.variant, p.as_of, p.campaign_id, p.keyword_id,
         m0.m_from AS placement_m_from, m1.m_to AS placement_m_to,
         IF(m0.m_from IS NULL OR m1.m_to IS NULL, NULL, ABS(m1.m_to - m0.m_from) > 1e-6) AS placement_changed
  FROM _prow p
  LEFT JOIN m0
    ON m0.predictor = p.predictor AND m0.variant = p.variant AND m0.as_of = p.as_of
   AND m0.campaign_id = p.campaign_id AND m0.keyword_id = p.keyword_id
  LEFT JOIN m1
    ON m1.predictor = p.predictor AND m1.variant = p.variant AND m1.as_of = p.as_of
   AND m1.campaign_id = p.campaign_id AND m1.keyword_id = p.keyword_id;

  -- ── 5a. errors: one row per due ledger row ─────────────────────────────────────────────────────
  CREATE TEMP TABLE _g1 AS
  WITH j AS (
    SELECT d.*,
           ap.applied_scenario, ap.matched_change_ids, ap.other_change_ids,
           pl.placement_changed, pl.placement_m_from, pl.placement_m_to,
           COALESCE(r.clk, 0)                     AS real_clicks,
           COALESCE(r.sp, 0.0)                    AS real_spend,
           COALESCE(r.ord, 0)                     AS real_orders,
           COALESCE(r.gp, 0.0)                    AS real_gp,
           COALESCE(r.gp, 0.0) - COALESCE(r.sp, 0.0) AS real_net,
           CASE WHEN ar.kw_arch THEN 'KEYWORD_ARCHIVED' WHEN ar.camp_arch THEN 'CAMPAIGN_ARCHIVED' END AS ungradable_reason
    FROM _due d
    JOIN _app ap
      ON ap.predictor = d.predictor AND ap.variant = d.variant AND ap.as_of = d.as_of
     AND ap.campaign_id = d.campaign_id AND ap.keyword_id = d.keyword_id
    JOIN _plc pl
      ON pl.predictor = d.predictor AND pl.variant = d.variant AND pl.as_of = d.as_of
     AND pl.campaign_id = d.campaign_id AND pl.keyword_id = d.keyword_id
    LEFT JOIN _real r
      ON r.campaign_id = d.campaign_id AND r.keyword_id = d.keyword_id
     AND r.horizon_from = d.horizon_from AND r.horizon_to = d.horizon_to
    LEFT JOIN _arch ar
      ON ar.campaign_id = d.campaign_id AND ar.keyword_id = d.keyword_id
     AND ar.horizon_from = d.horizon_from AND ar.horizon_to = d.horizon_to
  )
  SELECT j.*,
         (j.scenario = j.applied_scenario) AS is_applied,
         IF(j.real_orders >= j.min_orders
            AND COALESCE(SAFE_DIVIDE(j.real_gp, j.real_spend), -1) >= j.family_bar, 1, 0) AS real_side,
         (j.pred_side = IF(j.real_orders >= j.min_orders
                           AND COALESCE(SAFE_DIVIDE(j.real_gp, j.real_spend), -1) >= j.family_bar, 1, 0)) AS side_correct,
         j.pred_net - j.real_net      AS err_net,
         ABS(j.pred_net - j.real_net) AS abs_err_net,
         CASE
           WHEN j.real_clicks = 0  THEN '0'
           WHEN j.real_clicks <= 5  THEN '1-5'
           WHEN j.real_clicks <= 10 THEN '6-10'
           WHEN j.real_clicks <= 20 THEN '11-20'
           WHEN j.real_clicks <= 40 THEN '21-40'
           WHEN j.real_clicks <= 80 THEN '41-80'
           ELSE '81+'
         END AS click_bucket
  FROM j;

  -- ── 5b. the curve and the line, over every current grade including tonight's ──────────────────
  CREATE TEMP TABLE _line AS
  WITH cur AS (     -- the current grade of every plan row (its DO_NOTHING row) before tonight
    SELECT c.*
    FROM `onyga-482313.OI.FACT_PREDICTION_GRADE` c
    WHERE c.scenario = 'DO_NOTHING'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY c.predictor, c.variant, c.as_of, c.campaign_id, c.keyword_id, c.scenario
                               ORDER BY c.regrade_seq DESC) = 1
  ),
  pop AS (
    -- one row per plan row: current grades not re-graded tonight, then tonight's
    SELECT c.predictor, c.family, c.calendar_state, c.real_clicks, c.real_spend, c.side_correct
    FROM cur c
    LEFT JOIN _g1 n
      ON n.predictor = c.predictor AND n.variant = c.variant AND n.as_of = c.as_of
     AND n.campaign_id = c.campaign_id AND n.keyword_id = c.keyword_id AND n.scenario = c.scenario
    WHERE c.grade <> 'UNGRADABLE' AND n.predictor IS NULL
    UNION ALL
    SELECT predictor, family, calendar_state, real_clicks, real_spend, side_correct
    FROM _g1
    WHERE scenario = 'DO_NOTHING' AND ungradable_reason IS NULL
  ),
  cum AS (
    SELECT p.predictor, p.family, p.calendar_state, fl AS bucket_floor,
           COUNT(*) AS cum_rows,
           SAFE_DIVIDE(SUM(IF(p.side_correct, p.real_spend, 0)), SUM(p.real_spend)) AS cum_accuracy
    FROM pop p, UNNEST([1, 6, 11, 21, 41, 81]) AS fl
    WHERE p.real_clicks >= fl
    GROUP BY p.predictor, p.family, p.calendar_state, fl
  )
  SELECT predictor, family, calendar_state,
         MIN(IF(cum_accuracy >= min_acc_d AND cum_rows >= min_rows_d, bucket_floor, NULL)) AS min_clicks
  FROM cum
  GROUP BY predictor, family, calendar_state;

  -- ── 6. the labels, and the append ─────────────────────────────────────────────────────────────
  INSERT INTO `onyga-482313.OI.FACT_PREDICTION_GRADE` (
    predictor, variant, as_of, campaign_id, keyword_id, scenario, regrade_seq,
    family, channel, calendar_state, window_days, is_live_plan, holdout, family_bar, min_orders, move,
    current_bid, planned_bid, campaign_current_budget, campaign_planned_budget,
    horizon_from, horizon_to, built_at, builder_version, rule_version, response_model_version,
    basis_clicks, basis_spend, alloc_spend, act_is_noop,
    pred_clicks, pred_spend, pred_orders, pred_gp, pred_net, pred_side,
    applied_scenario, is_applied, matched_change_ids, other_change_ids,
    placement_changed, placement_m_from, placement_m_to,
    real_clicks, real_spend, real_orders, real_gp, real_net, real_side, side_correct,
    err_net, abs_err_net, click_bucket, min_clicks_at_grade, grade, ungradable_reason,
    graded_at, watermark, grader_version, regrade_reason
  )
  SELECT
    g.predictor, g.variant, g.as_of, g.campaign_id, g.keyword_id, g.scenario,
    COALESCE(g.prev_seq + 1, 0),
    g.family, g.channel, g.calendar_state, g.window_days, g.is_live_plan, g.holdout, g.family_bar, g.min_orders, g.move,
    g.current_bid, g.planned_bid, g.campaign_current_budget, g.campaign_planned_budget,
    g.horizon_from, g.horizon_to, g.built_at, g.builder_version, g.rule_version, g.response_model_version,
    g.basis_clicks, g.basis_spend, g.alloc_spend, g.act_is_noop,
    g.pred_clicks, g.pred_spend, g.pred_orders, g.pred_gp, g.pred_net, g.pred_side,
    g.applied_scenario, g.is_applied, g.matched_change_ids, g.other_change_ids,
    g.placement_changed, g.placement_m_from, g.placement_m_to,
    g.real_clicks, g.real_spend, g.real_orders, g.real_gp, g.real_net, g.real_side, g.side_correct,
    g.err_net, g.abs_err_net, g.click_bucket, l.min_clicks,
    CASE
      WHEN g.ungradable_reason IS NOT NULL THEN 'UNGRADABLE'
      WHEN g.real_clicks = 0 OR l.min_clicks IS NULL OR g.real_clicks < l.min_clicks THEN 'INCONCLUSIVE'
      WHEN g.side_correct THEN 'RIGHT'
      ELSE 'WRONG'
    END,
    g.ungradable_reason,
    graded_at_d, wm_d, grader_version_d,
    IF(g.prev_seq IS NOT NULL, reason, NULL)
  FROM _g1 g
  LEFT JOIN _line l
    ON l.predictor = g.predictor AND l.family = g.family AND l.calendar_state = g.calendar_state;

  SET n_inserted = @@row_count;

  ASSERT n_inserted = n_due
    AS 'SP_GRADE_PREDICTIONS: the rows inserted differ from the ledger rows due; a join dropped or doubled a prediction.';

  -- ── 7. the report card ────────────────────────────────────────────────────────────────────────
  CREATE TEMP TABLE _g AS
  SELECT g.*, DATE_TRUNC(g.as_of, WEEK(SUNDAY)) AS wk, (g.grade <> 'UNGRADABLE') AS ok
  FROM `onyga-482313.OI.FACT_PREDICTION_GRADE` g
  WHERE g.predictor <> 'FIXTURE'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY g.predictor, g.variant, g.as_of, g.campaign_id, g.keyword_id, g.scenario
                             ORDER BY g.regrade_seq DESC) = 1;

  -- every grade under its own family x state and under the predictor's rollup ('ALL', 'ALL')
  CREATE TEMP TABLE _gl AS
  WITH gx AS (
    SELECT g.* EXCEPT (family, calendar_state), x.family, x.calendar_state, x.is_rollup
    FROM _g g,
         UNNEST([STRUCT(g.family AS family, g.calendar_state AS calendar_state, FALSE AS is_rollup),
                 STRUCT('ALL' AS family, 'ALL' AS calendar_state, TRUE AS is_rollup)]) AS x
  ),
  wk_rank AS (
    SELECT predictor, variant, family, calendar_state, wk,
           DENSE_RANK() OVER (PARTITION BY predictor, variant, family, calendar_state ORDER BY wk DESC) AS wr
    FROM (SELECT DISTINCT predictor, variant, family, calendar_state, wk FROM gx)
  )
  SELECT gx.*, lv AS level, IF(lv = 'WINDOW', gx.wk, NULL) AS lv_wk
  FROM gx
  JOIN wk_rank w
    ON w.predictor = gx.predictor AND w.variant = gx.variant AND w.family = gx.family
   AND w.calendar_state = gx.calendar_state AND w.wk = gx.wk,
  UNNEST(ARRAY_CONCAT(['SINCE_START', 'WINDOW'], IF(w.wr <= 3, ['TRAILING_3'], ARRAY<STRING>[]))) AS lv;

  CREATE TEMP TABLE _sc_acc AS
  SELECT predictor, variant, family, calendar_state, level, lv_wk, 'ACCURACY' AS row_type, sel AS scenario,
         MIN(wk) AS window_from, DATE_ADD(MAX(wk), INTERVAL 6 DAY) AS window_to,
         COUNT(DISTINCT wk) AS n_windows, COUNT(DISTINCT as_of) AS n_nights,
         COUNTIF(inn) AS n_rows,
         COUNT(DISTINCT IF(inn, keyword_id, NULL)) AS keywords,
         SUM(IF(inn, pred_clicks, 0))  AS pred_clicks,  SUM(IF(inn, real_clicks, 0)) AS real_clicks,
         SUM(IF(inn, pred_spend, 0))   AS pred_spend,   SUM(IF(inn, real_spend, 0))  AS real_spend,
         SUM(IF(inn, pred_orders, 0))  AS pred_orders,  SUM(IF(inn, real_orders, 0)) AS real_orders,
         SUM(IF(inn, pred_gp, 0))      AS pred_gp,      SUM(IF(inn, real_gp, 0))     AS real_gp,
         SUM(IF(inn, pred_net, 0))     AS pred_net,     SUM(IF(inn, real_net, 0))    AS real_net,
         SUM(IF(inn, abs_err_net, 0))  AS mae_net_usd,
         SAFE_DIVIDE(SUM(IF(inn, abs_err_net, 0)), SUM(IF(inn, real_spend, 0)))                AS mae_net_share,
         SAFE_DIVIDE(SUM(IF(inn, err_net, 0)), SUM(IF(inn, real_spend, 0)))                    AS bias_share,
         SAFE_DIVIDE(SUM(IF(inn AND side_correct, real_spend, 0)), SUM(IF(inn, real_spend, 0))) AS side_accuracy,
         STRING_AGG(DISTINCT IF(inn, rule_version, NULL), ',' ORDER BY IF(inn, rule_version, NULL)) AS rule_versions,
         STRING_AGG(DISTINCT IF(inn, COALESCE(builder_version, 'pre-v27.170'), NULL), ','
                    ORDER BY IF(inn, COALESCE(builder_version, 'pre-v27.170'), NULL))      AS builder_versions
  FROM (
    SELECT g.*, sel,
           CASE sel
             WHEN 'APPLIED'    THEN g.ok AND g.is_applied
             WHEN 'DO_NOTHING' THEN g.ok AND g.scenario = 'DO_NOTHING'
             ELSE                   g.ok AND g.scenario = 'ACT'
           END AS inn
    FROM _gl g, UNNEST(['APPLIED', 'DO_NOTHING', 'ACT']) AS sel
  )
  GROUP BY predictor, variant, family, calendar_state, level, lv_wk, sel;

  CREATE TEMP TABLE _sc_money AS
  WITH m AS (
    SELECT predictor, variant, family, calendar_state, level, lv_wk,
           MIN(wk) AS window_from, DATE_ADD(MAX(wk), INTERVAL 6 DAY) AS window_to,
           COUNT(DISTINCT wk) AS n_windows, COUNT(DISTINCT as_of) AS n_nights,
           COUNTIF(ok AND scenario = 'DO_NOTHING') AS n_rows,
           SAFE_DIVIDE(SUM(IF(ok AND scenario = 'DO_NOTHING' AND is_applied, real_net, 0)),
                       SUM(IF(ok AND scenario = 'DO_NOTHING' AND is_applied, real_spend, 0)))       AS dn_net_per_dollar,
           SAFE_DIVIDE(SUM(IF(ok AND scenario = 'ACT' AND is_applied, real_net, 0)),
                       SUM(IF(ok AND scenario = 'ACT' AND is_applied, pred_spend, 0)))              AS act_net_per_pred_dollar,
           SAFE_DIVIDE(SUM(IF(ok AND scenario = 'DO_NOTHING',
                              alloc_spend * IF(real_spend > 0, real_net / real_spend, 0), NULL)),
                       SUM(IF(ok AND scenario = 'DO_NOTHING', alloc_spend, NULL)))                  AS counterfactual_net_per_alloc,
           SUM(IF(ok AND scenario = 'DO_NOTHING', alloc_spend, NULL))                               AS alloc_spend,
           SUM(IF(ok AND scenario = 'DO_NOTHING' AND real_spend = 0, alloc_spend, NULL))            AS alloc_unrealized,
           COUNTIF(ok AND applied_scenario = 'ACT' AND scenario = 'ACT')                            AS lift_rows,
           SUM(IF(ok AND applied_scenario = 'ACT', IF(scenario = 'ACT', pred_net, -pred_net), 0))   AS lift_pred_sum,
           SUM(IF(ok AND applied_scenario = 'ACT', IF(scenario = 'ACT', real_net, -pred_net), 0))   AS lift_real_sum,
           SUM(IF(ok, IF(scenario = 'ACT', pred_net, -pred_net), 0))                                AS pred_lift_all,
           SAFE_DIVIDE(SUM(IF(ok AND scenario = 'DO_NOTHING', abs_err_net, 0)),
                       SUM(IF(ok AND scenario = 'DO_NOTHING', real_spend, 0)))                      AS control_mae_net_share,
           SAFE_DIVIDE(SUM(IF(ok AND scenario = 'DO_NOTHING', err_net, 0)),
                       SUM(IF(ok AND scenario = 'DO_NOTHING', real_spend, 0)))                      AS control_bias_share,
           STRING_AGG(DISTINCT IF(ok, rule_version, NULL), ',' ORDER BY IF(ok, rule_version, NULL)) AS rule_versions,
           STRING_AGG(DISTINCT IF(ok, COALESCE(builder_version, 'pre-v27.170'), NULL), ','
                      ORDER BY IF(ok, COALESCE(builder_version, 'pre-v27.170'), NULL))              AS builder_versions
    FROM _gl
    GROUP BY predictor, variant, family, calendar_state, level, lv_wk
  )
  SELECT m.* EXCEPT (lift_pred_sum, lift_real_sum),
         'MONEY' AS row_type,
         IF(m.lift_rows = 0, NULL, m.lift_pred_sum) AS pred_lift,
         IF(m.lift_rows = 0, NULL, m.lift_real_sum) AS realised_lift,
         'DO_NOTHING_PREDICTION' AS lift_control,
         IF(m.lift_rows = 0,
            'Lift is ungraded: no ACT scenario applied on these rows (no uploaded plan matched). The control is the DO_NOTHING prediction; its own accuracy is control_mae_net_share / control_bias_share.',
            FORMAT('Lift over %d ACT-applied rows, against the DO_NOTHING prediction (control_mae_net_share beside it).', m.lift_rows)) AS detail
  FROM m;

  CREATE TEMP TABLE _sc_curve AS
  SELECT g.predictor, g.variant, g.family, g.calendar_state, g.level, g.lv_wk, 'CURVE' AS row_type,
         b.bucket, b.bucket_floor,
         MIN(g.wk) AS window_from, DATE_ADD(MAX(g.wk), INTERVAL 6 DAY) AS window_to,
         COUNT(DISTINCT g.wk) AS n_windows, COUNT(DISTINCT g.as_of) AS n_nights,
         COUNTIF(g.click_bucket = b.bucket) AS bucket_rows,
         SUM(IF(g.click_bucket = b.bucket, g.real_spend, 0)) AS bucket_spend,
         SAFE_DIVIDE(SUM(IF(g.click_bucket = b.bucket AND g.side_correct, g.real_spend, 0)),
                     SUM(IF(g.click_bucket = b.bucket, g.real_spend, 0))) AS bucket_accuracy,
         IF(b.bucket_floor = 0, NULL, COUNTIF(g.real_clicks >= b.bucket_floor)) AS cum_rows,
         IF(b.bucket_floor = 0, NULL, SUM(IF(g.real_clicks >= b.bucket_floor, g.real_spend, 0))) AS cum_spend,
         IF(b.bucket_floor = 0, NULL,
            SAFE_DIVIDE(SUM(IF(g.real_clicks >= b.bucket_floor AND g.side_correct, g.real_spend, 0)),
                        SUM(IF(g.real_clicks >= b.bucket_floor, g.real_spend, 0)))) AS cum_accuracy
  FROM _gl g
  CROSS JOIN UNNEST([STRUCT('0' AS bucket, 0 AS bucket_floor), ('1-5', 1), ('6-10', 6), ('11-20', 11),
                     ('21-40', 21), ('41-80', 41), ('81+', 81)]) AS b
  WHERE NOT g.is_rollup AND g.ok AND g.scenario = 'DO_NOTHING'
  GROUP BY g.predictor, g.variant, g.family, g.calendar_state, g.level, g.lv_wk, b.bucket, b.bucket_floor;

  CREATE TEMP TABLE _sc_line AS
  WITH grp AS (
    SELECT predictor, variant, family, calendar_state, level, lv_wk,
           MIN(wk) AS window_from, DATE_ADD(MAX(wk), INTERVAL 6 DAY) AS window_to,
           COUNT(DISTINCT wk) AS n_windows, COUNT(DISTINCT as_of) AS n_nights,
           COUNT(*) AS n_rows,
           SAFE_DIVIDE(SUM(real_spend), SUM(real_clicks)) AS settled_cpc
    FROM _gl
    WHERE NOT is_rollup AND ok AND scenario = 'DO_NOTHING'
    GROUP BY predictor, variant, family, calendar_state, level, lv_wk
  ),
  ln AS (
    SELECT predictor, variant, family, calendar_state, level, lv_wk,
           MIN(IF(cum_accuracy >= min_acc_d AND cum_rows >= min_rows_d, bucket_floor, NULL)) AS min_clicks,
           ARRAY_AGG(STRUCT(bucket_floor AS fl, cum_accuracy AS acc, cum_rows AS n)
                     ORDER BY IF(cum_rows >= min_rows_d, 0, 1), cum_accuracy DESC, bucket_floor
                     LIMIT 1)[SAFE_OFFSET(0)] AS best
    FROM _sc_curve
    WHERE bucket_floor >= 1 AND cum_rows > 0
    GROUP BY predictor, variant, family, calendar_state, level, lv_wk
  )
  SELECT g.*, 'LINE' AS row_type,
         ln.min_clicks,
         ln.min_clicks * g.settled_cpc AS min_dollars,
         min_acc_d AS bar_side_accuracy,
         min_rows_d AS bar_min_rows,
         CASE
           WHEN ln.min_clicks IS NOT NULL THEN
             FORMAT('Line at %d realised clicks (about $%.2f at $%.2f per click): from there up the side the plan called is right on at least %.0f%% of the spend, with at least %d rows behind it.',
                    ln.min_clicks, ln.min_clicks * g.settled_cpc, g.settled_cpc, 100 * min_acc_d, min_rows_d)
           WHEN ln.best.fl IS NULL THEN
             FORMAT('No line: no graded row has a click; a floor needs side accuracy %.2f with at least %d rows.', min_acc_d, min_rows_d)
           ELSE
             FORMAT('No line: no click floor reaches side accuracy %.2f with at least %d rows behind it. Best %s: %.3f at %d+ clicks over %d rows.',
                    min_acc_d, min_rows_d,
                    IF(ln.best.n >= min_rows_d, 'with enough rows', 'of any size (none has enough rows)'),
                    COALESCE(ln.best.acc, 0), ln.best.fl, ln.best.n)
         END AS detail
  FROM grp g
  LEFT JOIN ln
    ON ln.predictor = g.predictor AND ln.variant = g.variant AND ln.family = g.family
   AND ln.calendar_state = g.calendar_state AND ln.level = g.level
   AND ln.lv_wk IS NOT DISTINCT FROM g.lv_wk;

  CREATE TEMP TABLE _sc_honesty AS
  SELECT predictor, variant, family, calendar_state, level, lv_wk, 'HONESTY' AS row_type,
         MIN(wk) AS window_from, DATE_ADD(MAX(wk), INTERVAL 6 DAY) AS window_to,
         COUNT(DISTINCT wk) AS n_windows, COUNT(DISTINCT as_of) AS n_nights,
         COUNTIF(scenario = 'DO_NOTHING')                                                AS n_rows,
         COUNTIF(scenario = 'DO_NOTHING' AND grade = 'RIGHT')                            AS n_right,
         COUNTIF(scenario = 'DO_NOTHING' AND grade = 'WRONG')                            AS n_wrong,
         COUNTIF(scenario = 'DO_NOTHING' AND grade = 'INCONCLUSIVE')                     AS n_inconclusive,
         COUNTIF(scenario = 'DO_NOTHING' AND grade = 'UNGRADABLE')                       AS n_ungradable,
         COUNTIF(scenario = 'DO_NOTHING' AND NOT act_is_noop AND applied_scenario = 'DO_NOTHING') AS n_act_no_matching_action,
         COUNTIF(scenario = 'DO_NOTHING' AND applied_scenario = 'OTHER_ACTION')          AS n_other_action,
         COUNTIF(scenario = 'DO_NOTHING' AND placement_changed)                          AS n_placement_changed,
         COUNTIF(scenario = 'DO_NOTHING' AND real_clicks = 0 AND basis_clicks > 0)       AS n_predicted_but_zero_clicks
  FROM _gl
  GROUP BY predictor, variant, family, calendar_state, level, lv_wk;

  CREATE TEMP TABLE _sc_young AS
  WITH lk AS (   -- one row per plan row of the ledger
    SELECT l.predictor, l.variant, l.family, l.as_of, l.horizon_to,
           (gk.predictor IS NOT NULL) AS graded
    FROM _led l
    LEFT JOIN (SELECT DISTINCT predictor, variant, as_of, campaign_id, keyword_id
               FROM _g WHERE scenario = 'DO_NOTHING') gk
      ON gk.predictor = l.predictor AND gk.variant = l.variant AND gk.as_of = l.as_of
     AND gk.campaign_id = l.campaign_id AND gk.keyword_id = l.keyword_id
    WHERE l.scenario = 'DO_NOTHING' AND l.predictor <> 'FIXTURE'
  ),
  y AS (
    SELECT lk.predictor, lk.variant, f AS family,
           MIN(lk.as_of) AS first_night, MAX(lk.as_of) AS last_night,
           COUNT(*) AS ledger_rows, COUNTIF(lk.graded) AS graded_rows, COUNTIF(NOT lk.graded) AS waiting_rows,
           MIN(IF(NOT lk.graded, DATE_ADD(lk.horizon_to, INTERVAL settle_days_d DAY), NULL)) AS next_due_watermark
    FROM lk, UNNEST([lk.family, 'ALL']) AS f
    GROUP BY lk.predictor, lk.variant, f
  )
  SELECT predictor, variant, family, 'ALL' AS calendar_state, 'SINCE_START' AS level, 'YOUNG' AS row_type,
         first_night AS window_from, last_night AS window_to,
         ledger_rows, graded_rows, waiting_rows, next_due_watermark,
         CASE
           WHEN waiting_rows = 0 THEN
             FORMAT('%s, %s: every one of its %d predictions is graded.', family, predictor, ledger_rows)
           WHEN graded_rows = 0 THEN
             FORMAT('%s, %s: nothing is old enough to grade. %d predictions wait; the first becomes gradable when the ads watermark reaches %t (its horizon end + %d settled days); the watermark is %t.',
                    family, predictor, waiting_rows, next_due_watermark, settle_days_d, wm_d)
           ELSE
             FORMAT('%s, %s: %d of %d predictions graded; %d wait, the next gradable when the ads watermark reaches %t (horizon end + %d settled days); the watermark is %t.',
                    family, predictor, graded_rows, ledger_rows, waiting_rows, next_due_watermark, settle_days_d, wm_d)
         END AS detail
  FROM y;

  CREATE TEMP TABLE _sc_next AS
  WITH night AS (SELECT MAX(as_of) AS as_of FROM _led WHERE predictor <> 'FIXTURE'),
  t AS (
    SELECT l.*, f AS fam
    FROM _led l
    JOIN night n ON n.as_of = l.as_of,
    UNNEST([l.family, 'ALL']) AS f
    WHERE l.is_live_plan AND l.predictor <> 'FIXTURE'
  ),
  s AS (
    SELECT predictor, variant, fam AS family, MAX(calendar_state) AS calendar_state, MAX(as_of) AS as_of,
           MIN(horizon_from) AS window_from, MAX(horizon_to) AS window_to,
           COUNTIF(scenario = 'DO_NOTHING') AS n_rows,
           SUM(IF(scenario = 'DO_NOTHING', pred_net, 0))   AS dn_pred_net,
           SUM(IF(scenario = 'ACT', pred_net, 0))          AS act_pred_net,
           SUM(IF(scenario = 'DO_NOTHING', pred_spend, 0)) AS dn_pred_spend,
           SUM(IF(scenario = 'ACT', pred_spend, 0))        AS act_pred_spend
    FROM t
    GROUP BY predictor, variant, fam
  )
  SELECT predictor, variant, family, calendar_state, 'TONIGHT' AS level, 'NEXT_WEEK' AS row_type,
         window_from, window_to, 1 AS n_nights, n_rows,
         dn_pred_net, act_pred_net, dn_pred_spend, act_pred_spend,
         FORMAT('%s, night %t, plan %s (live): do nothing %s$%.2f; upload the plan %s$%.2f (predicted net over %t to %t; spend $%.2f vs $%.2f; %d keywords).',
                family, as_of, variant,
                IF(dn_pred_net < 0, '-', ''), ABS(dn_pred_net),
                IF(act_pred_net < 0, '-', ''), ABS(act_pred_net),
                window_from, window_to, dn_pred_spend, act_pred_spend, n_rows) AS detail
  FROM s;

  CREATE OR REPLACE TABLE `onyga-482313.OI.T_PREDICTION_SCORECARD`
  OPTIONS (description = "v27.173 (2026-10-03, learning-contract piece 2 Task 5): the report card of the plan's predictions, rebuilt (CREATE OR REPLACE) by SP_GRADE_PREDICTIONS at the end of every run from the current grades of FACT_PREDICTION_GRADE (predictor FIXTURE excluded) and, for YOUNG and NEXT_WEEK, from V_PREDICTION_LEDGER. Grain predictor x variant x family x calendar_state x level x row_type (+ scenario on ACCURACY, + bucket on CURVE, + the week on WINDOW); family/calendar_state 'ALL' = the predictor's rollup. Levels WINDOW (Sunday-start week of as_of), TRAILING_3 (the group's three most recent graded windows), SINCE_START; TONIGHT for NEXT_WEEK. Row types ACCURACY (applied / DO_NOTHING / ACT: mae_net_usd, mae_net_share, bias_share, spend-weighted side_accuracy), MONEY (dn_net_per_dollar, act_net_per_pred_dollar, counterfactual_net_per_alloc = FN_PLAN_SCORECARD's GRADE metric, pred_lift / realised_lift over ACT-applied rows, lift_control DO_NOTHING_PREDICTION), CURVE (per click bucket and cumulative side accuracy), LINE (min_clicks at MIN_INVEST_SIDE_ACCURACY with MIN_INVEST_MIN_ROWS rows, min_dollars), HONESTY (ungradable, ACT with no matching action, other action, placement changed, predicted but zero clicks), YOUNG (what waits and when it becomes gradable), NEXT_WEEK (tonight's live plan per family: do nothing vs upload the plan, predicted net). UNGRADABLE rows enter HONESTY only. SOP: architecture/LEARNING.md 5.")
  AS
  SELECT
    CAST(predictor AS STRING)                    AS predictor,
    CAST(variant AS STRING)                      AS variant,
    CAST(family AS STRING)                       AS family,
    CAST(calendar_state AS STRING)               AS calendar_state,
    CAST(level AS STRING)                        AS level,
    CAST(row_type AS STRING)                     AS row_type,
    CAST(scenario AS STRING)                     AS scenario,
    CAST(bucket AS STRING)                       AS bucket,
    CAST(bucket_floor AS INT64)                  AS bucket_floor,
    CAST(window_from AS DATE)                    AS window_from,
    CAST(window_to AS DATE)                      AS window_to,
    CAST(n_windows AS INT64)                     AS n_windows,
    CAST(n_nights AS INT64)                      AS n_nights,
    CAST(n_rows AS INT64)                        AS n_rows,
    CAST(keywords AS INT64)                      AS keywords,
    CAST(pred_clicks AS FLOAT64)                 AS pred_clicks,
    CAST(real_clicks AS FLOAT64)                 AS real_clicks,
    CAST(pred_spend AS FLOAT64)                  AS pred_spend,
    CAST(real_spend AS FLOAT64)                  AS real_spend,
    CAST(pred_orders AS FLOAT64)                 AS pred_orders,
    CAST(real_orders AS FLOAT64)                 AS real_orders,
    CAST(pred_gp AS FLOAT64)                     AS pred_gp,
    CAST(real_gp AS FLOAT64)                     AS real_gp,
    CAST(pred_net AS FLOAT64)                    AS pred_net,
    CAST(real_net AS FLOAT64)                    AS real_net,
    CAST(mae_net_usd AS FLOAT64)                 AS mae_net_usd,
    CAST(mae_net_share AS FLOAT64)               AS mae_net_share,
    CAST(bias_share AS FLOAT64)                  AS bias_share,
    CAST(side_accuracy AS FLOAT64)               AS side_accuracy,
    CAST(dn_net_per_dollar AS FLOAT64)           AS dn_net_per_dollar,
    CAST(act_net_per_pred_dollar AS FLOAT64)     AS act_net_per_pred_dollar,
    CAST(counterfactual_net_per_alloc AS FLOAT64) AS counterfactual_net_per_alloc,
    CAST(alloc_spend AS FLOAT64)                 AS alloc_spend,
    CAST(alloc_unrealized AS FLOAT64)            AS alloc_unrealized,
    CAST(pred_lift AS FLOAT64)                   AS pred_lift,
    CAST(realised_lift AS FLOAT64)               AS realised_lift,
    CAST(lift_rows AS INT64)                     AS lift_rows,
    CAST(pred_lift_all AS FLOAT64)               AS pred_lift_all,
    CAST(lift_control AS STRING)                 AS lift_control,
    CAST(control_mae_net_share AS FLOAT64)       AS control_mae_net_share,
    CAST(control_bias_share AS FLOAT64)          AS control_bias_share,
    CAST(bucket_rows AS INT64)                   AS bucket_rows,
    CAST(bucket_spend AS FLOAT64)                AS bucket_spend,
    CAST(bucket_accuracy AS FLOAT64)             AS bucket_accuracy,
    CAST(cum_rows AS INT64)                      AS cum_rows,
    CAST(cum_spend AS FLOAT64)                   AS cum_spend,
    CAST(cum_accuracy AS FLOAT64)                AS cum_accuracy,
    CAST(min_clicks AS INT64)                    AS min_clicks,
    CAST(min_dollars AS FLOAT64)                 AS min_dollars,
    CAST(settled_cpc AS FLOAT64)                 AS settled_cpc,
    CAST(bar_side_accuracy AS FLOAT64)           AS bar_side_accuracy,
    CAST(bar_min_rows AS INT64)                  AS bar_min_rows,
    CAST(n_right AS INT64)                       AS n_right,
    CAST(n_wrong AS INT64)                       AS n_wrong,
    CAST(n_inconclusive AS INT64)                AS n_inconclusive,
    CAST(n_ungradable AS INT64)                  AS n_ungradable,
    CAST(n_act_no_matching_action AS INT64)      AS n_act_no_matching_action,
    CAST(n_other_action AS INT64)                AS n_other_action,
    CAST(n_placement_changed AS INT64)           AS n_placement_changed,
    CAST(n_predicted_but_zero_clicks AS INT64)   AS n_predicted_but_zero_clicks,
    CAST(ledger_rows AS INT64)                   AS ledger_rows,
    CAST(graded_rows AS INT64)                   AS graded_rows,
    CAST(waiting_rows AS INT64)                  AS waiting_rows,
    CAST(next_due_watermark AS DATE)             AS next_due_watermark,
    CAST(dn_pred_net AS FLOAT64)                 AS dn_pred_net,
    CAST(act_pred_net AS FLOAT64)                AS act_pred_net,
    CAST(dn_pred_spend AS FLOAT64)               AS dn_pred_spend,
    CAST(act_pred_spend AS FLOAT64)              AS act_pred_spend,
    CAST(rule_versions AS STRING)                AS rule_versions,
    CAST(builder_versions AS STRING)             AS builder_versions,
    CAST(detail AS STRING)                       AS detail,
    wm_d                                         AS watermark,
    grader_version_d                             AS grader_version,
    graded_at_d                                  AS scored_at
  FROM (
    SELECT * FROM _sc_acc
    FULL OUTER UNION ALL BY NAME SELECT * FROM _sc_money
    FULL OUTER UNION ALL BY NAME SELECT * FROM _sc_curve
    FULL OUTER UNION ALL BY NAME SELECT * FROM _sc_line
    FULL OUTER UNION ALL BY NAME SELECT * FROM _sc_honesty
    FULL OUTER UNION ALL BY NAME SELECT * FROM _sc_young
    FULL OUTER UNION ALL BY NAME SELECT * FROM _sc_next
  );

  -- ── the report ────────────────────────────────────────────────────────────────────────────────
  SELECT FORMAT(
    'SP_GRADE_PREDICTIONS %s completed: watermark %t (FN_ADS_ANCHOR_CAP %t), SETTLE_HORIZON_DAYS %d; %d ledger rows due%s, %d inserted (%d first grades, %d re-grades); labels RIGHT %d, WRONG %d, INCONCLUSIVE %d, UNGRADABLE %d; applied ACT %d, DO_NOTHING %d, OTHER_ACTION %d; T_PREDICTION_SCORECARD %d rows; %d seconds',
    grader_version_d, wm_d, `onyga-482313.OI.FN_ADS_ANCHOR_CAP`(), settle_days_d, n_due,
    IF(regrade_from IS NULL, '', FORMAT(' (re-grade of the nights from %t: %s)', regrade_from, reason)),
    n_inserted,
    (SELECT COUNTIF(prev_seq IS NULL) FROM _g1), (SELECT COUNTIF(prev_seq IS NOT NULL) FROM _g1),
    (SELECT COUNTIF(grade = 'RIGHT') FROM `onyga-482313.OI.FACT_PREDICTION_GRADE` WHERE graded_at = graded_at_d),
    (SELECT COUNTIF(grade = 'WRONG') FROM `onyga-482313.OI.FACT_PREDICTION_GRADE` WHERE graded_at = graded_at_d),
    (SELECT COUNTIF(grade = 'INCONCLUSIVE') FROM `onyga-482313.OI.FACT_PREDICTION_GRADE` WHERE graded_at = graded_at_d),
    (SELECT COUNTIF(grade = 'UNGRADABLE') FROM `onyga-482313.OI.FACT_PREDICTION_GRADE` WHERE graded_at = graded_at_d),
    (SELECT COUNTIF(scenario = 'DO_NOTHING' AND applied_scenario = 'ACT') FROM _g1),
    (SELECT COUNTIF(scenario = 'DO_NOTHING' AND applied_scenario = 'DO_NOTHING') FROM _g1),
    (SELECT COUNTIF(scenario = 'DO_NOTHING' AND applied_scenario = 'OTHER_ACTION') FROM _g1),
    (SELECT COUNT(*) FROM `onyga-482313.OI.T_PREDICTION_SCORECARD`),
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), graded_at_d, SECOND)
  ) AS log_message;

  SELECT as_of, predictor, scenario, grade, applied_scenario, COUNT(*) AS inserted
  FROM `onyga-482313.OI.FACT_PREDICTION_GRADE`
  WHERE graded_at = graded_at_d
  GROUP BY as_of, predictor, scenario, grade, applied_scenario
  ORDER BY as_of, predictor, scenario, grade, applied_scenario;
END;
