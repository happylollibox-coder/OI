-- =============================================
-- Add effect_date column to FACT_FINANCIAL_TRANSACTIONS table
-- =============================================
--
-- Purpose: Add effect_date column to existing FACT_FINANCIAL_TRANSACTIONS table
-- This preserves existing data (unlike CREATE OR REPLACE TABLE)
-- Note: revenue_period_date column will remain but won't be populated by SP
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Add effect_date column to FACT_FINANCIAL_TRANSACTIONS table
ALTER TABLE `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`
ADD COLUMN IF NOT EXISTS effect_date DATE OPTIONS(description="Date to use for reporting (manual_effect_date if provided, else transaction_date - effect_days_to_reduce, else transaction_date)");
