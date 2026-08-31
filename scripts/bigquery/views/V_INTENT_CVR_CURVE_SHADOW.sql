CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_CVR_CURVE_SHADOW`
OPTIONS (description = "SHADOW REBUILD of V_INTENT_CVR_CURVE. NOTHING READS THIS. Promotion is the plan's Task 9, only after the scorecard and the money gate pass. Three changes against the live curve, all measured in docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md: (1) NESTED MONTHLY RECENCY WEIGHTING on the base estimator, windows 1/2/3/6/12 months summed, the house shape from V_KEYWORD_RATES at monthly scale - the current month counts 5x, one month back 4x, two back 3x, three-to-five back 2x, six-to-eleven back 1x and anything twelve or more months old counts 0x. Walk-forward over 499 product x intent cells: weighted abs error 1.3402% flat-full-history -> 1.2583% nested, on MORE predictions (1,300 -> 1,350), which is why nested and not exponential decay (1.2101% but on ~70 fewer cells). (2) An explicit INTENT_CVR_CALIBRATION factor removing the residual ~13% under-bias that survives every decay shape, because shrinking toward a global prior pulls the scored (larger, better-converting) cells down. (3) The hardcoded season CTE is GONE, replaced by the product of every index in DE_INTENT_INDEX_REGISTRY carrying is_active - each shrunk toward 1.000 by LEAST(1, support_clicks / INTENT_IDX_MIN_SUPPORT), each COALESCEd to 1.000 when absent, so an inactive or sparse index contributes exactly nothing. BOTH INDEXES ARE is_active = FALSE TODAY, so season_index is 1.0000 on every row and this view currently differs from live by recency weighting and calibration only. THREE COLUMNS CHANGED MEANING WITHOUT CHANGING NAME OR TYPE - read the header before consuming them: base_clicks and base_orders are now RECENCY-WEIGHTED (effective) counts, not raw ones, and confidence and base_self_weight are computed from those; season_clicks is the support behind the WEAKEST applied index rather than a pooled cell's raw clicks, and is 0 while no index is active; season_orders has no equivalent under the registry design and is published NULL rather than a fabricated 0. Grain is unchanged: one row per product_short_name x intent_key x month_of_year, all 12 months always present. Acceptance: scripts/bigquery/tests/INTENT_INDEX_acceptance.sql R09-R11.")
AS
-- =============================================================================================
-- V_INTENT_CVR_CURVE_SHADOW
-- 12-month conversion-rate curve per (product x intent theme), learned from the ads signal.
-- Grain: product_short_name x intent_key x month_of_year (1-12) — IDENTICAL to the live view.
--
--   cvr_hat(product, intent, month)
--     = calibration x base_cvr(product, intent) x PRODUCT( index_i(month) )   over ACTIVE indexes
--
--   base_cvr    — how well this product converts this intent, pooled over all months, with
--                 recent months weighted more (see RECENCY below).
--   index_i     — every row of DE_INTENT_INDEX_REGISTRY with is_active. Absent, inactive or
--                 thin => exactly 1.000, so the formula degrades to base_cvr x calibration.
--   calibration — INTENT_CVR_CALIBRATION, a threshold row, never a literal. It removes a
--                 measured level bias; it is NOT a fudge factor and it WILL drift.
--
-- WHY THIS EXISTS. Measured 2026-08-31, T_INTENT_BID_BASE under-prices a click 1.69x ($0.387
-- predicted against $0.655 realised over 2,107 keyword-weeks). Three causes: an inert
-- season_index, a month key that cannot represent a moving holiday, and full-history pooling
-- with no recency weight. The third affects 100% of the catalog and is what (b) below fixes.
--
-- ---------------------------------------------------------------------------------------------
-- RECENCY: WHY SUMMING NESTED WINDOWS IS THE WEIGHTING
-- Windows 1/2/3/6/12 months NEST, so a row's weight is simply how many of them contain it.
-- Current month 5x, one back 4x, two back 3x, three-to-five 2x, six-to-eleven 1x, and TWELVE OR
-- MORE MONTHS BACK 0x — outside the widest window is outside the evidence base, exactly as
-- V_KEYWORD_RATES drops everything past 90 days. That last point is the one to hold on to: this
-- view no longer sees a second copy of last year's August. It is a deliberate trade — the
-- walk-forward measured the flat full-history estimator as the WORST of the four shapes tried.
--
-- THE WEIGHTS APPLY TO THE BASE LADDER ONLY (i_lvl / f_lvl / p_lvl). The registry indexes carry
-- their own estimators and their own priors; weighting them here would double-count.
--
-- CONSEQUENCE FOR base_clicks / base_orders / confidence / base_self_weight: they are all
-- computed on WEIGHTED counts now. A cell whose evidence is recent reports up to 5x its raw
-- clicks; a cell whose evidence is all older than a year reports 0 and lands on INSUFFICIENT.
-- That is the honest reading — confidence should describe the evidence the estimator actually
-- used — but it means the numbers are NOT comparable row-for-row against the live view, and the
-- 500/100/20 confidence cut-points were chosen against raw clicks and have not been re-derived.
-- ---------------------------------------------------------------------------------------------
--
-- DIFFERENCES FROM V_INTENT_CVR_CURVE THAT ARE NOT IN THE FOUR PLANNED CHANGES, all deliberate:
--   * first_sale / in_launch_ramp are GONE. Their only consumer was the season CTE's
--     `WHERE NOT o.in_launch_ramp`, and that CTE is deleted here. Carrying a scan of
--     V_UNIFIED_DAILY that feeds nothing costs money and implies a guard that is not running.
--     WHERE THE GUARD LIVES NOW: V_INTENT_IDX_SEASON_PHASE reimplements it (measured immaterial
--     at that grain — 2 rows of 204). V_INTENT_IDX_SEASON_MONTH DOES NOT HAVE IT. So relative to
--     live, the calendar-month seasonal layer loses its launch-ramp quarantine. That is a
--     property of the Task 2 index view, not something this view can fix, and it is recorded
--     here because this is where the two designs meet.
--   * obs no longer selects Ads_cost / GROSS_PROFIT. The live view selects both and aggregates
--     neither; they are bytes scanned for nothing.
--   * params filters coach_mode = 'GUARDIAN' AND product_family IS NULL. The live view does not,
--     and today that is a no-op (all six INTENT rows are GUARDIAN/NULL). It stops a future
--     BLITZ-scoped or family-scoped row from silently handing MAX() a second candidate — the
--     same fix already made in both index views.
--
-- READ confidence BEFORE ACTING. base_clicks < INSUFFICIENT means the number is mostly its
-- parent's, not its own.
--
-- Dependencies: FACT_AMAZON_ADS, V_INTENT_RESOLVED, DIM_PRODUCT, DE_COACH_THRESHOLDS,
--               DE_INTENT_INDEX_REGISTRY, V_INTENT_IDX_SEASON_MONTH, V_INTENT_IDX_SEASON_PHASE
-- SOP: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md
-- Project: onyga-482313 / Dataset: OI
-- =============================================================================================

WITH params AS (
  SELECT
    MAX(IF(threshold_key = 'INTENT_CVR_BASE_PRIOR_CLICKS', threshold_value, NULL)) AS k_base,
    MAX(IF(threshold_key = 'INTENT_CVR_CALIBRATION',       threshold_value, NULL)) AS calibration,
    MAX(IF(threshold_key = 'INTENT_IDX_MIN_SUPPORT',       threshold_value, NULL)) AS idx_min_support
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id = 'INTENT' AND coach_mode = 'GUARDIAN' AND product_family IS NULL
),

-- The ads watermark, lifted out so the nested-window arithmetic below states it once.
wm AS (SELECT MAX(date) AS watermark FROM `onyga-482313.OI.FACT_AMAZON_ADS`),

-- Every ads click that carries an intent theme, stamped with product, family, month and how many
-- whole calendar months back it sits from the watermark's month.
obs_raw AS (
  SELECT
    p.parent_name,
    p.product_short_name,
    i.intent_key,
    i.intent_type,
    EXTRACT(MONTH FROM a.date) AS month_of_year,
    a.Ads_clicks, a.Ads_orders,
    DATE_DIFF(DATE_TRUNC((SELECT watermark FROM wm), MONTH),
              DATE_TRUNC(a.date, MONTH), MONTH) AS months_ago
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN `onyga-482313.OI.V_INTENT_RESOLVED` i ON i.search_term = a.search_term
  JOIN `onyga-482313.OI.DIM_PRODUCT` p       ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
  WHERE i.intent_key IS NOT NULL
    AND p.parent_name IS NOT NULL AND p.parent_name != 'UNKNOWN'
),

-- The five nested windows, all ending at the watermark's month. Summing their indicators IS the
-- step decay: 5/4/3/2/1/0. Written once here rather than ten times inline.
obs_w AS (
  SELECT *,
    CAST(months_ago < 1  AS INT64)
  + CAST(months_ago < 2  AS INT64)
  + CAST(months_ago < 3  AS INT64)
  + CAST(months_ago < 6  AS INT64)
  + CAST(months_ago < 12 AS INT64) AS recency_w
  FROM obs_raw
),

obs AS (
  SELECT *,
    Ads_clicks * recency_w AS w_clicks,
    Ads_orders * recency_w AS w_orders
  FROM obs_w
),

-- ---- Rung 4: global -------------------------------------------------------
g AS (SELECT SAFE_DIVIDE(SUM(w_orders), SUM(w_clicks)) AS cvr FROM obs),

-- ---- Rung 3: intent (all products, all months) ----------------------------
i_lvl AS (
  SELECT o.intent_key,
    SUM(o.w_clicks) AS clicks, SUM(o.w_orders) AS orders,
    SAFE_DIVIDE(SUM(o.w_orders) + p.k_base * g.cvr,
                SUM(o.w_clicks) + p.k_base) AS cvr
  FROM obs o CROSS JOIN params p CROSS JOIN g
  GROUP BY o.intent_key, p.k_base, g.cvr
),

-- ---- Rung 2: family x intent ---------------------------------------------
f_lvl AS (
  SELECT o.parent_name, o.intent_key,
    SUM(o.w_clicks) AS clicks, SUM(o.w_orders) AS orders,
    SAFE_DIVIDE(SUM(o.w_orders) + p.k_base * i_lvl.cvr,
                SUM(o.w_clicks) + p.k_base) AS cvr
  FROM obs o
  JOIN i_lvl ON i_lvl.intent_key = o.intent_key
  CROSS JOIN params p
  GROUP BY o.parent_name, o.intent_key, p.k_base, i_lvl.cvr
),

-- ---- Rung 1: product x intent = base_cvr ---------------------------------
p_lvl AS (
  SELECT o.parent_name, o.product_short_name, o.intent_key, ANY_VALUE(o.intent_type) AS intent_type,
    SUM(o.w_clicks) AS base_clicks, SUM(o.w_orders) AS base_orders,
    SAFE_DIVIDE(SUM(o.w_orders) + p.k_base * f_lvl.cvr,
                SUM(o.w_clicks) + p.k_base) AS base_cvr,
    f_lvl.cvr AS family_cvr
  FROM obs o
  JOIN f_lvl ON f_lvl.parent_name = o.parent_name AND f_lvl.intent_key = o.intent_key
  CROSS JOIN params p
  GROUP BY o.parent_name, o.product_short_name, o.intent_key, p.k_base, f_lvl.cvr
),

-- ---- The index registry --------------------------------------------------
-- Replaces the hardcoded `season` CTE. Each index is joined on its own declared keys, gated on
-- being ACTIVE, and shrunk toward 1.000 in proportion to its own published support.
active_idx AS (
  SELECT index_name FROM `onyga-482313.OI.DE_INTENT_INDEX_REGISTRY` WHERE is_active
),

-- SHRINKAGE. `1 + (v - 1) * LEAST(1, support/min_support)` moves a cell from its published value
-- toward 1.000 as its support falls short of INTENT_IDX_MIN_SUPPORT. At full support it is v; at
-- zero support it is exactly 1.000.
-- WHAT INTENT_IDX_MIN_SUPPORT = 100 ACTUALLY GATES, per spec section 7.5 — this view RELIES on it
-- and must not be read as "100 clicks in a year". V_INTENT_IDX_SEASON_PHASE divides whole-history
-- phase clicks by ONE projection year's days, and ads history covers roughly two occurrences of
-- each holiday, so its support runs about 2x a one-year rate and the gate behaves like ~50
-- one-year clicks. That equivalence LOOSENS on its own as history accumulates. It is the only
-- thing holding christmas's off-season 0.2567 — 755 OFF clicks carrying 2 orders — out of the
-- curve. Spec section 7.5 sets the trigger to re-derive it: whichever comes first of season_phase
-- being activated or history passing three occurrences. It is NOT re-derived here, because
-- season_phase is still is_active = FALSE and this view applies nothing.
-- V_INTENT_IDX_SEASON_MONTH's support is a plain click count and needs no such reading.
idx_month AS (
  SELECT s.intent_type, s.month_of_year,
    1.0 + (s.index_value - 1.0) * LEAST(1.0, SAFE_DIVIDE(s.support_clicks, p.idx_min_support)) AS iv,
    s.support_clicks
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_MONTH` s CROSS JOIN params p
  WHERE 'season_month' IN (SELECT index_name FROM active_idx)
),
idx_phase AS (
  SELECT s.intent_key, s.month_of_year,
    1.0 + (s.index_value - 1.0) * LEAST(1.0, SAFE_DIVIDE(s.support_clicks, p.idx_min_support)) AS iv,
    s.support_clicks
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE` s CROSS JOIN params p
  WHERE 'season_phase' IN (SELECT index_name FROM active_idx)
),

months AS (SELECT m AS month_of_year FROM UNNEST(GENERATE_ARRAY(1, 12)) m)

SELECT
  pl.parent_name,
  pl.product_short_name,
  pl.intent_key,
  pl.intent_type,
  m.month_of_year,

  ROUND(pl.base_cvr, 5)                                                  AS base_cvr,

  -- The product of every ACTIVE index. Exactly 1.0000 when none is active, which is the state
  -- this view ships in. COALESCE is what makes an index optional.
  ROUND(COALESCE(im.iv, 1.0) * COALESCE(ip.iv, 1.0), 4)                  AS season_index,

  -- LEAST(..., 1.0) is a guard, not a working clamp: base_cvr, calibration and every shrunk index
  -- are strictly positive and base_cvr is itself a shrunk rate, so the cap is not expected to
  -- bind. It exists so that a future index with a large multiplier cannot price a bid off a
  -- conversion rate above 100%.
  ROUND(LEAST(pr.calibration * pl.base_cvr
              * COALESCE(im.iv, 1.0) * COALESCE(ip.iv, 1.0), 1.0), 5)    AS cvr_hat,

  -- RECENCY-WEIGHTED, not raw. See the header. Same names and types as live; different scale.
  pl.base_clicks,
  pl.base_orders,

  -- NEAREST HONEST EQUIVALENT of live's season_clicks, which was one pooled cell's raw clicks.
  -- The registry has no single pooled cell: it has one support figure per contributing index.
  -- The MINIMUM is published because the weakest factor is what bounds how far this row's
  -- seasonal adjustment can be trusted. MIN over UNNEST skips NULLs, so an index that is
  -- inactive or has no row for this cell simply does not participate; 0 means no active index
  -- reached this row at all, which is every row while both indexes are is_active = FALSE.
  COALESCE((SELECT MIN(s) FROM UNNEST([im.support_clicks, ip.support_clicks]) AS s), 0)
                                                                         AS season_clicks,

  -- NO EQUIVALENT EXISTS. The index contract (spec section 4.1) publishes index_value and
  -- support_clicks and no order count, so there is no honest number to put here. Published NULL
  -- rather than 0, because 0 would be indistinguishable from a genuine measured zero. The column
  -- is retained because the live view emits it and this view's whole purpose is to be diffable
  -- against that one. Nothing in the repo reads it (checked: only V_INTENT_BID_BASE reads this
  -- view, and it selects base_cvr, season_index, cvr_hat, base_clicks, confidence and
  -- base_self_weight).
  CAST(NULL AS INT64)                                                    AS season_orders,

  ROUND(pl.family_cvr, 5)                                                AS family_cvr,

  -- How much of base_cvr is the cell's own evidence rather than its family's, on WEIGHTED
  -- clicks. clicks / (clicks + k). 0.5 means half-borrowed.
  ROUND(SAFE_DIVIDE(pl.base_clicks, pl.base_clicks + pr.k_base), 3)      AS base_self_weight,
  CASE
    WHEN pl.base_clicks >= 500 THEN 'HIGH'
    WHEN pl.base_clicks >= 100 THEN 'MEDIUM'
    WHEN pl.base_clicks >= 20  THEN 'LOW'
    ELSE 'INSUFFICIENT'
  END                                                                    AS confidence
FROM p_lvl pl
CROSS JOIN months m
LEFT JOIN idx_month im ON im.intent_type = pl.intent_type AND im.month_of_year = m.month_of_year
LEFT JOIN idx_phase ip ON ip.intent_key  = pl.intent_key  AND ip.month_of_year = m.month_of_year
CROSS JOIN params pr;
