-- BigQuery Scheduled Query for Daily Currency Rate Updates
-- This query calls the stored procedure to update currency rates
--
-- To set this up:
-- 1. Go to BigQuery Console → Scheduled Queries
-- 2. Create new scheduled query
-- 3. Copy this SQL
-- 4. Set schedule: Every day at 6:00 AM (weekdays only)
-- 5. Set timezone: America/New_York (or your preferred timezone)
-- 6. Set destination: None (this is just a procedure call)

CALL `onyga-482313.OI.SP_UPDATE_CURRENCY_RATES`(
  CURRENT_DATE(),  -- start_date
  CURRENT_DATE(),  -- end_date
  FALSE            -- is_historical_load
);

-- Expected output on success:
-- Starting currency rate update from 2024-01-XX to 2024-01-XX (historical_load: false)
-- Sample currency rates inserted for 2024-01-XX. In production, this would fetch from exchange rate API.

-- Note: This will use the stored procedure which currently inserts sample data.
-- For real API data, you need to implement the Cloud Function approach or update the stored procedure.