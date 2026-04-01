-- =============================================
-- Add IS_REOCCURING column to DIM_PAYMENT_SOURCE_HIERARCHY table
-- =============================================
--
-- Purpose: Add IS_REOCCURING column to existing DIM_PAYMENT_SOURCE_HIERARCHY table
-- This preserves existing data (unlike CREATE OR REPLACE TABLE)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Add IS_REOCCURING column to DIM_PAYMENT_SOURCE_HIERARCHY table
ALTER TABLE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
ADD COLUMN IF NOT EXISTS IS_REOCCURING BOOL OPTIONS(description="Indicates if the payment source is recurring");

-- Set all existing rows to TRUE
UPDATE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
SET IS_REOCCURING = TRUE
WHERE IS_REOCCURING IS NULL;
