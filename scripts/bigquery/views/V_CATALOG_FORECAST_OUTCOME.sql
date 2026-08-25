CREATE OR REPLACE VIEW `onyga-482313.OI.V_CATALOG_FORECAST_OUTCOME`
OPTIONS (description = "DID THE CATALOG'S CLAIM HOLD? One row per claim in FACT_CATALOG_FORECAST, with every LINK of the chain scored separately against what actually happened. Forecast chain step 3 (THREE_LAYERS.md 2.0.1, 6). SCORING THE LINKS IS THE POINT, not scoring the money alone: 2.0.1 made the answer a chain precisely so a wrong contribution names its own fault -- 'maybe more clicks, maybe less cpc, maybe something else' -- and a single total error cannot say which. WHY NET PROFIT IS SCORED IN DOLLARS AND NOT PER CENT. Measured (spec 3.3): net profit is a small difference between two large numbers, so hitting 15% on it requires predicting gross profit to 1.3-2.8% -- a bar no forecast meets, and one that gets HARDER the closer a family sits to break-even, which is exactly where this account lives. Percentage error is therefore published on the links and on GROSS profit, where it is meaningful, and net profit contribution is scored in DOLLARS. A percentage on a rounding error is not a measurement. IT REFUSES TO ANSWER EARLY, TWICE OVER: PENDING until the window has closed, then PENDING_SETTLE until settles_on -- SP accrues 7 days and SB 14, and grading before then marks the Catalog down for sales that have not landed. Abstention is not accuracy: a green run made only of PENDING rows means nothing has been tested yet. ZERO ACTUALS ARE NOT ZERO ERROR: a keyword that took no clicks has no percentage error, only a dollar one, and reads NO_TRAFFIC rather than being scored as a miss or silently dropped -- both of which would flatter the Catalog. Actuals join on campaign_id AND lowercased targeting, never on campaign_name, because ids in this account carry more than one name. The 85% is NOT measured here: per-subject error says which link to fix, but only 13.8% of keywords take enough orders in a week for a percentage to mean anything, so the pass mark is measured on the SUM at family grain in V_CATALOG_SCORECARD. Read by V_CATALOG_SCORECARD. Decides nothing and can move no bid.")
AS
WITH k AS (SELECT 0.15 AS link_tolerance),
wm AS (SELECT MAX(date) AS watermark FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
claims AS (SELECT * FROM `onyga-482313.OI.FACT_CATALOG_FORECAST`),
-- Actuals over exactly the claimed window. Summed to the keyword because FACT_AMAZON_ADS is at
-- search-term grain and a keyword's week is the sum of the terms that served under it.
actuals AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id,
         LOWER(TRIM(a.targeting)) AS targeting,
         c.window_start, c.window_end,
         SUM(a.Ads_clicks) AS actual_clicks,
         SUM(a.Ads_orders) AS actual_orders,
         SUM(a.Ads_cost)   AS actual_cost,
         SUM(a.GROSS_PROFIT) AS actual_gross_profit
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN (SELECT DISTINCT window_start, window_end FROM claims) c
    ON a.date BETWEEN c.window_start AND c.window_end
  WHERE a.targeting IS NOT NULL
  GROUP BY 1, 2, 3, 4
),
j AS (
  SELECT c.*,
         IFNULL(a.actual_clicks, 0)       AS actual_clicks,
         IFNULL(a.actual_orders, 0)       AS actual_orders,
         IFNULL(a.actual_cost, 0)         AS actual_cost,
         IFNULL(a.actual_gross_profit, 0) AS actual_gross_profit,
         a.actual_clicks IS NULL          AS no_traffic
  FROM claims c
  LEFT JOIN actuals a
    ON a.campaign_id = c.campaign_id
   AND a.targeting = LOWER(TRIM(c.target_text))
   AND a.window_start = c.window_start AND a.window_end = c.window_end
),
scored AS (
  SELECT j.*,
         (SELECT watermark FROM wm) AS watermark,
         -- The actual contribution, computed with the SAME crediting rule the claim used, so the
         -- comparison measures the forecast and not a change of accounting.
         j.actual_gross_profit / NULLIF(j.keyword_bar, 0) - j.actual_cost AS actual_contribution,
         CASE WHEN j.window_end > (SELECT watermark FROM wm) THEN 'PENDING'
              WHEN j.settles_on > (SELECT watermark FROM wm) THEN 'PENDING_SETTLE'
              WHEN j.actual_clicks = 0 THEN 'NO_TRAFFIC'
              ELSE 'SCORED' END AS status
  FROM j
)
SELECT
  forecast_on, window_start, window_end, window_days, season, settles_on, watermark, status,
  family, campaign_id, campaign_name, keyword_id, target_text, match_type, channel,
  best_cpc, best_cpc_at_grid_edge, optimum_below_floor,

  -- LINK BY LINK: predicted, actual, and the error as a percentage where a percentage means anything
  ROUND(predicted_clicks, 2) AS predicted_clicks, actual_clicks,
  IF(status = 'SCORED' AND actual_clicks > 0,
     ROUND(ABS(predicted_clicks - actual_clicks) / actual_clicks, 4), NULL) AS clicks_error,

  ROUND(predicted_orders, 2) AS predicted_orders, actual_orders,
  IF(status = 'SCORED' AND actual_orders > 0,
     ROUND(ABS(predicted_orders - actual_orders) / actual_orders, 4), NULL) AS orders_error,

  ROUND(predicted_cost, 2) AS predicted_cost, ROUND(actual_cost, 2) AS actual_cost,
  IF(status = 'SCORED' AND actual_cost > 0,
     ROUND(ABS(predicted_cost - actual_cost) / actual_cost, 4), NULL) AS cost_error,

  ROUND(predicted_gross_profit, 2) AS predicted_gross_profit,
  ROUND(actual_gross_profit, 2) AS actual_gross_profit,
  IF(status = 'SCORED' AND actual_gross_profit > 0,
     ROUND(ABS(predicted_gross_profit - actual_gross_profit) / actual_gross_profit, 4), NULL)
    AS gross_profit_error,

  -- THE PRICE LINK. The Catalog chose best_cpc; what did the account actually pay?
  ROUND(SAFE_DIVIDE(actual_cost, NULLIF(actual_clicks, 0)), 4) AS actual_cpc,
  IF(status = 'SCORED' AND actual_clicks > 0 AND best_cpc > 0,
     ROUND(ABS(best_cpc - SAFE_DIVIDE(actual_cost, actual_clicks)) / best_cpc, 4), NULL)
    AS cpc_error,

  -- NET PROFIT IN DOLLARS. Never a percentage -- see the header.
  ROUND(predicted_contribution, 2) AS predicted_contribution,
  ROUND(actual_contribution, 2)    AS actual_contribution,
  IF(status = 'SCORED', ROUND(predicted_contribution - actual_contribution, 2), NULL)
    AS contribution_error_dollars,

  -- Per-link verdicts, so the Catalog can see WHICH link to fix rather than only that it missed.
  IF(status = 'SCORED' AND actual_clicks > 0,
     ABS(predicted_clicks - actual_clicks) / actual_clicks <= (SELECT link_tolerance FROM k), NULL)
    AS clicks_hit,
  IF(status = 'SCORED' AND actual_gross_profit > 0,
     ABS(predicted_gross_profit - actual_gross_profit) / actual_gross_profit
       <= (SELECT link_tolerance FROM k), NULL) AS gross_profit_hit,
  IF(status = 'SCORED' AND actual_clicks > 0 AND best_cpc > 0,
     ABS(best_cpc - SAFE_DIVIDE(actual_cost, actual_clicks)) / best_cpc
       <= (SELECT link_tolerance FROM k), NULL) AS cpc_hit,

  -- WHICH LINK BROKE. The named output 2.0.1 asked for.
  CASE WHEN status <> 'SCORED' THEN NULL
       WHEN actual_clicks = 0 THEN 'NO_TRAFFIC'
       WHEN actual_clicks > 0
            AND ABS(predicted_clicks - actual_clicks) / actual_clicks > (SELECT link_tolerance FROM k)
         THEN 'CLICKS'
       WHEN actual_orders > 0
            AND ABS(predicted_orders - actual_orders) / actual_orders > (SELECT link_tolerance FROM k)
         THEN 'CONVERSION'
       WHEN actual_gross_profit > 0
            AND ABS(predicted_gross_profit - actual_gross_profit) / actual_gross_profit
                > (SELECT link_tolerance FROM k)
         THEN 'GROSS_PROFIT'
       ELSE 'NONE' END AS worst_link,

  cvr_used, gp_per_order_used, elasticity, keyword_bar, halo_credit,
  rate_basis, clicks_basis, elasticity_basis
FROM scored;
