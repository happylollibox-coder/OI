-- =============================================
-- Add manual_effect_date column to STG_UNIFIED_TRANSACTION_SOURCES table
-- =============================================
--
-- Purpose: Add manual_effect_date column to existing STG_UNIFIED_TRANSACTION_SOURCES table
-- This preserves existing data (unlike CREATE OR REPLACE TABLE)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Add manual_effect_date column to STG_UNIFIED_TRANSACTION_SOURCES table
ALTER TABLE `onyga-482313.OI.STG_UNIFIED_TRANSACTION_SOURCES`
ADD COLUMN IF NOT EXISTS manual_effect_date DATE OPTIONS(description="Manually entered date override (nullable, for manual entry)");
