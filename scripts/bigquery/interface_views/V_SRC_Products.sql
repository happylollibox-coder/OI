-- =============================================
-- OI Database Project - V_SRC_Products
-- =============================================
--
-- Purpose: Standardized product data from Fivetran item_summary table
-- Business Logic: Filters active products and standardizes field names
-- Dependencies: 
--   - fivetran-hl.amazon_selling_partner.item_summary
--   - fivetran-hl.amazon_selling_partner.item_relationship (for parent_asin)
--   - fivetran-hl.amazon_selling_partner.item_product_type (for product_type)
--   - fivetran-hl.amazon_selling_partner.marketplace_participation (for marketplace attributes)
--   - fivetran-hl.amazon_selling_partner.item_dimension (for item dimensions)
--   - fivetran-hl.amazon_selling_partner.item_offer_detail (for listing price)
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2025-01-01
--
-- =============================================

DROP VIEW IF EXISTS `OI.V_SRC_Products`;
CREATE VIEW `onyga-482313.OI.V_SRC_Products`
AS 
SELECT
  -- Product identifiers
  CAST(ism.asin AS STRING) AS asin,
  CAST(ism.marketplace_id AS STRING) AS marketplace,
  CAST(NULL AS STRING) AS sku,  -- SKU not available in item_summary table
  CAST(rel.parent_asin AS STRING) AS parent_asin,  -- Parent ASIN from item_relationship
  
  -- Marketplace attributes from marketplace_participation
  CAST(mp.name AS STRING) AS marketplace_name,
  CAST(mp.country_code AS STRING) AS marketplace_country_code,
  CAST(mp.default_currency_code AS STRING) AS marketplace_default_currency_code,
  
  -- Product attributes (mapped from actual item_summary schema)
  CAST(ism.item_name AS STRING) AS product_name,
  CAST(ism.display_name AS STRING) AS display_name,
  CAST(ism.brand AS STRING) AS brand,
  CAST(ism.manufacturer AS STRING) AS manufacturer,
  CAST(pt.product_type AS STRING) AS product_type,  -- Product type from item_product_type table
  CAST(ism.color AS STRING) AS color,
  CAST(ism.release_date AS DATE) AS launch_date,
  
  -- Listing price from item_offer_detail (first offer per ASIN)
  CAST(iod.listing_price_currency_code AS STRING) AS listing_price_currency_code,
  iod.listing_price_amount AS listing_price_amount,
  
  -- Item dimensions from item_dimension
  CAST(idim.item_height_unit AS STRING) AS item_height_unit,
  idim.item_height_value AS item_height_value,
  CAST(idim.item_length_unit AS STRING) AS item_length_unit,
  idim.item_length_value AS item_length_value,
  CAST(idim.item_weight_unit AS STRING) AS item_weight_unit,
  idim.item_weight_value AS item_weight_value,
  CAST(idim.item_width_unit AS STRING) AS item_width_unit,
  idim.item_width_value AS item_width_value,
  CAST(idim.package_height_unit AS STRING) AS package_height_unit,
  idim.package_height_value AS package_height_value,
  CAST(idim.package_length_unit AS STRING) AS package_length_unit,
  idim.package_length_value AS package_length_value,
  CAST(idim.package_weight_unit AS STRING) AS package_weight_unit,
  idim.package_weight_value AS package_weight_value,
  CAST(idim.package_width_unit AS STRING) AS package_width_unit,
  idim.package_width_value AS package_width_value,
  
  -- Fivetran metadata
  ism._fivetran_synced
  
FROM `fivetran-hl.amazon_selling_partner.item_summary` AS ism
LEFT JOIN (
  SELECT 
    child_asin,
    parent_asin,
    ROW_NUMBER() OVER (PARTITION BY child_asin ORDER BY parent_asin) AS rn
  FROM `fivetran-hl.amazon_selling_partner.item_relationship`
  -- Note: Removed _fivetran_deleted filter - all relationships currently marked as deleted
  -- but we still want to use them for parent_asin
  QUALIFY rn = 1
) AS rel
  ON ism.asin = rel.child_asin
LEFT JOIN `fivetran-hl.amazon_selling_partner.item_product_type` AS pt
  ON ism.asin = pt.asin
  AND ism.marketplace_id = pt.marketplace_id
LEFT JOIN `fivetran-hl.amazon_selling_partner.marketplace_participation` AS mp
  ON ism.marketplace_id = mp.id
LEFT JOIN `fivetran-hl.amazon_selling_partner.item_dimension` AS idim
  ON ism.asin = idim.asin
  AND ism.marketplace_id = idim.marketplace_id
LEFT JOIN (
  SELECT 
    asin,
    listing_price_currency_code,
    listing_price_amount,
    ROW_NUMBER() OVER (PARTITION BY asin ORDER BY index) AS rn
  FROM `fivetran-hl.amazon_selling_partner.item_offer_detail`
  QUALIFY rn = 1
) AS iod
  ON ism.asin = iod.asin
-- Note: item_summary table doesn't have _fivetran_deleted field
-- All records in this table are considered active
;

-- =============================================
-- VIEW DESCRIPTION
-- =============================================
--
-- This view standardizes product data from Fivetran's item_summary table.
-- It filters for active products only and provides a consistent interface
-- for populating DIM_PRODUCT.
--
-- Note: Field names may need adjustment based on actual item_summary schema.
-- Common variations:
-- - product_name might be: title, item_name, product_title
-- - marketplace might be: marketplace_id, marketplace_code
-- - launch_date might be: release_date, first_available_date
--
-- To verify schema, run:
-- SELECT * FROM `fivetran-hl.amazon_selling_partner.item_summary` LIMIT 1
--
-- =============================================
