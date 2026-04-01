-- =============================================
-- OI Database Project - SP_UPDATE_FBA_INVENTORY_MONTHLY_SNAPSHOT
-- =============================================
--
-- Purpose: Update monthly snapshot of FBA inventory summary
-- Only updates current month, inserts new month when month changes
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_UPDATE_FBA_INVENTORY_MONTHLY_SNAPSHOT`()
OPTIONS (
  description = "Update monthly snapshot of FBA inventory summary. Only updates current month, inserts new month when month changes. Filters by granularity_id = 'ATVPDKIKX0DER' and joins to DIM_PRODUCT."
)
BEGIN
  -- Declare variables
  DECLARE current_month_str STRING;
  DECLARE current_year INT64;
  DECLARE current_month_num INT64;
  DECLARE total_affected INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();
  
  -- Get current month information
  SET current_year = EXTRACT(YEAR FROM CURRENT_DATE());
  SET current_month_num = EXTRACT(MONTH FROM CURRENT_DATE());
  SET current_month_str = FORMAT_DATE('%Y-%m', CURRENT_DATE());

  -- MERGE: Update current month, insert if new month
  MERGE `onyga-482313.OI.STG_FBA_INVENTORY_MONTHLY_SNAPSHOT` AS stg
  USING (
    SELECT
      -- Month identifiers
      FORMAT_DATE('%Y-%m', CURRENT_DATE()) as snapshot_month,
      EXTRACT(YEAR FROM CURRENT_DATE()) as snapshot_year,
      EXTRACT(MONTH FROM CURRENT_DATE()) as snapshot_month_num,
      
      -- Product dimension join
      dim.product_id,
      
      -- Product identifiers
      inv.asin,
      inv.fnsku,
      inv.seller_sku,
      
      -- Inventory fields from source (adjust field names based on actual schema)
      -- These are common FBA inventory fields - adjust as needed
      inv.product_name,
      inv.condition_type,
      inv.warehouse_condition_code,
      inv.quantity_available,
      inv.quantity_reserved,
      inv.quantity_unfulfillable,
      inv.quantity_total,
      inv.inbound_quantity,
      inv.inbound_working,
      inv.inbound_shipped,
      inv.inbound_receiving,
      inv.reserved_fc_transfers,
      inv.reserved_fc_processing,
      inv.reserved_customer_orders,
      inv.unfulfillable_quantity,
      inv.unfulfillable_customer_damage,
      inv.unfulfillable_warehouse_damage,
      inv.unfulfillable_distributor_damage,
      inv.unfulfillable_carrier_damage,
      inv.unfulfillable_defective,
      inv.unfulfillable_expired,
      
      -- Source metadata
      inv.granularity_id,
      CURRENT_DATE() as snapshot_date
      
    FROM `fivetran-hl.amazon_selling_partner.fba_inventory_summary` inv
    LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` dim
      ON inv.asin = dim.asin
    WHERE inv.granularity_id = 'ATVPDKIKX0DER'
      AND inv.asin IS NOT NULL
  ) AS source
  ON (
    stg.snapshot_month = source.snapshot_month
    AND stg.asin = source.asin
    AND COALESCE(stg.fnsku, '') = COALESCE(source.fnsku, '')
  )
  WHEN MATCHED AND stg.snapshot_month = current_month_str THEN
    -- Only update if it's the current month (previous months are frozen)
    UPDATE SET
      product_id = source.product_id,
      seller_sku = source.seller_sku,
      product_name = source.product_name,
      condition_type = source.condition_type,
      warehouse_condition_code = source.warehouse_condition_code,
      quantity_available = source.quantity_available,
      quantity_reserved = source.quantity_reserved,
      quantity_unfulfillable = source.quantity_unfulfillable,
      quantity_total = source.quantity_total,
      inbound_quantity = source.inbound_quantity,
      inbound_working = source.inbound_working,
      inbound_shipped = source.inbound_shipped,
      inbound_receiving = source.inbound_receiving,
      reserved_fc_transfers = source.reserved_fc_transfers,
      reserved_fc_processing = source.reserved_fc_processing,
      reserved_customer_orders = source.reserved_customer_orders,
      unfulfillable_quantity = source.unfulfillable_quantity,
      unfulfillable_customer_damage = source.unfulfillable_customer_damage,
      unfulfillable_warehouse_damage = source.unfulfillable_warehouse_damage,
      unfulfillable_distributor_damage = source.unfulfillable_distributor_damage,
      unfulfillable_carrier_damage = source.unfulfillable_carrier_damage,
      unfulfillable_defective = source.unfulfillable_defective,
      unfulfillable_expired = source.unfulfillable_expired,
      granularity_id = source.granularity_id,
      snapshot_date = source.snapshot_date,
      updated_at = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN
    -- Insert new records (for new month or new products)
    INSERT (
      snapshot_month,
      snapshot_year,
      snapshot_month_num,
      product_id,
      asin,
      fnsku,
      seller_sku,
      product_name,
      condition_type,
      warehouse_condition_code,
      quantity_available,
      quantity_reserved,
      quantity_unfulfillable,
      quantity_total,
      inbound_quantity,
      inbound_working,
      inbound_shipped,
      inbound_receiving,
      reserved_fc_transfers,
      reserved_fc_processing,
      reserved_customer_orders,
      unfulfillable_quantity,
      unfulfillable_customer_damage,
      unfulfillable_warehouse_damage,
      unfulfillable_distributor_damage,
      unfulfillable_carrier_damage,
      unfulfillable_defective,
      unfulfillable_expired,
      granularity_id,
      snapshot_date,
      created_at,
      updated_at
    )
    VALUES (
      source.snapshot_month,
      source.snapshot_year,
      source.snapshot_month_num,
      source.product_id,
      source.asin,
      source.fnsku,
      source.seller_sku,
      source.product_name,
      source.condition_type,
      source.warehouse_condition_code,
      source.quantity_available,
      source.quantity_reserved,
      source.quantity_unfulfillable,
      source.quantity_total,
      source.inbound_quantity,
      source.inbound_working,
      source.inbound_shipped,
      source.inbound_receiving,
      source.reserved_fc_transfers,
      source.reserved_fc_processing,
      source.reserved_customer_orders,
      source.unfulfillable_quantity,
      source.unfulfillable_customer_damage,
      source.unfulfillable_warehouse_damage,
      source.unfulfillable_distributor_damage,
      source.unfulfillable_carrier_damage,
      source.unfulfillable_defective,
      source.unfulfillable_expired,
      source.granularity_id,
      source.snapshot_date,
      CURRENT_TIMESTAMP(),
      CURRENT_TIMESTAMP()
    );

  SET total_affected = @@row_count;
  SET end_time = CURRENT_TIMESTAMP();

  -- Log the operation results
  SELECT FORMAT(
    'SP_UPDATE_FBA_INVENTORY_MONTHLY_SNAPSHOT completed:\n' ||
    '  Snapshot Month: %s\n' ||
    '  Total rows affected: %d\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    current_month_str,
    total_affected,
    TIMESTAMP_DIFF(end_time, start_time, SECOND),
    CAST(end_time AS STRING)
  ) as operation_summary;
END;
