CREATE OR REPLACE VIEW `onyga-482313.OI.V_INTENT_INDEX_SCORECARD`
OPTIONS (description = "Walk-forward verdict per index per month for the intent CVR curve, over the trailing 18 target months. For each target month M the base rate is fitted on observations strictly BEFORE M and scored against what M actually did; errors are weighted by clicks so verdicts follow the money. ADD_ONE_IN asks whether a candidate index helps on top of the ACTIVE set; LEAVE_ONE_OUT asks whether an index still earns its place inside it, without which the registry only ever grows. err_delta_pct is the RELATIVE change in weighted absolute error, so -1.0 means the error fell by one percent of itself. Bias is checked alongside error because an index can lower error while skewing the level -- which is exactly how the full-history pooling defect went unnoticed. A POOLED all-months row per index x test carries target_month NULL plus months_improved / months_scored. READ THE POOLED ROW AND THE MONTHS TOGETHER; neither alone is the answer. REGISTRY-DRIVEN SINCE 2026-09-11: the indexes scored are the rows of DE_INTENT_INDEX_REGISTRY, active or not, with NO index name in this SQL, and their values come from T_INTENT_IDX_HISTORY rather than the live index views -- target month M is scored with the newest snapshot taken strictly BEFORE M, and where none exists yet the LATEST snapshot is used and leakage_flag is TRUE, so an index verdict now states how much look-ahead it carries instead of hiding it (the old limitation L1). snapshot_month_used names the snapshot. The active set for both tests is what the registry says is_active at scoring time; while nothing is active LEAVE_ONE_OUT is evaluated against the hypothetical whole registry, which is the only version of the test that can produce a row today and matches the pre-registry output exactly. TWO STATED LIMITATIONS remain, in the header: the base here is flat-pooled and not the shadow's recency-weighted base, and 18 target months give a yearly index at most two observations per calendar month. THIS VIEW PROMOTES NOTHING; is_active is written by a human. READ THE MATERIALISED COPY, T_INTENT_INDEX_SCORECARD -- this view scans the observation chain once per read at thousands of slot-seconds. Acceptance: scripts/bigquery/tests/INTENT_INDEX_acceptance.sql R12-R14, R16, R20. Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md")
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
-- REGISTRY-DRIVEN, HISTORY-FED (2026-09-11). Two things changed from the first cut and they are
-- one change, because one table solves both.
--
--   (a) NO INDEX NAME APPEARS IN THIS SQL. The set of indexes scored is the row set of
--       DE_INTENT_INDEX_REGISTRY, active or not. The first cut hardcoded season_month and
--       season_phase with their own join columns, so a third index meant editing this view --
--       which defeats the registry. Now a new index is a registry row, a snapshot taken by
--       SP_SCORE_INTENT_INDEXES, and nothing else.
--
--   (b) INDEX VALUES COME FROM T_INTENT_IDX_HISTORY, NOT THE LIVE INDEX VIEWS. The first cut
--       read the views as deployed -- fitted on ALL of history, including every target month
--       and everything after it -- so an index verdict was optimistic by an unmeasured amount
--       (its limitation L1). SP_SCORE_INTENT_INDEXES now keeps one snapshot per index per UTC
--       month, and for target month M this view uses the snapshot with the LARGEST
--       snapshot_month STRICTLY BEFORE M. Strictly before, not "at or before": a snapshot
--       stamped M is whatever the last procedure run inside M wrote, fitted on most of M's own
--       clicks, so scoring M with it is the leakage being removed. Where no earlier snapshot
--       exists -- every target month older than the first snapshot -- the LATEST snapshot is
--       used and the row carries leakage_flag = TRUE. snapshot_month_used names the snapshot on
--       every per-month row (NULL on the pooled row, whose leakage_flag is TRUE if any of its
--       months leaked). So an IMPROVES on a flagged row still reads "worth taking to the money
--       gate"; an IMPROVES on an unflagged row is a genuine out-of-sample result. The flags
--       clear themselves one month at a time as snapshots accumulate; nothing needs editing.
--       THE FIRST SNAPSHOT IS 2026-09, so every row is flagged until the 2026-10 target month
--       is scored against it. Acceptance R20 checks the flag against the history.
--
-- HOW AN INDEX IS JOINED TO AN OBSERVATION: THE NULL-WILDCARD CONTRACT. History rows carry the
-- four possible join keys as columns; an index that does not key on one leaves it NULL. The join
-- is (h.key IS NULL OR h.key = o.key) on product_short_name / intent_key / intent_type and a
-- STRICT equality on month_of_year. The procedure refuses to write a declared key as NULL and
-- refuses an index with no wildcard key at all (a row NULL on all three matches everything,
-- acceptance R18), and R19 checks the history is unique on its grain, because a duplicate row
-- here would fan a scored cell out and double-count its clicks. An index with no snapshot at all
-- produces NO rows (the join to snap_pick is inner) and R12 reports it -- scoring it as 1.000
-- everywhere would be a vacuous NEUTRAL, which is worse than a missing row.
--
-- ---------------------------------------------------------------------------------------------
-- WHAT THE TWO TESTS MEAN, IN TERMS OF THE ACTIVE SET
-- Let A = the indexes the registry marks is_active at scoring time, and iv_i the shrunk value of
-- index i on a cell. Every prediction is base_cvr x PRODUCT over some set of indexes.
--   * ADD_ONE_IN(i):     with = A u {i},  without = A \ {i}.
--                        "Does i help on top of what is actually live?"
--   * LEAVE_ONE_OUT(i):  with = H u {i},  without = H \ {i},  where H = A if A is non-empty,
--                        else THE WHOLE REGISTRY.
--                        "Does i still earn its place inside the set it would ship with?"
-- WHY H FALLS BACK TO THE WHOLE REGISTRY. Both registry rows are is_active = FALSE today, so A is
-- empty and LEAVE_ONE_OUT has nothing to remove. Evaluated literally it would return zero rows,
-- R12 (every registered index is scored under both tests) would fail, and Task 7 would have no
-- evidence to gate on. Against the hypothetical full registry it answers "if everything were
-- promoted, would this one still earn its place", which is the question that matters at the
-- promotion decision and the only version that can produce a row today. It is also exactly what
-- the first cut computed (with = base x season_month x season_phase, without = drop the named
-- one), so the pre-registry output is reproduced -- measured, see below. Once anything is
-- promoted the fallback stops applying and both tests read the real A; for an active index the
-- two tests then coincide (with = A, without = A \ {i}), which is what "converge on the same
-- baseline" meant in the first cut's header.
-- The products are EXP(SUM(LN(iv))) as window sums over the cell x index fan-out, so a set of any
-- size costs one aggregation. LN is safe because index_value > 0 is enforced at write time and the
-- shrinkage 1 + (v - 1) * s with s in [0, 1] keeps it positive.
--
-- ---------------------------------------------------------------------------------------------
-- INDEXES ARE APPLIED EXACTLY AS THE SHADOW CURVE WOULD APPLY THEM -- SHRUNK, NOT RAW
-- DEVIATION FROM THE PLAN'S DRAFT SQL, deliberate. The draft multiplied by the published
-- index_value. V_INTENT_CVR_CURVE_SHADOW does not: it applies
--     1 + (index_value - 1) * LEAST(1, support_clicks / INTENT_IDX_MIN_SUPPORT)
-- so a thin cell is pulled back to 1.000 and contributes nothing. That gate is load-bearing --
-- spec section 7.5 records that 161 of 204 published season_phase rows sit below it and are
-- pinned to 1.000 -- so scoring the UNSHRUNK index would deliver a verdict about a curve that
-- cannot ship. Measured both ways 2026-08-31 it changed no verdict (season_month unmoved because
-- its support clears the gate everywhere; season_phase moved -0.53% -> -0.28% pooled, not across a
-- threshold). Kept anyway: this view has to score the curve that would actually run, and the
-- gate's effective strictness loosens on its own as history accumulates (spec 7.5).
--
-- ---------------------------------------------------------------------------------------------
-- TWO LIMITATIONS. STATED, NOT FIXED. Read them before reading a verdict.
-- (L1 of the first cut -- indexes not walk-forward -- is now measured per row as leakage_flag
-- rather than stated; it is a limitation of the DATA until snapshots accumulate, not of the view.)
--
-- L2. THE BASE HERE IS FLAT-POOLED; THE SHADOW'S IS RECENCY-WEIGHTED. This view fits base_cvr on
--     all prior months with equal weight (the plan's design). V_INTENT_CVR_CURVE_SHADOW fits it
--     on nested 1/2/3/6/12 windows. So a verdict says "this index helps ON TOP OF A FLAT BASE",
--     not "on top of the base that will ship". The two changes are separable by design -- Task 6
--     (V_INTENT_BASE_TUNING) measures the recency shape and this view measures the indexes -- but
--     nothing here proves they compose. Visible in the numbers: bias pools to ~0.80, so every
--     level column on this view sits ~1.25x under the realised CVR. That is the D3 under-pricing,
--     still present because the base here is flat and carries no INTENT_CVR_CALIBRATION; the
--     indexes do not touch it, and by contract cannot -- each is normalised to a clicks-weighted
--     mean of 1.000. So read a verdict as a statement about SHAPE only. Task 8's money gate runs
--     against the shadow, which is where the composed answer comes from.
--
-- L3. TWO OBSERVATIONS PER CALENDAR MONTH, AT MOST. Ads data starts 2024-09-05. A yearly-seasonal
--     index therefore gets at most two observations of any one month, which spec section 8
--     already flags and which is a reason to prefer manual promotion.
--
-- ---------------------------------------------------------------------------------------------
-- WHAT IT SAYS TODAY. Measured 2026-09-11 at ads watermark 2026-09-10, 1,170 predictions and
-- 817,915 clicks, first cut and this cut on the SAME watermark. Every row leakage_flag = TRUE
-- (one snapshot, 2026-09, and no target month is later than it), so the index values are the
-- same as-deployed values the first cut read, and the two cuts must agree exactly:
--     index         test            pooled err_delta   verdict    IMPROVES / months_scored
--     season_month  ADD_ONE_IN          -16.42%        IMPROVES          8 / 18
--     season_month  LEAVE_ONE_OUT       -16.42%        IMPROVES          8 / 18
--     season_phase  ADD_ONE_IN           -0.57%        NEUTRAL           3 / 18
--     season_phase  LEAVE_ONE_OUT        -0.57%        NEUTRAL           3 / 18
-- AGREEMENT WITH THE FIRST CUT, MEASURED 2026-09-11: 76 rows before and after, identical key
-- sets, ZERO cell differences across all 15 original columns; the only change is the two new
-- columns (snapshot_month_used, leakage_flag). The rewrite moved no verdict and no number.
-- The 2026-08-31 reading (watermark 2026-08-31) was -16.23 / -16.20 / -0.53 / -0.49 with 6 and 3
-- improving months; the shift is ten days of new clicks and a new partial target month, not the
-- rewrite. NOT ONE MONTH READS INSUFFICIENT, then or now: INTENT_IDX_MIN_SCORED_CLICKS = 500 is a
-- per-MONTH click total and every month clears it by two orders of magnitude (spec section 6
-- step 3 predicted otherwise about a per-CELL denominator). season_month's own split is the thing
-- to argue about: a pooled IMPROVES made of a minority of high-click winning months outvoting the
-- rest. season_phase improves in the Valentine's/Easter window it was built for and is inert
-- elsewhere, which is what a fix reaching ~9% of clicks should look like.
--
-- ---------------------------------------------------------------------------------------------
-- COST: THE OBSERVATION SET IS SCANNED EXACTLY ONCE, AND THAT IS A DESIGN CONSTRAINT
-- BigQuery inlines a CTE at every reference rather than materialising it. The plan's draft
-- referenced `scored` in four separate GROUP BYs and `obs` in three CTEs, which is seven
-- evaluations of a chain that regexes 337k search terms across 18 target months. That is the
-- same wall this project has already hit: the Task 4 acceptance file was REJECTED by BigQuery at
-- 97,066 CPU-seconds against a 33,500 on-demand ceiling, and T_INTENT_CVR_CURVE exists because
-- the live curve cost ~27k CPU-seconds per scan.
-- So the shape here is deliberate and must not be "simplified" back:
--   * `cell` joins targets to obs ONCE, on o.mo <= t.target_month, and separates the fitting
--     window from the target month with IF(o.mo < t.target_month, ...) / IF(o.mo = ..., ...).
--   * the global prior is a WINDOW FUNCTION over that same aggregate, not a third scan.
--   * `scored` (the ~1,170 cells that clear the click floors) is referenced ONCE, in cell_idx,
--     where it fans out to one row per registered index. Everything downstream -- the set
--     products as window sums, the two tests as an UNNEST, the per-month aggregation and the
--     pooled row via GROUPING SETS -- works on that fan-out, which is hundreds of rows per index.
--     The registry, the snapshot picker and the history are small tables joined AFTER the click
--     floors, never before them.
-- MEASURED: first cut 6,215 slot-seconds / 116 MB (2026-08-31) and 5,575 / 118.5 MB on the
-- 2026-09-11 baseline run; this cut 970 slot-seconds / 94 MB for the same 76 rows. The drop is
-- real, not a measurement artefact: the two index views are no longer inlined here -- their
-- scans moved into SP_SCORE_INTENT_INDEXES's snapshot INSERTs (1,873 and 2,962 slot-seconds,
-- once per run) and this view reads the resulting table. Whole procedure: 6,734 slot-seconds.
--
-- ---------------------------------------------------------------------------------------------
-- INTENT SOURCE: V_ADS_SEARCH_TERM_INTENT, NOT V_INTENT_RESOLVED
-- The curve reads V_INTENT_RESOLVED (the human-verified overlay). This view reads the raw
-- classifier, for two reasons: the index views being scored are themselves defined on
-- V_ADS_SEARCH_TERM_INTENT, so their intent_key / intent_type domains match here; and it is
-- half the cost. Measured both ways 2026-08-31 the verdicts were identical (V_INTENT_RESOLVED:
-- 13,247 slot-seconds, 1,766 predictions vs 1,162) -- the cell population moves, the verdicts
-- do not, and absolute errors are not comparable across the two.
--
-- MIN(intent_type) RATHER THAN ANY_VALUE. Two intent_keys carry more than one intent_type
-- (measured 2026-08-31 on V_INTENT_RESOLVED; the same shape exists here). ANY_VALUE would make
-- the intent_type join key nondeterministic between runs, which is the recorded ANY_VALUE
-- pairing defect in a new place. MIN is total and cheap.
--
-- Dependencies: FACT_AMAZON_ADS, V_ADS_SEARCH_TERM_INTENT, DIM_PRODUCT, DE_COACH_THRESHOLDS,
--               DE_INTENT_INDEX_REGISTRY, T_INTENT_IDX_HISTORY
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

-- One prediction per scored cell, BEFORE any index is applied. The join keys ride along for the
-- history join below.
--   act_clicks >= 60 : the target month must carry enough clicks for its realised CVR to mean
--                      anything. Same cut the offline sweep used.
--   fit_clicks > 0   : a cell with no history before M has nothing to predict FROM.
scored AS (
  SELECT c.target_month, c.fitted_through,
         c.product_short_name, c.intent_key, c.intent_type,
         c.act_clicks AS clicks,
         SAFE_DIVIDE(c.act_orders, c.act_clicks) AS actual_cvr,
         SAFE_DIVIDE(c.fit_orders + p.k_base * c.prior_cvr, c.fit_clicks + p.k_base) AS base_cvr
  FROM cell_p c
  CROSS JOIN params p
  WHERE c.act_clicks >= 60 AND c.fit_clicks > 0
),

-- The registry is the list of indexes to score and the definition of the active set. any_active
-- decides whether LEAVE_ONE_OUT's reference set H is the real active set or the whole registry.
registry AS (
  SELECT index_name, is_active,
         LOGICAL_OR(is_active) OVER () AS any_active
  FROM `onyga-482313.OI.DE_INTENT_INDEX_REGISTRY`
),

-- Which snapshot scores which target month: the newest one STRICTLY BEFORE the month, else the
-- latest with leakage_flag = TRUE. One row per index x target month; an index with no snapshot
-- at all has no row here and therefore no scorecard row (R12 fires).
snaps AS (
  SELECT DISTINCT index_name, snapshot_month
  FROM `onyga-482313.OI.T_INTENT_IDX_HISTORY`
),
snap_pick AS (
  SELECT t.target_month, s.index_name,
         COALESCE(MAX(IF(s.snapshot_month < t.target_month, s.snapshot_month, NULL)),
                  MAX(s.snapshot_month))                                  AS snapshot_month_used,
         MAX(IF(s.snapshot_month < t.target_month, s.snapshot_month, NULL)) IS NULL AS leakage_flag
  FROM targets t
  CROSS JOIN snaps s
  GROUP BY 1, 2
),

-- Every history row, shrunk by its own support exactly as V_INTENT_CVR_CURVE_SHADOW shrinks it.
hist AS (
  SELECT h.index_name, h.snapshot_month,
         h.product_short_name, h.intent_key, h.intent_type, h.month_of_year,
         1.0 + (h.index_value - 1.0) * LEAST(1.0, SAFE_DIVIDE(h.support_clicks, p.idx_min_support)) AS iv
  FROM `onyga-482313.OI.T_INTENT_IDX_HISTORY` h
  CROSS JOIN params p
),

-- THE FAN-OUT: one row per scored cell x registered index, carrying that index's shrunk value
-- on that cell from the chosen snapshot. COALESCE to 1.0 is the "index absent on this cell" case
-- and is what makes an index optional, matching the curve's own LEFT JOIN + COALESCE. The
-- NULL-wildcard join is the header's contract. `scored` is referenced here and nowhere else.
cell_idx AS (
  SELECT s.target_month, s.fitted_through,
         s.product_short_name, s.intent_key,
         s.clicks, s.actual_cvr, s.base_cvr,
         r.index_name, r.is_active,
         (r.is_active OR NOT r.any_active) AS in_h,
         sp.snapshot_month_used, sp.leakage_flag,
         LN(COALESCE(h.iv, 1.0)) AS ln_iv
  FROM scored s
  CROSS JOIN registry r
  JOIN snap_pick sp ON sp.index_name   = r.index_name
                   AND sp.target_month = s.target_month
  LEFT JOIN hist h  ON h.index_name     = r.index_name
                   AND h.snapshot_month = sp.snapshot_month_used
                   AND (h.intent_type        IS NULL OR h.intent_type        = s.intent_type)
                   AND (h.intent_key         IS NULL OR h.intent_key         = s.intent_key)
                   AND (h.product_short_name IS NULL OR h.product_short_name = s.product_short_name)
                   AND h.month_of_year = EXTRACT(MONTH FROM s.target_month)
),

-- The set products per cell as window sums of logs: ln_a over the active set A, ln_h over the
-- LEAVE_ONE_OUT reference set H. One pass over the fan-out, whatever the registry's size.
cell_prod AS (
  SELECT ci.*,
         SUM(IF(ci.is_active, ci.ln_iv, 0))
           OVER (PARTITION BY ci.target_month, ci.product_short_name, ci.intent_key) AS ln_a,
         SUM(IF(ci.in_h, ci.ln_iv, 0))
           OVER (PARTITION BY ci.target_month, ci.product_short_name, ci.intent_key) AS ln_h
  FROM cell_idx ci
),

-- The two tests per cell x index, as the header defines them: with = SET u {i}, without =
-- SET \ {i}. Adding i to a set that already holds it changes nothing; removing it from a set
-- that does not hold it changes nothing.
tests AS (
  SELECT cp.target_month, cp.fitted_through, cp.index_name,
         cp.snapshot_month_used, cp.leakage_flag,
         cp.clicks, cp.actual_cvr,
         x.test_kind,
         cp.base_cvr * EXP(x.ln_with)    AS pred_with,
         cp.base_cvr * EXP(x.ln_without) AS pred_without
  FROM cell_prod cp
  CROSS JOIN UNNEST([
    STRUCT('ADD_ONE_IN' AS test_kind,
           cp.ln_a + IF(cp.is_active, 0, cp.ln_iv) AS ln_with,
           cp.ln_a - IF(cp.is_active, cp.ln_iv, 0) AS ln_without),
    STRUCT('LEAVE_ONE_OUT',
           cp.ln_h + IF(cp.in_h, 0, cp.ln_iv),
           cp.ln_h - IF(cp.in_h, cp.ln_iv, 0))
  ]) AS x
),

-- ONE aggregation to index x test x month. e_* are click-weighted absolute errors, s* are
-- click-weighted predicted volumes whose ratio to s_actual is the bias.
per_month AS (
  SELECT t.index_name, t.test_kind, t.target_month,
         MAX(t.fitted_through)                          AS fitted_through,
         SUM(t.clicks)                                  AS clicks_scored,
         COUNT(*)                                       AS n_predictions,
         SUM(t.clicks * ABS(t.pred_with    - t.actual_cvr)) AS e_with,
         SUM(t.clicks * ABS(t.pred_without - t.actual_cvr)) AS e_without,
         SUM(t.clicks * t.pred_with)                    AS sw,
         SUM(t.clicks * t.pred_without)                 AS swo,
         SUM(t.clicks * t.actual_cvr)                   AS s_actual,
         MAX(t.snapshot_month_used)                     AS snapshot_month_used,
         LOGICAL_OR(t.leakage_flag)                     AS leakage_flag
  FROM tests t
  GROUP BY 1, 2, 3
),

-- The per-month verdict, needed HERE and not only at the end because months_improved on the
-- pooled row counts it. Identical CASE to the published one; over a single month the aggregate
-- below sums one row, so the two cannot disagree.
m AS (
  SELECT pm.*,
         CASE
           WHEN pm.clicks_scored < p.min_scored THEN 'INSUFFICIENT'
           WHEN SAFE_DIVIDE(pm.e_with - pm.e_without, NULLIF(pm.e_without, 0)) * 100 >= 1.0
             OR ABS(SAFE_DIVIDE(pm.sw,  pm.s_actual) - 1.0)
              > ABS(SAFE_DIVIDE(pm.swo, pm.s_actual) - 1.0) + 0.02 THEN 'HURTS'
           WHEN SAFE_DIVIDE(pm.e_with - pm.e_without, NULLIF(pm.e_without, 0)) * 100 <= -1.0
            AND ABS(SAFE_DIVIDE(pm.sw,  pm.s_actual) - 1.0)
             <= ABS(SAFE_DIVIDE(pm.swo, pm.s_actual) - 1.0) + 0.02 THEN 'IMPROVES'
           ELSE 'NEUTRAL' END AS verdict_month
  FROM per_month pm CROSS JOIN params p
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
         COUNTIF(verdict_month != 'INSUFFICIENT') AS months_scored,
         MAX(snapshot_month_used)                 AS snapshot_month_used,
         LOGICAL_OR(leakage_flag)                 AS leakage_flag
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
  IF(r.target_month IS NULL, r.months_scored,   NULL) AS months_scored,
  -- Which snapshot of the index scored this month (NULL on the pooled row, which spans several),
  -- and whether that snapshot post-dates the month -- TRUE means the index had already seen the
  -- clicks it is being scored against. On the pooled row: TRUE if any month leaked.
  IF(r.target_month IS NULL, NULL, r.snapshot_month_used) AS snapshot_month_used,
  r.leakage_flag
FROM rolled r
CROSS JOIN params p;
