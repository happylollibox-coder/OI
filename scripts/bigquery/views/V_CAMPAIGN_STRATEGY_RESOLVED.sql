-- V_CAMPAIGN_STRATEGY_RESOLVED: one row per CURRENT campaign with a resolved strategy_id.
-- Precedence: manual override > Automatic targeting > experiment mapping (normalized) > inline name classifier > UNCLASSIFIED.
-- Grain: one row per campaign_id (is_current).
-- Fix history (2026-07-22): targeting now outranks the legacy experiment mapping (autos were folded into
-- INTENT by the mapping view); mapping-status join deduped (fixes fan-out/double-counted spend on renamed
-- campaigns); name classifier computed inline from DIM_CAMPAIGN.campaign_name so PAUSED-but-spending
-- campaigns (never enter the ENABLED-filtered mapping view) still classify; mapping strategy normalized
-- to the canonical 6-strategy enum (HUNTER/LOW_COST_DISCOVERY→INTENT, COMPETITOR_CONQUEST→COMPETITOR;
-- unrecognized→NULL so nothing stray leaks through).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_STRATEGY_RESOLVED` AS
WITH
auto_share AS (
  SELECT campaign_id,
    SAFE_DIVIDE(SUM(IF(UPPER(targeting_type)='AUTOMATIC', Ads_cost, 0)), NULLIF(SUM(Ads_cost),0)) AS auto_spend_share
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 120 DAY)
  GROUP BY campaign_id
),
fam AS (
  SELECT campaign_id, parent_name FROM (
    SELECT a.campaign_id, p.parent_name,
      ROW_NUMBER() OVER (PARTITION BY a.campaign_id ORDER BY SUM(a.Ads_cost) DESC) rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = a.most_advertised_asin_impressions
    WHERE p.parent_name IS NOT NULL AND a.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 120 DAY)
    GROUP BY a.campaign_id, p.parent_name
  ) WHERE rn = 1
),
map AS (  -- dedupe: V_CAMPAIGN_MAPPING_STATUS fans out on renamed campaigns
  SELECT campaign_id, current_strategy_id FROM (
    SELECT campaign_id, current_strategy_id,
      ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY spend_60d DESC) rn
    FROM `onyga-482313.OI.V_CAMPAIGN_MAPPING_STATUS`
  ) WHERE rn = 1
),
base AS (
  SELECT
    c.campaign_id, c.campaign_name, c.campaign_type,
    fam.parent_name,
    aus.auto_spend_share,
    CASE UPPER(map.current_strategy_id)
      WHEN 'AUTO' THEN 'AUTO'
      WHEN 'EXACT_BOOST' THEN 'EXACT_BOOST'
      WHEN 'INTENT' THEN 'INTENT'
      WHEN 'HUNTER' THEN 'INTENT'
      WHEN 'LOW_COST_DISCOVERY' THEN 'INTENT'
      WHEN 'COMPETITOR' THEN 'COMPETITOR'
      WHEN 'COMPETITOR_CONQUEST' THEN 'COMPETITOR'
      WHEN 'BRAND_DEFENSE' THEN 'BRAND_DEFENSE'
      WHEN 'PRODUCT_DEFENSE' THEN 'PRODUCT_DEFENSE'
      ELSE NULL
    END AS mapped_strategy,
    CASE
      WHEN REGEXP_CONTAINS(UPPER(c.campaign_name), r'BRAND.?DEF') THEN 'BRAND_DEFENSE'
      WHEN REGEXP_CONTAINS(UPPER(c.campaign_name), r'PRODUCT.?DEF') THEN 'PRODUCT_DEFENSE'
      WHEN REGEXP_CONTAINS(UPPER(c.campaign_name), r'CONQUEST|COPYCAT|COMPETE|/PT\b') THEN 'COMPETITOR'
      WHEN REGEXP_CONTAINS(UPPER(c.campaign_name), r'\bBOOST\b|/EXACT\b|[- ]EXACT\b') THEN 'EXACT_BOOST'
      WHEN REGEXP_CONTAINS(UPPER(c.campaign_name), r'SP/AUTO\b|\bAUTO\b|DISCOVERY') THEN 'AUTO'
      WHEN REGEXP_CONTAINS(UPPER(c.campaign_name), r'BROAD|PHRASE|HUNTER|STORE') THEN 'INTENT'
      ELSE NULL
    END AS name_strategy,
    ovr.strategy_id AS override_strategy_id
  FROM `onyga-482313.OI.DIM_CAMPAIGN` c
  LEFT JOIN map USING (campaign_id)
  LEFT JOIN `onyga-482313.OI.DE_CAMPAIGN_STRATEGY` ovr USING (campaign_id)
  LEFT JOIN auto_share aus USING (campaign_id)
  LEFT JOIN fam USING (campaign_id)
  WHERE c.is_current = TRUE
)
SELECT
  campaign_id, campaign_name, campaign_type, parent_name,
  auto_spend_share, mapped_strategy, name_strategy, override_strategy_id,
  COALESCE(
    override_strategy_id,
    IF(auto_spend_share >= 0.5, 'AUTO', NULL),
    mapped_strategy,
    name_strategy,
    'UNCLASSIFIED'
  ) AS strategy_id,
  CASE
    WHEN override_strategy_id IS NOT NULL THEN 'override'
    WHEN auto_spend_share >= 0.5 THEN 'targeting'
    WHEN mapped_strategy IS NOT NULL THEN 'mapping'
    WHEN name_strategy IS NOT NULL THEN 'name'
    ELSE 'unclassified'
  END AS strategy_source
FROM base;
