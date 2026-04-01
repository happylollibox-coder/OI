-- =============================================
-- OI Database Project - UNCATEGORIZED_TRANSACTIONS_REVIEW Table
-- =============================================
--
-- Purpose: Review table for uncategorized transactions
-- Allows manual categorization of transactions before creating rules
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Create the review table for uncategorized transactions
CREATE OR REPLACE TABLE `onyga-482313.OI.UNCATEGORIZED_TRANSACTIONS_REVIEW` (
  review_id INT64,
  source_system STRING,
  transaction_pattern STRING,
  example_description STRING,
  transaction_count INT64,
  total_amount FLOAT64,
  avg_amount FLOAT64,
  suggested_category STRING,
  suggested_subcategory STRING,
  target_subcategory_id INT64,
  status STRING DEFAULT 'PENDING', -- PENDING, REVIEWED, APPROVED
  notes STRING,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY source_system, status;