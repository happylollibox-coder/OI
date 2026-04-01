-- =============================================
-- Rename IS_REOCCURING column to IS_FUTURE_REOCCURING in DIM_PAYMENT_SOURCE_HIERARCHY table
-- =============================================
--
-- Purpose: Rename IS_REOCCURING column to IS_FUTURE_REOCCURING
-- This preserves existing data (unlike CREATE OR REPLACE TABLE)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Rename IS_REOCCURING column to IS_FUTURE_REOCCURING
ALTER TABLE `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
RENAME COLUMN IS_REOCCURING TO IS_FUTURE_REOCCURING;
