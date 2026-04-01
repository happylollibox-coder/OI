-- =============================================
-- OI Database Project - FACT_FINANCIAL_TRANSACTIONS Table
-- =============================================
--
-- Purpose: Unified fact table containing all financial transactions
-- Used for financial analysis and reporting
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Create the unified financial transactions fact table
CREATE OR REPLACE TABLE `onyga-482313.OI.FACT_FINANCIAL_TRANSACTIONS` (
  -- Core Transaction Fields
  transaction_date DATE NOT NULL,
  amount FLOAT64 NOT NULL,
  currency STRING,
  transaction_description STRING,
  transaction_type STRING, -- INCOME, PAYMENT, DEBIT, CREDIT, TRANSFER

  -- Source Identification
  source_system STRING NOT NULL, -- 'BANK_LEUMI_ILS', 'BANK_LEUMI_FOREIGN', 'PAYONEER_ADVA_TAL', 'PAYONEER_HAPPY_LOLLI'
  source_transaction_id STRING NOT NULL,
  account_name STRING,

  -- Enhanced Analytics Fields
  payment_direction STRING, -- 'INCOMING', 'OUTGOING', 'INTERNAL_TRANSFER'
  payment_source STRING, -- 'AMAZON', 'GOOGLE_ADS', 'INTERNAL', 'CUSTOMER_PAYMENT'
  payment_source_category STRING(65535), -- Category from DIM_PAYMENT_SOURCE_HIERARCHY (e.g., 'ADVERTISING', 'E-COMMERCE', 'SERVICES')
  payment_source_sub_category STRING(65535), -- Sub-category from DIM_PAYMENT_SOURCE_HIERARCHY (e.g., 'Search Ads', 'Marketplace', 'Tools')

  -- Time Dimensions (pre-calculated for performance)
  transaction_year INT64,
  transaction_month INT64,
  transaction_day INT64,
  factless_transaction_key STRING, -- Factless key: date_key-UNKNOWN format (e.g., '20240101-UNKNOWN') based on transaction_date
  factless_effect_key STRING, -- Factless key: date_key-UNKNOWN format (e.g., '20240101-UNKNOWN') based on effect_date

  -- Source-Specific Metadata (JSON for flexibility)
  source_metadata JSON,

  -- Technical Fields
  processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  data_source_file STRING,

  -- Conversion Fields (from GENERAL_CONVERSION)
  account_nick_name STRING, -- Friendly account name from GENERAL_CONVERSION

  -- Effect Date (for accrual accounting)
  -- Uses manual_effect_date if provided, otherwise uses transaction_date
  -- This allows transactions to be attributed to a different period than when payment was received
  effect_date DATE, -- Date to use for reporting (manual_effect_date if provided, else transaction_date)

  -- Currency Conversion Fields (from DIM_CURRENCY_RATES)
  amount_usd FLOAT64, -- Amount converted to USD
  amount_ils FLOAT64, -- Amount converted to ILS
  amount_hkd FLOAT64, -- Amount converted to HKD

  -- Factless Key
  factless_key STRING, -- Composite key: date_key - asin (e.g., '20240101-B0123456789'), NULL if asin not available

  -- Constraints
  -- Note: PRIMARY KEY is not enforced. Using TRUNCATE + INSERT approach ensures STG and FACT have same rows
  PRIMARY KEY (source_system, source_transaction_id, transaction_date) NOT ENFORCED
)
PARTITION BY transaction_date
CLUSTER BY source_system, account_name, payment_source_category;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This unified fact table serves as the central repository for all financial transactions
-- with intelligent budget categorization for 2026-2027 planning.
--
-- Key Features:
-- - Standardized transaction amounts (positive = inflow, negative = outflow)
-- - Payment source categorization via DIM_PAYMENT_SOURCE_HIERARCHY
-- - Flexible source-specific data storage
-- - Optimized for time-series analysis and reporting
--
-- Usage:
-- - Financial dashboards and reporting
-- - Cash flow analysis
-- - Expense trend analysis
-- - Revenue and expense reporting by payment source category
--
-- =============================================
