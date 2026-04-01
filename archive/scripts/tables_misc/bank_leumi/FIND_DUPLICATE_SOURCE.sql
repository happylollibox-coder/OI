-- =============================================
-- Find Duplicate Source Values
-- =============================================
-- This query identifies which values are causing duplicates in FACT_FINANCIAL_TRANSACTIONS
--
-- Issue: Multiple categorization rules match the same transaction,
--        causing the JOIN to create duplicate rows
-- =============================================

-- 1. Show transactions that have duplicates in FACT
SELECT 
  source_system, 
  source_transaction_id, 
  transaction_date, 
  amount, 
  transaction_description,
  COUNT(*) as duplicate_count
FROM `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`
GROUP BY 
  source_system, 
  source_transaction_id, 
  transaction_date, 
  amount, 
  transaction_description
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC
LIMIT 20;

-- 2. Show transaction descriptions that match multiple categorization rules
SELECT 
  stg.source_system, 
  stg.transaction_description,
  COUNT(DISTINCT r.rule_id) as matching_rules,
  STRING_AGG(DISTINCT CAST(r.rule_id AS STRING), ', ' ORDER BY CAST(r.rule_id AS STRING)) as rule_ids
FROM `onyga-482313.OI.STG_UNIFIED_TRANSACTION_SOURCES` stg
LEFT JOIN `onyga-482313.OI.CFG_TRANSACTION_CATEGORIZATION_RULES` r
  ON (r.source_system_filter IS NULL OR r.source_system_filter = stg.source_system)
  AND (r.description_pattern IS NULL OR REGEXP_CONTAINS(stg.transaction_description, r.description_pattern))
  AND (r.amount_min IS NULL OR stg.amount >= r.amount_min)
  AND (r.amount_max IS NULL OR stg.amount <= r.amount_max)
  AND (r.currency_filter IS NULL OR r.currency_filter = stg.currency)
  AND r.is_active = TRUE
GROUP BY stg.source_system, stg.transaction_description
HAVING COUNT(DISTINCT r.rule_id) > 1
ORDER BY matching_rules DESC
LIMIT 20;

-- 3. Show the specific categorization rules that match "Card charge (GOOGLE*ADS5932893176)"
SELECT 
  r.rule_id, 
  r.rule_name, 
  r.description_pattern, 
  r.priority,
  r.source_system_filter,
  c.subcategory_name,
  c.category_name
FROM `onyga-482313.OI.CFG_TRANSACTION_CATEGORIZATION_RULES` r
LEFT JOIN `onyga-482313.OI.DIM_BUDGET_CATEGORIES` c
  ON r.target_subcategory_id = c.subcategory_id
WHERE r.rule_id IN (
  SELECT DISTINCT r.rule_id
  FROM `onyga-482313.OI.STG_UNIFIED_TRANSACTION_SOURCES` stg
  LEFT JOIN `onyga-482313.OI.CFG_TRANSACTION_CATEGORIZATION_RULES` r
    ON (r.source_system_filter IS NULL OR r.source_system_filter = stg.source_system)
    AND (r.description_pattern IS NULL OR REGEXP_CONTAINS(stg.transaction_description, r.description_pattern))
    AND (r.amount_min IS NULL OR stg.amount >= r.amount_min)
    AND (r.amount_max IS NULL OR stg.amount <= r.amount_max)
    AND (r.currency_filter IS NULL OR r.currency_filter = stg.currency)
    AND r.is_active = TRUE
  WHERE stg.transaction_description = 'Card charge (GOOGLE*ADS5932893176)'
    AND stg.source_system = 'PAYONEER_HAPPY_LOLLI'
)
AND r.is_active = TRUE
ORDER BY r.priority;
