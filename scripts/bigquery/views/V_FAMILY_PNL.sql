-- =============================================
-- V_FAMILY_PNL — family economics INCLUDING THE ORGANIC HALO (2026-08-19).
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md. SOP: architecture/TWO_BOOK_PNL.md.
--
-- WHY THIS EXISTS: every bid decision was judged on ads-ATTRIBUTED profit, which excludes a large
-- share of units. A family can therefore read as a disaster on ads net ROAS and be fine on TOTAL net
-- ROAS, and the gap between the two IS its halo. Cutting such a family's keywords on the ads number
-- destroys the organic demand carrying it. NO FAMILY, ROAS OR HALO VALUE IS NAMED IN THIS HEADER
-- (Standing Rule 0 — describe the mechanism, publish the query, never pin a measurement). See it:
--   SELECT family, ads_net_roas, total_net_roas, halo_factor, net_profit
--   FROM `onyga-482313.OI.V_FAMILY_PNL` WHERE period_label = 'M3' ORDER BY halo_factor DESC;
--
-- NET PROFIT IS A TRUE NET, NOT A GROSS MARGIN. V_UNIFIED_DAILY.cogs is all-in — landed product
-- cost, inbound shipping, FBA pick/pack AND the Amazon referral fee — so sales - cogs - ad_cost is
-- after Amazon's fees, not a gross margin dressed up as one. Check the composition against
-- V_UNIFIED_DAILY rather than against a figure written here.
--
-- HALO FACTOR IS MEASURED, NEVER ASSUMED: total_net_roas / ads_net_roas, read straight from dollars.
-- An earlier draft inferred it from unit ratios plus an equal-margin assumption. That is the defect
-- the measured form exists to avoid: the halo differs materially BETWEEN families, and an
-- equal-margin assumption flattens exactly that spread — which is the only thing the bar reads.
--
-- ---------------------------------------------------------------------------------------------
-- RULING (2026-08-19) — WHICH WATERMARK YOU ARE ENDING ON DECIDES WHETHER YOU DROP ITS LAST DAY.
-- The house rule "every multi-day window ends at wm - 1" (feedback_window_convention_complete_days)
-- is TRUE OF THE ADS WATERMARK AND ONLY OF IT. The two watermarks differ in kind:
--
--   * ADS watermark — its newest day is PARTIAL. FACT_AMAZON_ADS is materially under-loaded at age
--     1 and keeps restating for the first few days (fact_oi_ads_restatement_settle,
--     fact_oi_fresh_ads_data_reading_rules — read the loaded share off V_ADS_SETTLE_CURVE rather
--     than from a percentage typed here). Nothing in the ads pipeline removes that half-loaded day,
--     so an ads window MUST end at wm - 1 or it reads a fake dip.
--
--   * ORDERS watermark (the one this view uses) — its newest day is COMPLETE BY CONSTRUCTION. The wm
--     CTE below does not take MAX(date); it takes the newest day that CLEARED THE SESSIONS GATE
--     (HAVING SUM(ASIN_SESSIONS) > 0). Mid-sync days land orders before sessions, so they score 0
--     sessions and are excluded by that HAVING — the gate is exactly the partial-day filter that the
--     ads side lacks. A day that survives it is whole. Ending at wm - 1 here would silently DISCARD
--     one good, fully-loaded day from every window, which is a real loss, not a safety margin.
--
-- So: M3 / M1 / W2 below end AT the orders watermark, on purpose. Do not "fix" this back to wm - 1.
-- If you ever repoint this view at an ads-watermark source, the wm - 1 rule applies again.
-- ---------------------------------------------------------------------------------------------
--
-- CALENDAR MONTHS ARE COMPLETE MONTHS ONLY (defect fix 2026-08-19). The previous cut emitted the
-- CURRENT month with period_end = LAST_DAY(month), so a month that had only run part-way claimed a
-- full month's end date. Month-over-month consumers (the Invest ramp test, which asks the one
-- question that matters for a young product: is this launch IMPROVING?) would have compared a part
-- month against a whole one and declared a working launch dead — a pure artefact of day count, and
-- it showed up as a units column falling on exactly the launches the test was built to protect.
-- Now: a '%Y-%m' row exists only when its LAST_DAY falls STRICTLY BEFORE the start of the
-- watermark's month, and the running month is published as a single row labelled 'MTD' whose
-- period_end IS THE WATERMARK, so it can never be mistaken for a full month from its dates alone.
-- Belt and braces, every row carries is_complete_period (BOOL) so a consumer cannot get this wrong
-- by accident: filter is_complete_period for trajectory, read 'MTD' for "so far this month".
-- BASELINE_MAY_JUL and the M3/M1/W2 rolling windows are complete by construction.
--
-- GRAIN: one row per (family, period). Organic sales are measurable at family grain and NOT
-- attributable to a keyword — that limit is the whole reason the engine bridge (V_FAMILY_BAR) exists
-- instead of a per-keyword organic number.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_FAMILY_PNL` AS
WITH wm AS (
  -- Sessions gate skips mid-sync partial days (orders land before sessions).
  -- Same rule as V_SUMMARY_7D / V_DATA_FRESHNESS / V_PLAN_FORECAST — architecture/ORDERS_WATERMARK.md.
  -- This gate is ALSO the reason windows below may end AT wm rather than wm-1: see the RULING in the
  -- file header. A day that clears HAVING SUM(ASIN_SESSIONS) > 0 is a complete day, not a partial one.
  SELECT MAX(date) AS d
  FROM (
    SELECT date
    FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
    WHERE Performance_TYPE = 'Organic'
    GROUP BY date
    HAVING SUM(ASIN_SESSIONS) > 0
  )
),
periods AS (
  -- Rolling windows. Every one ENDS AT THE ORDERS WATERMARK — complete by construction of wm (the
  -- sessions gate above), so no partial day enters a blended number. RULING: "windows end at wm-1"
  -- is the ADS-watermark rule (day-1 ads are only partly loaded); it does NOT apply to the orders
  -- watermark, where ending at wm-1 would silently discard one good, fully-loaded day.
  SELECT 'M3' AS period_label, DATE_SUB((SELECT d FROM wm), INTERVAL 89 DAY) AS period_start, (SELECT d FROM wm) AS period_end, TRUE AS is_complete_period UNION ALL
  SELECT 'M1',                  DATE_SUB((SELECT d FROM wm), INTERVAL 29 DAY),                 (SELECT d FROM wm),              TRUE                        UNION ALL
  SELECT 'W2',                  DATE_SUB((SELECT d FROM wm), INTERVAL 13 DAY),                 (SELECT d FROM wm),              TRUE
),
-- Fixed calendar periods for month-over-month trajectory (the Invest ramp test) and for the
-- reproducible baseline the acceptance assertion checks.
cal AS (
  -- COMPLETE months only: LAST_DAY(m) must fall strictly before the start of the watermark's month.
  -- The running month is deliberately absent here — it is published as 'MTD' below.
  SELECT FORMAT_DATE('%Y-%m', m) AS period_label, m AS period_start, LAST_DAY(m) AS period_end, TRUE AS is_complete_period
  FROM UNNEST(GENERATE_DATE_ARRAY(
         DATE_TRUNC(DATE_SUB((SELECT d FROM wm), INTERVAL 365 DAY), MONTH),
         DATE_TRUNC((SELECT d FROM wm), MONTH), INTERVAL 1 MONTH)) m
  WHERE LAST_DAY(m) < DATE_TRUNC((SELECT d FROM wm), MONTH)
  UNION ALL
  -- The running month, HONESTLY LABELLED. period_end is the watermark, NOT the month end, so a
  -- consumer that compares it to a full month can see the shortfall from the dates alone.
  SELECT 'MTD', DATE_TRUNC((SELECT d FROM wm), MONTH), (SELECT d FROM wm), FALSE
  UNION ALL
  SELECT 'BASELINE_MAY_JUL', DATE '2026-05-01', DATE '2026-07-31', TRUE
),
all_periods AS (SELECT * FROM periods UNION ALL SELECT * FROM cal),
u AS (
  SELECT family, date, sales, cogs, ad_cost, ads_gross_profit, units, organic_units, ads_units
  FROM `onyga-482313.OI.V_UNIFIED_DAILY`
  WHERE family IS NOT NULL
)
SELECT
  p.period_label, p.period_start, p.period_end,
  -- FALSE on exactly one row per family ('MTD'). Filter on this for any month-over-month read.
  p.is_complete_period,
  u.family,
  -- THE GOAL: dollars. Net of COGS (all-in, incl. Amazon fees) and of ad spend.
  ROUND(SUM(u.sales - u.cogs) - SUM(u.ad_cost), 2)                                        AS net_profit,
  -- THE EFFICIENCY READ: breakeven is exactly 1.0, no parameters.
  ROUND(SAFE_DIVIDE(SUM(u.sales - u.cogs), NULLIF(SUM(u.ad_cost), 0)), 4)                 AS total_net_roas,
  -- WHAT THE ENGINE CURRENTLY SEES — published so the GAP is visible, not as a verdict.
  ROUND(SAFE_DIVIDE(SUM(u.ads_gross_profit), NULLIF(SUM(u.ad_cost), 0)), 4)               AS ads_net_roas,
  -- THE BRIDGE INPUT: measured, not assumed. NULL when there is no ads profit to divide by.
  ROUND(SAFE_DIVIDE(SUM(u.sales - u.cogs), NULLIF(SUM(u.ads_gross_profit), 0)), 4)        AS halo_factor,
  CAST(SUM(u.units) AS INT64)                                                             AS units,
  CAST(SUM(u.organic_units) AS INT64)                                                     AS organic_units,
  ROUND(100 * SAFE_DIVIDE(SUM(u.organic_units), NULLIF(SUM(u.units), 0)), 2)              AS organic_pct,
  ROUND(SUM(u.sales), 2)                                                                  AS total_sales,
  ROUND(SUM(u.ad_cost), 2)                                                                AS ad_spend,
  (SELECT d FROM wm)                                                                      AS orders_watermark
FROM all_periods p
JOIN u ON u.date BETWEEN p.period_start AND p.period_end
GROUP BY p.period_label, p.period_start, p.period_end, p.is_complete_period, u.family;
