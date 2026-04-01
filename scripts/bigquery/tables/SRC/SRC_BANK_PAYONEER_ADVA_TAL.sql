-- =============================================
-- OI Database Project - SRC_BANK_PAYONEER_ADVA_TAL Table Creation
-- =============================================
--
-- Purpose: Create and load Payoneer payment data for adva.tal account
-- Source: gs://happy-lolli-bucket-1/New/report_2023-2025 adva.tal payoneer.csv
-- Processing: Direct CSV import with data type conversions
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Create the table with proper schema
CREATE OR REPLACE TABLE `onyga-482313.OI.SRC_BANK_PAYONEER_ADVA_TAL` (
  -- Transaction date (Date format: DD MMM, YYYY)
  transaction_date DATE,

  -- Transaction description
  description STRING,

  -- Transaction amount (positive for income, negative for payments)
  amount FLOAT64,

  -- Currency code
  currency STRING,

  -- Transaction status
  status STRING,

  -- Running balance
  running_balance FLOAT64,

  -- Payoneer transaction ID
  transaction_id STRING,

  -- Metadata
  processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  source_file STRING,

  -- Account identifier (derived from filename)
  account_name STRING DEFAULT 'adva.tal'
)
PARTITION BY DATE(transaction_date)
CLUSTER BY transaction_date, status
OPTIONS (
  description = "Payoneer payment transactions for adva.tal account (2023-2025)"
);

-- =============================================
-- DATA LOADING INSTRUCTIONS
-- =============================================
--
-- 1. The CSV file is already in the correct format for BigQuery loading
-- 2. Load data directly from GCS:
--    bq load --source_format=CSV \
--      --skip_leading_rows=1 \
--      --project_id=onyga-482313 \
--      --allow_quoted_newlines \
--      onyga-482313:OI.SRC_BANK_PAYONEER_ADVA_TAL \
--      gs://happy-lolli-bucket-1/New/report_2023-2025\ adva.tal\ payoneer.csv \
--      transaction_date:DATE,description:STRING,amount:FLOAT64,currency:STRING,status:STRING,running_balance:FLOAT64,transaction_id:STRING
--
-- Note: Date format in CSV is "DD MMM, YYYY" but BigQuery auto-detects this format
-- =============================================
