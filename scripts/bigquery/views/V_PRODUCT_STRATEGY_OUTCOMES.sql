-- V_PRODUCT_STRATEGY_OUTCOMES — net-profit verdict per MANUAL strategy suggestion (pre vs post applied_at)
CREATE OR REPLACE VIEW `onyga-482313.OI.V_PRODUCT_STRATEGY_OUTCOMES` AS
WITH camp_parent AS (
  SELECT campaign_id, parent_name FROM (
    SELECT a.campaign_id, p.parent_name,
      ROW_NUMBER() OVER (PARTITION BY a.campaign_id ORDER BY SUM(a.Ads_cost) DESC) rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
    WHERE a.date >= DATE('2025-09-23') GROUP BY a.campaign_id, p.parent_name
  ) WHERE rn = 1
),
cal AS (
  SELECT d AS date,
    IF(MAX(CASE WHEN d BETWEEN h.boost_start AND h.cooldown_start THEN 1 END) = 1, 'PEAK', 'OFF') AS season
  FROM UNNEST(GENERATE_DATE_ARRAY(DATE('2025-09-23'), CURRENT_DATE('America/Los_Angeles'))) d
  LEFT JOIN `onyga-482313.OI.DIM_US_HOLIDAYS` h ON d BETWEEN h.boost_start AND h.cooldown_start
  GROUP BY d
),
kd AS (
  SELECT a.date, cp.parent_name, cal.season,
    CASE LOWER(a.targeting_type)
      WHEN 'broad' THEN 'BROAD' WHEN 'exact' THEN 'EXACT' WHEN 'phrase' THEN 'PHRASE'
      WHEN 'automatic' THEN 'AUTO' WHEN 'asin' THEN 'PRODUCT' WHEN 'asin expanded' THEN 'PRODUCT'
      WHEN 'category' THEN 'CATEGORY' ELSE UPPER(a.targeting_type) END AS match_type,
    SUM(a.GROSS_PROFIT) AS gp, SUM(a.Ads_cost) AS cost
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN camp_parent cp ON cp.campaign_id = a.campaign_id
  JOIN cal ON cal.date = a.date
  WHERE a.Ads_clicks > 0
  GROUP BY 1, 2, 3, 4
),
m AS (
  SELECT parent_name, season, match_type, enabled, cpc_target, status, applied_at,
    DATE(applied_at, 'America/Los_Angeles') AS applied_date,
    GREATEST(DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), DATE(applied_at, 'America/Los_Angeles'), DAY), 1) AS post_days
  FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE`
  WHERE source = 'MANUAL' AND applied_at IS NOT NULL
),
agg AS (
  SELECT m.parent_name, m.season, m.match_type, m.enabled, m.cpc_target, m.status, m.applied_at, m.post_days,
    SUM(IF(kd.date >= m.applied_date, kd.gp - kd.cost, 0)) AS post_net,
    SUM(IF(kd.date >= m.applied_date, kd.cost, 0)) AS post_cost,
    SUM(IF(kd.date < m.applied_date AND kd.date >= DATE_SUB(m.applied_date, INTERVAL m.post_days DAY), kd.gp - kd.cost, 0)) AS pre_net,
    SUM(IF(kd.date < m.applied_date AND kd.date >= DATE_SUB(m.applied_date, INTERVAL m.post_days DAY), kd.cost, 0)) AS pre_cost
  FROM m LEFT JOIN kd
    ON kd.parent_name = m.parent_name AND kd.season = m.season AND kd.match_type = m.match_type
  GROUP BY 1,2,3,4,5,6,7,8
)
SELECT *,
  ROUND(SAFE_DIVIDE(post_net, NULLIF(post_cost, 0)), 2) AS post_net_per_dollar,
  ROUND(SAFE_DIVIDE(pre_net,  NULLIF(pre_cost, 0)),  2) AS pre_net_per_dollar,
  CASE
    WHEN post_cost < 200 THEN 'INSUFFICIENT'
    WHEN SAFE_DIVIDE(post_net, NULLIF(post_cost,0)) >= COALESCE(SAFE_DIVIDE(pre_net, NULLIF(pre_cost,0)), 0) THEN 'GAIN'
    ELSE 'LOSS' END AS verdict
FROM agg;
