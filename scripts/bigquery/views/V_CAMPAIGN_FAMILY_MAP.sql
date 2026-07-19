-- V_CAMPAIGN_FAMILY_MAP — the single family attribution for every ENABLED campaign.
-- Coverage guarantee for the budget waterfall (Ori 2026-07-05): DE_CAMPAIGN_FAMILY override wins,
-- else the dominant advertised-ASIN family (last 90d), else the 'Unknown' catch-all — so no enabled
-- campaign can fall outside the budget. Reused by V_FAMILY_NET_PROFIT_7D / _BUDGET_ALLOCATION /
-- _CAMPAIGN_BUDGET_BASE / _DAILY_MOVE so the whole waterfall shares one attribution.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_FAMILY_MAP` AS
WITH enabled AS (
  SELECT campaign_id, campaign_name
  FROM `onyga-482313.OI.DIM_CAMPAIGN`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY last_updated_date DESC) = 1
     AND state = 'ENABLED'
),
asin_fam AS (
  SELECT campaign_id, parent_name FROM (
    SELECT a.campaign_id, p.parent_name,
      ROW_NUMBER() OVER (PARTITION BY a.campaign_id ORDER BY SUM(a.Ads_cost) DESC) rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p
      ON p.asin = COALESCE(a.most_advertised_asin_impressions, a.ASIN_BY_CAMPAIGN_NAME)
    WHERE a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
    GROUP BY a.campaign_id, p.parent_name
  ) WHERE rn = 1
)
SELECT e.campaign_id,
  COALESCE(cf.parent_name, af.parent_name, 'Unknown') AS parent_name
FROM enabled e
LEFT JOIN `onyga-482313.OI.DE_CAMPAIGN_FAMILY` cf ON cf.campaign_id = e.campaign_id
LEFT JOIN asin_fam af ON af.campaign_id = e.campaign_id;
