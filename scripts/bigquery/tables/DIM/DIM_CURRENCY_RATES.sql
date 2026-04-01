-- =============================================
-- OI Database Project - DIM_CURRENCY_RATES Table
-- =============================================
--
-- Purpose: Currency exchange rates dimension table
-- Used for converting transaction amounts to USD, ILS, HKD
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Create the currency rates dimension table
CREATE OR REPLACE TABLE `onyga-482313.OI.DIM_CURRENCY_RATES` (
  -- Primary key
  rate_id INT64 NOT NULL,

  -- Date for the exchange rate
  rate_date DATE NOT NULL,

  -- Source currency code
  from_currency STRING NOT NULL, -- 'USD', 'ILS', 'HKD', etc.

  -- Target currency code
  to_currency STRING NOT NULL, -- 'USD', 'ILS', 'HKD', etc.

  -- Exchange rate (1 from_currency = rate to_currency)
  exchange_rate FLOAT64 NOT NULL,

  -- Metadata
  source STRING, -- 'BANK_LEUMI', 'EXTERNAL_API', etc.
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  is_active BOOLEAN DEFAULT TRUE,

  -- Constraints
  PRIMARY KEY (rate_id) NOT ENFORCED
)
PARTITION BY rate_date
CLUSTER BY from_currency, to_currency, rate_date;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This dimension table stores currency exchange rates for converting
-- transaction amounts between different currencies.
--
-- Example:
-- - rate_date: 2025-01-15
-- - from_currency: 'USD'
-- - to_currency: 'ILS'
-- - exchange_rate: 3.65
-- Meaning: 1 USD = 3.65 ILS on 2025-01-15
--
-- Usage:
-- - Convert transaction amounts to standardized currencies (USD, ILS, HKD)
-- - Historical rate tracking for accurate financial reporting
-- - Multi-currency budget analysis
--
-- Note: This table should be populated by a scheduled job that fetches
-- current exchange rates (e.g., from a cloud function or external API)
--
-- =============================================