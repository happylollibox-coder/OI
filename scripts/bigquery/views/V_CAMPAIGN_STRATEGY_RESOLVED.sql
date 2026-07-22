-- V_CAMPAIGN_STRATEGY_RESOLVED: one row per CURRENT campaign with a resolved strategy_id.
-- Precedence: manual override > experiment mapping > Automatic targeting > name pattern > UNCLASSIFIED.
-- Grain: one row per campaign_id (is_current).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_STRATEGY_RESOLVED` AS
WITH
-- Spend-weighted share of Automatic-targeted rows per campaign (last 120d).
auto_share AS (
  SELECT
    campaign_id,
    SAFE_DIVIDE(
      SUM(IF(UPPER(targeting_type) = 'AUTOMATIC', Ads_cost, 0)),
      NULLIF(SUM(Ads_cost), 0)
    ) AS auto_spend_share
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 120 DAY)
  GROUP BY campaign_id
),
-- Dominant own-product family per campaign (by ad spend, last 120d).
fam AS (
  SELECT campaign_id, parent_name FROM (
    SELECT
      a.campaign_id,
      p.parent_name,
      ROW_NUMBER() OVER (PARTITION BY a.campaign_id ORDER BY SUM(a.Ads_cost) DESC) AS rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p
      ON p.asin = a.most_advertised_asin_impressions
    WHERE p.parent_name IS NOT NULL
      AND a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 120 DAY)
    GROUP BY a.campaign_id, p.parent_name
  ) WHERE rn = 1
)
SELECT
  c.campaign_id,
  c.campaign_name,
  c.campaign_type,
  fam.parent_name,
  ms.suggested_strategy,
  ms.current_strategy_id,
  ovr.strategy_id AS override_strategy_id,
  aus.auto_spend_share,
  -- Resolution precedence
  COALESCE(
    ovr.strategy_id,
    ms.current_strategy_id,
    IF(aus.auto_spend_share >= 0.5, 'AUTO', NULL),
    ms.suggested_strategy,
    'UNCLASSIFIED'
  ) AS strategy_id,
  CASE
    WHEN ovr.strategy_id IS NOT NULL THEN 'override'
    WHEN ms.current_strategy_id IS NOT NULL THEN 'mapping'
    WHEN aus.auto_spend_share >= 0.5 THEN 'targeting'
    WHEN ms.suggested_strategy IS NOT NULL THEN 'name'
    ELSE 'unclassified'
  END AS strategy_source
FROM `onyga-482313.OI.DIM_CAMPAIGN` c
LEFT JOIN `onyga-482313.OI.V_CAMPAIGN_MAPPING_STATUS` ms USING (campaign_id)
LEFT JOIN `onyga-482313.OI.DE_CAMPAIGN_STRATEGY` ovr USING (campaign_id)
LEFT JOIN auto_share aus USING (campaign_id)
LEFT JOIN fam USING (campaign_id)
WHERE c.is_current = TRUE;
