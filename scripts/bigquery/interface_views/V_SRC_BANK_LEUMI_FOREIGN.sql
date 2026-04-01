-- =============================================
-- OI Database Project - V_SRC_BANK_LEUMI_FOREIGN
-- =============================================
--
-- Purpose: Bank Leumi Foreign Currency account transactions data
-- Business Logic: Standardizes Bank Leumi foreign currency transaction data from HTML export
-- Dependencies: Raw data loaded from GCS gs://happy-lolli-bucket-1/New/Leumi Foreign history 2023-2025.xls
-- Project: onyga-482313
-- Dataset: OI
-- Created: Based on Bank Leumi Foreign Currency HTML export format
--
-- =============================================

DROP VIEW IF EXISTS `onyga-482313.OI.V_SRC_BANK_LEUMI_FOREIGN`;
CREATE VIEW `onyga-482313.OI.V_SRC_BANK_LEUMI_FOREIGN` AS

SELECT
  -- Bank branch number (סניף)
  branch,

  -- Account number (חשבון)
  account,

  -- Currency code (מטבע)
  currency,

  -- Transaction date (תאריך)
  transaction_date,

  -- Transaction description in Hebrew (תיאור תנועה)
  transaction_description,

  -- Bank reference number (אסמכתא)
  reference_number,

  -- Debit amount in foreign currency (בחובה) - expenses/withdrawals
  debit_amount,

  -- Credit amount in foreign currency (בזכות) - income/deposits
  credit_amount,

  -- Running balance in foreign currency (יתרה במט"ח)
  balance_foreign,

  -- Extended transaction description (תיאור מורחב)
  extended_description,

  -- Additional notes (הערות)
  notes,

  -- Net transaction amount (positive for credits, negative for debits)
  CASE
    WHEN credit_amount IS NOT NULL AND credit_amount > 0 THEN credit_amount
    WHEN debit_amount IS NOT NULL AND debit_amount > 0 THEN -debit_amount
    ELSE 0
  END as net_amount_foreign,

  -- Transaction type classification
  CASE
    WHEN credit_amount IS NOT NULL AND credit_amount > 0 THEN 'CREDIT'
    WHEN debit_amount IS NOT NULL AND debit_amount > 0 THEN 'DEBIT'
    ELSE 'UNKNOWN'
  END as transaction_type,

  -- Extract year and month for analysis
  EXTRACT(YEAR FROM transaction_date) as transaction_year,
  EXTRACT(MONTH FROM transaction_date) as transaction_month,
  EXTRACT(DAY FROM transaction_date) as transaction_day

FROM `onyga-482313.OI.SRC_BANK_LEUMI_FOREIGN`

WHERE transaction_date IS NOT NULL
ORDER BY transaction_date DESC;
