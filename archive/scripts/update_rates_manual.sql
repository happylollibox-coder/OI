-- Manual SQL script to update currency rates with current market values
-- Run this in BigQuery console to update rates manually

-- Get current rates from exchangerate-api.com (run this command in terminal first):
-- curl "https://api.exchangerate-api.com/v4/latest/USD"

-- Then update these values with the current rates from the API response
-- Current rates as of 2024-01-XX (update these values):

DECLARE usd_ils_rate FLOAT64 DEFAULT 3.822;
DECLARE usd_hkd_rate FLOAT64 DEFAULT 7.812;

-- Update currency rates
INSERT INTO `onyga-482313.OI.DIM_CURRENCY_RATES`
  (exchange_date, base_currency, target_currency, exchange_rate, inverse_rate,
   rate_source, rate_timestamp, is_business_day, data_quality_score,
   is_manual_override, last_updated_by)
VALUES
  -- USD as base currency
  (CURRENT_DATE(), 'USD', 'ILS', usd_ils_rate, 1/usd_ils_rate, 'MANUAL_UPDATE', CURRENT_TIMESTAMP(), TRUE, 95, FALSE, 'USER'),
  (CURRENT_DATE(), 'USD', 'HKD', usd_hkd_rate, 1/usd_hkd_rate, 'MANUAL_UPDATE', CURRENT_TIMESTAMP(), TRUE, 95, FALSE, 'USER'),
  (CURRENT_DATE(), 'USD', 'USD', 1.0, 1.0, 'MANUAL_UPDATE', CURRENT_TIMESTAMP(), TRUE, 95, FALSE, 'USER'),

  -- ILS as base currency
  (CURRENT_DATE(), 'ILS', 'USD', 1/usd_ils_rate, usd_ils_rate, 'MANUAL_UPDATE', CURRENT_TIMESTAMP(), TRUE, 95, FALSE, 'USER'),
  (CURRENT_DATE(), 'ILS', 'HKD', usd_hkd_rate/usd_ils_rate, usd_ils_rate/usd_hkd_rate, 'MANUAL_UPDATE', CURRENT_TIMESTAMP(), TRUE, 95, FALSE, 'USER'),
  (CURRENT_DATE(), 'ILS', 'ILS', 1.0, 1.0, 'MANUAL_UPDATE', CURRENT_TIMESTAMP(), TRUE, 95, FALSE, 'USER'),

  -- HKD as base currency
  (CURRENT_DATE(), 'HKD', 'USD', 1/usd_hkd_rate, usd_hkd_rate, 'MANUAL_UPDATE', CURRENT_TIMESTAMP(), TRUE, 95, FALSE, 'USER'),
  (CURRENT_DATE(), 'HKD', 'ILS', usd_ils_rate/usd_hkd_rate, usd_hkd_rate/usd_ils_rate, 'MANUAL_UPDATE', CURRENT_TIMESTAMP(), TRUE, 95, FALSE, 'USER'),
  (CURRENT_DATE(), 'HKD', 'HKD', 1.0, 1.0, 'MANUAL_UPDATE', CURRENT_TIMESTAMP(), TRUE, 95, FALSE, 'USER');

-- Verify the update
SELECT
  base_currency,
  target_currency,
  exchange_rate,
  rate_source,
  FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', rate_timestamp) as updated_at
FROM `onyga-482313.OI.DIM_CURRENCY_RATES`
WHERE exchange_date = CURRENT_DATE()
ORDER BY base_currency, target_currency;