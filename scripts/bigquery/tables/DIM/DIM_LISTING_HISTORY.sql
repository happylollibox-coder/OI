-- =============================================
-- OI Database Project - DIM_LISTING_HISTORY Table
-- =============================================
--
-- Purpose: SCD Type 2 dimension table for listing pricing history
-- Source: V_SRC_ActiveListingsReport (Daton ActiveListingsReport)
-- Pattern: SCD2 (close old row, insert new version on change)
-- Business Key: sellingPartnerId, marketplaceId, listing_id, seller_sku, asin1, fulfillment_channel
-- Tracked fields: price, Business_Price, Quantity_Price_Type,
--                 Quantity_Lower_Bound_1..5, Quantity_Price_1..5
-- effective_from/to: DATETIME derived from ReportstartDate column
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.DIM_LISTING_HISTORY` (
  -- Business Key
  sellingPartnerId STRING NOT NULL,
  marketplaceId STRING NOT NULL,
  listing_id STRING NOT NULL,
  seller_sku STRING NOT NULL,
  asin1 STRING NOT NULL,
  fulfillment_channel STRING NOT NULL,

  -- Non-tracked attribute
  marketplaceName STRING,

  -- Tracked fields (pricing tiers)
  price FLOAT64,
  Business_Price FLOAT64,
  Quantity_Price_Type STRING,
  Quantity_Lower_Bound_1 FLOAT64,
  Quantity_Price_1 FLOAT64,
  Quantity_Lower_Bound_2 FLOAT64,
  Quantity_Price_2 FLOAT64,
  Quantity_Lower_Bound_3 FLOAT64,
  Quantity_Price_3 FLOAT64,
  Quantity_Lower_Bound_4 FLOAT64,
  Quantity_Price_4 FLOAT64,
  Quantity_Lower_Bound_5 FLOAT64,
  Quantity_Price_5 FLOAT64,

  -- SCD Type 2 columns
  effective_from DATETIME NOT NULL,
  effective_to DATETIME,
  is_current BOOL NOT NULL
)
CLUSTER BY sellingPartnerId, asin1, is_current;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- SCD Type 2 dimension tracking listing pricing configuration over time.
-- Business key: sellingPartnerId + marketplaceId + listing_id + seller_sku + asin1 + fulfillment_channel
-- Tracked fields trigger a new version when changed:
--   price, Business_Price, Quantity_Price_Type,
--   Quantity_Lower_Bound_1..5, Quantity_Price_1..5
--
-- SCD2 timing:
-- - effective_from = DATETIME(ReportstartDate) from source view
-- - effective_to   = next version's effective_from - 3ms (NULL if current)
-- - is_current     = TRUE for the latest version
--
-- Population:
-- - Populated via SP_LOAD_DIM_LISTING_HISTORY stored procedure
-- - Source: V_SRC_ActiveListingsReport (Daton, auto-synced daily)
-- - Refresh: Daily via SP_ORCHESTRATE_DAILY_REFRESH
--
-- Query patterns:
--   Current state:  WHERE is_current = TRUE  (or use V_DIM_LISTING_CURRENT)
--   Point-in-time:  WHERE effective_from <= @dt AND (effective_to IS NULL OR effective_to > @dt)
