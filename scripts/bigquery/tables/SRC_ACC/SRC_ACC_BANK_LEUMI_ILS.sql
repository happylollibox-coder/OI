-- =============================================
-- OI Database Project - SRC_ACC_BANK_LEUMI_ILS Table
-- =============================================
--
-- Purpose: Accumulation table for Bank Leumi ILS transactions
-- Same schema as SRC_BANK_LEUMI_ILS plus insert_date, insert_file_name
-- Populated by hot-folder processor from SRC_BANK_LEUMI_ILS
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.SRC_ACC_BANK_LEUMI_ILS` (
  branch INT64,
  account STRING,
  transaction_date DATE,
  transaction_description STRING,
  reference_number STRING,
  debit_amount FLOAT64,
  credit_amount FLOAT64,
  balance_ils FLOAT64,
  extended_description STRING,
  notes STRING,
  processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  source_file STRING,
  insert_date TIMESTAMP NOT NULL,
  insert_file_name STRING NOT NULL
)
PARTITION BY DATE(transaction_date)
CLUSTER BY account, transaction_date
OPTIONS (
  description = "Accumulation table for Bank Leumi ILS. Populated by hot-folder from SRC_BANK_LEUMI_ILS."
);
