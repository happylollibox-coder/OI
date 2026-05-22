-- =============================================
-- OI Database Project - V_SRC_Products
-- =============================================
--
-- Purpose: Standardized product data from Daton CatalogItems + ActiveListingsReport
-- Business Logic: Flattens nested STRUCTs, deduplicates, filters to US marketplace
-- Dependencies:
--   - daton-491514.BigQuery.amazon_selling_partner_CatalogItems
--   - daton-491514.BigQuery.amazon_selling_partner_ActiveListingsReport
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2026-04-03 (migrated from fivetran-hl)
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SRC_Products`
AS
WITH catalog_base AS (
  -- Flatten CatalogItems: summaries, relationships, productTypes, dimensions
  SELECT
    ci.asin,
    s.marketplaceId AS marketplace_id,
    s.itemName AS product_name,
    s.brand,
    s.manufacturer,
    s.color,
    s.size,
    s.itemClassification AS item_classification,
    -- Parent ASIN from relationships (strip JSON quotes)
    REPLACE(rel.parentAsins, '"', '') AS parent_asin,
    -- Product type
    pt.productType AS product_type,
    -- Dimensions (item)
    idim.weight[SAFE_OFFSET(0)].unit AS item_weight_unit,
    idim.weight[SAFE_OFFSET(0)].value AS item_weight_value,
    idim.height[SAFE_OFFSET(0)].value AS item_height_value,
    idim.length[SAFE_OFFSET(0)].value AS item_length_value,
    idim.width[SAFE_OFFSET(0)].value AS item_width_value,
    -- Dimensions (package)
    pdim.weight[SAFE_OFFSET(0)].unit AS package_weight_unit,
    pdim.weight[SAFE_OFFSET(0)].value AS package_weight_value,
    pdim.height[SAFE_OFFSET(0)].value AS package_height_value,
    pdim.length[SAFE_OFFSET(0)].value AS package_length_value,
    pdim.width[SAFE_OFFSET(0)].value AS package_width_value,
    -- Metadata
    ci._daton_batch_runtime,
    ROW_NUMBER() OVER (PARTITION BY ci.asin ORDER BY ci._daton_batch_runtime DESC) AS rn
  FROM `daton-491514.BigQuery.amazon_selling_partner_CatalogItems` ci
  -- Flatten summaries (1 per marketplace)
  LEFT JOIN UNNEST(ci.summaries) s ON s.marketplaceId = 'ATVPDKIKX0DER'
  -- Flatten relationships for parent ASIN
  LEFT JOIN UNNEST(ci.relationships) r ON r.marketplaceId = 'ATVPDKIKX0DER'
  LEFT JOIN UNNEST(r.relationships) rel ON rel.type = 'VARIATION' AND rel.parentAsins IS NOT NULL
  -- Flatten product types
  LEFT JOIN UNNEST(ci.productTypes) pt ON pt.marketplaceId = 'ATVPDKIKX0DER'
  -- Flatten dimensions
  LEFT JOIN UNNEST(ci.dimensions) d ON d.marketplaceId = 'ATVPDKIKX0DER'
  LEFT JOIN UNNEST(d.item) idim
  LEFT JOIN UNNEST(d.package) pdim
  WHERE s.marketplaceId IS NOT NULL  -- Only US marketplace products
),
listings AS (
  -- Get SKU and listing price from ActiveListingsReport
  SELECT
    asin1 AS asin,
    seller_sku AS sku,
    CAST(price AS FLOAT64) AS listing_price_amount,
    ROW_NUMBER() OVER (PARTITION BY asin1 ORDER BY _daton_batch_runtime DESC) AS rn
  FROM `daton-491514.BigQuery.amazon_selling_partner_ActiveListingsReport`
  WHERE asin1 IS NOT NULL
)
SELECT
  -- Product identifiers
  CAST(cb.asin AS STRING) AS asin,
  CAST(cb.marketplace_id AS STRING) AS marketplace,
  CAST(l.sku AS STRING) AS sku,
  CAST(cb.parent_asin AS STRING) AS parent_asin,

  -- Marketplace attributes (hardcoded for single US marketplace)
  CAST('Amazon.com' AS STRING) AS marketplace_name,
  CAST('US' AS STRING) AS marketplace_country_code,
  CAST('USD' AS STRING) AS marketplace_default_currency_code,

  -- Product attributes
  CAST(cb.product_name AS STRING) AS product_name,
  CAST(cb.product_name AS STRING) AS display_name,
  CAST(cb.brand AS STRING) AS brand,
  CAST(cb.manufacturer AS STRING) AS manufacturer,
  CAST(cb.product_type AS STRING) AS product_type,
  CAST(cb.color AS STRING) AS color,
  CAST(NULL AS DATE) AS launch_date,  -- Not available in Daton CatalogItems

  -- Listing price from ActiveListingsReport
  CAST('USD' AS STRING) AS listing_price_currency_code,
  l.listing_price_amount,

  -- Item dimensions
  CAST(cb.item_weight_unit AS STRING) AS item_height_unit,
  cb.item_height_value,
  CAST(cb.item_weight_unit AS STRING) AS item_length_unit,
  cb.item_length_value,
  CAST(cb.item_weight_unit AS STRING) AS item_weight_unit,
  cb.item_weight_value,
  CAST(cb.item_weight_unit AS STRING) AS item_width_unit,
  cb.item_width_value,
  CAST(cb.package_weight_unit AS STRING) AS package_height_unit,
  cb.package_height_value,
  CAST(cb.package_weight_unit AS STRING) AS package_length_unit,
  cb.package_length_value,
  CAST(cb.package_weight_unit AS STRING) AS package_weight_unit,
  cb.package_weight_value,
  CAST(cb.package_weight_unit AS STRING) AS package_width_unit,
  cb.package_width_value,

  -- Metadata (replacing _fivetran_synced)
  TIMESTAMP_MILLIS(CAST(cb._daton_batch_runtime AS INT64)) AS _fivetran_synced

FROM catalog_base cb
LEFT JOIN listings l ON cb.asin = l.asin AND l.rn = 1
WHERE cb.rn = 1;
