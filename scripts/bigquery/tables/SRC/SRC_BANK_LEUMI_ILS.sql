-- =============================================
-- OI Database Project - SRC_BANK_LEUMI_ILS Table Creation
-- =============================================
--
-- Purpose: Create and load Bank Leumi ILS transaction data table
-- Source: gs://happy-lolli-bucket-1/New/Leumi ils history 2023-2025.xls
-- Processing: HTML file parsed to CSV using parse_leumi_html.py
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Create the table with proper schema
CREATE OR REPLACE TABLE `onyga-482313.OI.SRC_BANK_LEUMI_ILS` (
  -- Bank branch number
  branch INT64,

  -- Account number (including branch suffix)
  account STRING,

  -- Transaction date
  transaction_date DATE,

  -- Transaction description in Hebrew
  transaction_description STRING,

  -- Bank reference number
  reference_number STRING,

  -- Debit amount in ILS (expenses/withdrawals)
  debit_amount FLOAT64,

  -- Credit amount in ILS (income/deposits)
  credit_amount FLOAT64,

  -- Running balance in ILS
  balance_ils FLOAT64,

  -- Extended transaction description
  extended_description STRING,

  -- Additional notes
  notes STRING,

  -- Metadata
  processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  source_file STRING
)
PARTITION BY DATE(transaction_date)
CLUSTER BY account, transaction_date
OPTIONS (
  description = "Bank Leumi ILS account transactions from HTML export (2023-2025)"
);

-- =============================================
-- DATA LOADING INSTRUCTIONS
-- =============================================
--
-- 1. Download the HTML file from GCS:
--    gsutil cp gs://happy-lolli-bucket-1/New/Leumi\ ils\ history\ 2023-2025.xls /tmp/
--
-- 2. Parse HTML to CSV using the Python script:
--    python3 archive/scripts/tables_misc/bank_leumi/parse_leumi_html.py \
--      /tmp/Leumi\ ils\ history\ 2023-2025.xls \
--      /tmp/leumi_ils_transactions.csv
--
-- 3. Upload CSV to GCS staging area:
--    gsutil cp /tmp/leumi_ils_transactions.csv gs://happy-lolli-bucket-1/staging/
--
-- 4. Load data into BigQuery table:
--    bq load --source_format=CSV \
--      --skip_leading_rows=1 \
--      onyga-482313:OI.SRC_BANK_LEUMI_ILS \
--      gs://happy-lolli-bucket-1/staging/leumi_ils_transactions.csv \
--      branch:INT64,account:STRING,transaction_date:DATE,transaction_description:STRING,\
--      reference_number:STRING,debit_amount:FLOAT64,credit_amount:FLOAT64,\
--      balance_ils:FLOAT64,extended_description:STRING,notes:STRING
--
-- =============================================
