-- =============================================
-- DE_AD_REDIRECTS — the doorway-redirect ledger (2026-08-17, engine-finalization Task 4.6).
-- Ori: "if one variation is out of stock we should change the target ... to the best high demand
-- variation we have in stock ... when it is back in inventory recheck if we want to change it
-- back or leave it." One row per exported redirect; written at bulksheet export time (the
-- DE_NEGATIVE_KEYWORDS precedent — the export IS the decision record). V_AD_REDIRECT_RECHECK
-- watches ACTIVE rows and re-opens the decision when the out ASIN's stock returns.
-- status: ACTIVE (redirect live) | RESTORED (Ori changed it back) | KEPT (Ori kept the hero).
-- =============================================
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_AD_REDIRECTS` (
  id            STRING NOT NULL,   -- campaign_id|ad_group_id|out_asin
  family        STRING,
  campaign_id   STRING NOT NULL,
  campaign_name STRING,
  ad_group_id   STRING NOT NULL,
  out_asin      STRING NOT NULL,   -- the variation whose doorway was closed
  out_product   STRING,
  out_ad_id     STRING,            -- its Product Ad id (paused by the redirect bulksheet)
  hero_asin     STRING NOT NULL,   -- the doorway it was re-aimed to
  hero_product  STRING,
  hero_sku      STRING,
  redirected_at TIMESTAMP NOT NULL,
  status        STRING NOT NULL,   -- ACTIVE | RESTORED | KEPT
  decided_at    TIMESTAMP,         -- when Ori answered the recheck
  decided_note  STRING
);
