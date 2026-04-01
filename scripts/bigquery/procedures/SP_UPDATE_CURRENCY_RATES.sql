-- =============================================
-- OI Database Project - Update Currency Exchange Rates
-- =============================================
--
-- Purpose: Fetch and store daily currency exchange rates for ILS, USD, HKD
-- Supports historical backfill and daily updates
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_UPDATE_CURRENCY_RATES`(
  start_date DATE,
  end_date DATE,
  is_historical_load BOOLEAN
)
OPTIONS (
  description = "Update currency exchange rates for specified date range. Use is_historical_load=TRUE for backfill operations."
)
BEGIN
  -- Declare variables
  DECLARE api_response JSON;
  DECLARE api_success BOOLEAN DEFAULT FALSE;
  DECLARE rate_count INT64;
  DECLARE raw_response JSON;
  DECLARE deleted_count INT64;

  -- Set default values for parameters
  SET is_historical_load = COALESCE(is_historical_load, FALSE);

  -- Validate input parameters
  IF start_date > end_date THEN
    SELECT FORMAT('ERROR: Invalid date range: start_date (%t) cannot be after end_date (%t)', start_date, end_date) as error_message;
    RETURN;
  END IF;

  IF DATE_DIFF(end_date, start_date, DAY) > 365 AND NOT is_historical_load THEN
    SELECT FORMAT('ERROR: Date range too large for daily load: %d days. Use is_historical_load=TRUE for large ranges.',
                          DATE_DIFF(end_date, start_date, DAY)) as error_message;
    RETURN;
  END IF;

  -- Log the operation start
  SELECT FORMAT('Starting currency rate update from %t to %t (historical_load: %t)',
                start_date, end_date, is_historical_load) as operation_log;

  -- Fetch real currency rates from external API
  -- NOTE: This requires Cloud Functions to be set up. For now, it will fail without fallback.
  -- To make this work:
  -- 1. Enable Cloud Functions API in your GCP project
  -- 2. Deploy the Cloud Function from cloud-functions/fetch-exchange-rates/
  -- 3. Deploy the BigQuery remote function from scripts/bigquery/functions/FN_FETCH_EXCHANGE_RATES.sql

  -- Try to call the remote function (will fail if not set up)
  BEGIN
    SELECT 'DEBUG: About to call remote function...' as debug_step;
    SET raw_response = `onyga-482313.OI.FN_FETCH_EXCHANGE_RATES`();
    SELECT FORMAT('DEBUG: Remote function called. Response type: %s', JSON_TYPE(raw_response)) as debug_step;
    
    -- BigQuery remote function can return either:
    -- 1. { "replies": [{ "success": true, ... }] } - when called as remote function
    -- 2. Direct response { "success": true, ... } - when BigQuery unwraps it
    -- Handle both cases
    IF JSON_EXTRACT(raw_response, '$.replies') IS NOT NULL THEN
      -- Has replies array - extract first element
      SET api_response = JSON_EXTRACT(raw_response, '$.replies[0]');
      SELECT 'DEBUG: Extracted response from replies array' as debug_step;
    ELSE
      -- Direct response - use as is
      SET api_response = raw_response;
      SELECT 'DEBUG: Using direct response (no replies array)' as debug_step;
    END IF;
    
    -- Check success (handle both string 'true' and boolean true)
    SET api_success = (
      JSON_VALUE(api_response, '$.success') = 'true' OR
      JSON_VALUE(api_response, '$.success') = 'TRUE' OR
      SAFE_CAST(JSON_VALUE(api_response, '$.success') AS BOOLEAN) = TRUE
    );
    
    SELECT FORMAT('DEBUG: API success check result: %t', api_success) as debug_step;
                  
  EXCEPTION WHEN ERROR THEN
    -- Remote function not available - fail with error message
    SELECT FORMAT('ERROR: Real-time currency API not available. Error: %s', @@error.message) as error_message;
    RETURN;
  END;
  
  -- Show debug info if failed
  IF NOT api_success THEN
    SELECT FORMAT('ERROR: API call failed. Response: %s', TO_JSON_STRING(api_response)) as error_message;
    RETURN;
  END IF;

  IF api_success THEN
    -- Debug: Check how many rates we have
    SET rate_count = ARRAY_LENGTH(JSON_QUERY_ARRAY(api_response, '$.rates'));
    SELECT FORMAT('DEBUG: Found %d currency pairs in API response', rate_count) as debug_info;
    
    -- Count existing rows before deletion
    SET deleted_count = (
      SELECT COUNT(*)
      FROM `onyga-482313.OI.DIM_CURRENCY_RATES`
      WHERE exchange_date >= start_date AND exchange_date <= end_date
    );
    
    -- Delete existing rows for the date range being processed
    -- Execute as direct statement (not in BEGIN block)
    DELETE FROM `onyga-482313.OI.DIM_CURRENCY_RATES`
    WHERE exchange_date >= start_date AND exchange_date <= end_date;
    
    IF deleted_count > 0 THEN
      SELECT FORMAT('DEBUG: Deleted %d existing rows for date range %t to %t', deleted_count, start_date, end_date) as debug_info;
    ELSE
      SELECT FORMAT('DEBUG: No existing rows found for date range %t to %t (new data)', start_date, end_date) as debug_info;
    END IF;
    
    -- Insert real rates from API response for each date in the range
    INSERT INTO `onyga-482313.OI.DIM_CURRENCY_RATES`
      (exchange_date, base_currency, target_currency, exchange_rate, inverse_rate,
       rate_source, rate_timestamp, is_business_day, data_quality_score,
       is_manual_override, last_updated_by)
    SELECT
      date_val as exchange_date,
      JSON_VALUE(rate, '$.base_currency') as base_currency,
      JSON_VALUE(rate, '$.target_currency') as target_currency,
      SAFE_CAST(JSON_VALUE(rate, '$.exchange_rate') AS FLOAT64) as exchange_rate,
      SAFE_CAST(JSON_VALUE(rate, '$.inverse_rate') AS FLOAT64) as inverse_rate,
      'EXCHANGE_RATE_API' as rate_source,
      TIMESTAMP(JSON_VALUE(api_response, '$.timestamp')) as rate_timestamp,
      TRUE as is_business_day,
      SAFE_CAST(JSON_VALUE(api_response, '$.metadata.quality_score') AS INT64) as data_quality_score,
      FALSE as is_manual_override,
      'SYSTEM' as last_updated_by
    FROM 
      UNNEST(GENERATE_DATE_ARRAY(start_date, end_date)) as date_val
    CROSS JOIN
      UNNEST(JSON_QUERY_ARRAY(api_response, '$.rates')) as rate
    WHERE JSON_VALUE(rate, '$.exchange_rate') IS NOT NULL;

    SELECT FORMAT('Real currency rates fetched from API and inserted for date range %t to %t (%d dates, %d currency pairs per date). Provider: %s',
                  start_date,
                  end_date,
                  DATE_DIFF(end_date, start_date, DAY) + 1,
                  ARRAY_LENGTH(JSON_QUERY_ARRAY(api_response, '$.rates')),
                  JSON_VALUE(api_response, '$.metadata.api_provider')) as status_message;
  ELSE
    -- API call failed - return error message and don't insert any data
    SELECT FORMAT('ERROR: API call failed: %s. Cannot insert currency rates without real data.',
                  JSON_VALUE(api_response, '$.error')) as error_message;
  END IF;

END;

-- =============================================
-- PROCEDURE USAGE EXAMPLES
-- =============================================
--
-- Daily Update (run every business day):
-- CALL `onyga-482313.OI.SP_UPDATE_CURRENCY_RATES`(CURRENT_DATE(), CURRENT_DATE(), FALSE);
--
-- Weekly Update (catch up on weekends):
-- CALL `onyga-482313.OI.SP_UPDATE_CURRENCY_RATES`(
--   DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY),
--   CURRENT_DATE(),
--   FALSE
-- );
--
-- Historical Backfill (2023 data):
-- CALL `onyga-482313.OI.SP_UPDATE_CURRENCY_RATES`(
--   DATE('2023-01-01'),
--   CURRENT_DATE(),
--   TRUE
-- );
--
-- =============================================

-- =============================================
-- SCHEDULING RECOMMENDATIONS
-- =============================================
--
-- For production deployment, schedule this procedure using:
--
-- 1. Cloud Scheduler + Cloud Functions:
--    - Create a Cloud Function that calls this procedure
--    - Schedule with Cloud Scheduler for weekdays at 6 AM EST
--
-- 2. BigQuery Scheduled Queries:
--    - Create a scheduled query that calls this procedure
--    - Set frequency to daily, with retry logic
--
-- 3. Airflow/Cloud Composer:
--    - DAG that calls the procedure with proper error handling
--    - Includes data quality checks and alerts
--
-- =============================================
