-- =============================================
-- OI Database Project - V_UNIFIED_TRANSACTION_SOURCES View
-- =============================================
--
-- Purpose: Simple UNION ALL view of all transaction sources without additional logic
-- This provides raw transaction data for staging table processing
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_UNIFIED_TRANSACTION_SOURCES` AS

-- Bank Leumi ILS Transactions
SELECT
  transaction_date,
  CASE WHEN credit_amount IS NOT NULL AND credit_amount > 0 THEN credit_amount
       WHEN debit_amount IS NOT NULL AND debit_amount > 0 THEN -debit_amount
       ELSE 0 END as amount,
  'ILS' as currency,
    CASE 
    WHEN transaction_description IN (
    'העברת כספים'
    , 'העברת משכורת'
    , 'העברה תוך יומי.'
     , 'העברה דיגיטל'
         , 'רשויות אינטרנט'
     , 'הוראת קבע'
     , 'העברה עצמית'
     , 'כיסוי חובה'
     , 'הע. אינטרנט'
     , 'העברת מטח'
     , 'מסיטיבנק ס-.י'
     , 'בנק דיסקונט'
     , 'מב.ירושלים ס-י'
     , 'העברה תוך יומי'
    )   
    
    THEN ifnull(transaction_description||' - '||extended_description,transaction_description)
    ELSE transaction_description
  END as transaction_description,
  CASE WHEN credit_amount IS NOT NULL AND credit_amount > 0 THEN 'CREDIT'
       WHEN debit_amount IS NOT NULL AND debit_amount > 0 THEN 'DEBIT'
       ELSE 'UNKNOWN' END as transaction_type,
  'BANK_LEUMI_ILS' as source_system,
  reference_number as source_transaction_id,
  CONCAT(branch, '-', account) as account_name,
  JSON_OBJECT(
    'branch', branch,
    'account', account,
    'debit_amount', debit_amount,
    'credit_amount', credit_amount,
    'balance_ils', balance_ils,
    'extended_description', extended_description,
    'notes', notes
  ) as source_metadata,
  CURRENT_TIMESTAMP() as processed_at,
  'BANK_LEUMI_ILS' as data_source_file
FROM `onyga-482313.OI.V_SRC_BANK_LEUMI_ILS`



UNION ALL

-- Bank Leumi Foreign Transactions
SELECT
  transaction_date,
  CASE WHEN credit_amount IS NOT NULL AND credit_amount > 0 THEN credit_amount
       WHEN debit_amount IS NOT NULL AND debit_amount > 0 THEN -debit_amount
       ELSE 0 END as amount,
  currency,
  CASE 
    WHEN transaction_description IN (
    'העברת כספים'
    , 'יצוא ישיר'
    , 'יבוא ישיר'
    , 'ניכוי מס'
    , 'סגירת חש.מטח'
    , 'מחשבון לחש.'
    )
    
    
    THEN ifnull( transaction_description||' - '||extended_description, transaction_description)
    ELSE transaction_description
  END as transaction_description,
    
  CASE WHEN credit_amount IS NOT NULL AND credit_amount > 0 THEN 'CREDIT'
       WHEN debit_amount IS NOT NULL AND debit_amount > 0 THEN 'DEBIT'
       ELSE 'UNKNOWN' END as transaction_type,
  'BANK_LEUMI_FOREIGN' as source_system,
  reference_number as source_transaction_id,
  CONCAT(branch, '-', account) as account_name,
  JSON_OBJECT(
    'branch', branch,
    'account', account,
    'currency', currency,
    'debit_amount', debit_amount,
    'credit_amount', credit_amount,
    'balance_foreign', balance_foreign,
    'extended_description', extended_description,
    'notes', notes
  ) as source_metadata,
  CURRENT_TIMESTAMP() as processed_at,
  'BANK_LEUMI_FOREIGN' as data_source_file
FROM `onyga-482313.OI.V_SRC_BANK_LEUMI_FOREIGN`

    
UNION ALL

-- Payoneer Adva Tal Transactions
SELECT
  transaction_date,
  amount,
  currency,
  description as transaction_description,
  'PAYMENT' as transaction_type, -- Payoneer transactions are payment type
  'PAYONEER_ADVA_TAL' as source_system,
  transaction_id as source_transaction_id,
  'adva.tal' as account_name,
  JSON_OBJECT(
    'status', 'Completed',
    'transaction_id', transaction_id
  ) as source_metadata,
  CURRENT_TIMESTAMP() as processed_at,
  'PAYONEER_ADVA_TAL' as data_source_file
FROM `onyga-482313.OI.SRC_BANK_PAYONEER_ADVA_TAL`

UNION ALL

-- Payoneer Happy Lolli Transactions
SELECT
  transaction_date,
  amount,
  currency,
  description as transaction_description,
  'PAYMENT' as transaction_type, -- Payoneer transactions are payment type
  'PAYONEER_HAPPY_LOLLI' as source_system,
  transaction_id as source_transaction_id,
  'happy_lolli' as account_name,
  JSON_OBJECT(
    'status', 'Completed',
    'transaction_id', transaction_id
  ) as source_metadata,
  CURRENT_TIMESTAMP() as processed_at,
  'PAYONEER_HAPPY_LOLLI' as data_source_file
FROM `onyga-482313.OI.SRC_BANK_PAYONEER_HAPPY_LOLLI`;
