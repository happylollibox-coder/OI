-- DE_CAMPAIGN_FAMILY — campaign→family override for the coacher's ASIN-blind campaigns.
-- The coacher attributes family via the advertised ASIN (ASIN → DIM_PRODUCT.parent_name).
-- Video / Sponsored-Brands / Store campaigns report most_advertised_asin = 'Unknown', which
-- matches no product, so V_ADS_COACH_DATA's inner JOIN asin_economics DROPS them entirely and
-- they fall out of coaching regardless of their DIM_EXPERIMENT_CAMPAIGN strategy mapping.
-- This table supplies the family directly, keyed by campaign_id, as a fallback the engine reads
-- when the ASIN yields no family. 'Store' is a virtual family (whole-store brand campaigns, no
-- single product ASIN) — Ori 2026-07-05. Backend override; the Campaign Mapping panel can write it.
CREATE TABLE IF NOT EXISTS `onyga-482313.OI.DE_CAMPAIGN_FAMILY` (
  campaign_id  STRING NOT NULL,   -- Amazon campaign id
  parent_name  STRING NOT NULL,   -- family override: Bottle|Bunny|Fresh|LolliBall|LolliME|Lollibox|Store
  note         STRING,            -- why this override exists
  updated_at   TIMESTAMP,
  updated_by   STRING
);
