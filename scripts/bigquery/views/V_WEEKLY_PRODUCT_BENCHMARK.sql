-- V_WEEKLY_PRODUCT_BENCHMARK — per-product historical peak/offseason benchmarks (Coacher D surface).
-- For each product: the last completed PEAK week and the mean of its last up-to-4 PEAK weeks, plus
-- the same for OFF weeks. Two nets per window so the organic halo is visible:
--   net      = ads-attributed (V_WEEKLY_CELL_NET, GROSS_PROFIT − Ads_cost)
--   biz_net  = total business net incl. organic (V_UNIFIED_DAILY, sales − cogs − ad_cost)
--   halo     = biz_net − net  (what organic adds on top of the ads-direct result)
-- Both rolled to the same Sun–Sat week; current (partial) week excluded.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_PRODUCT_BENCHMARK` AS
WITH biz AS (   -- total business net (incl organic) per family x Sun–Sat week
  SELECT family AS parent_name,
         DATE_TRUNC(date, WEEK(SUNDAY)) AS week_start,
         SUM(sales - cogs - ad_cost) AS biz_net
  FROM `onyga-482313.OI.V_UNIFIED_DAILY`
  GROUP BY 1, 2
),
pw AS (   -- roll ads cells up to product x week x season + attach the week's business net
  SELECT c.parent_name, c.week_start, c.season,
         SUM(c.net_profit) AS net, SUM(c.spend) AS spend,
         ANY_VALUE(b.biz_net) AS biz_net
  FROM `onyga-482313.OI.V_WEEKLY_CELL_NET` c
  LEFT JOIN biz b ON b.parent_name = c.parent_name AND b.week_start = c.week_start
  WHERE c.week_start < DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'), WEEK(SUNDAY))
  GROUP BY c.parent_name, c.week_start, c.season
),
ranked AS (   -- most-recent-first rank within each product x season
  SELECT parent_name, week_start, season, net, spend, biz_net,
         ROW_NUMBER() OVER (PARTITION BY parent_name, season ORDER BY week_start DESC) AS rn
  FROM pw
)
SELECT
  parent_name,
  -- last completed PEAK week
  CAST(MAX(IF(season = 'PEAK' AND rn = 1, week_start, NULL)) AS STRING) AS last_peak_week,
  ROUND(MAX(IF(season = 'PEAK' AND rn = 1, net,     NULL)), 2) AS last_peak_net,
  ROUND(MAX(IF(season = 'PEAK' AND rn = 1, spend,   NULL)), 2) AS last_peak_spend,
  ROUND(MAX(IF(season = 'PEAK' AND rn = 1, biz_net, NULL)), 2) AS last_peak_biz_net,
  -- mean of last up-to-4 PEAK weeks (+ the earliest week of that window, for tooltips)
  ROUND(AVG(IF(season = 'PEAK' AND rn <= 4, net,     NULL)), 2) AS peak_avg4_net,
  ROUND(AVG(IF(season = 'PEAK' AND rn <= 4, spend,   NULL)), 2) AS peak_avg4_spend,
  ROUND(AVG(IF(season = 'PEAK' AND rn <= 4, biz_net, NULL)), 2) AS peak_avg4_biz_net,
  COUNTIF(season = 'PEAK' AND rn <= 4) AS peak_weeks_n,
  CAST(MIN(IF(season = 'PEAK' AND rn <= 4, week_start, NULL)) AS STRING) AS peak_avg_from_week,
  -- last completed OFF week
  CAST(MAX(IF(season = 'OFF' AND rn = 1, week_start, NULL)) AS STRING) AS last_off_week,
  ROUND(MAX(IF(season = 'OFF' AND rn = 1, net,     NULL)), 2) AS last_off_net,
  ROUND(MAX(IF(season = 'OFF' AND rn = 1, spend,   NULL)), 2) AS last_off_spend,
  ROUND(MAX(IF(season = 'OFF' AND rn = 1, biz_net, NULL)), 2) AS last_off_biz_net,
  -- mean of last up-to-4 OFF weeks (+ the earliest week of that window, for tooltips)
  ROUND(AVG(IF(season = 'OFF' AND rn <= 4, net,     NULL)), 2) AS off_avg4_net,
  ROUND(AVG(IF(season = 'OFF' AND rn <= 4, spend,   NULL)), 2) AS off_avg4_spend,
  ROUND(AVG(IF(season = 'OFF' AND rn <= 4, biz_net, NULL)), 2) AS off_avg4_biz_net,
  COUNTIF(season = 'OFF' AND rn <= 4) AS off_weeks_n,
  CAST(MIN(IF(season = 'OFF' AND rn <= 4, week_start, NULL)) AS STRING) AS off_avg_from_week
FROM ranked
GROUP BY parent_name
