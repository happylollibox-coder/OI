-- =============================================
-- OI Database Project - Remote Function for Exchange Rates
-- =============================================
--
-- Purpose: BigQuery remote function that calls Cloud Function to fetch rates
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- Create remote function to call Cloud Function
CREATE OR REPLACE FUNCTION `onyga-482313.OI.FN_FETCH_EXCHANGE_RATES`()
RETURNS JSON
REMOTE WITH CONNECTION `onyga-482313.US.bigquery-connection`
OPTIONS (
  description = "Fetch current exchange rates from external API via Cloud Function",
  endpoint = "https://fetch-exchange-rates-405291422506.us-central1.run.app",
  max_batching_rows = 1
);

-- =============================================
-- USAGE
-- =============================================
--
-- Call the function:
-- SELECT `onyga-482313.OI.FN_FETCH_EXCHANGE_RATES`() as api_response;
--
-- =============================================
