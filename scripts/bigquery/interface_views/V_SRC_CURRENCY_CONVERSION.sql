-- =============================================
-- OI Database Project - Currency Conversion View
-- =============================================
--
-- Purpose: Provide easy currency conversion functionality for ILS, USD, HKD
-- Supports historical conversions and real-time lookups
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SRC_CURRENCY_CONVERSION` AS

WITH latest_rates AS (
  -- Get the most recent rate for each currency pair
  SELECT
    base_currency,
    target_currency,
    exchange_rate,
    inverse_rate,
    exchange_date,
    rate_timestamp,
    data_quality_score,
    ROW_NUMBER() OVER (
      PARTITION BY base_currency, target_currency
      ORDER BY exchange_date DESC, rate_timestamp DESC
    ) as recency_rank
  FROM `onyga-482313.OI.DIM_CURRENCY_RATES`
  WHERE data_quality_score > 0  -- Exclude error records
    AND NOT is_manual_override  -- Prefer automatic rates unless manually overridden
),

-- Get manually overridden rates (these take precedence)
manual_rates AS (
  SELECT
    base_currency,
    target_currency,
    exchange_rate,
    inverse_rate,
    exchange_date,
    rate_timestamp,
    data_quality_score,
    ROW_NUMBER() OVER (
      PARTITION BY base_currency, target_currency
      ORDER BY exchange_date DESC, rate_timestamp DESC
    ) as recency_rank
  FROM `onyga-482313.OI.DIM_CURRENCY_RATES`
  WHERE is_manual_override = TRUE
),

-- Combine rates with precedence to manual overrides
current_rates AS (
  SELECT
    COALESCE(m.base_currency, l.base_currency) as base_currency,
    COALESCE(m.target_currency, l.target_currency) as target_currency,
    COALESCE(m.exchange_rate, l.exchange_rate) as exchange_rate,
    COALESCE(m.inverse_rate, l.inverse_rate) as inverse_rate,
    COALESCE(m.exchange_date, l.exchange_date) as exchange_date,
    COALESCE(m.rate_timestamp, l.rate_timestamp) as rate_timestamp,
    COALESCE(m.data_quality_score, l.data_quality_score) as data_quality_score,
    CASE WHEN m.base_currency IS NOT NULL THEN TRUE ELSE FALSE END as is_manual_override
  FROM manual_rates m
  FULL OUTER JOIN latest_rates l
    ON m.base_currency = l.base_currency
    AND m.target_currency = l.target_currency
    AND m.recency_rank = 1
    AND l.recency_rank = 1
  WHERE COALESCE(m.recency_rank, 1) = 1
)

-- Main conversion view
SELECT
  -- Current rates (most recent for each pair)
  cr.base_currency,
  cr.target_currency,
  cr.exchange_rate,
  cr.inverse_rate,
  cr.exchange_date as rate_date,
  cr.rate_timestamp,
  cr.data_quality_score,
  cr.is_manual_override,

  -- Historical rates for time-travel queries
  hr.exchange_date,
  hr.exchange_rate as historical_exchange_rate,
  hr.inverse_rate as historical_inverse_rate,
  hr.rate_timestamp as historical_rate_timestamp,
  hr.data_quality_score as historical_data_quality_score,

  -- Metadata
  CASE
    WHEN cr.data_quality_score >= 90 THEN 'EXCELLENT'
    WHEN cr.data_quality_score >= 70 THEN 'GOOD'
    WHEN cr.data_quality_score >= 50 THEN 'FAIR'
    ELSE 'POOR'
  END as rate_quality_category,

  -- Conversion functions (example amounts)
  -- Note: These are examples - actual usage would pass in the amount to convert
  NULL as sample_amount_to_convert,  -- Placeholder for user input
  NULL as converted_amount,          -- Placeholder for calculation

  -- Audit information
  CURRENT_TIMESTAMP() as view_refreshed_at,
  'V_SRC_CURRENCY_CONVERSION' as view_name

FROM current_rates cr
-- Cross join with historical rates for complete time series
CROSS JOIN `onyga-482313.OI.DIM_CURRENCY_RATES` hr
WHERE cr.base_currency = hr.base_currency
  AND cr.target_currency = hr.target_currency
  AND hr.data_quality_score > 0;  -- Exclude error records

-- =============================================
-- VIEW DESCRIPTION & USAGE
-- =============================================
--
-- This view provides comprehensive currency conversion capabilities:
--
-- Key Fields:
-- - base_currency/target_currency: Currency pair (e.g., 'USD' to 'ILS')
-- - exchange_rate: Rate to convert FROM base TO target (1 USD = X ILS)
-- - inverse_rate: Rate to convert FROM target TO base (1 ILS = X USD)
-- - rate_date: Date the rate is effective for
-- - data_quality_score: Reliability indicator (0-100)
--
-- Usage Examples:
--
-- 1. Convert amount to USD (common reporting currency):
--    SELECT
--      transaction_date,
--      amount,
--      currency,
--      CASE
--        WHEN currency = 'ILS' THEN amount * inverse_rate
--        WHEN currency = 'HKD' THEN amount * inverse_rate
--        WHEN currency = 'USD' THEN amount
--      END as amount_in_usd
--    FROM your_transaction_table t
--    JOIN `onyga-482313.OI.V_SRC_CURRENCY_CONVERSION` c
--      ON c.target_currency = 'USD'
--      AND c.base_currency = t.currency
--      AND c.rate_date <= t.transaction_date
--    QUALIFY ROW_NUMBER() OVER (
--      PARTITION BY t.transaction_id
--      ORDER BY c.rate_date DESC
--    ) = 1;
--
-- 2. Get current exchange rates:
--    SELECT *
--    FROM `onyga-482313.OI.V_SRC_CURRENCY_CONVERSION`
--    WHERE rate_date = (
--      SELECT MAX(rate_date)
--      FROM `onyga-482313.OI.V_SRC_CURRENCY_CONVERSION`
--    );
--
-- 3. Historical conversion (as of specific date):
--    SELECT *
--    FROM `onyga-482313.OI.V_SRC_CURRENCY_CONVERSION`
--    WHERE exchange_date <= '2024-01-15'
--    QUALIFY ROW_NUMBER() OVER (
--      PARTITION BY base_currency, target_currency
--      ORDER BY exchange_date DESC
--    ) = 1;
--
-- 4. Check rate quality:
--    SELECT
--      base_currency,
--      target_currency,
--      rate_date,
--      rate_quality_category,
--      data_quality_score
--    FROM `onyga-482313.OI.V_SRC_CURRENCY_CONVERSION`
--    WHERE rate_quality_category IN ('POOR', 'FAIR');
--
-- =============================================

-- =============================================
-- BUSINESS RULES & ASSUMPTIONS
-- =============================================
--
-- 1. All rates are stored with USD as the intermediate currency
-- 2. Cross-currency rates are calculated automatically
-- 3. Manual overrides take precedence over automatic rates
-- 4. Historical rates are preserved for accurate back-dating
-- 5. Weekends use Friday's rates (forward-filled)
-- 6. Error records (quality_score = 0) are excluded from conversions
--
-- =============================================
