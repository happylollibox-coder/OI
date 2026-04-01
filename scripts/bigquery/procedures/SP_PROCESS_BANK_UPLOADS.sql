-- =============================================
-- OI Database Project - SP_PROCESS_BANK_UPLOADS Stored Procedure
-- =============================================
--
-- Purpose: Process bank transaction uploads from SRC tables to SRC_ACC tables
-- Uses MERGE to prevent duplicates in accumulated tables
-- Truncates SRC tables after successful processing
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_PROCESS_BANK_UPLOADS`()
OPTIONS (
  description = "Process bank uploads: MERGE from SRC to SRC_ACC, then truncate SRC tables"
)
BEGIN
  -- Declare variables for logging
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;
  DECLARE leumi_foreign_merged INT64 DEFAULT 0;
  DECLARE leumi_ils_merged INT64 DEFAULT 0;
  DECLARE payoneer_happy_merged INT64 DEFAULT 0;
  DECLARE tables_processed INT64 DEFAULT 0;

  SET start_time = CURRENT_TIMESTAMP();

  -- ============================================
  -- Process SRC_BANK_LEUMI_FOREIGN → SRC_ACC_BANK_LEUMI_FOREIGN
  -- ============================================

  IF EXISTS (SELECT 1 FROM `onyga-482313.OI.SRC_BANK_LEUMI_FOREIGN` LIMIT 1) THEN
    -- MERGE: Insert only if transaction doesn't already exist
    -- Natural key: account, transaction_date, reference_number, debit_amount, credit_amount, transaction_description
    MERGE `onyga-482313.OI.SRC_ACC_BANK_LEUMI_FOREIGN` AS target
    USING (
      SELECT DISTINCT
        branch,
        account,
        currency,
        transaction_date,
        transaction_description,
        reference_number,
        debit_amount,
        credit_amount,
        balance_foreign,
        extended_description,
        notes
      FROM `onyga-482313.OI.SRC_BANK_LEUMI_FOREIGN`
      WHERE transaction_date IS NOT NULL
        AND account IS NOT NULL
    ) AS source
    ON target.account = source.account
       AND target.transaction_date = source.transaction_date
       AND target.reference_number = source.reference_number
       AND COALESCE(CAST(target.debit_amount AS STRING), 'NULL') = COALESCE(CAST(source.debit_amount AS STRING), 'NULL')
       AND COALESCE(CAST(target.credit_amount AS STRING), 'NULL') = COALESCE(CAST(source.credit_amount AS STRING), 'NULL')
       AND target.transaction_description = source.transaction_description
    WHEN NOT MATCHED THEN
      INSERT (
        branch,
        account,
        currency,
        transaction_date,
        transaction_description,
        reference_number,
        debit_amount,
        credit_amount,
        balance_foreign,
        extended_description,
        notes,
        insert_date,
        insert_file_name
      )
      VALUES (
        source.branch,
        source.account,
        source.currency,
        source.transaction_date,
        source.transaction_description,
        source.reference_number,
        source.debit_amount,
        source.credit_amount,
        source.balance_foreign,
        source.extended_description,
        source.notes,
        CURRENT_TIMESTAMP(),
        'manual_upload'
      );

    SET leumi_foreign_merged = @@row_count;

    -- Truncate SRC table after successful processing
    TRUNCATE TABLE `onyga-482313.OI.SRC_BANK_LEUMI_FOREIGN`;

    SET tables_processed = tables_processed + 1;
  END IF;

  -- ============================================
  -- Process SRC_BANK_LEUMI_ILS → SRC_ACC_BANK_LEUMI_ILS
  -- ============================================

  IF EXISTS (SELECT 1 FROM `onyga-482313.OI.SRC_BANK_LEUMI_ILS` LIMIT 1) THEN
    -- MERGE: Insert only if transaction doesn't already exist
    -- Natural key: account, transaction_date, reference_number, debit_amount, credit_amount, transaction_description
    MERGE `onyga-482313.OI.SRC_ACC_BANK_LEUMI_ILS` AS target
    USING (
      SELECT DISTINCT
        branch,
        account,
        transaction_date,
        transaction_description,
        reference_number,
        debit_amount,
        credit_amount,
        balance_ils,
        extended_description,
        notes
      FROM `onyga-482313.OI.SRC_BANK_LEUMI_ILS`
      WHERE transaction_date IS NOT NULL
        AND account IS NOT NULL
    ) AS source
    ON target.account = source.account
       AND target.transaction_date = source.transaction_date
       AND target.reference_number = source.reference_number
       AND COALESCE(CAST(target.debit_amount AS STRING), 'NULL') = COALESCE(CAST(source.debit_amount AS STRING), 'NULL')
       AND COALESCE(CAST(target.credit_amount AS STRING), 'NULL') = COALESCE(CAST(source.credit_amount AS STRING), 'NULL')
       AND target.transaction_description = source.transaction_description
    WHEN NOT MATCHED THEN
      INSERT (
        branch,
        account,
        transaction_date,
        transaction_description,
        reference_number,
        debit_amount,
        credit_amount,
        balance_ils,
        extended_description,
        notes,
        insert_date,
        insert_file_name
      )
      VALUES (
        source.branch,
        source.account,
        source.transaction_date,
        source.transaction_description,
        source.reference_number,
        source.debit_amount,
        source.credit_amount,
        source.balance_ils,
        source.extended_description,
        source.notes,
        CURRENT_TIMESTAMP(),
        'manual_upload'
      );

    SET leumi_ils_merged = @@row_count;

    -- Truncate SRC table after successful processing
    TRUNCATE TABLE `onyga-482313.OI.SRC_BANK_LEUMI_ILS`;

    SET tables_processed = tables_processed + 1;
  END IF;

  -- ============================================
  -- Process SRC_BANK_PAYONEER_HAPPY_LOLLI → SRC_ACC_BANK_PAYONEER_HAPPY_LOLLI
  -- ============================================

  IF EXISTS (SELECT 1 FROM `onyga-482313.OI.SRC_BANK_PAYONEER_HAPPY_LOLLI` LIMIT 1) THEN
    -- MERGE: Insert only if transaction doesn't already exist
    -- Natural key: transaction_id (should be unique), or transaction_date + description + amount
    MERGE `onyga-482313.OI.SRC_ACC_BANK_PAYONEER_HAPPY_LOLLI` AS target
    USING (
      SELECT DISTINCT
        transaction_date,
        description,
        amount,
        currency,
        status,
        transaction_id
      FROM `onyga-482313.OI.SRC_BANK_PAYONEER_HAPPY_LOLLI`
      WHERE transaction_date IS NOT NULL
        AND transaction_id IS NOT NULL
    ) AS source
    ON target.transaction_id = source.transaction_id
       OR (
         target.transaction_date = source.transaction_date
         AND target.description = source.description
         AND COALESCE(CAST(target.amount AS STRING), 'NULL') = COALESCE(CAST(source.amount AS STRING), 'NULL')
         AND target.currency = source.currency
       )
    WHEN NOT MATCHED THEN
      INSERT (
        transaction_date,
        description,
        amount,
        currency,
        status,
        transaction_id,
        insert_date,
        insert_file_name
      )
      VALUES (
        source.transaction_date,
        source.description,
        source.amount,
        source.currency,
        source.status,
        source.transaction_id,
        CURRENT_TIMESTAMP(),
        'manual_upload'
      );

    SET payoneer_happy_merged = @@row_count;

    -- Truncate SRC table after successful processing
    TRUNCATE TABLE `onyga-482313.OI.SRC_BANK_PAYONEER_HAPPY_LOLLI`;

    SET tables_processed = tables_processed + 1;
  END IF;

  SET end_time = CURRENT_TIMESTAMP();

  -- Log the operation results
  SELECT FORMAT(
    'SP_PROCESS_BANK_UPLOADS completed:\n' ||
    '  BANK_LEUMI_FOREIGN: Merged %d rows (duplicates prevented by natural key)\n' ||
    '  BANK_LEUMI_ILS: Merged %d rows (duplicates prevented by natural key)\n' ||
    '  PAYONEER_HAPPY_LOLLI: Merged %d rows (duplicates prevented by transaction_id)\n' ||
    '  Total tables processed: %d\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    leumi_foreign_merged,
    leumi_ils_merged,
    payoneer_happy_merged,
    tables_processed,
    TIMESTAMP_DIFF(end_time, start_time, SECOND),
    CAST(end_time AS STRING)
  ) as operation_summary;
END;
