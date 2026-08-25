CREATE OR REPLACE VIEW `onyga-482313.OI.V_CATALOG_SCORECARD`
OPTIONS (description = "THE CATALOG'S OWN REPORT CARD, at family grain -- where the pass mark lives. Forecast chain step 3 (THREE_LAYERS.md 2.0, 2.0.1, 6). Ori 2026-08-25: 'the catalog needs to measure itself how much he is correct and strive to at least 85%.' WHY FAMILY AND NOT KEYWORD: measured, only 13.8% of keywords take 7 or more orders in a week, so a single sale moves a keyword's percentage by more than the whole tolerance and a per-keyword 85% would be scoring dice. 100% of families clear that bar. So the Catalog PREDICTS PER SUBJECT and is SCORED ON THE SUM -- per-subject error still says which link to fix, it is simply not the pass mark. WHAT THE PASS MARK IS MEASURED ON, and this is a correction the spec earned by measurement (3.3): NOT net profit. Net profit is a small difference between two large numbers, so 15% on it demands gross profit to 1.3-2.8% -- unmeetable, and hardest exactly where a family sits near break-even, which is where this account lives. The headline percentage is GROSS PROFIT, which does not cancel; net profit contribution is reported in DOLLARS beside it. CLAIM COVERAGE IS PUBLISHED AND MATTERS AS MUCH AS THE SCORE: a family whose claims cover a fifth of its ad spend has not been forecast, it has been sampled, and a green score over that fifth is not a green family. Read coverage first. Nothing is scored before it settles -- a family is graded only when every claim inside it has, so one slow SB claim holds the whole family rather than letting a partial window pass as a full one. Decides nothing and can move no bid.")
AS
WITH k AS (SELECT 0.15 AS headline_tolerance, 0.60 AS min_claim_coverage),
o AS (SELECT * FROM `onyga-482313.OI.V_CATALOG_FORECAST_OUTCOME`),
-- What the family ACTUALLY spent over the window, claimed or not. The denominator for coverage:
-- without it a scorecard cannot tell "the Catalog was right" from "the Catalog barely spoke".
family_actual AS (
  SELECT c.family, c.window_start, c.window_end,
         SUM(a.Ads_cost) AS family_actual_cost,
         SUM(a.GROSS_PROFIT) AS family_actual_gross_profit,
         SUM(a.Ads_clicks) AS family_actual_clicks
  FROM (SELECT DISTINCT family, campaign_id, window_start, window_end FROM o) c
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` a
    ON CAST(a.campaign_id AS STRING) = c.campaign_id
   AND a.date BETWEEN c.window_start AND c.window_end
  GROUP BY 1, 2, 3
),
agg AS (
  SELECT family, forecast_on, window_start, window_end, season,
         COUNT(*) AS subjects,
         COUNTIF(status = 'SCORED')         AS subjects_scored,
         COUNTIF(status = 'PENDING')        AS subjects_pending,
         COUNTIF(status = 'PENDING_SETTLE') AS subjects_pending_settle,
         COUNTIF(status = 'NO_TRAFFIC')     AS subjects_no_traffic,
         MAX(settles_on) AS family_settles_on,
         SUM(predicted_clicks) AS predicted_clicks, SUM(actual_clicks) AS actual_clicks,
         SUM(predicted_orders) AS predicted_orders, SUM(actual_orders) AS actual_orders,
         SUM(predicted_cost) AS predicted_cost, SUM(actual_cost) AS actual_cost,
         SUM(predicted_gross_profit) AS predicted_gross_profit,
         SUM(actual_gross_profit) AS actual_gross_profit,
         SUM(predicted_contribution) AS predicted_contribution,
         SUM(actual_contribution) AS actual_contribution,
         COUNTIF(worst_link = 'CLICKS')       AS broke_on_clicks,
         COUNTIF(worst_link = 'CONVERSION')   AS broke_on_conversion,
         COUNTIF(worst_link = 'GROSS_PROFIT') AS broke_on_gross_profit,
         COUNTIF(worst_link = 'NONE')         AS all_links_held
  FROM o GROUP BY 1, 2, 3, 4, 5
),
j AS (
  SELECT a.*, f.family_actual_cost, f.family_actual_gross_profit, f.family_actual_clicks,
         SAFE_DIVIDE(a.actual_cost, NULLIF(f.family_actual_cost, 0)) AS claim_coverage,
         -- A family is graded only when EVERY claim in it has settled. Grading a family whose SB
         -- claims are still accruing scores it on a window that is only partly in.
         a.subjects_pending = 0 AND a.subjects_pending_settle = 0 AS family_ready
  FROM agg a LEFT JOIN family_actual f USING (family, window_start, window_end)
)
SELECT
  family, forecast_on, window_start, window_end, season, family_settles_on,
  subjects, subjects_scored, subjects_pending, subjects_pending_settle, subjects_no_traffic,

  -- READ THIS BEFORE THE SCORE. A green grade over a fifth of the spend is not a green family.
  ROUND(claim_coverage, 4) AS claim_coverage,
  ROUND(family_actual_cost, 2) AS family_actual_cost,

  ROUND(predicted_clicks, 1) AS predicted_clicks, actual_clicks,
  ROUND(predicted_orders, 1) AS predicted_orders, actual_orders,
  ROUND(predicted_cost, 2) AS predicted_cost, ROUND(actual_cost, 2) AS actual_cost,
  ROUND(predicted_gross_profit, 2) AS predicted_gross_profit,
  ROUND(actual_gross_profit, 2) AS actual_gross_profit,

  -- THE HEADLINE. Gross profit, because it does not cancel the way net profit does.
  IF(family_ready AND actual_gross_profit > 0,
     ROUND(ABS(predicted_gross_profit - actual_gross_profit) / actual_gross_profit, 4), NULL)
    AS gross_profit_error,

  -- NET PROFIT IN DOLLARS, never as a ratio of a near-zero number.
  ROUND(predicted_contribution, 2) AS predicted_contribution,
  ROUND(actual_contribution, 2) AS actual_contribution,
  IF(family_ready, ROUND(predicted_contribution - actual_contribution, 2), NULL)
    AS contribution_error_dollars,

  CASE WHEN NOT family_ready THEN 'PENDING'
       WHEN actual_gross_profit <= 0 THEN 'NO_BASIS'
       WHEN claim_coverage < (SELECT min_claim_coverage FROM k) THEN 'UNDER_COVERED'
       WHEN ABS(predicted_gross_profit - actual_gross_profit) / actual_gross_profit
            <= (SELECT headline_tolerance FROM k) THEN 'PASS'
       ELSE 'MISS' END AS grade,

  -- WHICH LINK IS COSTING THE FAMILY ITS SCORE. The diagnosis, not just the verdict.
  broke_on_clicks, broke_on_conversion, broke_on_gross_profit, all_links_held,
  CASE WHEN NOT family_ready THEN NULL
       WHEN broke_on_clicks >= GREATEST(broke_on_conversion, broke_on_gross_profit)
            AND broke_on_clicks > 0 THEN 'CLICKS'
       WHEN broke_on_conversion >= broke_on_gross_profit AND broke_on_conversion > 0
         THEN 'CONVERSION'
       WHEN broke_on_gross_profit > 0 THEN 'GROSS_PROFIT'
       ELSE 'NONE' END AS dominant_broken_link
FROM j;
