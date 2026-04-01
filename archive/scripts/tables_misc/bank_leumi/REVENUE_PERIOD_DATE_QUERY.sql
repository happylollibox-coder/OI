-- =============================================
-- Query to identify transactions for revenue_period_date logic
-- =============================================
-- 
-- Logic: transaction_date minus 15 days for Amazon incoming payments to Happy Lolli account
-- 
-- Criteria:
--   - source_system = 'PAYONEER_HAPPY_LOLLI'
--   - account_name = 'happy_lolli'
--   - payment_direction = 'INCOMING'
--   - transaction_description LIKE '%Amazon%'
-- 
-- =============================================

-- Query to identify relevant transactions from FACT table
-- These transactions should have revenue_period_date = transaction_date - 15 days
-- All other transactions should have revenue_period_date = transaction_date
SELECT 
  source_system,
  account_name,
  payment_direction,
  transaction_description,
  transaction_date,
  DATE_SUB(transaction_date, INTERVAL 15 DAY) as revenue_period_date,
  FORMAT_DATE('%Y-%m', transaction_date) as transaction_period,
  FORMAT_DATE('%Y-%m', DATE_SUB(transaction_date, INTERVAL 15 DAY)) as revenue_period,
  amount
FROM `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS`
WHERE  
   payment_direction = 'INCOMING'
  AND  (transaction_description LIKE '%Payment from Amazon%' 
        OR transaction_description LIKE '%ETSY%'
        OR transaction_description LIKE '%יצוא ישיר - TRANSFER FROM: 371547008375866, HAPPY LOLLI LLC%')
ORDER BY transaction_date DESC;

-- =============================================
-- Query to identify relevant transactions from STG table (before they go to FACT)
-- =============================================

SELECT 
  source_system,
  account_name,
  transaction_description,
  transaction_date,
  amount,
  CASE WHEN amount > 0 THEN 'INCOMING' ELSE 'OUTGOING' END as payment_direction,
  DATE_SUB(transaction_date, INTERVAL 15 DAY) as revenue_period_date,
  FORMAT_DATE('%Y-%m', transaction_date) as transaction_period,
  FORMAT_DATE('%Y-%m', DATE_SUB(transaction_date, INTERVAL 15 DAY)) as revenue_period
FROM `onyga-482313.OI.STG_UNIFIED_TRANSACTION_SOURCES`
WHERE amount > 0  -- INCOMING
  AND (transaction_description LIKE '%Payment from Amazon%' 
       OR transaction_description LIKE '%ETSY%'
       OR transaction_description LIKE '%יצוא ישיר - TRANSFER FROM: 371547008375866, HAPPY LOLLI LLC%')
ORDER BY transaction_date DESC;
