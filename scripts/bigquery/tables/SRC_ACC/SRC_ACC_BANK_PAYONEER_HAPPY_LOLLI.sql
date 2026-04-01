-- =============================================
-- OI Database Project - SRC_ACC_BANK_PAYONEER_HAPPY_LOLLI Table
-- =============================================
--
-- Purpose: Accumulation table for Payoneer Happy Lolli transactions
-- Same schema as SRC_BANK_PAYONEER_HAPPY_LOLLI plus insert_date, insert_file_name
-- Populated by hot-folder processor from SRC_BANK_PAYONEER_HAPPY_LOLLI
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.SRC_ACC_BANK_PAYONEER_HAPPY_LOLLI` (
  transaction_date DATE,
  description STRING,
  amount FLOAT64,
  currency STRING,
  status STRING,
  running_balance FLOAT64,
  transaction_id STRING,
  processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  source_file STRING,
  account_name STRING DEFAULT 'happy_lolli',
  insert_date TIMESTAMP NOT NULL,
  insert_file_name STRING NOT NULL
)
PARTITION BY DATE(transaction_date)
CLUSTER BY transaction_date, status
OPTIONS (
  description = "Accumulation table for Payoneer Happy Lolli. Populated by hot-folder from SRC_BANK_PAYONEER_HAPPY_LOLLI."
);
