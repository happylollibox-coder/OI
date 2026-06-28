-- V_WEEKLY_PRODUCT_BENCHMARK — per-product historical peak/offseason benchmarks (Coacher D surface).
-- For each product: the last completed PEAK week and the mean of its last up-to-4 PEAK weeks, plus
-- the same for OFF weeks. Net profit (ads-attributed) + spend. Source = V_WEEKLY_CELL_NET, which
-- already tags each week PEAK/OFF per-product (per-product relevant peak). Current (partial) week
-- excluded so benchmarks are completed weeks only. Lets This Week read the forward-net plan against
-- what peak/offseason actually delivered.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_PRODUCT_BENCHMARK` AS
WITH pw AS (   -- roll cells up to product x week x season (completed weeks only)
  SELECT parent_name, week_start, season,
         SUM(net_profit) AS net, SUM(spend) AS spend
  FROM `onyga-482313.OI.V_WEEKLY_CELL_NET`
  WHERE week_start < DATE_TRUNC(CURRENT_DATE('America/Los_Angeles'), WEEK(MONDAY))
  GROUP BY parent_name, week_start, season
),
ranked AS (   -- most-recent-first rank within each product x season
  SELECT parent_name, week_start, season, net, spend,
         ROW_NUMBER() OVER (PARTITION BY parent_name, season ORDER BY week_start DESC) AS rn
  FROM pw
)
SELECT
  parent_name,
  -- last completed PEAK week
  CAST(MAX(IF(season = 'PEAK' AND rn = 1, week_start, NULL)) AS STRING) AS last_peak_week,
  ROUND(MAX(IF(season = 'PEAK' AND rn = 1, net,   NULL)), 2) AS last_peak_net,
  ROUND(MAX(IF(season = 'PEAK' AND rn = 1, spend, NULL)), 2) AS last_peak_spend,
  -- mean of last up-to-4 PEAK weeks (+ the earliest week of that window, for tooltips)
  ROUND(AVG(IF(season = 'PEAK' AND rn <= 4, net,   NULL)), 2) AS peak_avg4_net,
  ROUND(AVG(IF(season = 'PEAK' AND rn <= 4, spend, NULL)), 2) AS peak_avg4_spend,
  COUNTIF(season = 'PEAK' AND rn <= 4) AS peak_weeks_n,
  CAST(MIN(IF(season = 'PEAK' AND rn <= 4, week_start, NULL)) AS STRING) AS peak_avg_from_week,
  -- last completed OFF week
  CAST(MAX(IF(season = 'OFF' AND rn = 1, week_start, NULL)) AS STRING) AS last_off_week,
  ROUND(MAX(IF(season = 'OFF' AND rn = 1, net,   NULL)), 2) AS last_off_net,
  ROUND(MAX(IF(season = 'OFF' AND rn = 1, spend, NULL)), 2) AS last_off_spend,
  -- mean of last up-to-4 OFF weeks (+ the earliest week of that window, for tooltips)
  ROUND(AVG(IF(season = 'OFF' AND rn <= 4, net,   NULL)), 2) AS off_avg4_net,
  ROUND(AVG(IF(season = 'OFF' AND rn <= 4, spend, NULL)), 2) AS off_avg4_spend,
  COUNTIF(season = 'OFF' AND rn <= 4) AS off_weeks_n,
  CAST(MIN(IF(season = 'OFF' AND rn <= 4, week_start, NULL)) AS STRING) AS off_avg_from_week
FROM ranked
GROUP BY parent_name
