-- =============================================
-- Add factless_key column to fact tables
-- =============================================

-- Add factless_key to FACT_FACTLESS_BRIDGE
ALTER TABLE `onyga-482313.OI.FACT_FACTLESS_BRIDGE`
ADD COLUMN IF NOT EXISTS factless_key STRING;

-- Add factless_key to FACT_INVENTORY_SNAPSHOT
ALTER TABLE `onyga-482313.OI.FACT_INVENTORY_SNAPSHOT`
ADD COLUMN IF NOT EXISTS factless_key STRING;

-- Add factless_key to FACT_PURCHASE_ORDER
ALTER TABLE `onyga-482313.OI.FACT_PURCHASE_ORDER`
ADD COLUMN IF NOT EXISTS factless_key STRING;

-- Add factless_key to FACT_FINANCIAL_TRANSACTIONS
ALTER TABLE `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`
ADD COLUMN IF NOT EXISTS factless_key STRING;
