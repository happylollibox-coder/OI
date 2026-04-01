-- =============================================
-- List inactive payment sources that can be safely deleted
-- =============================================
--
-- Purpose: Show all payment sources marked as is_active = FALSE
-- These have been verified to not exist in FACT_FINANCIAL_TRANSACTIONS
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

SELECT 
  payment_source,
  category,
  sub_category,
  IS_FUTURE_REOCCURING,
  is_active,
  created_at,
  updated_at
FROM `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY`
WHERE is_active = FALSE
ORDER BY updated_at DESC, payment_source;
