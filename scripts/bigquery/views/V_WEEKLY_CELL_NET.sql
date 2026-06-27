-- V_WEEKLY_CELL_NET — weekly ads net profit/spend per strategy cell. Coacher D.
-- Grain: parent_name x season(PEAK/OFF, per-product peak) x match_type x intent_class x week_start.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_CELL_NET` AS
WITH camp_parent AS (
  SELECT campaign_id, parent_name FROM (
    SELECT a.campaign_id, p.parent_name,
      ROW_NUMBER() OVER (PARTITION BY a.campaign_id ORDER BY SUM(a.Ads_cost) DESC) rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
    WHERE a.date >= DATE('2025-09-23') GROUP BY a.campaign_id, p.parent_name
  ) WHERE rn = 1
),
peak_weeks AS (   -- windows where the occasion is a RELEVANT peak for the family (per-product peak)
  SELECT r.family, h.boost_start, h.cooldown_start
  FROM `onyga-482313.OI.V_PEAK_RELEVANCE` r
  JOIN `onyga-482313.OI.DIM_US_HOLIDAYS` h ON h.holiday_name = r.holiday_name
  WHERE r.is_relevant_peak
),
base AS (
  SELECT
    cp.parent_name,
    DATE_TRUNC(a.date, WEEK(MONDAY)) AS week_start,
    CASE UPPER(a.targeting_type)
      WHEN 'BROAD' THEN 'BROAD' WHEN 'EXACT' THEN 'EXACT' WHEN 'PHRASE' THEN 'PHRASE'
      WHEN 'AUTOMATIC' THEN 'AUTO' WHEN 'ASIN' THEN 'PRODUCT' WHEN 'ASIN EXPANDED' THEN 'PRODUCT'
      WHEN 'CATEGORY' THEN 'CATEGORY' ELSE UPPER(a.targeting_type) END AS match_type,
    COALESCE(ic.intent_class, 'GENERIC') AS intent_class,
    a.GROSS_PROFIT, a.Ads_cost, a.date
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN camp_parent cp ON cp.campaign_id = a.campaign_id
  LEFT JOIN `onyga-482313.OI.V_KEYWORD_INTENT_CLASS` ic
    ON ic.parent_name = cp.parent_name AND ic.keyword_text = LOWER(a.targeting)
  WHERE a.date >= DATE('2025-09-23')
)
SELECT
  b.parent_name, b.week_start, b.match_type, b.intent_class,
  IF(EXISTS (SELECT 1 FROM peak_weeks pw
             WHERE pw.family = b.parent_name AND b.date BETWEEN pw.boost_start AND pw.cooldown_start),
     'PEAK', 'OFF') AS season,
  ROUND(SUM(b.GROSS_PROFIT - b.Ads_cost), 2) AS net_profit,
  ROUND(SUM(b.Ads_cost), 2) AS spend,
  SUM(CASE WHEN b.GROSS_PROFIT IS NOT NULL THEN 1 ELSE 0 END) AS rows_n
FROM base b
GROUP BY b.parent_name, b.week_start, b.match_type, b.intent_class, season
