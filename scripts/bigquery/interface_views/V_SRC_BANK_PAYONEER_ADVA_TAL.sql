-- =============================================
-- OI Database Project - V_SRC_BANK_PAYONEER_ADVA_TAL
-- =============================================
--
-- Purpose: Payoneer payment transactions data for adva.tal account
-- Business Logic: Standardizes Payoneer transaction data with enhanced analytics fields
-- Dependencies: Raw data loaded from GCS gs://happy-lolli-bucket-1/New/report_2023-2025 adva.tal payoneer.csv
-- Project: onyga-482313
-- Dataset: OI
-- Created: Based on Payoneer CSV export format
--
-- =============================================

DROP VIEW IF EXISTS `onyga-482313.OI.V_SRC_BANK_PAYONEER_ADVA_TAL`;
CREATE VIEW `onyga-482313.OI.V_SRC_BANK_PAYONEER_ADVA_TAL` AS

SELECT
  -- Transaction date
  transaction_date,

  -- Transaction description
  description,

  -- Transaction amount (raw)
  amount,

  -- Currency
  currency,

  -- Transaction status
  status,

  -- Payoneer transaction ID
  transaction_id,

  -- Account name
  account_name,

  -- Transaction type classification
  CASE
    WHEN amount > 0 THEN 'INCOME'
    WHEN amount < 0 THEN 'PAYMENT'
    ELSE 'UNKNOWN'
  END as transaction_type,

  -- Net amount (absolute value for easier aggregation)
  ABS(amount) as net_amount,

  -- Payment direction
  CASE
    WHEN description LIKE '%Payment to%' THEN 'OUTGOING'
    WHEN description LIKE '%Payment from%' THEN 'INCOMING'
    ELSE 'UNKNOWN'
  END as payment_direction,

  -- Extract year and month for analysis
  EXTRACT(YEAR FROM transaction_date) as transaction_year,
  EXTRACT(MONTH FROM transaction_date) as transaction_month,
  EXTRACT(DAY FROM transaction_date) as transaction_day,

  -- Source information
  CASE
    WHEN description LIKE '%Amazon%' THEN 'AMAZON'
    WHEN description LIKE '%HAPPY LOLLI%' THEN 'HAPPY_LOLLI'
    ELSE 'OTHER'
  END as payment_source,

  -- Metadata
  processed_at,
  source_file

FROM `onyga-482313.OI.SRC_BANK_PAYONEER_ADVA_TAL`

WHERE transaction_date IS NOT NULL
ORDER BY transaction_date DESC;
