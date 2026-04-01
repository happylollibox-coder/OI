-- =============================================
-- Rename date key columns in FACT_FINANCIAL_TRANSACTIONS
-- =============================================

-- Drop old columns
ALTER TABLE `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`
DROP COLUMN IF EXISTS transaction_date_key;

ALTER TABLE `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`
DROP COLUMN IF EXISTS effect_date_key;

-- Add new columns with new names and STRING type
ALTER TABLE `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`
ADD COLUMN IF NOT EXISTS factless_transaction_key STRING;

ALTER TABLE `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`
ADD COLUMN IF NOT EXISTS factless_effect_key STRING;
