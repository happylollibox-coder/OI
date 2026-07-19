-- V_RUN_SEARCH_TERM — search terms under each launch-window (NEW) campaign's target, for the third level
-- of the Weekly Run card (campaign → keyword/auto-group → search terms). One row per
-- (campaign, keyword_id, search_term) over the last 28 complete days. The card groups these into
-- Spenders (by spend) · Winners (converted, by net ROAS) · Negates (≥15 clicks / 0 orders), top 3 + other.
-- FACT_AMAZON_ADS is search-term grain, so this just aggregates it per matched keyword.
--
-- Spenders also carry a per-DAY-AVERAGE spend & sales run-rate at three horizons (1d / 7d / 28d) so you can
-- see whether a term's daily burn is rising or fading. The denominator is the campaign's days elapsed in
-- each window (capped at the window), NOT the raw window length — a day-3 launch divides its 28d total by
-- 3, not 28, so young campaigns aren't understated.
-- Spec: architecture/CAMPAIGN_LAUNCH_RAMP.md §"Phase 1".
CREATE OR REPLACE VIEW `onyga-482313.OI.V_RUN_SEARCH_TERM` AS
WITH wm AS (SELECT LEAST(MAX(date), `onyga-482313.OI.FN_ADS_ANCHOR_CAP`()) AS d
            FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
-- new campaigns + their age (day_of_ramp) — the per-day-average denominator
new_camp AS (SELECT campaign_id, MAX(day_of_ramp) AS age FROM `onyga-482313.OI.V_LAUNCH_PHASE1` GROUP BY 1),
st AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id, CAST(a.keyword_id AS STRING) AS keyword_id,
    a.SEARCH_TERM AS search_term, ANY_VALUE(nc.age) AS age,
    SUM(a.Ads_clicks) AS clicks, SUM(a.Ads_orders) AS orders, SUM(a.Ads_units) AS units,
    SUM(a.Ads_cost) AS spend, SUM(a.Ads_sales) AS sales, SUM(a.GROSS_PROFIT) AS gp,
    -- windowed spend/sales (numerators for the per-day averages)
    SUM(IF(a.date = (SELECT d FROM wm), a.Ads_cost, 0))  AS sp_1d,
    SUM(IF(a.date = (SELECT d FROM wm), a.Ads_sales, 0)) AS sl_1d,
    SUM(IF(a.date >= DATE_SUB((SELECT d FROM wm), INTERVAL 6 DAY), a.Ads_cost, 0))  AS sp_7d,
    SUM(IF(a.date >= DATE_SUB((SELECT d FROM wm), INTERVAL 6 DAY), a.Ads_sales, 0)) AS sl_7d,
    SUM(a.Ads_cost)  AS sp_28d,
    SUM(a.Ads_sales) AS sl_28d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN new_camp nc ON nc.campaign_id = CAST(a.campaign_id AS STRING)
  WHERE a.keyword_id IS NOT NULL AND a.SEARCH_TERM IS NOT NULL AND a.SEARCH_TERM != ''
    AND a.date >= DATE_SUB((SELECT d FROM wm), INTERVAL 27 DAY) AND a.date <= (SELECT d FROM wm)
  GROUP BY 1, 2, 3
)
SELECT campaign_id, keyword_id, search_term, clicks, orders, units,
  ROUND(spend, 2) AS spend, ROUND(sales, 2) AS sales,
  ROUND(SAFE_DIVIDE(gp, NULLIF(spend, 0)), 2) AS net_roas,
  ROUND(100 * SAFE_DIVIDE(spend, NULLIF(sales, 0)), 0) AS acos,
  (clicks >= 15 AND orders = 0) AS is_negate,
  (orders > 0) AS is_winner,
  -- per-day averages (÷ campaign days elapsed in each window)
  ROUND(sp_1d, 2) AS d1_spend, ROUND(sl_1d, 2) AS d1_sales,
  ROUND(sp_7d  / GREATEST(1, LEAST(7,  COALESCE(age, 7))),  2) AS d7_spend,
  ROUND(sl_7d  / GREATEST(1, LEAST(7,  COALESCE(age, 7))),  2) AS d7_sales,
  ROUND(sp_28d / GREATEST(1, LEAST(28, COALESCE(age, 28))), 2) AS d28_spend,
  ROUND(sl_28d / GREATEST(1, LEAST(28, COALESCE(age, 28))), 2) AS d28_sales
FROM st
WHERE clicks > 0;
