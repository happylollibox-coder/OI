-- =============================================
-- Add running_balance column to Payoneer tables
-- =============================================

-- Add running_balance to SRC_BANK_PAYONEER_HAPPY_LOLLI
ALTER TABLE `onyga-482313.OI.SRC_BANK_PAYONEER_HAPPY_LOLLI`
ADD COLUMN IF NOT EXISTS running_balance FLOAT64 
OPTIONS(description="Running balance after transaction");

-- Add running_balance to SRC_BANK_PAYONEER_ADVA_TAL
ALTER TABLE `onyga-482313.OI.SRC_BANK_PAYONEER_ADVA_TAL`
ADD COLUMN IF NOT EXISTS running_balance FLOAT64 
OPTIONS(description="Running balance after transaction");
