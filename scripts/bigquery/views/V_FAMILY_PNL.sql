-- =============================================
-- V_FAMILY_PNL — family economics INCLUDING THE ORGANIC HALO (2026-08-19).
-- Spec: docs/superpowers/specs/2026-08-19-two-book-pnl-design.md. SOP: architecture/TWO_BOOK_PNL.md.
--
-- WHY THIS EXISTS: every bid decision was judged on ads-ATTRIBUTED profit, which excludes 30-40% of
-- units. Measured 2026-08-19: Bottle reads 0.60 on ads net ROAS (a disaster the engine would cut)
-- but 0.95 on TOTAL net ROAS, because its halo factor is 1.59 — the strongest in the account.
-- Cutting Bottle's keywords on the ads number destroys the organic demand carrying it.
--
-- NET PROFIT IS A TRUE NET, NOT A GROSS MARGIN. Verified 2026-08-19: V_UNIFIED_DAILY.cogs is all-in
-- (product $54,155 + inbound shipping $14,337 + FBA pick/pack $45,044 + Amazon referral $38,498
-- over May-Jul), so sales - cogs - ad_cost is after Amazon's fees.
--
-- HALO FACTOR IS MEASURED, NEVER ASSUMED: total_net_roas / ads_net_roas, read straight from dollars.
-- An earlier draft inferred it from unit ratios plus an equal-margin assumption; the measured values
-- range 1.07 (Fresh) to 1.59 (Bottle), which that assumption would have flattened.
--
-- WATERMARK: blended sales+ads measures cut at the ORDERS watermark, never the ads watermark (ads
-- rows run ~1 day ahead of the business report). The wm CTE is copied verbatim from
-- V_FAMILY_NET_PROFIT_7D / V_SUMMARY_7D — see architecture/ORDERS_WATERMARK.md. Do not "simplify" it:
-- the sessions gate is what skips mid-sync partial days, where orders land before sessions.
--
-- GRAIN: one row per (family, period). Organic sales are measurable at family grain and NOT
-- attributable to a keyword — that limit is the whole reason the engine bridge (V_FAMILY_BAR) exists
-- instead of a per-keyword organic number.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_FAMILY_PNL` AS
WITH wm AS (
  -- Sessions gate skips mid-sync partial days (orders land before sessions).
  -- Same rule as V_SUMMARY_7D / V_DATA_FRESHNESS / V_PLAN_FORECAST — architecture/ORDERS_WATERMARK.md.
  SELECT MAX(date) AS d
  FROM (
    SELECT date
    FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
    WHERE Performance_TYPE = 'Organic'
    GROUP BY date
    HAVING SUM(ASIN_SESSIONS) > 0
  )
),
-- The reporting periods this view publishes. Every window ENDS AT THE WATERMARK (a complete day by
-- construction of wm), so no partial day enters a blended number.
periods AS (
  SELECT 'M3'  AS period_label, DATE_SUB((SELECT d FROM wm), INTERVAL 89 DAY) AS period_start, (SELECT d FROM wm) AS period_end UNION ALL
  SELECT 'M1',                  DATE_SUB((SELECT d FROM wm), INTERVAL 29 DAY),                 (SELECT d FROM wm)              UNION ALL
  SELECT 'W2',                  DATE_SUB((SELECT d FROM wm), INTERVAL 13 DAY),                 (SELECT d FROM wm)
),
-- Fixed calendar periods for month-over-month trajectory (the Invest ramp test) and for the
-- reproducible baseline the acceptance assertion checks.
cal AS (
  SELECT FORMAT_DATE('%Y-%m', m) AS period_label, m AS period_start, LAST_DAY(m) AS period_end
  FROM UNNEST(GENERATE_DATE_ARRAY(
         DATE_TRUNC(DATE_SUB((SELECT d FROM wm), INTERVAL 365 DAY), MONTH),
         DATE_TRUNC((SELECT d FROM wm), MONTH), INTERVAL 1 MONTH)) m
  UNION ALL
  SELECT 'BASELINE_MAY_JUL', DATE '2026-05-01', DATE '2026-07-31'
),
all_periods AS (SELECT * FROM periods UNION ALL SELECT * FROM cal),
u AS (
  SELECT family, date, sales, cogs, ad_cost, ads_gross_profit, units, organic_units, ads_units
  FROM `onyga-482313.OI.V_UNIFIED_DAILY`
  WHERE family IS NOT NULL
)
SELECT
  p.period_label, p.period_start, p.period_end,
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
GROUP BY p.period_label, p.period_start, p.period_end, u.family;
