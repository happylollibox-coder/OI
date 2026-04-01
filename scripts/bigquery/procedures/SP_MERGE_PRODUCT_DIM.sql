-- =============================================
-- OI Database Project - SP_MERGE_PRODUCT_DIM Stored Procedure
-- =============================================
--
-- Purpose: Merge active products from Fivetran item_summary into DIM_PRODUCT
-- Uses MERGE for upsert-only operations (no deletes)
-- Cost data (cost_of_goods, shipping_cost, fba_cost) is managed by DIM_COSTS_HISTORY, not here.
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_MERGE_PRODUCT_DIM`()
OPTIONS (
  description = "Merge active products from V_SRC_Products into DIM_PRODUCT table (upsert only, no deletes). Cost data managed by DIM_COSTS_HISTORY."
)
BEGIN
  -- Declare variables for logging
  DECLARE matched_count INT64;
  DECLARE inserted_count INT64;
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- MERGE products from source view into dimension table
  -- Match on ASIN when available, otherwise on SKU + marketplace
  MERGE `onyga-482313.OI.DIM_PRODUCT` AS dim
  USING (
    SELECT
      -- Generate deterministic product_id using FARM_FINGERPRINT
      -- This ensures same product gets same ID across runs
      ABS(FARM_FINGERPRINT(
        CONCAT(
          COALESCE(vp.asin, ''),
          '|',
          COALESCE(vp.marketplace, '')
        )
      )) AS product_id,
      vp.asin,
      vp.parent_asin,
      CAST(NULL AS STRING) AS parent_name, -- parent_name populated from staging table
      CAST(vp.sku AS STRING) AS sku,
      vp.marketplace,
      vp.marketplace_name,
      vp.marketplace_country_code,
      vp.marketplace_default_currency_code,
      vp.product_name,
      vp.display_name,
      vp.brand,
      vp.manufacturer,
      vp.product_type,
      vp.color,
      vp.launch_date,
      vp.listing_price_currency_code,
      vp.listing_price_amount,
      vp.item_height_unit,
      vp.item_height_value,
      vp.item_length_unit,
      vp.item_length_value,
      vp.item_weight_unit,
      vp.item_weight_value,
      vp.item_width_unit,
      vp.item_width_value,
      vp.package_height_unit,
      vp.package_height_value,
      vp.package_length_unit,
      vp.package_length_value,
      vp.package_weight_unit,
      vp.package_weight_value,
      vp.package_width_unit,
      vp.package_width_value,
      vp._fivetran_synced,
      vp.color AS product_short_name
    FROM `onyga-482313.OI.V_SRC_Products` vp
    WHERE vp.marketplace = 'ATVPDKIKX0DER'
    
    UNION ALL
    
    -- Add UNKNOWN product row for factless fact table joins
    SELECT
      ABS(FARM_FINGERPRINT('UNKNOWN|ATVPDKIKX0DER')) AS product_id,
      'UNKNOWN' AS asin,
      'UNKNOWN' AS parent_asin,
      'UNKNOWN' AS parent_name,
      'UNKNOWN' AS sku,
      'ATVPDKIKX0DER' AS marketplace,
      'UNKNOWN' AS marketplace_name,
      'UNKNOWN' AS marketplace_country_code,
      'UNKNOWN' AS marketplace_default_currency_code,
      'UNKNOWN' AS product_name,
      'UNKNOWN' AS display_name,
      'UNKNOWN' AS brand,
      'UNKNOWN' AS manufacturer,
      'UNKNOWN' AS product_type,
      'UNKNOWN' AS color,
      NULL AS launch_date,
      'UNKNOWN' AS listing_price_currency_code,
      NULL AS listing_price_amount,
      'UNKNOWN' AS item_height_unit,
      NULL AS item_height_value,
      'UNKNOWN' AS item_length_unit,
      NULL AS item_length_value,
      'UNKNOWN' AS item_weight_unit,
      NULL AS item_weight_value,
      'UNKNOWN' AS item_width_unit,
      NULL AS item_width_value,
      'UNKNOWN' AS package_height_unit,
      NULL AS package_height_value,
      'UNKNOWN' AS package_length_unit,
      NULL AS package_length_value,
      'UNKNOWN' AS package_weight_unit,
      NULL AS package_weight_value,
      'UNKNOWN' AS package_width_unit,
      NULL AS package_width_value,
      NULL AS _fivetran_synced,
      'UNKNOWN' AS product_short_name
  ) AS source
  ON (
    -- Match on ASIN + marketplace (primary key)
    (dim.asin = source.asin 
     AND COALESCE(dim.marketplace, '') = COALESCE(source.marketplace, ''))
  )
  WHEN MATCHED THEN
    -- Update all fields except product_id and created_at
    UPDATE SET
      asin = COALESCE(source.asin, dim.asin), -- Preserve existing ASIN if source doesn't have one
      parent_asin = source.parent_asin,
      parent_name = COALESCE(source.parent_name, dim.parent_name), -- Preserve parent_name from staging
      sku = COALESCE(source.sku, dim.sku), -- Preserve SKU from staging
      marketplace = source.marketplace,
      marketplace_name = source.marketplace_name,
      marketplace_country_code = source.marketplace_country_code,
      marketplace_default_currency_code = source.marketplace_default_currency_code,
      product_name = source.product_name,
      display_name = source.display_name,
      brand = source.brand,
      manufacturer = source.manufacturer,
      product_type = source.product_type,
      color = source.color,
      launch_date = source.launch_date,
      listing_price_currency_code = COALESCE(dim.listing_price_currency_code, source.listing_price_currency_code),
      listing_price_amount = COALESCE(dim.listing_price_amount, source.listing_price_amount),
      item_height_unit = source.item_height_unit,
      item_height_value = source.item_height_value,
      item_length_unit = source.item_length_unit,
      item_length_value = source.item_length_value,
      item_weight_unit = source.item_weight_unit,
      item_weight_value = source.item_weight_value,
      item_width_unit = source.item_width_unit,
      item_width_value = source.item_width_value,
      package_height_unit = source.package_height_unit,
      package_height_value = source.package_height_value,
      package_length_unit = source.package_length_unit,
      package_length_value = source.package_length_value,
      package_weight_unit = source.package_weight_unit,
      package_weight_value = source.package_weight_value,
      package_width_unit = source.package_width_unit,
      package_width_value = source.package_width_value,
      _fivetran_synced = source._fivetran_synced,
      is_active = TRUE,
      manufacture_day = dim.manufacture_day,
      shipment_days = dim.shipment_days,
      -- Preserve manually managed fields (never overwrite from Fivetran)
      package_quantity = dim.package_quantity,
      package_cubic_feet = dim.package_cubic_feet,
      product_short_name = COALESCE(dim.product_short_name, source.product_short_name),
      updated_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN
    -- Insert new products with auto-generated product_id
    INSERT (
      product_id,
      asin,
      parent_asin,
      parent_name,
      sku,
      marketplace,
      marketplace_name,
      marketplace_country_code,
      marketplace_default_currency_code,
      product_name,
      display_name,
      brand,
      manufacturer,
      product_type,
      color,
      launch_date,
      listing_price_currency_code,
      listing_price_amount,
      item_height_unit,
      item_height_value,
      item_length_unit,
      item_length_value,
      item_weight_unit,
      item_weight_value,
      item_width_unit,
      item_width_value,
      package_height_unit,
      package_height_value,
      package_length_unit,
      package_length_value,
      package_weight_unit,
      package_weight_value,
      package_width_unit,
      package_width_value,
      _fivetran_synced,
      is_active,
      manufacture_day,
      shipment_days,
      package_quantity,
      package_cubic_feet,
      product_short_name,
      created_at,
      updated_at
    )
    VALUES (
      source.product_id,
      source.asin,
      source.parent_asin,
      source.parent_name,
      source.sku,
      source.marketplace,
      source.marketplace_name,
      source.marketplace_country_code,
      source.marketplace_default_currency_code,
      source.product_name,
      source.display_name,
      source.brand,
      source.manufacturer,
      source.product_type,
      source.color,
      source.launch_date,
      source.listing_price_currency_code,
      source.listing_price_amount,
      source.item_height_unit,
      source.item_height_value,
      source.item_length_unit,
      source.item_length_value,
      source.item_weight_unit,
      source.item_weight_value,
      source.item_width_unit,
      source.item_width_value,
      source.package_height_unit,
      source.package_height_value,
      source.package_length_unit,
      source.package_length_value,
      source.package_weight_unit,
      source.package_weight_value,
      source.package_width_unit,
      source.package_width_value,
      source._fivetran_synced,
      TRUE, -- is_active
      NULL, -- manufacture_day (populated separately)
      NULL, -- shipment_days (populated separately)
      NULL, -- package_quantity (populated separately)
      NULL, -- package_cubic_feet (populated separately)
      source.product_short_name, -- product_short_name (initialized from color, managed manually)
      CURRENT_TIMESTAMP(), -- created_at
      CURRENT_TIMESTAMP()  -- updated_at
    );

  SET matched_count = @@row_count;

  -- Log the operation results
  SELECT FORMAT(
    'SP_MERGE_PRODUCT_DIM completed: MERGE affected %d rows (MATCHED/INSERTED), Duration: %d seconds',
    matched_count,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) as operation_summary;
END;
