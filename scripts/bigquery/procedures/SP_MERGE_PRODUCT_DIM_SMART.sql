-- =============================================
-- OI Database Project - SP_MERGE_PRODUCT_DIM_SMART
-- =============================================
--
-- Purpose: Smart wrapper that only runs MERGE if source table has changed
-- Checks _fivetran_synced timestamp to detect changes
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_MERGE_PRODUCT_DIM_SMART`()
OPTIONS (
  description = "Smart wrapper for SP_MERGE_PRODUCT_DIM that only runs if source table has new/updated records"
)
BEGIN
  -- Declare variables
  DECLARE source_last_sync TIMESTAMP;
  DECLARE dim_last_sync TIMESTAMP;
  DECLARE has_changes BOOLEAN;
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- Get the latest _fivetran_synced timestamp from source table
  SET source_last_sync = (
    SELECT MAX(_fivetran_synced)
    FROM `fivetran-hl.amazon_selling_partner.item_summary`
    -- Note: _fivetran_deleted may not exist, adjust filter if needed
  );

  -- Get the latest _fivetran_synced timestamp from dimension table
  SET dim_last_sync = (
    SELECT MAX(_fivetran_synced)
    FROM `onyga-482313.OI.DIM_PRODUCT`
  );

  -- Check if source has newer data than dimension table
  SET has_changes = (
    source_last_sync IS NOT NULL 
    AND (dim_last_sync IS NULL OR source_last_sync > dim_last_sync)
  );

  -- Only run merge if there are changes
  IF has_changes THEN
    -- Call the actual merge procedure
    CALL `onyga-482313.OI.SP_MERGE_PRODUCT_DIM`();
    
    SELECT FORMAT(
      'SP_MERGE_PRODUCT_DIM_SMART: Changes detected (source: %s, dim: %s). MERGE executed. Duration: %d seconds',
      CAST(source_last_sync AS STRING),
      CAST(COALESCE(dim_last_sync, TIMESTAMP('1970-01-01')) AS STRING),
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
    ) as operation_summary;
  ELSE
    SELECT FORMAT(
      'SP_MERGE_PRODUCT_DIM_SMART: No changes detected (source: %s, dim: %s). MERGE skipped. Duration: %d seconds',
      CAST(COALESCE(source_last_sync, TIMESTAMP('1970-01-01')) AS STRING),
      CAST(COALESCE(dim_last_sync, TIMESTAMP('1970-01-01')) AS STRING),
      TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
    ) as operation_summary;
  END IF;
END;
