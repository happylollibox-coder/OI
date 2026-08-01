-- =============================================
-- OI Database Project - FACT_ADS_ADVERTISED_DAILY Table
-- =============================================
--
-- Purpose: Advertised-ASIN-grain daily ads fact. Records performance of the
--          ASIN that was ADVERTISED (not the ASIN that was purchased), so
--          per-product P&L attribution is honest: ~79% of ad-attributed
--          purchases land on a different ASIN than the advertised one, and
--          FACT_AMAZON_ADS (search-term grain) can only approximate the
--          advertised ASIN via most_advertised_asin_* heuristics.
-- Grain:   date x ad_id x advertised_asin
--          (one product ad = one advertised ASIN/SKU; verified unique,
--          also unique on date x campaign_id x ad_group_id x advertised_asin)
-- Method:  Idempotent MERGE, 30-day rolling reload window
--          (SP_LOAD_FACT_ADS_ADVERTISED_DAILY)
-- Source:  V_SRC_AmazonAds_advertised_product
--          (fivetran-hl.amazon_ads.advertised_product_report)
-- Coverage: Sponsored Products ONLY. Amazon has no advertised-product report
--          for SB (sb_ad_report is creative-grain, no ASIN); SD equivalent
--          (sd_product_ad_report) has no ASIN column and negligible volume.
--          History starts 2025-09-23 (Fivetran connector start), vs
--          2024-09-05 for FACT_AMAZON_ADS.
-- Timezone: date is reported by Amazon in the profile timezone
--          (America/Los_Angeles for the US profile) — already LA-local,
--          consistent with the FACT layer convention. No conversion applied.
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.FACT_ADS_ADVERTISED_DAILY` (
  date DATE NOT NULL,                    -- Report date (LA-local, as reported by Amazon)
  campaign_id STRING NOT NULL,
  campaign_name STRING,                  -- Current name from DIM_CAMPAIGN (is_current)
  campaign_type STRING,                  -- 'SP' (source report is SP-only)
  ad_group_id STRING NOT NULL,
  ad_group_name STRING,                  -- Current name from DIM_AD_GROUP (is_current)
  ad_id STRING NOT NULL,                 -- Product ad id (1 ad = 1 advertised ASIN/SKU)
  advertised_asin STRING NOT NULL,       -- The ASIN shown in the ad
  advertised_sku STRING,

  -- Traffic + spend (exact, not search-term-truncated: impressions here are
  -- the TRUE ad impressions; FACT_AMAZON_ADS term grain undercounts them)
  Ads_impressions INT64,
  Ads_clicks INT64,
  Ads_cost FLOAT64,                      -- source cost (== spend in this report)

  -- Conversions, 14d attribution window (canonical, matches Amazon console)
  Ads_orders INT64,                      -- purchases_14_d
  Ads_units INT64,                       -- units_sold_clicks_14_d
  Ads_sales FLOAT64,                     -- sales_14_d

  -- Same-SKU split (14d) — the honest "this ad sold THIS product" numbers
  orders_same_sku_14d INT64,
  units_same_sku_14d INT64,
  sales_same_sku_14d FLOAT64,

  -- Halo (14d, derived: total - same_sku) — sales the ad drove on OTHER ASINs
  orders_other_sku_14d INT64,
  units_other_sku_14d INT64,
  sales_other_sku_14d FLOAT64,

  -- 7d attribution window (for parity with coacher 7d metrics)
  Ads_orders_7d INT64,
  Ads_units_7d INT64,
  Ads_sales_7d FLOAT64,

  _fivetran_synced TIMESTAMP,
  loaded_at TIMESTAMP,                   -- When SP_LOAD_FACT_ADS_ADVERTISED_DAILY wrote the row

  PRIMARY KEY (date, ad_id, advertised_asin) NOT ENFORCED
)
PARTITION BY date
CLUSTER BY advertised_asin, campaign_id, ad_group_id
OPTIONS (
  description = "Advertised-ASIN-grain daily ads fact (SP only). Grain: date x ad_id x advertised_asin. Source: advertised_product_report via V_SRC_AmazonAds_advertised_product. 14d attribution canonical; same-SKU vs other-SKU (halo) split included. History from 2025-09-23. Loaded by SP_LOAD_FACT_ADS_ADVERTISED_DAILY (idempotent MERGE, 30-day rolling window)."
);

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- Why this table exists:
-- - FACT_AMAZON_ADS is search-term/campaign oriented; its per-ASIN spend is a
--   heuristic (most_advertised_asin_impressions / ASIN_BY_CAMPAIGN_NAME).
-- - Amazon reports advertised-product metrics DIRECTLY at
--   date x ad x advertised ASIN grain; this table records them verbatim.
-- - Use this table for per-product ad spend/P&L attribution; use
--   sales_same_sku_14d vs sales_other_sku_14d to separate direct sales
--   from cross-ASIN halo.
--
-- Known coverage caveats (documented, by design):
-- - SP only. SB spend (~40% of total) has no advertised-ASIN report at Amazon.
-- - History starts 2025-09-23.
-- - Spend runs ~1.4% below FACT_AMAZON_ADS SP spend (28d check 2026-07-03..30:
--   $18,063.68 vs $18,325.86), spread thinly across all campaigns — report-level
--   reconciliation noise between Amazon's advertised-product and search-term
--   reports, not missing campaigns.
--
-- =============================================
