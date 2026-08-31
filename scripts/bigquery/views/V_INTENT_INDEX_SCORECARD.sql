CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_INDEX_SCORECARD`
OPTIONS (description = "Walk-forward verdict per index per month for the intent CVR curve, over the trailing 18 target months. For each target month M the base rate is fitted on observations strictly BEFORE M and scored against what M actually did; errors are weighted by clicks so verdicts follow the money. ADD_ONE_IN asks whether a candidate index helps; LEAVE_ONE_OUT asks whether an index still earns its place, without which the registry only ever grows. err_delta_pct is the RELATIVE change in weighted absolute error, so -1.0 means the error fell by one percent of itself. Bias is checked alongside error because an index can lower error while skewing the level -- which is exactly how the full-history pooling defect went unnoticed. A POOLED all-months row per index x test carries target_month NULL plus months_improved / months_scored: an index that wins eleven months and loses December is a different thing from one that wins six and loses six, and measured 2026-08-31 season_month is emphatically the second kind -- it pools to IMPROVES at -16.2% while 11 of its 18 individual months read HURTS. READ THE POOLED ROW AND THE MONTHS TOGETHER; neither alone is the answer. THREE STATED LIMITATIONS, all in the header: the index views are NOT re-fitted per target month, the base here is flat-pooled and not the shadow's recency-weighted base, and neither index is is_active so LEAVE_ONE_OUT is hypothetical. THIS VIEW PROMOTES NOTHING; is_active is written by a human. READ THE MATERIALISED COPY, T_INTENT_INDEX_SCORECARD -- this view costs ~6,200 slot-seconds per scan. Acceptance: scripts/bigquery/tests/INTENT_INDEX_acceptance.sql R12-R14, R16. Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md")
AS
-- =============================================================================================
-- V_INTENT_INDEX_SCORECARD
-- The evidence layer for DE_INTENT_INDEX_REGISTRY. Grain: index_name x test_kind x target_month,
-- plus one POOLED row per index x test carrying target_month = NULL.
--
-- Spec section 5 defines the contract. Verdict order, evaluated exactly as written there:
--   1. INSUFFICIENT  clicks_scored < INTENT_IDX_MIN_SCORED_CLICKS
--   2. HURTS         err_delta_pct >= +1.0  OR  ABS(bias_with-1) > ABS(bias_without-1) + 0.02
--   3. IMPROVES      err_delta_pct <= -1.0  AND ABS(bias_with-1) <= ABS(bias_without-1) + 0.02
--   4. NEUTRAL       otherwise
-- The 0.02 bias tolerance stops trivial jitter from vetoing a genuine error reduction.
--
-- ---------------------------------------------------------------------------------------------
-- WHAT THE TWO TESTS MEAN TODAY, WHEN THE ACTIVE SET IS EMPTY
-- Both registry rows are is_active = FALSE, so the genuinely active set is {} and the shadow
-- curve multiplies every row by exactly 1.0000. That has a different consequence for each test
-- and the difference is NOT cosmetic:
--   * ADD_ONE_IN is measured against the real baseline. "without" is base_cvr alone, which IS
--     the empty active set. This test is answering the question it names.
--   * LEAVE_ONE_OUT has nothing to remove. It is therefore evaluated against a HYPOTHETICAL
--     active set = THE WHOLE REGISTRY: "with" is base x season_month x season_phase, "without"
--     drops the one index named. It answers "if both were promoted, would this one still earn
--     its place", which is the question that matters at the Task 9 promotion decision and the
--     only version of the test that can produce a row at all today.
-- THIS VIEW DELIBERATELY DOES NOT READ is_active. If it did, LEAVE_ONE_OUT would return zero
-- rows, R12 (every registered index is scored under both tests) would fail, and Task 7 would
-- have no evidence to gate on. When an index IS promoted the two tests converge on the same
-- baseline and this note stops applying -- RE-READ IT THEN.
--
-- ---------------------------------------------------------------------------------------------
-- INDEXES ARE APPLIED EXACTLY AS THE SHADOW CURVE WOULD APPLY THEM -- SHRUNK, NOT RAW
-- DEVIATION FROM THE PLAN'S DRAFT SQL, deliberate. The draft multiplied by the published
-- index_value. V_INTENT_CVR_CURVE_SHADOW does not: it applies
--     1 + (index_value - 1) * LEAST(1, support_clicks / INTENT_IDX_MIN_SUPPORT)
-- so a thin cell is pulled back to 1.000 and contributes nothing. That gate is load-bearing --
-- spec section 7.5 records that 161 of 204 published season_phase rows sit below it and are
-- pinned to 1.000 -- so scoring the UNSHRUNK index would deliver a verdict about a curve that
-- cannot ship.
-- MEASURED BOTH WAYS 2026-08-31, AND TODAY IT CHANGES NO VERDICT. Pooled err_delta_pct:
--     test                            shrunk (this view)   unshrunk (plan draft)   verdict
--     season_month  ADD_ONE_IN             -16.23%              -16.23%            IMPROVES both
--     season_month  LEAVE_ONE_OUT          -16.20%              -16.09%            IMPROVES both
--     season_phase  ADD_ONE_IN              -0.53%               -0.28%            NEUTRAL  both
--     season_phase  LEAVE_ONE_OUT           -0.49%               -0.11%            NEUTRAL  both
-- season_month is unmoved because its support (a raw click count pooled at intent_type) clears
-- INTENT_IDX_MIN_SUPPORT everywhere, so the shrinkage never binds on it. season_phase moves, but
-- not across a threshold. THE DEVIATION IS KEPT ANYWAY, because the reason for it is structural
-- rather than about today's number: this view has to score the curve that would actually run, and
-- spec section 7.5 records that the gate's effective strictness LOOSENS on its own as history
-- accumulates. The day it stops pinning 161 of 204 phase rows to 1.000 is the day the two columns
-- diverge, and by then the choice must already be the right one.
--
-- ---------------------------------------------------------------------------------------------
-- THREE LIMITATIONS. STATED, NOT FIXED. Read them before reading a verdict.
--
-- L1. THE INDEXES ARE NOT WALK-FORWARD. The base rate is: fitted_through < target_month is
--     enforced by construction and checked by R14. The index views are NOT -- they are read as
--     deployed, fitted on the whole of history including the target month and everything after
--     it. So an index verdict is OPTIMISTIC by an unmeasured amount: part of what it "predicts"
--     it has already seen. Fixing it means re-fitting each index inside each of the 18 target
--     months, which is a second and a third aggregation of the observation set and is what the
--     CPU ceiling in this chain does not have room for. The honest reading of an IMPROVES is
--     "worth taking to the money gate", never "proven".
--
-- L2. THE BASE HERE IS FLAT-POOLED; THE SHADOW'S IS RECENCY-WEIGHTED. This view fits base_cvr on
--     all prior months with equal weight (the plan's design). V_INTENT_CVR_CURVE_SHADOW fits it
--     on nested 1/2/3/6/12 windows. So a verdict says "this index helps ON TOP OF A FLAT BASE",
--     not "on top of the base that will ship". The two changes are separable by design -- Task 6
--     (V_INTENT_BASE_TUNING) measures the recency shape and this view measures the indexes -- but
--     nothing here proves they compose. Visible in the numbers: bias_without pools to 0.7956 and
--     bias_with to 0.7954, so every level column on this view sits ~1.26x under the realised CVR.
--     That is the D3 under-pricing, still present because the base here is flat and carries no
--     INTENT_CVR_CALIBRATION; the indexes do not touch it, and by contract cannot -- each is
--     normalised to a clicks-weighted mean of 1.000. So read a verdict as a statement about
--     SHAPE only. Task 8's money gate runs against the shadow, which is where the composed
--     answer -- recency, calibration and indexes together -- comes from.
--
-- L3. TWO OBSERVATIONS PER CALENDAR MONTH, AT MOST. Ads data starts 2024-09-05; 18 target months
--     end at 2025-03. A yearly-seasonal index therefore gets at most two observations of any one
--     month, which spec section 8 already flags and which is a reason to prefer manual promotion.
--
-- ---------------------------------------------------------------------------------------------
-- WHAT IT SAYS TODAY, measured 2026-08-31 at watermark 2026-08-31, on 1,162 predictions and
-- 827,848 clicks. Recorded because Task 7 gates on it and because two of the four numbers
-- contradict the spec's own prediction in section 6 step 3.
--     index         test            pooled err_delta   verdict    per-month IMPROVES/NEUTRAL/HURTS
--     season_month  ADD_ONE_IN          -16.23%        IMPROVES          6 / 1 / 11
--     season_month  LEAVE_ONE_OUT       -16.20%        IMPROVES          6 / 1 / 11
--     season_phase  ADD_ONE_IN           -0.53%        NEUTRAL           3 / 11 / 4
--     season_phase  LEAVE_ONE_OUT        -0.49%        NEUTRAL           3 / 11 / 4
-- NOT ONE MONTH READS INSUFFICIENT. Spec section 6 step 3 expected season_month to be
-- INSUFFICIENT "on the great majority of cells at today's grain"; every one of the 18 months
-- clears INTENT_IDX_MIN_SCORED_CLICKS = 500 by two orders of magnitude, because the threshold is
-- a per-MONTH click total and the pooling grain the spec had in mind was per-CELL. The check is
-- doing what spec section 5 defines; the prediction was about a different denominator.
-- season_month's own split is the thing to argue about: it improves May-Jul 2025 and Dec-Feb and
-- hurts in eleven other months, so the pooled IMPROVES is a small number of high-click months
-- outvoting the rest. season_phase improves in Jan-Mar 2026, which is the Valentine's/Easter
-- window it was built for, and is inert (NEUTRAL) in eleven months, which is what a fix reaching
-- ~9% of clicks should look like.
--
-- ---------------------------------------------------------------------------------------------
-- COST: THE OBSERVATION SET IS SCANNED EXACTLY ONCE, AND THAT IS A DESIGN CONSTRAINT
-- BigQuery inlines a CTE at every reference rather than materialising it. The plan's draft
-- referenced `scored` in four separate GROUP BYs and `obs` in three CTEs (prior, fitted, actual),
-- which is seven evaluations of a chain that regexes 337k search terms across 18 target months.
-- That is the same wall this project has already hit twice: the Task 4 acceptance file was
-- REJECTED by BigQuery at 97,066 CPU-seconds against a 33,500 on-demand ceiling, and
-- T_INTENT_CVR_CURVE exists because the live curve cost ~27k CPU-seconds per scan.
-- So the shape here is deliberate and must not be "simplified" back:
--   * `cell` joins targets to obs ONCE, on o.mo <= t.target_month, and separates the fitting
--     window from the target month with IF(o.mo < t.target_month, ...) / IF(o.mo = ..., ...).
--     One join replaces the draft's separate `fitted` and `actual` scans.
--   * the global prior is a WINDOW FUNCTION over that same aggregate, not a third scan. It is
--     arithmetically identical: SUM(fit_orders)/SUM(fit_clicks) over every cell at that target
--     month IS the pooled prior over all observations before it.
--   * the four index x test rows come from ONE per-month aggregation carrying all eight sums,
--     fanned out afterwards by CROSS JOIN UNNEST over 18 rows.
--   * the pooled row comes from GROUP BY GROUPING SETS, so `m` is read once for both levels
--     rather than UNION ALLed with an aggregate of itself.
-- MEASURED 2026-08-31: 6,215 slot-seconds / 116 MB, against a budget that scales at ~256
-- CPU-seconds per MB billed. The draft shape was not measured because it does not need to be --
-- it is the shape that was already rejected once.
--
-- ---------------------------------------------------------------------------------------------
-- INTENT SOURCE: V_ADS_SEARCH_TERM_INTENT, NOT V_INTENT_RESOLVED
-- The curve reads V_INTENT_RESOLVED (the human-verified overlay). This view reads the raw
-- classifier, for two reasons: the two index views being scored are themselves defined on
-- V_ADS_SEARCH_TERM_INTENT, so their intent_key / intent_type domains match here; and it is
-- half the cost. THE CHOICE DOES NOT MOVE THE VERDICTS -- measured both ways 2026-08-31:
--     source                    season_month ADD_ONE_IN   season_phase ADD_ONE_IN   slot-sec
--     V_ADS_SEARCH_TERM_INTENT  IMPROVES  -16.23%  6/18   NEUTRAL  -0.53%  3/18       6,215
--     V_INTENT_RESOLVED         IMPROVES  -15.14%  6/18   NEUTRAL  -0.09%  1/18      13,247
-- It does move the cell population (1,162 vs 1,766 predictions), so absolute errors are not
-- comparable across the two; the verdicts are.
--
-- MIN(intent_type) RATHER THAN ANY_VALUE. Two intent_keys carry more than one intent_type
-- (measured 2026-08-31 on V_INTENT_RESOLVED; the same shape exists here). ANY_VALUE would make
-- the season_month join key nondeterministic between runs, which is the recorded ANY_VALUE
-- pairing defect in a new place. MIN is total and cheap. It can disagree with the shadow curve's
-- own ANY_VALUE for those keys; they are two of thousands and carry no material clicks.
--
-- Dependencies: FACT_AMAZON_ADS, V_ADS_SEARCH_TERM_INTENT, DIM_PRODUCT, DE_COACH_THRESHOLDS,
--               V_INTENT_IDX_SEASON_MONTH, V_INTENT_IDX_SEASON_PHASE
-- Consumers: SP_SCORE_INTENT_INDEXES -> T_INTENT_INDEX_SCORECARD. Nothing reads this view live.
-- Project: onyga-482313 / Dataset: OI
-- =============================================================================================

WITH params AS (
  -- coach_mode / product_family filtered for the same reason the curve filters them: thresholds
  -- resolve on strategy_id + coach_mode, and an unfiltered MAX() would silently take a
  -- BLITZ-scoped or family-scoped row as if it were the GUARDIAN one.
  SELECT
    MAX(IF(threshold_key = 'INTENT_CVR_BASE_PRIOR_CLICKS', threshold_value, NULL)) AS k_base,
    MAX(IF(threshold_key = 'INTENT_IDX_MIN_SCORED_CLICKS', threshold_value, NULL)) AS min_scored,
    MAX(IF(threshold_key = 'INTENT_IDX_MIN_SUPPORT',       threshold_value, NULL)) AS idx_min_support
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id = 'INTENT' AND coach_mode = 'GUARDIAN' AND product_family IS NULL
),

wm AS (SELECT MAX(date) AS watermark FROM `onyga-482313.OI.FACT_AMAZON_ADS`),

-- Monthly observations at the curve's own cell grain. THE ONLY REFERENCE TO THE HEAVY CHAIN.
obs AS (
  SELECT d.product_short_name, i.intent_key,
         MIN(i.intent_type) AS intent_type,
         DATE_TRUNC(f.date, MONTH) AS mo,
         SUM(f.Ads_clicks) AS clicks, SUM(f.Ads_orders) AS orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  JOIN `onyga-482313.OI.V_ADS_SEARCH_TERM_INTENT` i ON i.search_term = f.search_term
  JOIN `onyga-482313.OI.DIM_PRODUCT` d              ON d.asin = f.ASIN_BY_CAMPAIGN_NAME
  WHERE f.campaign_id <> '-1' AND f.Ads_clicks > 0
    AND i.intent_key IS NOT NULL
    AND d.parent_name IS NOT NULL AND d.parent_name != 'UNKNOWN'
  GROUP BY 1, 2, 4
),

-- The 18 target months, ending at the watermark's own month. That month is PARTIAL at any
-- watermark other than a month end, so its clicks_scored is smaller than a full month's and it
-- is the row most likely to read INSUFFICIENT.
targets AS (
  SELECT DATE_TRUNC(DATE_SUB(wm.watermark, INTERVAL n MONTH), MONTH) AS target_month
  FROM wm, UNNEST(GENERATE_ARRAY(0, 17)) AS n
),

-- ONE join of targets to obs. `mo < target_month` is the fitting window, `mo = target_month` is
-- what actually happened. fitted_through is the newest month inside the fitting window, which is
-- what R14 reads to prove no future was consulted.
cell AS (
  SELECT t.target_month, o.product_short_name, o.intent_key,
         MIN(o.intent_type)                          AS intent_type,
         SUM(IF(o.mo < t.target_month, o.clicks, 0)) AS fit_clicks,
         SUM(IF(o.mo < t.target_month, o.orders, 0)) AS fit_orders,
         MAX(IF(o.mo < t.target_month, o.mo, NULL))  AS fitted_through,
         SUM(IF(o.mo = t.target_month, o.clicks, 0)) AS act_clicks,
         SUM(IF(o.mo = t.target_month, o.orders, 0)) AS act_orders
  FROM targets t
  JOIN obs o ON o.mo <= t.target_month
  GROUP BY 1, 2, 3
),

-- The global prior for shrinkage, as a window over the SAME aggregate rather than a second scan.
cell_p AS (
  SELECT c.*,
         SAFE_DIVIDE(SUM(c.fit_orders) OVER (PARTITION BY c.target_month),
                     NULLIF(SUM(c.fit_clicks) OVER (PARTITION BY c.target_month), 0)) AS prior_cvr
  FROM cell c
),

-- Both indexes, shrunk by their own support exactly as V_INTENT_CVR_CURVE_SHADOW shrinks them.
-- See the header: applying the raw published value would score a curve that cannot ship.
idx_month AS (
  SELECT s.intent_type, s.month_of_year,
         1.0 + (s.index_value - 1.0) * LEAST(1.0, SAFE_DIVIDE(s.support_clicks, p.idx_min_support)) AS iv
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_MONTH` s CROSS JOIN params p
),
idx_phase AS (
  SELECT s.intent_key, s.month_of_year,
         1.0 + (s.index_value - 1.0) * LEAST(1.0, SAFE_DIVIDE(s.support_clicks, p.idx_min_support)) AS iv
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE` s CROSS JOIN params p
),

-- One prediction per scored cell. COALESCE to 1.0 is the "index absent" case and is what makes
-- an index optional, matching the curve's own LEFT JOIN + COALESCE.
--   act_clicks >= 60 : the target month must carry enough clicks for its realised CVR to mean
--                      anything. Same cut the offline sweep used.
--   fit_clicks > 0   : a cell with no history before M has nothing to predict FROM; the draft
--                      excluded these via an inner join and this reproduces that.
scored AS (
  SELECT c.target_month, c.fitted_through,
         c.act_clicks AS clicks,
         SAFE_DIVIDE(c.act_orders, c.act_clicks) AS actual_cvr,
         SAFE_DIVIDE(c.fit_orders + p.k_base * c.prior_cvr, c.fit_clicks + p.k_base) AS base_cvr,
         COALESCE(im.iv, 1.0) AS iv_month,
         COALESCE(ip.iv, 1.0) AS iv_phase
  FROM cell_p c
  CROSS JOIN params p
  LEFT JOIN idx_month im ON im.intent_type    = c.intent_type
                        AND im.month_of_year  = EXTRACT(MONTH FROM c.target_month)
  LEFT JOIN idx_phase ip ON ip.intent_key     = c.intent_key
                        AND ip.month_of_year  = EXTRACT(MONTH FROM c.target_month)
  WHERE c.act_clicks >= 60 AND c.fit_clicks > 0
),

-- ALL EIGHT SUMS IN ONE AGGREGATION. e_* are click-weighted absolute errors, s_* are
-- click-weighted predicted volumes whose ratio to s_actual is the bias. Every test below is a
-- pair drawn from these; nothing needs a second pass over `scored`.
per_month AS (
  SELECT target_month,
         MAX(fitted_through) AS fitted_through,
         SUM(clicks)         AS clicks_scored,
         COUNT(*)            AS n_predictions,
         SUM(clicks * ABS(base_cvr                       - actual_cvr)) AS e_none,
         SUM(clicks * ABS(base_cvr * iv_month            - actual_cvr)) AS e_m,
         SUM(clicks * ABS(base_cvr            * iv_phase - actual_cvr)) AS e_p,
         SUM(clicks * ABS(base_cvr * iv_month * iv_phase - actual_cvr)) AS e_mp,
         SUM(clicks * base_cvr)                       AS s_none,
         SUM(clicks * base_cvr * iv_month)            AS s_m,
         SUM(clicks * base_cvr            * iv_phase) AS s_p,
         SUM(clicks * base_cvr * iv_month * iv_phase) AS s_mp,
         SUM(clicks * actual_cvr)                     AS s_actual
  FROM scored
  GROUP BY target_month
),

-- The four index x test rows, as a fan-out over 18 aggregated rows. ADD_ONE_IN compares against
-- the EMPTY set (e_none); LEAVE_ONE_OUT compares the full registry against the registry minus
-- the named index. Header, "WHAT THE TWO TESTS MEAN TODAY", is the argument for that asymmetry.
tests AS (
  SELECT pm.target_month, pm.fitted_through, pm.clicks_scored, pm.n_predictions, pm.s_actual,
         x.index_name, x.test_kind, x.e_with, x.e_without, x.sw, x.swo
  FROM per_month pm
  CROSS JOIN UNNEST([
    STRUCT('season_month' AS index_name, 'ADD_ONE_IN'    AS test_kind,
           pm.e_m  AS e_with, pm.e_none AS e_without, pm.s_m  AS sw, pm.s_none AS swo),
    STRUCT('season_phase',               'ADD_ONE_IN',
           pm.e_p,            pm.e_none,             pm.s_p,          pm.s_none),
    STRUCT('season_month',               'LEAVE_ONE_OUT',
           pm.e_mp,           pm.e_p,                pm.s_mp,         pm.s_p),
    STRUCT('season_phase',               'LEAVE_ONE_OUT',
           pm.e_mp,           pm.e_m,                pm.s_mp,         pm.s_m)
  ]) AS x
),

-- The per-month verdict, needed HERE and not only at the end because months_improved on the
-- pooled row counts it. Identical CASE to the published one; over a single month the aggregate
-- below sums one row, so the two cannot disagree.
m AS (
  SELECT t.*,
         CASE
           WHEN t.clicks_scored < p.min_scored THEN 'INSUFFICIENT'
           WHEN SAFE_DIVIDE(t.e_with - t.e_without, NULLIF(t.e_without, 0)) * 100 >= 1.0
             OR ABS(SAFE_DIVIDE(t.sw,  t.s_actual) - 1.0)
              > ABS(SAFE_DIVIDE(t.swo, t.s_actual) - 1.0) + 0.02 THEN 'HURTS'
           WHEN SAFE_DIVIDE(t.e_with - t.e_without, NULLIF(t.e_without, 0)) * 100 <= -1.0
            AND ABS(SAFE_DIVIDE(t.sw,  t.s_actual) - 1.0)
             <= ABS(SAFE_DIVIDE(t.swo, t.s_actual) - 1.0) + 0.02 THEN 'IMPROVES'
           ELSE 'NEUTRAL' END AS verdict_month
  FROM tests t CROSS JOIN params p
),

-- GROUPING SETS, NOT UNION ALL. Both the per-month level and the pooled level come out of ONE
-- read of `m`; a UNION ALL of `m` with an aggregate of `m` would re-inline the whole chain and
-- double the cost of the view for two extra rows per index.
rolled AS (
  SELECT index_name, test_kind, target_month,
         MAX(fitted_through) AS fitted_through,
         SUM(clicks_scored)  AS clicks_scored,
         SUM(n_predictions)  AS n_predictions,
         SUM(e_with)         AS e_with,
         SUM(e_without)      AS e_without,
         SUM(sw)             AS sw,
         SUM(swo)            AS swo,
         SUM(s_actual)       AS s_actual,
         COUNTIF(verdict_month = 'IMPROVES')      AS months_improved,
         COUNTIF(verdict_month != 'INSUFFICIENT') AS months_scored
  FROM m
  GROUP BY GROUPING SETS ((index_name, test_kind, target_month), (index_name, test_kind))
)

SELECT
  r.index_name,
  r.test_kind,
  -- NULL on the pooled row. R14 reads `WHERE target_month IS NOT NULL` for exactly this reason.
  r.target_month,
  r.fitted_through,
  ROUND(SAFE_DIVIDE(r.e_with,    r.clicks_scored), 6) AS err_with,
  ROUND(SAFE_DIVIDE(r.e_without, r.clicks_scored), 6) AS err_without,
  -- RELATIVE, per spec section 5: -1.0 is "the error fell by one percent of itself".
  ROUND(SAFE_DIVIDE(r.e_with - r.e_without, NULLIF(r.e_without, 0)) * 100, 2) AS err_delta_pct,
  ROUND(SAFE_DIVIDE(r.sw,  r.s_actual), 4) AS bias_with,
  ROUND(SAFE_DIVIDE(r.swo, r.s_actual), 4) AS bias_without,
  r.n_predictions,
  r.clicks_scored,
  CASE
    WHEN r.clicks_scored < p.min_scored THEN 'INSUFFICIENT'
    WHEN SAFE_DIVIDE(r.e_with - r.e_without, NULLIF(r.e_without, 0)) * 100 >= 1.0
      OR ABS(SAFE_DIVIDE(r.sw,  r.s_actual) - 1.0)
       > ABS(SAFE_DIVIDE(r.swo, r.s_actual) - 1.0) + 0.02 THEN 'HURTS'
    WHEN SAFE_DIVIDE(r.e_with - r.e_without, NULLIF(r.e_without, 0)) * 100 <= -1.0
     AND ABS(SAFE_DIVIDE(r.sw,  r.s_actual) - 1.0)
      <= ABS(SAFE_DIVIDE(r.swo, r.s_actual) - 1.0) + 0.02 THEN 'IMPROVES'
    ELSE 'NEUTRAL' END AS verdict,
  -- POOLED ROW ONLY. months_scored counts months whose own verdict was not INSUFFICIENT;
  -- months_improved counts those that read IMPROVES. NULL on a per-month row, where the pair
  -- would only ever be 1/1 or 0/1 and would read like a statistic.
  IF(r.target_month IS NULL, r.months_improved, NULL) AS months_improved,
  IF(r.target_month IS NULL, r.months_scored,   NULL) AS months_scored
FROM rolled r
CROSS JOIN params p;
