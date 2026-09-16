CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_CVR_CURVE`
OPTIONS (description = "THE SERVED intent CVR curve: one row per product x intent_key x month_of_year, cvr_hat = calibration x base_cvr x PRODUCT(active indexes). PROMOTED 2026-09-12 from V_INTENT_CVR_CURVE_SHADOW (plan Task 9) after the money gate passed on the curve-only basis: with each product's realised in-window GP-per-order held fixed for every curve, under-pricing 1.618x on the previous flat-pooled curve -> 1.141x on this body with no index active (bar 1.15), false-CUT rate 51.0% -> 44.8%, over 2,431 keyword-weeks 2026-01-05..08-23. Three changes against the previous body, all measured in docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md: (1) NESTED MONTHLY RECENCY WEIGHTING on every rung of the estimator including the global one, windows 1/2/3/6/12 months summed (current month 5x, one back 4x, two back 3x, three-to-five 2x, six-to-eleven 1x, twelve or more 0x), the house shape from V_KEYWORD_RATES at monthly scale; (2) INTENT_CVR_CALIBRATION, a threshold row refit by SP_SCORE_INTENT_INDEXES inside a band (1.1718 at promotion); (3) the hardcoded season CTE is gone, replaced by the product of every DE_INTENT_INDEX_REGISTRY row carrying is_active, each shrunk toward 1.000 by LEAST(1, support_clicks / INTENT_IDX_MIN_SUPPORT) and COALESCEd to 1.000 when absent. NO INDEX IS ACTIVE AT PROMOTION, by measurement not by caution: the same gate read 1.265x with season_month active and 1.140x with season_phase active, so season_month moves money the wrong way despite its pooled IMPROVES on error (it loses 10 of 18 months) and season_phase is inert at its current support. Activation is a human decision on the scorecard plus this gate. WHAT CHANGES MEANING versus the previous body: base_clicks / base_orders are recency-weighted effective counts; confidence comes from a Kish effective sample size, not from them; season_clicks / season_orders publish NULL (no single pooled season cell exists). 30.7% of rows carry base_clicks = 0 because all of their history is older than a year and fall to the family rung with confidence INSUFFICIENT -- a dormant cell is indistinguishable from a never-run one. Schema: same 15 columns, order and types as before. Grain unchanged. V_INTENT_CVR_CURVE_SHADOW stays as the staging copy (identical body at promotion): change the shadow, gate it, then promote -- never edit this view directly. Materialised to T_INTENT_CVR_CURVE by SP_REFRESH_SEARCH_TERM_INTENT (orchestrator Task 16.1, 3x daily); ~27k CPU-seconds per scan, so consumers read the table. Acceptance: scripts/bigquery/tests/INTENT_INDEX_acceptance.sql R09-R11 (against the shadow) and R15.")
AS
-- =============================================================================================
-- V_INTENT_CVR_CURVE — the served intent CVR curve. PROMOTED 2026-09-12 from V_INTENT_CVR_CURVE_SHADOW.
--
-- DO NOT EDIT THIS VIEW DIRECTLY. The house pattern since the target-CPC revert is: change the
-- SHADOW, run the scorecard and the money gate (scripts/bigquery/queries/intent_money_gate.sql),
-- then promote by copying the shadow body here with the name swapped (plan Task 9). At promotion
-- the two bodies are identical; the shadow is where the next change goes.
--
-- THE PROMOTION RECORD (2026-09-12), so the next reader knows what this body earned its place on.
-- Money gate, window 2026-01-05..08-23, 2,431 keyword-weeks, each product's realised in-window
-- GP-per-order held fixed for every curve so only the CURVE differs:
--     curve                                under-pricing   false-CUT rate
--     previous body (flat-pooled base)         1.618x           51.0%
--     this body, no index active               1.141x           44.8%     <- promoted
--     this body + season_phase                 1.140x           44.8%
--     this body + season_month                 1.265x           48.0%
--     this body + both                         1.260x           48.1%
-- Bar (plan Task 8): under-pricing <= 1.15 and a lower false-CUT rate. The literal gate with
-- TODAY's catalog margin reads 1.43x for the same body: the difference is the 2026 AOV collapse
-- (window GP-per-order ~$16.60 vs $13.69 today), which hits every curve equally and is a
-- business fact, not a curve defect. season_month is NOT active because it moves money the wrong
-- way (1.265x) even though it pools to IMPROVES on error -- it loses 10 of 18 months and every
-- scorecard row is leakage-flagged until snapshots accumulate. season_phase is inert at its
-- current support. Both stay is_active = FALSE; a human flips them, on evidence.
--
-- The design notes below are the shadow's, kept verbatim: they describe this body.
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
-- THE WEIGHTS APPLY TO EVERY RUNG OF THE LADDER, INCLUDING THE GLOBAL ONE (g), AND THAT IS THE
-- POINT rather than an oversight. Each rung is the shrinkage target of the rung below it, so
-- leaving g flat would pull a recency-weighted product x intent estimate back toward a stale
-- full-history global prior — reintroducing at the last rung exactly the defect the weighting
-- exists to remove, and worst for the thinnest cells, which are the ones most dominated by their
-- parents. MEASURED AT THIS VIEW'S OWN SCOPE (obs, after the V_INTENT_RESOLVED and DIM_PRODUCT
-- joins), the g rung reads 3.0486% flat against 4.0886% nested-weighted, a lift of 1.3412 — which
-- is the ENTIRE recency half of the view's 1.5508 level shift, the other half being the 1.151
-- calibration. So g is not incidental to the change; it carries most of it.
--
-- WHAT IS NOT WEIGHTED: the registry indexes. They carry their own estimators, their own priors
-- and their own normalisation to a clicks-weighted mean of 1.000; weighting them here would
-- double-count and would break that contract.
--
-- ---------------------------------------------------------------------------------------------
-- CONFIDENCE IS NOT COMPUTED FROM base_clicks, AND THAT IS DELIBERATE
-- base_clicks is the WEIGHTED evidence the estimator used. It is the right input to shrinkage —
-- base_self_weight = base_clicks / (base_clicks + k_base) is the exact weight the Beta-binomial
-- applies, and k_base = 400 was itself fit against nested-weighted counts, so that column is
-- correct as it stands. It is the WRONG input to a trust label. Weighting multiplies numerator
-- and denominator alike, so it moves the point estimate but adds no information: a cell with 100
-- real clicks all in the current month reports base_clicks = 500 and would be labelled HIGH off
-- the sampling noise of 100 clicks.
--
-- That is not hypothetical. Measured over all 10,439 cells at watermark 2026-08-31, the incumbent
-- 500/100/20 cut-points applied to each candidate basis give:
--
--     basis                       HIGH   MEDIUM   LOW   INSUFFICIENT
--     raw clicks (live's basis)    339      553  1193           8354
--     weighted clicks              312      497  1106           8524
--     effective sample size        155      330   723           9231
--
-- The middle row is the trap: the recency cut discards 45.57% of all clicks, yet the labels
-- barely move — HIGH falls only 339 -> 312. That near-agreement is an artefact of the 5x
-- inflation cancelling the lost history, not evidence that the cells are still well-supported.
-- 157 of those 312 HIGH cells — 50.3% — do not have 500 effective clicks behind them.
--
-- SO CONFIDENCE IS BANDED ON KISH'S EFFECTIVE SAMPLE SIZE, n_eff = (SUM w)^2 / SUM(w^2), summed
-- over clicks. Two properties make it the right statistic here, and both are why the cut-points
-- KEEP the values 500/100/20 rather than being re-fitted to a new distribution:
--   1. IT IS DENOMINATED IN RAW CLICKS. A cell whose evidence sits entirely in one month has
--      n_eff = c^2*w^2 / (c*w^2) = c, its exact raw click count, whatever w is. So 500/100/20
--      keep the meaning they have always had, and re-fitting them to the inflated weighted
--      distribution would be fitting a label to an artefact.
--   2. IT NEVER OVER-CLAIMS. n_eff <= n always; measured, ZERO of 10,439 cells land in a higher
--      band under n_eff than their raw click count would give. The weighted count promotes 54
--      cells past 500 that do not have 500 raw clicks; n_eff promotes none.
-- The inflation it removes runs at a median of 2.0x, p95 5.0x (max 6.0x, which is rounding on
-- single-digit cells; the theoretical ceiling is the 5x top weight).
-- n_eff is INTERNAL: publishing it would add a 16th column and break the diff contract with the
-- live view that this whole view exists to serve. The formula is right here, in p_lvl, so it is
-- recomputable by anyone auditing a label. Revisit when Task 9 is free to change the contract.
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
-- A LOSS THIS DESIGN ACCEPTS, stated because nothing else states it: A DORMANT CELL IS NOW
-- INDISTINGUISHABLE FROM A NEVER-RUN ONE. Live reported a cell's full historical click count, so
-- a reader could see "this ran 5,000 clicks two years ago and has been quiet since". Here that
-- cell reports base_clicks = 0, base_self_weight 0 and INSUFFICIENT — identical to an intent this
-- product has never advertised on. 30.7% of rows are in that state. The estimator is right to
-- ignore stale evidence when pricing; the GRID has nonetheless lost the ability to tell "dormant"
-- from "new", which matters to anyone reading it to decide what to revive. Not fixed here.
--
-- READ confidence BEFORE ACTING. INSUFFICIENT means the number is mostly its parent's, not its
-- own — and now also means the cell's own recent evidence is thin, which is the stronger claim.
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
    Ads_orders * recency_w AS w_orders,
    -- Sum of SQUARED weights, the denominator of Kish's effective sample size. Carried from here
    -- so the confidence label can be banded on evidence rather than on inflated evidence; see the
    -- CONFIDENCE block in the header. Every click in this row shares one weight, so the row's
    -- contribution to SUM(w^2) is clicks * w * w.
    Ads_clicks * recency_w * recency_w AS w2_clicks
  FROM obs_w
),

-- ---- Rung 4: global -------------------------------------------------------
-- WEIGHTED, deliberately. See the header: an unweighted g would be the stale prior every thin
-- cell shrinks toward, and it carries 1.3412 of the view's 1.5508 level shift.
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
    -- KISH EFFECTIVE SAMPLE SIZE, (SUM w)^2 / SUM(w^2), in raw-click units. Internal: it bands
    -- `confidence` and is not published, because a 16th column would break the diff contract with
    -- the live view. NULL when a cell has no surviving evidence, which the CASE reads as
    -- INSUFFICIENT. Full argument in the header's CONFIDENCE block.
    CAST(ROUND(SAFE_DIVIDE(POW(SUM(o.w_clicks), 2), NULLIF(SUM(o.w2_clicks), 0))) AS INT64)
      AS base_clicks_eff,
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
-- V_INTENT_IDX_SEASON_MONTH's support is a plain click count and needs no such reading. THE TWO
-- SUPPORT FIGURES ARE THEREFORE NOT COMMENSURABLE, which is one reason season_clicks below
-- publishes NULL rather than trying to combine them.
idx_month AS (
  SELECT s.intent_type, s.month_of_year,
    1.0 + (s.index_value - 1.0) * LEAST(1.0, SAFE_DIVIDE(s.support_clicks, p.idx_min_support)) AS iv
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_MONTH` s CROSS JOIN params p
  WHERE 'season_month' IN (SELECT index_name FROM active_idx)
),
idx_phase AS (
  SELECT s.intent_key, s.month_of_year,
    1.0 + (s.index_value - 1.0) * LEAST(1.0, SAFE_DIVIDE(s.support_clicks, p.idx_min_support)) AS iv
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
  -- bind — measured, the largest cvr_hat is 0.36961, leaving 2.71x of headroom. It exists so that
  -- a future index with a large multiplier cannot price a bid off a conversion rate above 100%.
  -- Acceptance R10 carries a PRE-CAP arm so that a cap which starts binding is DETECTABLE rather
  -- than silently swallowed, because the post-cap value can never violate the post-cap test.
  ROUND(LEAST(pr.calibration * pl.base_cvr
              * COALESCE(im.iv, 1.0) * COALESCE(ip.iv, 1.0), 1.0), 5)    AS cvr_hat,

  -- RECENCY-WEIGHTED, not raw. Correct for shrinkage, wrong for a trust label — see the header.
  pl.base_clicks,
  pl.base_orders,

  -- BOTH PUBLISHED NULL, and the honest reason is the same for both: under the registry design
  -- there is no single pooled "season cell", so there is no single number to count. Live had one
  -- — the intent x month cell — and reported its clicks and orders.
  --   * season_orders: no registry index publishes an order count at all. The contract (spec
  --     section 4.1) is index_value + support_clicks and nothing else.
  --   * season_clicks: each active index publishes its OWN support, and the two are not
  --     commensurable — season_month's is a raw click count, season_phase's is a projected
  --     per-day support running ~2x a one-year rate (spec section 7.5). Summing them
  --     double-counts the same clicks; taking the MINIMUM, which an earlier cut of this view did,
  --     names the LEAST influential factor, since an index below INTENT_IDX_MIN_SUPPORT is shrunk
  --     to ~1.000 and contributes nothing to the row.
  -- NULL rather than 0 in both cases: 0 is indistinguishable from a measured zero. The columns
  -- are retained because the live view emits them and this view exists to be diffable against it.
  -- Nothing in the repo reads either (checked: V_INTENT_BID_BASE is the only consumer of this
  -- view, and it takes base_cvr, season_index, cvr_hat, base_clicks, confidence, base_self_weight).
  -- IF a future consumer needs per-index support, add per-index columns to the index contract
  -- rather than reviving a single blended number; that decision belongs with Task 8/9, when an
  -- index is actually activated and the contract is free to change.
  CAST(NULL AS INT64)                                                    AS season_clicks,
  CAST(NULL AS INT64)                                                    AS season_orders,

  ROUND(pl.family_cvr, 5)                                                AS family_cvr,

  -- How much of base_cvr is the cell's own evidence rather than its family's. clicks / (clicks+k)
  -- on WEIGHTED clicks, which is exactly the weight the Beta-binomial applies and exactly the
  -- basis k_base = 400 was fit against. 0.5 means half-borrowed. Correct as it stands.
  ROUND(SAFE_DIVIDE(pl.base_clicks, pl.base_clicks + pr.k_base), 3)      AS base_self_weight,

  -- BANDED ON EFFECTIVE SAMPLE SIZE, NOT ON base_clicks. The cut-points are unchanged at
  -- 500/100/20 because n_eff is denominated in raw clicks, so they mean what they always meant.
  -- Re-fitting them to the weighted distribution would have fitted a label to a 2x-5x artefact.
  -- Header, CONFIDENCE block, carries the measured band populations and the argument.
  CASE
    WHEN pl.base_clicks_eff >= 500 THEN 'HIGH'
    WHEN pl.base_clicks_eff >= 100 THEN 'MEDIUM'
    WHEN pl.base_clicks_eff >= 20  THEN 'LOW'
    ELSE 'INSUFFICIENT'
  END                                                                    AS confidence
FROM p_lvl pl
CROSS JOIN months m
LEFT JOIN idx_month im ON im.intent_type = pl.intent_type AND im.month_of_year = m.month_of_year
LEFT JOIN idx_phase ip ON ip.intent_key  = pl.intent_key  AND ip.month_of_year = m.month_of_year
CROSS JOIN params pr;
