-- =============================================
-- Add date key columns to FACT_FINANCIAL_TRANSACTIONS
-- =============================================

-- Add transaction_date_key column
ALTER TABLE `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`
ADD COLUMN IF NOT EXISTS transaction_date_key INT64;

-- Add effect_date_key column
ALTER TABLE `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`
ADD COLUMN IF NOT EXISTS effect_date_key INT64;
