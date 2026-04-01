-- =============================================
-- OI Database Project - DIM_PRODUCT Table
-- =============================================
--
-- Purpose: Product dimension table for active products
-- Used for product master data with ASIN as optional identifier
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Create the product dimension table
CREATE OR REPLACE TABLE `onyga-482313.OI.DIM_PRODUCT` (
  -- Primary key (auto-generated)
  product_id INT64 NOT NULL,

  -- Product identifiers
  asin STRING, -- Amazon Standard Identification Number (optional for new products)
  parent_asin STRING, -- Parent ASIN from item_relationship table
  parent_name STRING, -- Parent product name
  sku STRING, -- Merchant SKU
  marketplace STRING, -- Marketplace identifier (e.g., 'US', 'UK', 'DE')
  
  -- Marketplace attributes from marketplace_participation
  marketplace_name STRING, -- Marketplace name
  marketplace_country_code STRING, -- Marketplace country code
  marketplace_default_currency_code STRING, -- Marketplace default currency code

  -- Product attributes from Fivetran
  product_name STRING,
  display_name STRING, -- Product display name
  brand STRING,
  manufacturer STRING,
  product_type STRING,
  color STRING, -- Product color
  launch_date DATE,
  
  -- Fivetran metadata
  _fivetran_synced TIMESTAMP, -- Data freshness tracking from source
  
  -- Status
  is_active BOOLEAN DEFAULT TRUE, -- Derived from _fivetran_deleted = false
  
  -- Cost and logistics fields
  cost_of_goods FLOAT64, -- Cost of goods
  shipping_cost FLOAT64, -- Shipping cost
  manufacture_day INT64, -- Manufacturing day
  shipment_days INT64, -- Shipment days
  
  -- Listing price from item_offer_detail
  listing_price_currency_code STRING, -- Listing price currency code
  listing_price_amount FLOAT64, -- Listing price amount
  
  -- Item dimensions from item_dimension
  item_height_unit STRING, -- Item height unit
  item_height_value INT64, -- Item height value
  item_length_unit STRING, -- Item length unit
  item_length_value INT64, -- Item length value
  item_weight_unit STRING, -- Item weight unit
  item_weight_value INT64, -- Item weight value
  item_width_unit STRING, -- Item width unit
  item_width_value INT64, -- Item width value
  package_height_unit STRING, -- Package height unit
  package_height_value INT64, -- Package height value
  package_length_unit STRING, -- Package length unit
  package_length_value INT64, -- Package length value
  package_weight_unit STRING, -- Package weight unit
  package_weight_value INT64, -- Package weight value
  package_width_unit STRING, -- Package width unit
  package_width_value INT64, -- Package width value
  
  -- Custom shipping fields (manually managed, not from Fivetran)
  package_quantity INT64, -- Units per manufacturer shipping carton
  package_cubic_feet FLOAT64, -- Cubic feet per shipping carton (for cost allocation)
  
  -- Metadata
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),

  -- Constraints
  PRIMARY KEY (product_id) NOT ENFORCED
)
CLUSTER BY asin, sku, marketplace;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This dimension table stores product master data from Fivetran's item_summary table.
-- Products are identified by ASIN when available, but ASIN is optional for new products.
--
-- Key Features:
-- - product_id: Auto-generated unique identifier (ensures uniqueness even when ASIN is null)
-- - asin: Optional identifier for existing products
-- - sku + marketplace: Alternative identifier when ASIN is not available
-- - Upsert-only: Products are merged from Fivetran, never deleted
-- - Cost fields: cost_of_goods, shipping_cost (can be populated separately)
-- - Logistics fields: manufacture_day, shipment_days (can be populated separately)
--
-- Population:
-- - Populated via SP_MERGE_PRODUCT_DIM stored procedure
-- - Source: fivetran-hl.amazon_selling_partner.item_summary
-- - Filter: Only active products (_fivetran_deleted = false)
--
-- Usage:
-- - Product dimension for fact tables
-- - Product master data reference
-- - Product attribute lookups
--
-- =============================================
