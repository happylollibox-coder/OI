-- =============================================
-- OI Database Project - STG_UNIFIED_TRANSACTION_SOURCES Table
-- =============================================
--
-- Purpose: Staging table for unified transaction sources
-- Holds processed transaction data before categorization into FACT table
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Create the staging table for unified transaction sources
CREATE OR REPLACE TABLE `onyga-482313.OI.STG_UNIFIED_TRANSACTION_SOURCES` (
  -- Core Transaction Fields
  transaction_date DATE NOT NULL,
  amount FLOAT64 NOT NULL,
  currency STRING,
  transaction_description STRING,
  transaction_type STRING,

  -- Source Identification
  source_system STRING NOT NULL,
  source_transaction_id STRING NOT NULL,
  account_name STRING,

  -- Source-Specific Metadata (JSON for flexibility)
  source_metadata JSON,

  -- Technical Fields
  processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  data_source_file STRING,

  -- Manual Date Override (for accrual accounting)
  manual_effect_date DATE, -- Manually entered date override (nullable, for manual entry)

  -- Deduplication key (combination that should be unique)
  PRIMARY KEY (source_system, source_transaction_id, transaction_date) NOT ENFORCED
)
PARTITION BY transaction_date
CLUSTER BY source_system, account_name;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This staging table serves as an intermediate step between raw source data
-- and the final categorized fact table. It provides:
--
-- - Clean, standardized data from all sources
-- - Deduplication based on source key
-- - Ready for categorization processing
-- - Audit trail of processing timestamps
--
-- The SP_STG_UNIFIED_TRANSACTION_SOURCES procedure manages this table.
--
-- =============================================