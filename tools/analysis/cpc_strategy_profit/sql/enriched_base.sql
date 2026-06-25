-- target × day enriched base for CPC strategy analysis
-- Net profit (ads-attributed) = GROSS_PROFIT - Ads_cost
WITH camp_parent AS (        -- campaign -> dominant parent by spend (100% asin coverage)
  SELECT campaign_id, parent_name
  FROM (
    SELECT a.campaign_id, p.parent_name,
           ROW_NUMBER() OVER (PARTITION BY a.campaign_id
                              ORDER BY SUM(a.Ads_cost) DESC) AS rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
    WHERE a.date >= DATE('2025-09-23')
    GROUP BY a.campaign_id, p.parent_name
  ) WHERE rn = 1
),
tos AS (                     -- campaign × day TOS covariate
  SELECT campaign_id, report_date,
         SAFE_DIVIDE(SUM(IF(placement='TOP_OF_SEARCH', cost, 0)), NULLIF(SUM(cost),0)) AS tos_cost_share
  FROM `onyga-482313.OI.V_CAMPAIGN_PLACEMENT_REPORT`
  GROUP BY campaign_id, report_date
),
tos_bid AS (                 -- campaign TOS bid-adjustment % (current setting snapshot)
  SELECT campaign_id, MAX(top_of_search_pct) AS tos_bid_adj_pct
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` GROUP BY campaign_id
),
cal AS (                     -- one calendar segment per LA-local date
  SELECT d AS date,
    COALESCE(MAX(CASE
      WHEN d BETWEEN h.peak_start AND h.cooldown_start THEN CONCAT(h.holiday_name,'_PEAK')
      WHEN d BETWEEN h.boost_start AND h.peak_start    THEN CONCAT(h.holiday_name,'_BOOST')
      WHEN d BETWEEN h.pre_season_start AND h.boost_start THEN CONCAT(h.holiday_name,'_PRE')
      WHEN d BETWEEN h.cooldown_start AND h.cooldown_end THEN CONCAT(h.holiday_name,'_COOLDOWN')
    END),
    CONCAT('EVERYDAY_', FORMAT_DATE('%Y-%m', d))) AS calendar_segment
  FROM UNNEST(GENERATE_DATE_ARRAY(DATE('2025-09-23'), CURRENT_DATE('America/Los_Angeles'))) d
  LEFT JOIN `onyga-482313.OI.DIM_US_HOLIDAYS` h
    ON d BETWEEN h.pre_season_start AND h.cooldown_end
  GROUP BY d
),
ads AS (
  SELECT
    a.date,
    a.campaign_id,
    a.ad_group_id,
    COALESCE(a.keyword_id, a.targeting) AS target_key,
    ANY_VALUE(a.targeting)      AS targeting,
    ANY_VALUE(a.targeting_type) AS targeting_type,
    ANY_VALUE(a.campaign_type)  AS campaign_type,
    SUM(a.Ads_clicks)   AS clicks,
    SUM(a.Ads_cost)     AS cost,
    SUM(a.Ads_orders)   AS orders,
    SUM(a.Ads_units)    AS units,
    SUM(a.Ads_sales)    AS sales,
    SUM(a.GROSS_PROFIT) AS gross_profit
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  WHERE a.date >= DATE('2025-09-23')
    AND a.date <  DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 2 DAY)   -- lag trim
  GROUP BY a.date, a.campaign_id, a.ad_group_id, target_key
  HAVING SUM(a.Ads_clicks) > 0
)
SELECT
  cp.parent_name,
  ads.date, ads.campaign_id, ads.ad_group_id, ads.target_key,
  ads.targeting, ads.targeting_type, ads.campaign_type,
  ads.clicks, ads.cost, ads.orders, ads.units, ads.sales, ads.gross_profit,
  (ads.gross_profit - ads.cost)          AS net_profit,
  SAFE_DIVIDE(ads.cost, ads.clicks)      AS cpc,
  cal.calendar_segment,
  tos.tos_cost_share,
  tb.tos_bid_adj_pct
FROM ads
JOIN camp_parent cp ON cp.campaign_id = ads.campaign_id
JOIN cal           ON cal.date = ads.date
LEFT JOIN tos      ON tos.campaign_id = ads.campaign_id AND tos.report_date = ads.date
LEFT JOIN tos_bid tb ON tb.campaign_id = ads.campaign_id
WHERE cp.parent_name IS NOT NULL
ORDER BY parent_name, campaign_id, target_key, date
