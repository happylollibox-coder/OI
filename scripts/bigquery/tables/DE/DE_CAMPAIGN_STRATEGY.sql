-- DE_CAMPAIGN_STRATEGY: manual per-campaign strategy override (highest precedence).
-- Written by the Admin "Campaign Strategy" panel. One row per campaign_id.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_CAMPAIGN_STRATEGY` (
  campaign_id STRING NOT NULL,
  strategy_id STRING NOT NULL,   -- AUTO|BRAND_DEFENSE|COMPETITOR|EXACT_BOOST|INTENT|PRODUCT_DEFENSE|UNCLASSIFIED
  notes STRING,
  updated_by STRING,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (campaign_id) NOT ENFORCED
)
OPTIONS (description = "Manual per-campaign strategy override. Highest precedence in V_CAMPAIGN_STRATEGY_RESOLVED.");
