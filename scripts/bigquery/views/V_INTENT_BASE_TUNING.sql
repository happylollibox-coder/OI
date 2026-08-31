CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_BASE_TUNING`
OPTIONS (description = "Walk-forward error and bias for the intent curve's BASE estimator over a grid of (recency shape, k_base), so the shipped constants stay re-derivable rather than ossified. Nine rows: three shapes x three priors. The in-warehouse version of the offline sweep that chose nested 1/2/3/6/12 at k_base = 400. MEASURED 2026-08-31 THE ORDERING REPRODUCES: nested_1_2_3_6_12 @ 400 is the best row at 1.3142% weighted absolute error, bias 0.8503, implied_calibration 1.1761; all three flat rows are the worst three, flat @ 800 last at 1.4841%. READ implied_calibration -- it is 1/bias, and it is what INTENT_CVR_CALIBRATION (1.151 today) must be refit from, because the account's CVR and AOV both moved more than 30% in 2026 and a stale calibration silently re-introduces the level error this whole change exists to remove. The absolute error levels here are NOT comparable to the offline sweep's (different cell population); the ordering is what reproduces and the ordering is what to read. THIS VIEW SHIPS NOTHING -- a threshold is changed by a human. Read the materialised copy, T_INTENT_BASE_TUNING; this view costs ~950 slot-seconds per scan. Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md")
AS
-- =============================================================================================
-- V_INTENT_BASE_TUNING
-- Grain: shape x k_base. Nine rows, ordered best error first.
--
-- WHY IT EXISTS. The base parameters were derived offline in a notebook that no longer exists in
-- runnable form. They will drift. This view re-derives them where the data lives, so that
-- "nested 1/2/3/6/12 at k = 400" is a measurement anyone can re-run rather than a number in a
-- comment. Same walk-forward harness as V_INTENT_INDEX_SCORECARD: for each of 18 target months
-- the estimator is fitted strictly BEFORE the month and scored against it, click-weighted.
--
-- ---------------------------------------------------------------------------------------------
-- THE THREE SHAPES. Weights are the sum of nested-window indicators, which is what makes them a
-- step decay without a decay constant to fit. months_ago is measured from the TARGET month, so
-- the freshest evidence a walk-forward fit can see is months_ago = 1:
--   flat                1 for every prior month, no recency at all -- the estimator that ships
--                       in V_INTENT_CVR_CURVE today, and the thing being argued against.
--   nested_1_2_3_6_12   5/4/3/2/2/2/1/1/1/1/1/1 then 0 -- the shadow curve's shape.
--   nested_1_3_6_12_24  a slower variant that keeps a second year at weight 1, included so that
--                       "drop everything past twelve months" is a measured choice and not an
--                       assumption. At k = 400 it costs 3.4% of relative error against the
--                       shipped shape (1.3591 vs 1.3142) while scoring 2 more cells.
--
-- k_base is the Beta-binomial prior in clicks. It enters ONLY the shrinkage
-- (w_orders + k*prior) / (w_clicks + k), never the weighting, which is why the grid is applied
-- AFTER the aggregation rather than fanned across it -- see COST below.
--
-- ---------------------------------------------------------------------------------------------
-- WHAT THE COLUMNS MEAN
--   weighted_abs_error_pct  SUM(clicks * |predicted - actual|) / SUM(clicks), in percentage
--                           points of CVR. Lower is better. This is the ranking column.
--   bias                    SUM(clicks * predicted) / SUM(clicks * actual). Below 1 is
--                           UNDER-prediction, which is the direction of the 1.69x defect.
--   implied_calibration     1 / bias. The multiplier that would remove the level error of THAT
--                           row. INTENT_CVR_CALIBRATION is this number for the chosen row.
--   n_predictions           cells scored. It differs BY SHAPE and that is the point: a shape
--                           that wins by discarding evidence would show a smaller count here.
--                           Measured, nested_1_2_3_6_12 scores 1,145 against flat's 1,115 -- it
--                           scores MORE cells, not fewer, because the 5x top weight more than
--                           replaces what the twelve-month cutoff drops.
--
-- ---------------------------------------------------------------------------------------------
-- MEASURED 2026-08-31, at watermark 2026-08-31. Recorded here as the reproduction the plan asked
-- for, not as a value anything reads:
--     shape                k_base   err%     bias     implied_calibration   n
--     nested_1_2_3_6_12       400   1.3142   0.8503   1.1761                1145
--     nested_1_2_3_6_12       200   1.3169   0.8543   1.1705                1145
--     nested_1_2_3_6_12       800   1.3216   0.8445   1.1842                1145
--     nested_1_3_6_12_24      400   1.3591   0.8341   1.1989                1147
--     nested_1_3_6_12_24      200   1.3626   0.8379   1.1934                1147
--     nested_1_3_6_12_24      800   1.3636   0.8287   1.2067                1147
--     flat                    200   1.4314   0.8034   1.2446                1115
--     flat                    400   1.4485   0.7962   1.2560                1115
--     flat                    800   1.4841   0.7868   1.2710                1115
-- FLAT DOES NOT WIN. It loses on every prior, and it loses on bias too -- it is the most
-- under-predicting shape in the grid, which is D3 showing up as a number. The shipped choice,
-- nested_1_2_3_6_12 @ 400, is the top row.
-- TWO HONEST DISAGREEMENTS WITH THE OFFLINE SWEEP, neither of which changes the ordering:
--   * the error LEVELS are higher here (1.3142 against the sweep's 1.2583 for the same shape).
--     Different cell population; the sweep's exact filter is not reconstructible.
--   * implied_calibration reads 1.1761 for the chosen row, against the shipped
--     INTENT_CVR_CALIBRATION of 1.151. That is a 2.2% gap and it is the drift this view exists
--     to make visible. It is NOT acted on here -- changing a threshold is a human's decision and
--     belongs with the money gate, not with a view deployment.
--
-- ---------------------------------------------------------------------------------------------
-- COST. Same discipline as V_INTENT_INDEX_SCORECARD, same reason: BigQuery re-inlines a CTE at
-- every reference, the Task 4 acceptance file was REJECTED at 97,066 CPU-seconds against a
-- 33,500 ceiling, and T_INTENT_CVR_CURVE exists because this chain already cost ~27k per scan.
--   * the observation set is scanned ONCE, in `obs`. The plan's draft referenced it three times
--     (prior, weighted, act).
--   * `cell` joins targets to obs once on mo <= target_month and splits the fitting window from
--     the target month inside the aggregate, so all three shapes AND the realised outcome come
--     out of one pass.
--   * THE k GRID IS APPLIED AFTER AGGREGATION, not before. The draft did
--     `FROM grid g CROSS JOIN targets t JOIN obs o`, fanning the observation set nine ways before
--     grouping. k does not enter w_clicks or w_orders at all, so it cannot change the
--     aggregation -- fanning across it computed the same sums nine times.
--   * the global prior is a WINDOW over the same aggregate rather than a fourth scan, and is
--     arithmetically identical to the draft's separate GROUP BY.
-- MEASURED: 942 slot-seconds / 92 MB, against a budget that scales at ~256 CPU-seconds per MB.
--
-- INTENT SOURCE is V_ADS_SEARCH_TERM_INTENT, matching the plan and V_INTENT_INDEX_SCORECARD. The
-- curve itself reads V_INTENT_RESOLVED. Measured both ways 2026-08-31, THE ORDERING IS IDENTICAL
-- -- nested_1_2_3_6_12 @ 400 first, the three flat rows last -- but the levels are not
-- (V_INTENT_RESOLVED: 1.4762 best, 1.6389 worst, on 1,742 cells against 1,145; and 8x the slot
-- cost). One more reason to read the ordering rather than the level.
--
-- Dependencies: FACT_AMAZON_ADS, V_ADS_SEARCH_TERM_INTENT, DIM_PRODUCT
-- Consumers: SP_SCORE_INTENT_INDEXES -> T_INTENT_BASE_TUNING. Nothing reads this view live.
-- Project: onyga-482313 / Dataset: OI
-- =============================================================================================

WITH wm AS (SELECT MAX(date) AS watermark FROM `onyga-482313.OI.FACT_AMAZON_ADS`),

-- THE ONLY REFERENCE TO THE HEAVY CHAIN.
obs AS (
  SELECT d.product_short_name, i.intent_key, DATE_TRUNC(f.date, MONTH) AS mo,
         SUM(f.Ads_clicks) AS clicks, SUM(f.Ads_orders) AS orders
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  JOIN `onyga-482313.OI.V_ADS_SEARCH_TERM_INTENT` i ON i.search_term = f.search_term
  JOIN `onyga-482313.OI.DIM_PRODUCT` d              ON d.asin = f.ASIN_BY_CAMPAIGN_NAME
  WHERE f.campaign_id <> '-1' AND f.Ads_clicks > 0
    AND i.intent_key IS NOT NULL
    AND d.parent_name IS NOT NULL AND d.parent_name != 'UNKNOWN'
  GROUP BY 1, 2, 3
),

targets AS (
  SELECT DATE_TRUNC(DATE_SUB(wm.watermark, INTERVAL n MONTH), MONTH) AS target_month
  FROM wm, UNNEST(GENERATE_ARRAY(0, 17)) AS n
),

-- One pass: all three weighted fits AND the realised outcome, per target month per cell.
-- DATE_DIFF(target_month, mo, MONTH) is >= 1 inside the fitting window, so `<= 1` is the
-- freshest available month and carries all five indicators.
cell AS (
  SELECT t.target_month, o.product_short_name, o.intent_key,

    SUM(IF(o.mo < t.target_month, o.clicks, 0)) AS c_flat,
    SUM(IF(o.mo < t.target_month, o.orders, 0)) AS o_flat,

    SUM(IF(o.mo < t.target_month, o.clicks * (
        CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 1  AS INT64)
      + CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 2  AS INT64)
      + CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 3  AS INT64)
      + CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 6  AS INT64)
      + CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 12 AS INT64)), 0)) AS c_a,
    SUM(IF(o.mo < t.target_month, o.orders * (
        CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 1  AS INT64)
      + CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 2  AS INT64)
      + CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 3  AS INT64)
      + CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 6  AS INT64)
      + CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 12 AS INT64)), 0)) AS o_a,

    SUM(IF(o.mo < t.target_month, o.clicks * (
        CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 1  AS INT64)
      + CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 3  AS INT64)
      + CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 6  AS INT64)
      + CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 12 AS INT64)
      + CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 24 AS INT64)), 0)) AS c_b,
    SUM(IF(o.mo < t.target_month, o.orders * (
        CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 1  AS INT64)
      + CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 3  AS INT64)
      + CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 6  AS INT64)
      + CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 12 AS INT64)
      + CAST(DATE_DIFF(t.target_month, o.mo, MONTH) <= 24 AS INT64)), 0)) AS o_b,

    SUM(IF(o.mo = t.target_month, o.clicks, 0)) AS act_clicks,
    SUM(IF(o.mo = t.target_month, o.orders, 0)) AS act_orders
  FROM targets t
  JOIN obs o ON o.mo <= t.target_month
  GROUP BY 1, 2, 3
),

-- The global prior, UNWEIGHTED by design: it is the level the whole grid shrinks toward, and
-- weighting it would fold a recency choice into the thing the recency choices are compared
-- against. (The shadow curve DOES weight its global rung; that is a property of the estimator
-- being shipped, not of this comparison.) Window over the same aggregate, not a second scan.
cell_p AS (
  SELECT c.*,
         SAFE_DIVIDE(SUM(c.o_flat) OVER (PARTITION BY c.target_month),
                     NULLIF(SUM(c.c_flat) OVER (PARTITION BY c.target_month), 0)) AS prior_cvr
  FROM cell c
),

-- The nine grid points, fanned out AFTER the aggregation. 3 shapes x 3 priors.
--   act_clicks >= 60 : the target month must carry enough clicks for its realised CVR to mean
--                      something. Same cut the offline sweep used.
--   w_clicks   >= 30 : the SHAPE must have surviving evidence for this cell. Applied per shape,
--                      which is exactly how a shape that thins its own evidence base shows up --
--                      as a smaller n_predictions rather than as a quietly better error.
grid AS (
  SELECT c.target_month, c.prior_cvr, c.act_clicks,
         SAFE_DIVIDE(c.act_orders, c.act_clicks) AS actual_cvr,
         s.shape, s.w_clicks, s.w_orders, kb AS k
  FROM cell_p c
  CROSS JOIN UNNEST([
    STRUCT('flat'               AS shape, c.c_flat AS w_clicks, c.o_flat AS w_orders),
    STRUCT('nested_1_2_3_6_12',           c.c_a,               c.o_a),
    STRUCT('nested_1_3_6_12_24',          c.c_b,               c.o_b)
  ]) AS s
  CROSS JOIN UNNEST([200.0, 400.0, 800.0]) AS kb
  WHERE c.act_clicks >= 60 AND s.w_clicks >= 30
)

SELECT
  shape,
  k AS k_base,
  COUNT(*) AS n_predictions,
  ROUND(SAFE_DIVIDE(
    SUM(act_clicks * ABS(SAFE_DIVIDE(w_orders + k * prior_cvr, w_clicks + k) - actual_cvr)),
    SUM(act_clicks)) * 100, 4) AS weighted_abs_error_pct,
  ROUND(SAFE_DIVIDE(
    SUM(act_clicks * SAFE_DIVIDE(w_orders + k * prior_cvr, w_clicks + k)),
    SUM(act_clicks * actual_cvr)), 4) AS bias,
  -- 1 / bias. What INTENT_CVR_CALIBRATION would have to be for this row to price the level right.
  ROUND(SAFE_DIVIDE(
    SUM(act_clicks * actual_cvr),
    SUM(act_clicks * SAFE_DIVIDE(w_orders + k * prior_cvr, w_clicks + k))), 4) AS implied_calibration
FROM grid
GROUP BY shape, k
ORDER BY weighted_abs_error_pct;
