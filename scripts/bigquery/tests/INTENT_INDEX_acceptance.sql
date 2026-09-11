-- =============================================================================================
-- INTENT INDEX REGISTRY acceptance. Every check returns a VIOLATION COUNT; PASS is 0.
-- Spec: docs/superpowers/specs/2026-08-31-intent-cvr-index-registry-design.md
--
-- THIS FILE IS A TWO-STATEMENT SCRIPT, NOT ONE QUERY, AND THAT SPLIT IS FORCED (2026-09-01).
-- R15 reads V_INTENT_BID_BASE, which inlines V_INTENT_CVR_CURVE. Folded into the single
-- statement, the suite was REJECTED for the third time in this chain's history: 76,659 CPU
-- seconds against a 43,500 limit at 170 MB of analysis bytes. The parts do not explain the
-- whole -- the suite alone measured 17,280 slot-seconds and R15's catalog arm 7,221 on its own,
-- so the excess is planner interaction, the same class as the "too many subqueries" blowup that
-- comes from a query inlining two heavy views at once (here: the SERVED curve under R15 and the
-- SHADOW curve under R09-R11). Splitting R15 into its own statement gives each its own CPU/bytes
-- budget. Measured on the split run that replaced the rejected one: statement 1 (R15) 7,540
-- slot-seconds on 171 MB, statement 2 (everything else) 17,651 on 143 MB, 25,191 for the script
-- -- against 76,659 for the same work merged. `bq query` runs the script and prints the final
-- statement's table, so the invocation is unchanged.
-- DO NOT re-merge the two statements without re-measuring.
-- =============================================================================================

-- R15 runs first and alone. Its comment, controls and cost are documented at the r15 CTE below.
CREATE TEMP TABLE r15_result AS
SELECT COALESCE(CAST(ABS(SAFE_DIVIDE(cat, hou) - 1.0) > 0.15 AS INT64), 1) AS v FROM (
  SELECT (SELECT SAFE_DIVIDE(SUM(gp_per_order * month_clicks), NULLIF(SUM(month_clicks), 0))
          FROM `onyga-482313.OI.V_INTENT_BID_BASE` WHERE month_clicks > 0) AS cat,
         (SELECT SAFE_DIVIDE(SUM(weighted_gross_profit), NULLIF(SUM(weighted_orders), 0))
          FROM `onyga-482313.OI.V_KEYWORD_RATES`) AS hou);

-- R01 THE REGISTRY EXISTS AND HAS A UNIQUE KEY. A duplicate index_name would apply the same
--     multiplier twice and square it.
--     NOTE: the registry is EMPTY until Task 2 seeds season_month, so a green R01 today has
--     validated nothing beyond the table existing — an empty table cannot hold a duplicate. It
--     starts enforcing once there are rows. Do not read today's 0 as evidence the key holds.
WITH r01 AS (
  SELECT COUNTIF(n > 1) AS v
  FROM (SELECT index_name, COUNT(*) AS n
        FROM `onyga-482313.OI.DE_INTENT_INDEX_REGISTRY` GROUP BY 1)
),
-- R02 EVERY THRESHOLD THE CURVE READS IS PRESENT, UNDER THE MODE IT WILL BE READ AT. A missing
--     row makes the multiplier NULL and silently blanks cvr_hat for the whole catalog.
--     coach_mode IS PART OF THE KEY, not a tag: thresholds resolve strategy_id+coach_mode ->
--     GLOBAL+coach_mode -> strategy_id+GUARDIAN -> GLOBAL+GUARDIAN -> hardcoded fallback (see the
--     header of DE_COACH_THRESHOLDS.sql and the four-way LEFT JOIN in V_ADS_COACH). A row landing
--     under BLITZ or COOLDOWN is invisible to a GUARDIAN read, which falls through to a GLOBAL
--     default instead — the curve then prices against a number nobody chose for it, and without
--     this filter the check would still report a clean 0. All five seeded rows are GUARDIAN.
--     COUNT(DISTINCT threshold_key) rather than COUNT(*): product_family is also part of the
--     grain, so a family-scoped override for one of these keys would push a row count past 5 and
--     let one extra row cancel out one missing row.
--     INTENT_PHASE_PRIOR_CLICKS joined this list at Task 3. It is not interchangeable with the
--     season prior: V_INTENT_IDX_SEASON_PHASE resolves it alone, and if it goes missing every
--     phase_index is NULL and the whole phase index empties. R06's COUNT(*) = 0 term would catch
--     the consequence, but only as "the view is empty" -- this check is what names the cause.
r02 AS (
  SELECT 6 - COUNT(DISTINCT threshold_key) AS v
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id = 'INTENT' AND coach_mode = 'GUARDIAN' AND threshold_key IN (
    'INTENT_CVR_BASE_PRIOR_CLICKS','INTENT_CVR_SEASON_PRIOR_CLICKS','INTENT_PHASE_PRIOR_CLICKS',
    'INTENT_CVR_CALIBRATION','INTENT_IDX_MIN_SUPPORT','INTENT_IDX_MIN_SCORED_CLICKS')
),
-- R02b THE VALUES ARE THE ONES THIS MIGRATION LANDED, not merely present. R02 proves the keys
--      exist and asserts none of the numbers. If the base-prior UPDATE were reverted, or a stale
--      copy of the migration were partially re-run, all five keys would still be there and R02
--      would stay green while the curve priced every intent off the old prior — which is one of
--      the three defects this work exists to fix, so it would fail silently in exactly the place
--      it was supposed to be fixed. Asserts the two values the migration deliberately sets:
--      the base prior it RAISES 200 -> 400, and the calibration constant. The other three are
--      seeded-and-never-yet-tuned, and Task 2 re-derives the season prior, so pinning those here
--      would only create a check that has to be edited every time a number is legitimately tuned.
r02b AS (
  SELECT COUNTIF(
           (threshold_key = 'INTENT_CVR_BASE_PRIOR_CLICKS' AND threshold_value != 400.0)
        OR (threshold_key = 'INTENT_CVR_CALIBRATION'       AND threshold_value != 1.151)
         ) AS v
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id = 'INTENT' AND coach_mode = 'GUARDIAN'
    AND threshold_key IN ('INTENT_CVR_BASE_PRIOR_CLICKS','INTENT_CVR_CALIBRATION')
),
-- R03 EVERY INDEX IS NORMALISED TO A CLICKS-WEIGHTED MEAN OF 1.000. An un-normalised index
--     silently shifts the whole catalog's level and INTENT_CVR_CALIBRATION absorbs it, which
--     hides the change from the scorecard. Tolerance 0.02.
r03 AS (
  SELECT COUNTIF(ABS(m - 1.0) > 0.02) AS v FROM (
    SELECT SAFE_DIVIDE(SUM(index_value * support_clicks), NULLIF(SUM(support_clicks),0)) AS m
    FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_MONTH`)
),
-- R03b THE INDEX GRID IS COMPLETE, AND R03/R04/R05 ARE NOT BEING GREEN OVER AN EMPTY VIEW.
--      Verified by negative control: with the view filtered to zero rows, R03, R04 and R05 all
--      return 0 — an empty set has no mean to be off by 0.02, no NULL to find, and 0 flat values
--      is not > 0 * 0.80. So all three would stay silent on total failure. That is reachable: the
--      params CTE resolves k_season from a single DE_COACH_THRESHOLDS row, and if that row is
--      deleted or moved to another coach_mode, k_season is NULL, every raw_index is NULL, the
--      final WHERE drops every row and the curve loses its whole seasonal layer while acceptance
--      reports a clean pass. Same shape as the R01 note above: a check over an empty table has
--      validated nothing. Also fails if any intent_type is missing a month, because the shadow
--      curve LEFT JOINs this grid and COALESCEs a miss to 1.000 — a silently neutral month.
--      THE EXPECTED TYPE COUNT IS SOURCED FROM DE_INTENT_THEMES, NOT FROM THE VIEW. The first
--      version compared COUNT(*) against COUNT(DISTINCT intent_type) * 12 read off the view
--      itself, which cannot detect a whole intent_type disappearing: t.cvr is one value per TYPE,
--      not per month, so a genuinely-zero all-month CVR nulls raw_index for all 12 of that type's
--      rows at once and the final WHERE drops the entire type — both sides of that comparison then
--      shrink together and it stays green while half the grid is gone. Counting the types that
--      V_ADS_SEARCH_TERM_INTENT can actually resolve (active themes carrying an ads regex) gives
--      an anchor the view cannot move.
r03b AS (
  SELECT CAST(COUNT(*) = 0
           OR COUNT(*) != (SELECT COUNT(DISTINCT intent_type)
                           FROM `onyga-482313.OI.DE_INTENT_THEMES`
                           WHERE is_active AND match_ads_regex IS NOT NULL
                             AND intent_type IS NOT NULL) * 12 AS INT64) AS v
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_MONTH`
),
-- R04 NO INDEX IS NULL OR NON-POSITIVE. A NULL multiplies cvr_hat to NULL; a zero or negative
--     value makes a bid of zero or a negative price.
r04 AS (
  SELECT COUNTIF(index_value IS NULL OR index_value <= 0) AS v
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_MONTH`
),
-- R05 THE INDEX IS ACTUALLY DOING SOMETHING. The defect this replaces had 85.3% of values inside
--     [0.95,1.05]. If the replacement is just as flat it has not been fixed.
--     THRESHOLD IS 0.30, NOT 0.80. Over a 24-row grid, 0.80 fires only at 20/24 (83%) — that is
--     essentially the original 85.3% defect restored exactly, so a regression to 40-50% flat,
--     serious by any standard, would sit here green. 0.30 fires at 8/24 (33%): far enough above
--     today's measured 4.2% (1/24) that ordinary drift in the underlying clicks will not trip it,
--     and small enough a fraction of 85.3% that it actually guards the property it names.
r05 AS (
  SELECT CAST(COUNTIF(index_value BETWEEN 0.95 AND 1.05) > COUNT(*) * 0.30 AS INT64) AS v
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_MONTH`
),
-- R06 PHASE INDEX IS NORMALISED PER INTENT. base_cvr already carries the intent's own level, so
--     an index whose intent-level mean is not 1.0 would double-count that level.
--     PER intent_key, not once overall: this view is keyed on intent_key and the shadow curve
--     joins it on intent_key, so a per-intent level error is exactly what would leak through.
--     THE `COUNT(*) = 0` TERM IS LOAD-BEARING AND GUARDS R07/R08 TOO. Verified by negative
--     control: with the view filtered to zero rows the plain COUNTIF form returns 0 — an empty
--     set has no mean to be off by 0.05 — and R08's duplicate check returns 0 for the same
--     reason. Total failure is reachable: k_phase resolves from a single DE_COACH_THRESHOLDS row,
--     INTENT_PHASE_PRIOR_CLICKS, and if it is deleted or moved to another coach_mode every
--     phase_index is NULL, the normaliser is NULL and the final WHERE drops the whole view.
--     NOT k_season / INTENT_CVR_SEASON_PRIOR_CLICKS -- that is the season_month view's prior, and
--     this index stopped reading it when it got its own grain-specific one. `m IS NULL` is in the same
--     spirit — a row set whose support_clicks sum to 0 yields a NULL mean, which ABS() > 0.05
--     would also wave through.
r06 AS (
  SELECT COUNTIF(m IS NULL OR ABS(m - 1.0) > 0.05) + CAST(COUNT(*) = 0 AS INT64) AS v FROM (
    SELECT intent_key, SAFE_DIVIDE(SUM(index_value * support_clicks), NULLIF(SUM(support_clicks),0)) AS m
    FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE` GROUP BY intent_key)
),
-- R07 THE PHASE INDEX SEPARATES PEAK FROM TROUGH. A mean-1.000 contract caps the maximum at
--     1/peak_click_share (1.41 for easter), so testing MAX is testing the normaliser, not the
--     signal. What must survive is the SPREAD: unshrunk, easter runs PEAK 1.206 against BOOST
--     0.301, a 4.0x swing. If the ratio collapses the moving-holiday fix has done nothing and
--     V_INTENT_CVR_CURVE keeps pricing Easter peak week off a pre-peak March average.
--     REPLACES a first cut that asked for MAX(index_value) >= 1.5. That bar was not merely missed
--     but UNREACHABLE: R06 pins the clicks-weighted mean to 1.000 and easter's peak month carries
--     ~74% of the projected support, capping its index at ~1.34 for any prior. The two checks
--     contradicted each other. See spec section 4.5, AMENDMENT 2026-08-31, Error 1.
--     COALESCE(..., 0) IS LOAD-BEARING, carried over from that first cut. Without it an empty or
--     all-NULL easter row set makes the ratio NULL and v NULL -- which is not the 0 this file
--     defines as PASS but reads like one at a glance. With it, total disappearance scores 0 < 2.0
--     and fails loudly, which is the correct verdict: no easter row means no moving-holiday fix.
r07 AS (
  SELECT CAST(COALESCE(SAFE_DIVIDE(MAX(index_value), NULLIF(MIN(index_value),0)), 0) < 2.0
              AS INT64) AS v
  FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE` WHERE intent_key = 'easter'
),
-- R08 ONE ROW PER intent_key x month_of_year. A duplicate multiplies the index twice.
--     Real risk here, not theory: the projection fans out over V_ADS_SEARCH_TERM_INTENT and over
--     overlapping holiday windows, and both fan-outs have to collapse in the GROUP BY.
--     Vacuously green over an empty view; R06's COUNT(*) = 0 term is what covers that case.
r08 AS (
  SELECT COUNTIF(n > 1) AS v FROM (
    SELECT intent_key, month_of_year, COUNT(*) AS n
    FROM `onyga-482313.OI.V_INTENT_IDX_SEASON_PHASE` GROUP BY 1,2)
),
-- =============================================================================================
-- R09-R11 cover V_INTENT_CVR_CURVE_SHADOW (plan Task 4). The shadow is the rebuilt curve, wired
-- to nothing until Task 9. These three exist to keep it DIFFABLE against the live curve, because
-- that diff is the only evidence the money gate has to work with.
--
-- WHY THEY SHARE ONE CTE INSTEAD OF READING THE VIEW THREE TIMES. BigQuery inlines a CTE at every
-- reference rather than materialising it, so three checks reading the shadow are three full
-- evaluations of a chain that regexes 337k search terms. Written the obvious way -- R09, R10 and
-- a two-directional R11 against the live view -- this file used 97,066 CPU seconds against an
-- on-demand ceiling of 33,500 and was REJECTED by BigQuery, not merely slow. That is the same
-- wall recorded against T_INTENT_CVR_CURVE in config.yaml ("broke a 3-way UNION at the on-demand
-- CPU cap on 2026-07-25"). Measured: R01-R08 alone 8,281 slot-seconds / 111 MB; one shadow scan
-- 12,693 / 131 MB; together well inside the ceiling, which scales at ~256 CPU-seconds per MB
-- billed. So the shadow is scanned EXACTLY ONCE, into `shadow_vs_served`, and the three verdicts
-- are read out of a single-row CTE via UNNEST at the bottom of the file. DO NOT "simplify" this
-- into three separate SELECTs over the view: it will not run.
--
-- WHY R11 COMPARES AGAINST T_INTENT_CVR_CURVE AND NOT V_INTENT_CVR_CURVE. Two reasons, one of
-- them a defect found while building this file.
--   1. Cost, as above. The live view is a second 7,630-slot-second chain.
--   2. THE LIVE VIEW IS NOT DETERMINISTIC, so an exact key-set equality against it would be a
--      flaky check. V_ADS_SEARCH_TERM_FACETS (upstream of V_INTENT_RESOLVED, which both curves
--      read) picks product_type with
--        ARRAY_AGG(ptk.product_type ORDER BY ptk.priority ASC, LENGTH(ptk.keyword) DESC LIMIT 1)
--      and that ORDER BY is not a total order: DE_PRODUCT_TYPE_KEYWORDS has 44 distinct
--      (priority, keyword-length) groups spanning more than one product_type, 288 values in all
--      (measured 2026-08-31). product_type composes into intent_key, so a tied term can resolve
--      to a different intent between two evaluations. Observed while measuring this task: the
--      live view reported 10,440 product x intent cells on one run and 10,441 on the next, and
--      the shadow reported 10,441 then 10,440 across three runs, differing by the single cell
--      "Fresh in Pink" x "teen-bracelet-gift". Same class as the recorded ANY_VALUE pairing
--      defect. It is upstream of this project and is NOT fixed here.
-- T_INTENT_CVR_CURVE is the frozen snapshot every consumer actually reads, so "the shadow still
-- covers what the catalog serves" is both the question worth asking and a stable one to ask.
-- WHAT THIS COSTS: the direction "the shadow grew keys the live view never had" is not tested
-- here. R09's uniqueness term catches a JOIN FAN-OUT, which is the mechanism that would produce
-- them; a genuinely new key can only come from new ads history, which is expected. The full
-- two-directional shadow-vs-live-view diff is a manual step, run once in Task 4 (result: 1 cell
-- of 10,441 differed, and that cell was itself the flapping one) and again in Task 7.
--
-- ONE SCAN OF EACH SIDE, UNIONED AND KEYED. n_shadow > 1 is a duplicate; n_served > 0 with
-- n_shadow = 0 is a served key the shadow lost.
shadow_vs_served AS (
  SELECT FORMAT('%T|%T|%T', product_short_name, intent_key, month_of_year) AS k,
         1 AS in_shadow, 0 AS in_served,
         CAST((cvr_hat IS NULL OR cvr_hat < 0 OR cvr_hat > 1.0
               OR season_index IS NULL OR season_index <= 0
               -- PRE-CAP ARM. cvr_hat is wrapped in LEAST(..., 1.0), so the post-cap arms above
               -- can NEVER observe a cap that has started to bind -- a runaway index would be
               -- silently clipped to exactly 1.0 and pass. This reconstructs the uncapped product
               -- from the published factors so that a binding cap is detectable rather than only
               -- documented. Approximate by construction: base_cvr is published rounded to 5dp
               -- and season_index to 4dp, which is far finer than a tripwire at 1.0 needs.
               -- Headroom today is 2.71x (largest cvr_hat 0.36961), so this arm is expected to
               -- stay silent; the point is that it CAN speak.
               OR (SELECT MAX(IF(threshold_key = 'INTENT_CVR_CALIBRATION', threshold_value, NULL))
                   FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
                   WHERE strategy_id = 'INTENT' AND coach_mode = 'GUARDIAN'
                     AND product_family IS NULL) * base_cvr * season_index > 1.0
              ) AS INT64) AS bad
  FROM `onyga-482313.OI.V_INTENT_CVR_CURVE_SHADOW`
  UNION ALL
  SELECT FORMAT('%T|%T|%T', product_short_name, intent_key, month_of_year), 0, 1, 0
  FROM `onyga-482313.OI.T_INTENT_CVR_CURVE`
),
keyed AS (
  SELECT k, SUM(in_shadow) AS n_shadow, SUM(in_served) AS n_served, SUM(bad) AS n_bad
  FROM shadow_vs_served GROUP BY k
),
-- COALESCE ON EVERY SUM IS LOAD-BEARING, same trap R07 documents. `keyed` is empty only when
-- BOTH sides are empty, and an aggregate with no GROUP BY still returns one row -- with every
-- SUM as NULL. Without these, v computes to NULL, which is not the 0 this file defines as PASS
-- but renders as a blank cell and reads like one. Verified by negative control.
verdicts AS (
  SELECT COUNTIF(n_shadow > 1)                       AS dup_shadow_keys,
         COALESCE(SUM(n_shadow), 0)                  AS rows_shadow,
         COALESCE(SUM(n_bad), 0)                     AS bad_shadow_rows,
         COUNTIF(n_served > 0 AND n_shadow = 0)      AS served_keys_missing,
         COALESCE(SUM(n_served), 0)                  AS rows_served
  FROM keyed
),
-- =============================================================================================
-- R12-R14 AND R16 COVER THE WALK-FORWARD EVIDENCE LAYER (plan Tasks 5-6). They read the
-- MATERIALISED tables, T_INTENT_INDEX_SCORECARD and T_INTENT_BASE_TUNING, NOT the views behind
-- them. That is not a shortcut, it is the only affordable shape:
--   * V_INTENT_INDEX_SCORECARD costs 6,215 slot-seconds / 116 MB per scan and V_INTENT_BASE_TUNING
--     942 / 92 MB (measured 2026-08-31). Four checks reading the scorecard view would be four
--     full evaluations, because BigQuery inlines a CTE at every reference -- which is exactly how
--     the R09-R11 block reached 97,066 CPU-seconds against a 33,500 ceiling and was REJECTED.
--   * the tables are 76 and 9 rows, so scanning them once per check is free and the checks stay
--     readable instead of being folded into another single-scan UNNEST block.
-- THE COST OF THAT CHOICE: these four checks verify the COPY, not the view. A view edited and
-- deployed without re-running SP_SCORE_INTENT_INDEXES would not be checked here at all. R16 is
-- what makes that survivable -- it fails the suite once either table is more than 8 days old --
-- and it is the reason R16 exists rather than being a nicety.
--
-- R12 EVERY REGISTERED INDEX IS SCORED UNDER BOTH TESTS. An index that never appears cannot be
--     judged, and the whole point of the registry is that nothing enters unmeasured. A missing
--     pair is silent otherwise: Task 7 reads verdicts by index_name and simply sees no row.
--     THE EMPTY-REGISTRY TERM IS LOAD-BEARING, AND IT GUARDS R13/R14 TOO. Verified by negative
--     control: with the registry filtered to zero rows the EXCEPT DISTINCT returns nothing and
--     the bare form reports a clean 0 -- an empty left side cannot miss anything. The same
--     control run against the scorecard side shows why this check is the block's emptiness
--     guard: with T_INTENT_INDEX_SCORECARD filtered to zero rows R12 returns 4 (both indexes,
--     both tests, all missing) while R13 and R14 both return 0, because an empty table has no
--     bad verdict and no leaked month. So R13 and R14 are vacuous on their own and R12 is what
--     makes them mean something.
r12 AS (
  SELECT (SELECT COUNT(*) FROM (
            SELECT r.index_name, t.test_kind
            FROM `onyga-482313.OI.DE_INTENT_INDEX_REGISTRY` r
            CROSS JOIN (SELECT 'ADD_ONE_IN' AS test_kind UNION ALL SELECT 'LEAVE_ONE_OUT') t
            EXCEPT DISTINCT
            SELECT index_name, test_kind FROM `onyga-482313.OI.T_INTENT_INDEX_SCORECARD`))
       + CAST((SELECT COUNT(*) FROM `onyga-482313.OI.DE_INTENT_INDEX_REGISTRY`) = 0 AS INT64) AS v
),
-- R13 VERDICTS ARE FROM THE CLOSED SET. Anything else means the CASE fell through and a verdict
--     is being read that the promotion rule in spec section 5 does not define. Task 7 gates on
--     'IMPROVES' and Task 9 promotes on it; an unrecognised string there fails open, silently,
--     as "not IMPROVES" rather than as an error.
--     `verdict IS NULL OR` IS LOAD-BEARING. NOT IN evaluates to NULL against a NULL verdict, and
--     COUNTIF does not count NULL -- so the bare form waves through the one value that would
--     actually appear if the CASE lost its ELSE. Verified by negative control.
r13 AS (
  SELECT COUNTIF(verdict IS NULL
              OR verdict NOT IN ('IMPROVES','NEUTRAL','HURTS','INSUFFICIENT')) AS v
  FROM `onyga-482313.OI.T_INTENT_INDEX_SCORECARD`
),
-- R14 THE SCORECARD NEVER READS THE FUTURE. A target month must be scored on strictly earlier
--     evidence or the verdict is leakage, not prediction -- and a leaking scorecard would say
--     yes to everything, which is the single worst failure this evidence layer can have.
--     `target_month IS NOT NULL` EXCLUDES THE POOLED ROW BY DESIGN, not by accident: the pooled
--     row has no target month to be earlier than, and its fitted_through is the MAX across
--     eighteen of them.
--     `fitted_through IS NULL` IS LOAD-BEARING: a per-month row with no fitting window at all
--     has not been scored on earlier evidence, it has been scored on nothing, and `NULL >=
--     target_month` is NULL, which COUNTIF does not count.
--     WHAT THIS DOES NOT COVER, stated because the check's name overclaims: it proves the BASE
--     RATE is walk-forward. The INDEX values are a separate question: since 2026-09-11 they come
--     from T_INTENT_IDX_HISTORY, scored with the newest snapshot strictly before the target month
--     where one exists, and every row where none exists yet carries leakage_flag = TRUE. R20
--     checks those labels against the history. Until snapshots accumulate (the first is 2026-09)
--     every row is flagged, so an IMPROVES here still means "take it to the money gate", never
--     "proven" -- read leakage_flag before reading the verdict.
r14 AS (
  SELECT COUNTIF(fitted_through IS NULL OR fitted_through >= target_month) AS v
  FROM `onyga-482313.OI.T_INTENT_INDEX_SCORECARD` WHERE target_month IS NOT NULL
),
-- R15 THE CATALOG AND THE ENGINE PRICE AGAINST THE SAME MONEY. V_KEYWORD_RATES exists precisely
--     so there is one definition of margin; a catalog gp_per_order more than 15% away from the
--     house's recency-weighted figure means two definitions are live again.
--     THIS CHECK READS THE VIEW, NOT T_INTENT_BID_BASE, AND THAT IS THE WHOLE POINT OF IT.
--     V_INTENT_BID_BASE reflects a change to the margin source immediately; the T_ copy only
--     moves when SP_REFRESH_SEARCH_TERM_INTENT rebuilds it, so the table LAGS the view by
--     however long it has been since the last refresh. Read a red R15 against a green view as
--     "the T_ table is stale", not as "the view is wrong" -- and note the converse is what this
--     check cannot see: it says nothing about what the T_ copy, which every consumer actually
--     reads, is currently priced at. Measured 2026-09-01, before this task's rebuild:
--     view $13.91 (passes, +3.8% from the house's $13.39) while T_INTENT_BID_BASE still carried
--     $19.96 (+49%, would fail). Both numbers are real; only the view is current.
--     WHY THE TWO SIDES ARE WEIGHTED DIFFERENTLY, ON PURPOSE. The catalog arm is weighted by
--     catalog clicks and the house arm by weighted orders, so even a perfect read leaves a mix
--     difference -- +3.8% today. The 15% band is sized to absorb that and still catch a genuine
--     second definition (the defect this replaced sat at +44% on the view and +49% in the table).
--     Tightening it below about 8% would make it a test of product mix, not of margin source.
--     COALESCE(..., 1) IS LOAD-BEARING and is this check's emptiness guard. Over an empty
--     V_INTENT_BID_BASE the inner SUM is NULL, SAFE_DIVIDE is NULL and CAST(NULL > 0.15 AS INT64)
--     is NULL -- which is not the 0 this file defines as PASS but renders as a blank cell and
--     reads like one. Verified by negative control 2026-09-01: the catalog arm restricted to
--     `WHERE FALSE` returns NULL in the bare form and 1 in the COALESCEd form; and substituting
--     the T_ table's $19.96 for the view's figure returns 1 while the view's own $13.91 returns 0,
--     so the check fires on a wrong number as well as on no number.
--     COST, MEASURED, because this file has now been rejected at the CPU ceiling three times.
--     The catalog arm is one full evaluation of V_INTENT_BID_BASE: 7,221 slot-seconds / 131 MB
--     standalone and 7,540 / 171 MB as statement 1 of the script (2026-09-01), essentially all of
--     which is V_INTENT_CVR_CURVE underneath it -- that view alone measures 7,598 slot-seconds,
--     and there is no cheaper formulation, weighting by base_clicks instead of month_clicks
--     measured the same to four decimals.
--     The suite ran 17,280 slot-seconds before this check, and folding R15 into that single
--     statement blew the ceiling at 76,659 -- which is why this check lives in its own statement
--     at the top of the file (see the header). If even that breaches the ceiling one day, the
--     mitigation is to point the catalog arm at T_INTENT_BID_BASE and accept the lag described
--     above, NOT to drop the check.
--     THE CHECK ITSELF IS THE TEMP TABLE AT THE TOP OF THIS FILE; this CTE only carries it into
--     the result set.
r15 AS (SELECT v FROM r15_result),
-- R16 THE MATERIALISED EVIDENCE IS FRESH. A stale table means promotion decisions are being made
--     against evidence from before the last curve change -- and because R12/R13/R14 read the
--     tables rather than the views, a stale table also means those three checks are green about
--     a version of the scorecard that no longer exists.
--     BOTH TABLES, not just the scorecard. SP_SCORE_INTENT_INDEXES writes them in sequence with
--     separate CURRENT_TIMESTAMP() calls, so a run that creates the scorecard and then fails on
--     the tuning view leaves one fresh table and one old one. Checking only the first would call
--     that a pass.
--     COALESCE(..., 1) ON EACH ARM IS LOAD-BEARING. Over an empty (or never-written) table
--     MAX(scored_at) is NULL, TIMESTAMP_DIFF is NULL, and CAST(NULL > 8 AS INT64) is NULL --
--     which is not the 0 this file defines as PASS but renders as a blank cell and reads like
--     one. Verified by negative control: the bare form over an emptied table returns NULL, the
--     COALESCEd form returns 1.
r16 AS (
  SELECT COALESCE(CAST(TIMESTAMP_DIFF(CURRENT_TIMESTAMP(),
           (SELECT MAX(scored_at) FROM `onyga-482313.OI.T_INTENT_INDEX_SCORECARD`), DAY) > 8
         AS INT64), 1)
       + COALESCE(CAST(TIMESTAMP_DIFF(CURRENT_TIMESTAMP(),
           (SELECT MAX(scored_at) FROM `onyga-482313.OI.T_INTENT_BASE_TUNING`), DAY) > 8
         AS INT64), 1) AS v
),
-- R17-R20 COVER T_INTENT_IDX_HISTORY, the index snapshot table added 2026-09-11, and the
-- scorecard's use of it. They read the TABLE and the materialised scorecard only -- the history
-- is a few hundred rows and the scorecard 76, so these are free, and none of them touches an
-- index view or the curve.
--
-- R17 THE HISTORY HAS THIS MONTH'S SNAPSHOT FOR EVERY REGISTERED INDEX. If it fires, one of two
--     things is true: SP_SCORE_INTENT_INDEXES has not run this UTC month, so the scorecard's
--     picker falls back to an older snapshot for every target month and every leakage label is
--     stale; or the procedure REFUSED a registry row at snapshot time (its guards RAISE on a
--     source_object that is not ^V_INTENT_IDX_[A-Z_]+$, a join_keys CSV outside the four allowed
--     names, a declared key arriving NULL, a non-positive index_value, an empty source) and that
--     index is now scored off last month's values or not at all. Same clock as the procedure:
--     CURRENT_DATE() with no zone, i.e. UTC, on both sides.
--     THE EMPTY-REGISTRY TERM IS LOAD-BEARING, same shape as R12: an empty left side of EXCEPT
--     cannot miss anything. Verified by negative control 2026-09-11: registry filtered to zero
--     rows -> bare form 0, this form 1; history without season_phase -> 1; history emptied -> 2;
--     live -> 0.
r17 AS (
  SELECT (SELECT COUNT(*) FROM (
            SELECT index_name FROM `onyga-482313.OI.DE_INTENT_INDEX_REGISTRY`
            EXCEPT DISTINCT
            SELECT index_name FROM `onyga-482313.OI.T_INTENT_IDX_HISTORY`
            WHERE snapshot_month = DATE_TRUNC(CURRENT_DATE(), MONTH)))
       + CAST((SELECT COUNT(*) FROM `onyga-482313.OI.DE_INTENT_INDEX_REGISTRY`) = 0 AS INT64) AS v
),
-- R18 NO HISTORY ROW IS NULL ON ALL THREE WILDCARD KEYS. The scorecard joins a history row to an
--     observation with (key IS NULL OR key = obs.key) on product_short_name / intent_key /
--     intent_type, so a row NULL on all three matches EVERY observation for its index in that
--     calendar month -- a global multiplier nobody registered. The procedure refuses to write
--     one (join_keys must name at least one non-month key); this checks the TABLE, because the
--     table accumulates and a hand INSERT or an earlier procedure version could have written one
--     that no rerun will clean up.
--     COUNT(*) = 0 IS LOAD-BEARING: COUNTIF over an empty table is 0. Verified by negative
--     control 2026-09-11: one all-NULL row appended -> 1; history emptied -> bare 0, this form 1;
--     live -> 0.
r18 AS (
  SELECT COUNTIF(product_short_name IS NULL AND intent_key IS NULL AND intent_type IS NULL)
       + CAST(COUNT(*) = 0 AS INT64) AS v
  FROM `onyga-482313.OI.T_INTENT_IDX_HISTORY`
),
-- R19 THE HISTORY IS UNIQUE ON ITS GRAIN: snapshot_month x index_name x the three wildcard keys
--     x month_of_year, NULLs grouping together as GROUP BY does. A duplicate fans the scorecard's
--     cell x index join out and counts that cell's clicks twice in the error, silently. The
--     procedure's DELETE-then-INSERT is idempotent per run, but two runs overlapping in time can
--     both pass the DELETE before either INSERTs -- the orchestrator runs three times a day and a
--     hand run during one of them is the realistic path. Verified by negative control
--     2026-09-11: one row duplicated -> 1; history emptied -> bare 0, this form 1; live -> 0.
r19 AS (
  SELECT COUNTIF(n > 1) + CAST(COUNT(*) = 0 AS INT64) AS v
  FROM (SELECT snapshot_month, index_name, product_short_name, intent_key, intent_type,
               month_of_year, COUNT(*) AS n
        FROM `onyga-482313.OI.T_INTENT_IDX_HISTORY` GROUP BY 1, 2, 3, 4, 5, 6)
),
-- R20 THE SCORECARD'S LEAKAGE LABELS MATCH THE HISTORY. For every per-month row,
--     snapshot_month_used must be the newest snapshot STRICTLY before the target month (else the
--     latest one), and leakage_flag must be TRUE exactly when no strictly-earlier snapshot
--     exists; every pooled row's flag must be the OR of its months. If it fires, the materialised
--     scorecard was built against a different history than the one on disk -- the history grew,
--     was replaced, or the view's picker was edited, and SP_SCORE_INTENT_INDEXES was not re-run
--     -- and an IMPROVES is being read under the wrong leakage label: an in-sample verdict
--     passing as out-of-sample, which is the one thing the history table exists to prevent.
--     TODAY EVERY ROW IS FLAGGED (one snapshot, 2026-09, and no target month is later than it),
--     so a check that merely counted TRUEs would be vacuous; this one RECOMPUTES the expected
--     label from the history and compares. Verified by negative control 2026-09-11, each on a
--     doctored temp copy: one leakage_flag flipped -> 1; snapshot_month_used shifted on one
--     target month -> 4; one pooled row's flag wrong -> 2; a 2026-03 snapshot added to the
--     history -> 24 (the six later target months x 2 indexes x 2 tests now expect 2026-03 and
--     FALSE while the scorecard still says 2026-09 and TRUE); history emptied -> 72; scorecard
--     emptied -> bare 0, this form 1; live -> 0.
r20 AS (
  SELECT (SELECT COUNTIF(s.snapshot_month_used IS DISTINCT FROM e.exp_snap
                      OR s.leakage_flag        IS DISTINCT FROM e.exp_leak)
          FROM `onyga-482313.OI.T_INTENT_INDEX_SCORECARD` s
          LEFT JOIN (
            SELECT s2.index_name, s2.target_month,
                   COALESCE(MAX(IF(h.snapshot_month < s2.target_month, h.snapshot_month, NULL)),
                            MAX(h.snapshot_month))                                  AS exp_snap,
                   MAX(IF(h.snapshot_month < s2.target_month, h.snapshot_month, NULL)) IS NULL AS exp_leak
            FROM (SELECT DISTINCT index_name, target_month
                  FROM `onyga-482313.OI.T_INTENT_INDEX_SCORECARD` WHERE target_month IS NOT NULL) s2
            LEFT JOIN (SELECT DISTINCT index_name, snapshot_month
                       FROM `onyga-482313.OI.T_INTENT_IDX_HISTORY`) h USING (index_name)
            GROUP BY 1, 2) e
            ON e.index_name = s.index_name AND e.target_month = s.target_month
          WHERE s.target_month IS NOT NULL)
       + (SELECT COUNTIF(p.leakage_flag IS DISTINCT FROM m.any_leak)
          FROM `onyga-482313.OI.T_INTENT_INDEX_SCORECARD` p
          JOIN (SELECT index_name, test_kind, LOGICAL_OR(leakage_flag) AS any_leak
                FROM `onyga-482313.OI.T_INTENT_INDEX_SCORECARD`
                WHERE target_month IS NOT NULL GROUP BY 1, 2) m USING (index_name, test_kind)
          WHERE p.target_month IS NULL)
       + (SELECT CAST(COUNT(*) = 0 AS INT64) FROM `onyga-482313.OI.T_INTENT_INDEX_SCORECARD`) AS v
)
SELECT 'R01 registry key unique' AS check_name, v FROM r01
UNION ALL SELECT 'R02 thresholds present', v FROM r02
UNION ALL SELECT 'R02b threshold values correct', v FROM r02b
UNION ALL SELECT 'R03 season_month index normalised to mean 1.000', v FROM r03
UNION ALL SELECT 'R03b season_month grid complete and non-empty', v FROM r03b
UNION ALL SELECT 'R04 season_month index never null or non-positive', v FROM r04
UNION ALL SELECT 'R05 season_month index is not flat', v FROM r05
UNION ALL SELECT 'R06 season_phase index normalised per intent_key', v FROM r06
UNION ALL SELECT 'R07 season_phase easter peak-to-trough ratio >= 2.0', v FROM r07
UNION ALL SELECT 'R08 season_phase one row per intent_key x month', v FROM r08
-- R09 SHADOW GRAIN IS ONE ROW PER product_short_name x intent_key x month_of_year, AND THE VIEW
--     IS NOT EMPTY. T_INTENT_BID_BASE, the intent-grid popup and tools/intent_grid/*.py all
--     assume that uniqueness; a duplicate lets one keyword be priced twice off contradictory
--     rows.
--     WHAT THIS CHECK PROVES TODAY, stated precisely because the obvious reading is wrong. The
--     mechanism worth guarding is the shadow's two new LEFT JOINs, idx_month and idx_phase: a
--     duplicate (intent_type, month) or (intent_key, month) in an index view would fan p_lvl out.
--     BUT BOTH REGISTRY ROWS ARE is_active = FALSE, so both CTEs are gated to zero rows by their
--     `IN (SELECT index_name FROM active_idx)` filter and contribute nothing to join cardinality.
--     A green R09 today therefore proves only that `p_lvl CROSS JOIN months` is unique -- which it
--     is by construction, p_lvl being a GROUP BY and months a 12-element literal. This check does
--     not begin testing the thing it is named for until Task 8 flips an index active, and it MUST
--     be re-read then. Same class as R01's empty-registry note.
--     THE rows_shadow = 0 TERM IS LOAD-BEARING. Negative control, run against the deployed view:
--     with the shadow replaced by `SELECT ... WHERE FALSE` the bare COUNTIF(n_shadow > 1) form
--     returns 0 -- an empty set has no duplicate to find -- so total failure reports a clean
--     pass. Reachable: obs is emptied by any break in V_INTENT_RESOLVED or DIM_PRODUCT.
-- R10 NO NULL / NEGATIVE / >1 cvr_hat AND NO NULL OR NON-POSITIVE season_index. A NULL cvr_hat
--     blanks value_per_click across the whole catalog; a CVR above 1 means more orders than
--     clicks and prices a bid off nonsense.
--     WHICH ARMS ACTUALLY HAVE TEETH, stated rather than implied. The POST-cap `> 1.0` and `< 0`
--     arms CANNOT fire against today's view: it wraps the product in LEAST(..., 1.0) and every
--     factor is positive. They guard a future edit that removes the cap; they are not testing
--     today. That is exactly why a PRE-cap arm was added below -- without it, a cap that starts
--     binding is invisible to this check by construction. The arms that
--     CAN fire are the NULLs and the emptiness term, and that is not hypothetical -- cvr_hat
--     multiplies INTENT_CVR_CALIBRATION, so deleting that threshold row, or moving it to another
--     coach_mode (which is why the curve's params CTE filters coach_mode), NULLs cvr_hat on all
--     125k rows while every other check in this file stays green. season_index is included
--     because it multiplies in BEFORE the cap: a zero or negative index_value republished by an
--     index view would zero every bid, and the curve COALESCEs a NULL one away, so this is the
--     only place it would surface. Negative control: over an empty shadow the bare COUNTIF form
--     returns 0, hence the shared emptiness term.
-- R11 THE SHADOW STILL COVERS EVERY KEY THE SERVED CATALOG COVERS. Losing keys silently drops
--     intents from the catalog rather than repricing them. Comparand and its limits are argued
--     at shadow_vs_served above. Measured 2026-08-31: T_INTENT_CVR_CURVE holds 10,177 cells,
--     every one of them present in the shadow, which carries 263 more from five weeks of newer
--     ads history.
--     TWO WAYS THIS CAN FIRE WITHOUT A REGRESSION, so read the failure before reverting: a human
--     REJECTing a term in DE_SEARCH_TERM_INTENT nulls its intent_key and legitimately retires a
--     cell, and the upstream product_type tie-break above can flip one. Both are single cells;
--     a real drop is structural.
--     THE rows_served = 0 TERM IS LOAD-BEARING and is the direction that goes vacuous here.
--     Negative control: with T_INTENT_CVR_CURVE filtered to WHERE FALSE the bare
--     COUNTIF(n_served > 0 AND n_shadow = 0) form returns 0 while the shadow holds 125k rows --
--     an empty comparand certifies anything. R09/R10's emptiness term covers the other side.
UNION ALL
SELECT x.check_name, x.v
FROM verdicts CROSS JOIN UNNEST([
  STRUCT('R09 shadow curve grain unique and non-empty' AS check_name,
         dup_shadow_keys     + CAST(rows_shadow = 0 AS INT64) AS v),
  STRUCT('R10 shadow cvr_hat and season_index sane',
         bad_shadow_rows     + CAST(rows_shadow = 0 AS INT64)),
  STRUCT('R11 shadow covers every served catalog key',
         served_keys_missing + CAST(rows_served = 0 AS INT64))
]) AS x
UNION ALL SELECT 'R12 every registered index scored under both tests', v FROM r12
UNION ALL SELECT 'R13 scorecard verdicts from the closed set', v FROM r13
UNION ALL SELECT 'R14 scorecard base fitted strictly before target month', v FROM r14
UNION ALL SELECT 'R15 catalog gp_per_order within 15% of the house definition (VIEW)', v FROM r15
UNION ALL SELECT 'R16 materialised scorecard and tuning fresh within 8 days', v FROM r16
UNION ALL SELECT 'R17 history has this month\'s snapshot for every registered index', v FROM r17
UNION ALL SELECT 'R18 no history row null on all three wildcard keys', v FROM r18
UNION ALL SELECT 'R19 history unique on its grain', v FROM r19
UNION ALL SELECT 'R20 scorecard leakage labels match the history', v FROM r20
ORDER BY check_name;
