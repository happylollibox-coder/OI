-- =============================================
-- Delete inactive payment sources from DIM_PAYMENT_SOURCE_HIERARCHY
-- =============================================
--
-- Purpose: Remove payment sources marked as is_active = FALSE
-- These have been verified to not exist in FACT_FINANCIAL_TRANSACTIONS
-- 
-- WARNING: This will permanently delete these rows from the table
-- Make sure to review LIST_INACTIVE_PAYMENT_SOURCES.sql first
-- 
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Delete inactive payment sources
DELETE FROM `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
WHERE is_active = FALSE;
