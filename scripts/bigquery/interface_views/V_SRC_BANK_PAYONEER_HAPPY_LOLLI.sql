-- =============================================
-- OI Database Project - V_SRC_BANK_PAYONEER_HAPPY_LOLLI
-- =============================================
--
-- Purpose: Payoneer payment transactions data for happy lolli account
-- Business Logic: Standardizes Payoneer transaction data with enhanced analytics fields
-- Dependencies: Raw data loaded from GCS gs://happy-lolli-bucket-1/New/report_2023-2025 happy lolli payoneer.csv
-- Project: onyga-482313
-- Dataset: OI
-- Created: Based on Payoneer CSV export format
--
-- =============================================

DROP VIEW IF EXISTS `onyga-482313.OI.V_SRC_BANK_PAYONEER_HAPPY_LOLLI`;
CREATE VIEW `onyga-482313.OI.V_SRC_BANK_PAYONEER_HAPPY_LOLLI` AS

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
    WHEN description LIKE '%Card charge%' THEN 'OUTGOING'
    ELSE 'UNKNOWN'
  END as payment_direction,

  -- Extract year and month for analysis
  EXTRACT(YEAR FROM transaction_date) as transaction_year,
  EXTRACT(MONTH FROM transaction_date) as transaction_month,
  EXTRACT(DAY FROM transaction_date) as transaction_day,

  -- Source information
  CASE
    WHEN description LIKE '%adva tal%' THEN 'ADVA_TAL'
    WHEN description LIKE '%AMAZON%' THEN 'AMAZON'
    WHEN description LIKE '%GOOGLE%' THEN 'GOOGLE_ADS'
    WHEN description LIKE '%HELIUM10%' THEN 'HELIUM10'
    WHEN description LIKE '%SYLVIA%' THEN 'SYLVIA'
    ELSE 'OTHER'
  END as payment_source,

  -- Category classification
  CASE
    WHEN description LIKE '%Card charge%' THEN 'CARD_PAYMENT'
    WHEN description LIKE '%Payment to%' THEN 'TRANSFER_OUT'
    WHEN description LIKE '%Payment from%' THEN 'TRANSFER_IN'
    ELSE 'OTHER'
  END as transaction_category

FROM `onyga-482313.OI.SRC_BANK_PAYONEER_HAPPY_LOLLI`

WHERE transaction_date IS NOT NULL
ORDER BY transaction_date DESC;
