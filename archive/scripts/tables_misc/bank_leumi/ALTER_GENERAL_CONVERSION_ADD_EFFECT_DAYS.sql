-- =============================================
-- Add effect_days_to_reduce column to GENERAL_CONVERSION table
-- =============================================
--
-- Purpose: Add effect_days_to_reduce column to existing GENERAL_CONVERSION table
-- This preserves existing data (unlike CREATE OR REPLACE TABLE)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Add effect_days_to_reduce column to GENERAL_CONVERSION table
-- First, drop the column if it exists (to fix any read-only issues)
ALTER TABLE `onyga-482313.OI.GENERAL_CONVERSION`
DROP COLUMN IF EXISTS effect_days_to_reduce;

-- Then add it fresh
ALTER TABLE `onyga-482313.OI.GENERAL_CONVERSION`
ADD COLUMN effect_days_to_reduce INT64;
