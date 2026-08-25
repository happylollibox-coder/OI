CREATE OR REPLACE VIEW `onyga-482313.OI.V_KEYWORD_RATES`
OPTIONS (description = "THE SHARED CONVERSION AND MARGIN RATES for a keyword: one definition, read by the Catalog and intended for the engine, so the two cannot price against different money. Ori 2026-08-25, on the halo and then again here: 'both should do the same.' NESTED RECENCY WEIGHTING, RULED BY ORI: keep the full 90-day evidence base but weight recent days more, via windows of 3, 7, 28 and 90 days. Because those windows NEST, summing their numerators and denominators IS a step-decay weighting -- the last 3 days count 4x, days 4-7 count 3x, days 8-28 count 2x, days 29-90 count 1x -- and the denominator is never smaller than a 90-day window ending at the same watermark, so shortening does not thin the evidence. Stated precisely against what the house uses TODAY, which is a 90-day window ending at the SETTLE BOUNDARY and therefore reaching 7 days further back: weighted evidence is 1.84x larger on average and 181 keywords clear 7 orders against 149 today, but 15 of 410 carry slightly FEWER weighted orders because those 7 extra days fall outside the new frame. That is the estimator working rather than failing -- those are keywords whose recent conversion has fallen, and the whole purpose of the weighting is to notice. That property is the point: a flat 28-day window forecasts better than 90 but drops 87 of 183 keywords below 7 orders and prices 28 of them on zero, which trades slow mispricing for violent mispricing. NO SETTLE LAG, AND THAT IS MEASURED RATHER THAN ASSUMED. Every window ends at the ads watermark. Backtested at three as-of dates against the house's current 90-day settled rate, predicting the next week's orders, weighted absolute error fell 45.2 -> 40.1, 105.7 -> 73.1 and 79.7 -> 77.4, and the BIAS fell too (+15.8 -> +11.3, +45.7 -> +25.0, -27.4 -> -23.7). The settled window was not merely noisier, it was systematically over-predicting, because 90 settled days are dominated by an older and better-converting period. Checked PER CHANNEL because SB genuinely settles slower and dropping its lag was the risky half: SB improved 45.8 -> 44.0, 120.0 -> 88.7, 84.9 -> 84.0 and SP 44.7 -> 37.4, 97.9 -> 64.6, 75.9 -> 72.6 -- better on both, worse on neither, so no per-channel exception is warranted. The house's current settled rates are published alongside as cvr_90_settled and gp_per_order_90_settled so any consumer can see exactly what changed and by how much. THIS VIEW DECIDES NOTHING and moves no bid; it publishes rates. Wiring the engine to it is a separate, reviewed change, because it moves real prices.")
AS
WITH k AS (SELECT [3, 7, 28, 90] AS windows, 7 AS settle_reference_days),
wm AS (SELECT MAX(date) AS watermark FROM `onyga-482313.OI.FACT_AMAZON_ADS`),
ct AS (
  SELECT CAST(campaign_id AS STRING) AS cid,
         CASE WHEN UPPER(ANY_VALUE(campaign_type)) = 'SB'
                OR CONTAINS_SUBSTR(UPPER(ANY_VALUE(campaign_type)), 'BRAND') THEN 'SB'
              ELSE 'SP' END AS channel
  FROM `onyga-482313.OI.DIM_CAMPAIGN` GROUP BY 1
),
f AS (
  SELECT CAST(a.campaign_id AS STRING) AS cid, LOWER(TRIM(a.targeting)) AS targeting,
         a.date, a.Ads_clicks AS clk, a.Ads_orders AS ord, a.GROSS_PROFIT AS gp
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a, wm
  WHERE a.targeting IS NOT NULL
    AND a.date > DATE_SUB(wm.watermark, INTERVAL 104 DAY) AND a.date <= wm.watermark
),
-- The four nested windows, all ending at the watermark. Summing them is the weighting.
agg AS (
  SELECT f.cid, f.targeting,
    SUM(IF(f.date > DATE_SUB(wm.watermark, INTERVAL  3 DAY), f.clk, 0)) AS c3,
    SUM(IF(f.date > DATE_SUB(wm.watermark, INTERVAL  3 DAY), f.ord, 0)) AS o3,
    SUM(IF(f.date > DATE_SUB(wm.watermark, INTERVAL  3 DAY), f.gp,  0)) AS g3,
    SUM(IF(f.date > DATE_SUB(wm.watermark, INTERVAL  7 DAY), f.clk, 0)) AS c7,
    SUM(IF(f.date > DATE_SUB(wm.watermark, INTERVAL  7 DAY), f.ord, 0)) AS o7,
    SUM(IF(f.date > DATE_SUB(wm.watermark, INTERVAL  7 DAY), f.gp,  0)) AS g7,
    SUM(IF(f.date > DATE_SUB(wm.watermark, INTERVAL 28 DAY), f.clk, 0)) AS c28,
    SUM(IF(f.date > DATE_SUB(wm.watermark, INTERVAL 28 DAY), f.ord, 0)) AS o28,
    SUM(IF(f.date > DATE_SUB(wm.watermark, INTERVAL 28 DAY), f.gp,  0)) AS g28,
    SUM(IF(f.date > DATE_SUB(wm.watermark, INTERVAL 90 DAY), f.clk, 0)) AS c90,
    SUM(IF(f.date > DATE_SUB(wm.watermark, INTERVAL 90 DAY), f.ord, 0)) AS o90,
    SUM(IF(f.date > DATE_SUB(wm.watermark, INTERVAL 90 DAY), f.gp,  0)) AS g90,
    -- what the house uses today: 90 days ending at the settle boundary. Published for comparison.
    SUM(IF(f.date <= DATE_SUB(wm.watermark, INTERVAL 7 DAY)
           AND f.date > DATE_SUB(wm.watermark, INTERVAL 97 DAY), f.clk, 0)) AS c90s,
    SUM(IF(f.date <= DATE_SUB(wm.watermark, INTERVAL 7 DAY)
           AND f.date > DATE_SUB(wm.watermark, INTERVAL 97 DAY), f.ord, 0)) AS o90s,
    SUM(IF(f.date <= DATE_SUB(wm.watermark, INTERVAL 7 DAY)
           AND f.date > DATE_SUB(wm.watermark, INTERVAL 97 DAY), f.gp,  0)) AS g90s
  FROM f, wm GROUP BY 1, 2
),
ks AS (
  SELECT CAST(campaign_id AS STRING) AS cid, CAST(keyword_id AS STRING) AS keyword_id,
         LOWER(TRIM(target_text)) AS targeting, ANY_VALUE(target_text) AS target_text,
         ANY_VALUE(family) AS family, ANY_VALUE(match_type) AS match_type
  FROM `onyga-482313.OI.FACT_KEYWORD_STATE`
  WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
  GROUP BY 1, 2, 3
)
SELECT
  a.cid AS campaign_id, ks.keyword_id, ks.target_text, ks.family, ks.match_type, ct.channel,
  (SELECT watermark FROM wm) AS rates_through,

  -- the weighted evidence: never less than the plain 90-day count
  a.c90 AS clicks_90,   -- 90 days to the WATERMARK: the honest denominator for the 4x nesting bound
  a.c3 + a.c7 + a.c28 + a.c90 AS weighted_clicks,
  a.o3 + a.o7 + a.o28 + a.o90 AS weighted_orders,
  ROUND(a.g3 + a.g7 + a.g28 + a.g90, 2) AS weighted_gross_profit,

  ROUND(SAFE_DIVIDE(a.o3 + a.o7 + a.o28 + a.o90,
                    NULLIF(a.c3 + a.c7 + a.c28 + a.c90, 0)), 6) AS cvr,
  ROUND(SAFE_DIVIDE(a.g3 + a.g7 + a.g28 + a.g90,
                    NULLIF(a.o3 + a.o7 + a.o28 + a.o90, 0)), 4) AS gp_per_order,
  ROUND(SAFE_DIVIDE(a.g3 + a.g7 + a.g28 + a.g90,
                    NULLIF(a.c3 + a.c7 + a.c28 + a.c90, 0)), 4) AS gp_per_click,

  -- what the house uses today, so the delta is visible rather than inferred
  ROUND(SAFE_DIVIDE(a.o90s, NULLIF(a.c90s, 0)), 6) AS cvr_90_settled,
  ROUND(SAFE_DIVIDE(a.g90s, NULLIF(a.o90s, 0)), 4) AS gp_per_order_90_settled,
  ROUND(SAFE_DIVIDE(a.g90s, NULLIF(a.c90s, 0)), 4) AS gp_per_click_90_settled,
  a.c90s AS clicks_90_settled, a.o90s AS orders_90_settled,

  CONCAT('DATA: nested 3/7/28/90d to ', CAST((SELECT watermark FROM wm) AS STRING),
         ' -- ', CAST(a.o3 + a.o7 + a.o28 + a.o90 AS STRING), ' weighted orders on ',
         CAST(a.c3 + a.c7 + a.c28 + a.c90 AS STRING), ' weighted clicks') AS rates_basis
FROM agg a
JOIN ks ON ks.cid = a.cid AND ks.targeting = a.targeting
JOIN ct ON ct.cid = a.cid;
