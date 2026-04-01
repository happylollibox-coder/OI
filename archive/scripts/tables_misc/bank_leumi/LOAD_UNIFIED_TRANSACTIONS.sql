-- =============================================
-- OI Database Project - Load Unified Financial Transactions
-- =============================================
--
-- Purpose: Load and categorize all transactions into the unified fact table
-- This script creates the categorization infrastructure and populates data
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- =============================================
-- STEP 1: CREATE DIMENSION TABLES
-- =============================================

-- Create budget categories dimension table
CREATE OR REPLACE TABLE `onyga-482313.OI.DIM_BUDGET_CATEGORIES` (
  category_id INT64 NOT NULL,
  category_name STRING NOT NULL,
  subcategory_id INT64 NOT NULL,
  subcategory_name STRING NOT NULL,
  category_type STRING NOT NULL,
  is_recurring BOOLEAN DEFAULT FALSE,
  budget_confidence STRING DEFAULT 'MEDIUM',
  forecast_multiplier FLOAT64 DEFAULT 1.0,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (category_id, subcategory_id) NOT ENFORCED
)
CLUSTER BY category_name, subcategory_name;

-- Create categorization rules table
CREATE OR REPLACE TABLE `onyga-482313.OI.CFG_TRANSACTION_CATEGORIZATION_RULES` (
  rule_id INT64 NOT NULL,
  rule_name STRING NOT NULL,
  rule_description STRING,
  source_system_filter STRING,
  description_pattern STRING,
  amount_min FLOAT64,
  amount_max FLOAT64,
  currency_filter STRING,
  target_subcategory_id INT64 NOT NULL,
  priority INT64 NOT NULL,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  created_by STRING DEFAULT 'SYSTEM',
  PRIMARY KEY (rule_id) NOT ENFORCED
)
CLUSTER BY priority, source_system_filter;

-- =============================================
-- STEP 2: POPULATE DIMENSION TABLES
-- =============================================

-- Insert budget categories
INSERT INTO `onyga-482313.OI.DIM_BUDGET_CATEGORIES`
  (category_id, category_name, subcategory_id, subcategory_name, category_type, is_recurring, budget_confidence)
VALUES
  -- INCOME CATEGORIES
  (1, 'REVENUE', 101, 'Amazon Sales & Commissions', 'INCOME', TRUE, 'HIGH'),
  (1, 'REVENUE', 102, 'Consulting Services', 'INCOME', FALSE, 'MEDIUM'),
  (1, 'REVENUE', 103, 'Business Revenue', 'INCOME', TRUE, 'MEDIUM'),
  (1, 'REVENUE', 104, 'Other Income', 'INCOME', FALSE, 'LOW'),

  -- EXPENSE CATEGORIES
  (3, 'MARKETING & ADVERTISING', 301, 'Amazon Advertising', 'EXPENSE', TRUE, 'HIGH'),
  (3, 'MARKETING & ADVERTISING', 302, 'Google Ads', 'EXPENSE', TRUE, 'HIGH'),
  (3, 'MARKETING & ADVERTISING', 303, 'Social Media Marketing', 'EXPENSE', TRUE, 'MEDIUM'),
  (3, 'MARKETING & ADVERTISING', 304, 'Other Digital Marketing', 'EXPENSE', FALSE, 'MEDIUM'),

  (4, 'BUSINESS TOOLS & SOFTWARE', 401, 'SEO & Research Tools', 'EXPENSE', TRUE, 'HIGH'),
  (4, 'BUSINESS TOOLS & SOFTWARE', 402, 'E-commerce Platforms', 'EXPENSE', TRUE, 'HIGH'),
  (4, 'BUSINESS TOOLS & SOFTWARE', 403, 'Accounting & Finance Software', 'EXPENSE', TRUE, 'HIGH'),
  (4, 'BUSINESS TOOLS & SOFTWARE', 404, 'Other Business Tools', 'EXPENSE', FALSE, 'MEDIUM'),

  (7, 'PERSONNEL & PAYROLL', 701, 'Salary & Wages', 'EXPENSE', TRUE, 'HIGH'),
  (7, 'PERSONNEL & PAYROLL', 702, 'Contractor Payments', 'EXPENSE', TRUE, 'HIGH'),
  (7, 'PERSONNEL & PAYROLL', 703, 'Benefits & Taxes', 'EXPENSE', TRUE, 'HIGH'),
  (7, 'PERSONNEL & PAYROLL', 704, 'Bonuses & Commissions', 'EXPENSE', FALSE, 'MEDIUM'),

  (8, 'FINANCIAL FEES', 801, 'Bank Fees', 'EXPENSE', TRUE, 'HIGH'),
  (8, 'FINANCIAL FEES', 802, 'Payment Processing Fees', 'EXPENSE', TRUE, 'HIGH'),
  (8, 'FINANCIAL FEES', 803, 'Currency Conversion Fees', 'EXPENSE', TRUE, 'MEDIUM'),
  (8, 'FINANCIAL FEES', 804, 'Other Financial Charges', 'EXPENSE', FALSE, 'LOW'),

  -- TRANSFER CATEGORIES
  (11, 'ACCOUNT TRANSFERS', 1101, 'Inter-Account Transfers', 'TRANSFER', TRUE, 'HIGH'),
  (11, 'ACCOUNT TRANSFERS', 1102, 'Currency Conversions', 'TRANSFER', TRUE, 'HIGH'),
  (11, 'ACCOUNT TRANSFERS', 1103, 'Balance Adjustments', 'TRANSFER', FALSE, 'LOW'),

  -- UNKNOWN CATEGORY (FALLBACK)
  (99, 'UNKNOWN', 9901, 'Uncategorized Transactions', 'UNKNOWN', FALSE, 'LOW');

-- Insert categorization rules
INSERT INTO `onyga-482313.OI.CFG_TRANSACTION_CATEGORIZATION_RULES`
  (rule_id, rule_name, rule_description, source_system_filter, description_pattern, target_subcategory_id, priority)
VALUES
  -- Payoneer Rules
  (1, 'Payoneer Google Ads', 'Google advertising payments', NULL, 'GOOGLE.*ADS', 302, 1),
  (2, 'Payoneer Helium10', 'Helium10 SEO tool payments', NULL, 'HELIUM10', 401, 2),
  (3, 'Payoneer Amazon Advertising', 'Amazon advertising costs', NULL, 'AMAZON.*ADVERTIS', 301, 3),
  (4, 'Payoneer Sylvia Payments', 'Contractor payments to Sylvia', NULL, 'SYLVIA', 702, 4),
  (5, 'Payoneer Amazon Commissions', 'Amazon sales commissions', NULL, 'Payment from Amazon', 101, 5),
  (6, 'Payoneer Adva Tal Transfers', 'Internal transfers to adva tal', NULL, 'Payment from adva tal', 1101, 6),
  (7, 'Payoneer Card Charges', 'Credit card processing fees', NULL, 'Card charge', 802, 7),

  -- Bank Leumi Rules
  (8, 'Bank Leumi Inter-Account Transfers', 'Transfers between bank accounts', 'BANK_LEUMI_ILS', 'העברה.*חשבון מקושר', 1101, 8),
  (9, 'Bank Leumi Salary Income', 'Salary deposits from employers', 'BANK_LEUMI_ILS', 'משכורת|שכר', 701, 9),
  (10, 'Bank Leumi Loan Payments', 'Monthly loan repayments', 'BANK_LEUMI_ILS', 'פרעון הלוואה', 803, 10),

  -- Fallback Rule
  (99, 'Uncategorized Transactions', 'Fallback for unmatched transactions', NULL, '.*', 9901, 99);

-- =============================================
-- STEP 3: CREATE STORED PROCEDURE
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_CATEGORIZE_TRANSACTIONS`(
  source_table_name STRING,
  target_table_name STRING
)
OPTIONS (
  description = "Categorize transactions from source table and insert into target table with budget categories"
)
BEGIN
  DECLARE query STRING;

  SET query = FORMAT("""
    INSERT INTO `%s` (
      transaction_date, amount, currency, transaction_description, transaction_type,
      source_system, source_transaction_id, account_name, payment_direction,
      transaction_category, budget_category, budget_subcategory, subcategory_id,
      is_recurring, budget_confidence, forecast_multiplier, payment_source,
      transaction_year, transaction_month, transaction_day, source_metadata,
      processed_at, data_source_file
    )
    WITH categorized_transactions AS (
      SELECT
        t.transaction_date,
        t.amount,
        t.currency,
        t.transaction_description,
        t.transaction_type,
        t.source_system,
        t.source_transaction_id,
        t.account_name,
        t.payment_direction,
        t.transaction_category,
        t.payment_source,
        t.transaction_year,
        t.transaction_month,
        t.transaction_day,
        t.source_metadata,
        t.processed_at,
        t.data_source_file,

        COALESCE(
          FIRST_VALUE(c.subcategory_name IGNORE NULLS) OVER (
            PARTITION BY t.transaction_date, t.source_transaction_id, t.source_system
            ORDER BY r.priority ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
          ),
          'Uncategorized Transactions'
        ) as budget_subcategory,

        COALESCE(
          FIRST_VALUE(c.category_name IGNORE NULLS) OVER (
            PARTITION BY t.transaction_date, t.source_transaction_id, t.source_system
            ORDER BY r.priority ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
          ),
          'UNKNOWN'
        ) as budget_category,

        COALESCE(
          FIRST_VALUE(c.subcategory_id IGNORE NULLS) OVER (
            PARTITION BY t.transaction_date, t.source_transaction_id, t.source_system
            ORDER BY r.priority ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
          ),
          9901
        ) as subcategory_id,

        COALESCE(
          FIRST_VALUE(c.is_recurring IGNORE NULLS) OVER (
            PARTITION BY t.transaction_date, t.source_transaction_id, t.source_system
            ORDER BY r.priority ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
          ),
          FALSE
        ) as is_recurring,

        COALESCE(
          FIRST_VALUE(c.budget_confidence IGNORE NULLS) OVER (
            PARTITION BY t.transaction_date, t.source_transaction_id, t.source_system
            ORDER BY r.priority ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
          ),
          'LOW'
        ) as budget_confidence,

        COALESCE(
          FIRST_VALUE(c.forecast_multiplier IGNORE NULLS) OVER (
            PARTITION BY t.transaction_date, t.source_transaction_id, t.source_system
            ORDER BY r.priority ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
          ),
          1.0
        ) as forecast_multiplier

      FROM `%s` t
      LEFT JOIN `onyga-482313.OI.CFG_TRANSACTION_CATEGORIZATION_RULES` r
        ON (r.source_system_filter IS NULL OR r.source_system_filter = t.source_system)
        AND (r.description_pattern IS NULL OR REGEXP_CONTAINS(t.transaction_description, r.description_pattern))
        AND (r.amount_min IS NULL OR t.amount >= r.amount_min)
        AND (r.amount_max IS NULL OR t.amount <= r.amount_max)
        AND (r.currency_filter IS NULL OR r.currency_filter = t.currency)
        AND r.is_active = TRUE
      LEFT JOIN `onyga-482313.OI.DIM_BUDGET_CATEGORIES` c
        ON r.target_subcategory_id = c.subcategory_id
    )
    SELECT DISTINCT
      transaction_date, amount, currency, transaction_description, transaction_type,
      source_system, source_transaction_id, account_name, payment_direction,
      transaction_category, budget_category, budget_subcategory, subcategory_id,
      is_recurring, budget_confidence, forecast_multiplier, payment_source,
      transaction_year, transaction_month, transaction_day, source_metadata,
      processed_at, data_source_file
    FROM categorized_transactions
  """, target_table_name, source_table_name);

  EXECUTE IMMEDIATE(query);

  SELECT FORMAT('Successfully categorized transactions from %s into %s', source_table_name, target_table_name) as status;
END;

-- =============================================
-- STEP 4: CREATE UNIFIED FACT TABLE
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS` (
  transaction_date DATE NOT NULL,
  amount FLOAT64 NOT NULL,
  currency STRING,
  transaction_description STRING,
  transaction_type STRING,
  source_system STRING NOT NULL,
  source_transaction_id STRING NOT NULL,
  account_name STRING,
  payment_direction STRING,
  transaction_category STRING,
  payment_source STRING,
  budget_category STRING,
  budget_subcategory STRING,
  subcategory_id INT64,
  is_recurring BOOLEAN,
  budget_confidence STRING,
  forecast_multiplier FLOAT64,
  transaction_year INT64,
  transaction_month INT64,
  transaction_day INT64,
  source_metadata JSON,
  processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  data_source_file STRING,
  categorization_rule_id INT64,
  PRIMARY KEY (source_system, source_transaction_id, transaction_date) NOT ENFORCED
)
PARTITION BY DATE(transaction_date)
CLUSTER BY source_system, budget_category, account_name;

-- =============================================
-- STEP 5: LOAD AND CATEGORIZE ALL TRANSACTIONS
-- =============================================

-- Note: The stored procedure calls below would be executed separately
-- to load data from each source system into the unified fact table

/*
-- Example stored procedure calls (run these individually):

-- Load Bank Leumi ILS transactions
CALL `onyga-482313.OI.SP_CATEGORIZE_TRANSACTIONS`(
  'onyga-482313.OI.V_SRC_BANK_LEUMI_ILS',
  'onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS'
);

-- Load Bank Leumi Foreign transactions
CALL `onyga-482313.OI.SP_CATEGORIZE_TRANSACTIONS`(
  'onyga-482313.OI.V_SRC_BANK_LEUMI_FOREIGN',
  'onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS'
);

-- Load Payoneer adva.tal transactions
CALL `onyga-482313.OI.SP_CATEGORIZE_TRANSACTIONS`(
  'onyga-482313.OI.V_SRC_BANK_PAYONEER_ADVA_TAL',
  'onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS'
);

-- Load Payoneer happy lolli transactions
CALL `onyga-482313.OI.SP_CATEGORIZE_TRANSACTIONS`(
  'onyga-482313.OI.V_SRC_BANK_PAYONEER_HAPPY_LOLLI',
  'onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS'
);
*/

-- =============================================
