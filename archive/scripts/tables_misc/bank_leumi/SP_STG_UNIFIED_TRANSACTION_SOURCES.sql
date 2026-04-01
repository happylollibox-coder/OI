-- =============================================
-- OI Database Project - SP_STG_UNIFIED_TRANSACTION_SOURCES Stored Procedure
-- =============================================
--
-- Purpose: Manage staging table for unified transaction sources
-- Uses MERGE to preserve manual_effect_date values when refreshing from V_UNIFIED_TRANSACTION_SOURCES
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_STG_UNIFIED_TRANSACTION_SOURCES`()
OPTIONS (
  description = "Refresh staging table with latest unified transaction sources data, preserving manual_effect_date values"
)
BEGIN
  -- Declare variables for logging
  DECLARE matched_count INT64;
  DECLARE inserted_count INT64;
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- Use MERGE to preserve manual_effect_date values when refreshing from view
  -- Match on (source_system, source_transaction_id, transaction_date)
  MERGE `onyga-482313.OI.STG_UNIFIED_TRANSACTION_SOURCES` AS stg
  USING (
    SELECT
      transaction_date,
      amount,
      currency,
      transaction_description,
      transaction_type,
      source_system,
      source_transaction_id,
      account_name,
      source_metadata,
      processed_at,
      data_source_file
    FROM `onyga-482313.OI.V_UNIFIED_TRANSACTION_SOURCES`
  ) AS view_data
  ON stg.source_system = view_data.source_system
    AND stg.source_transaction_id = view_data.source_transaction_id
    AND stg.transaction_date = view_data.transaction_date
  WHEN MATCHED THEN
    -- Update all fields except manual_effect_date (preserve manual entries)
    UPDATE SET
      transaction_date = view_data.transaction_date,
      amount = view_data.amount,
      currency = view_data.currency,
      transaction_description = view_data.transaction_description,
      transaction_type = view_data.transaction_type,
      account_name = view_data.account_name,
      source_metadata = view_data.source_metadata,
      processed_at = view_data.processed_at,
      data_source_file = view_data.data_source_file
  WHEN NOT MATCHED THEN
    -- Insert new rows with manual_effect_date = NULL
    INSERT (
      transaction_date,
      amount,
      currency,
      transaction_description,
      transaction_type,
      source_system,
      source_transaction_id,
      account_name,
      source_metadata,
      processed_at,
      data_source_file,
      manual_effect_date
    )
    VALUES (
      view_data.transaction_date,
      view_data.amount,
      view_data.currency,
      view_data.transaction_description,
      view_data.transaction_type,
      view_data.source_system,
      view_data.source_transaction_id,
      view_data.account_name,
      view_data.source_metadata,
      view_data.processed_at,
      view_data.data_source_file,
      NULL  -- manual_effect_date set to NULL for new rows
    );

  SET matched_count = @@row_count;

  -- Log the operation results
  SELECT FORMAT(
    'STG_UNIFIED_TRANSACTION_SOURCES refresh completed: MERGE affected %d rows (MATCHED/INSERTED), Duration: %d seconds',
    matched_count,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) as operation_summary;
END;