-- =============================================
-- Check if inactive payment sources exist in FACT_FINANCIAL_TRANSACTIONS
-- =============================================
--
-- Purpose: Verify that payment sources marked as is_active = FALSE
-- do not actually exist in FACT_FINANCIAL_TRANSACTIONS
-- This helps determine if inactive rows can be safely deleted
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Check for inactive payment sources that still exist in FACT_FINANCIAL_TRANSACTIONS
SELECT 
  h.payment_source,
  h.category,
  h.sub_category,
  h.is_active,
  COUNT(DISTINCT CONCAT(fact.source_system, '|', fact.source_transaction_id, '|', CAST(fact.transaction_date AS STRING))) as transaction_count,
  MIN(fact.transaction_date) as earliest_transaction,
  MAX(fact.transaction_date) as latest_transaction
FROM `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY` h
INNER JOIN `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS` fact
  ON h.payment_source = fact.payment_source
WHERE h.is_active = FALSE
GROUP BY 
  h.payment_source,
  h.category,
  h.sub_category,
  h.is_active
ORDER BY transaction_count DESC;

-- Summary: Count of inactive payment sources
SELECT 
  COUNT(DISTINCT h.payment_source) as inactive_payment_sources_count,
  COUNT(DISTINCT CASE WHEN fact.payment_source IS NOT NULL THEN h.payment_source END) as inactive_but_still_in_fact_count
FROM `onyga-482313.OI.DIM_PAYMENT_SOURCE_HIERARCHY` h
LEFT JOIN `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS` fact
  ON h.payment_source = fact.payment_source
WHERE h.is_active = FALSE;
