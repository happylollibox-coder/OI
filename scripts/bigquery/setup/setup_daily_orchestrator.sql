-- BigQuery Scheduled Query for Daily Refresh Orchestrator
-- This query calls the master orchestrator that runs all daily refresh procedures
--
-- To set this up:
-- 1. Go to BigQuery Console → Scheduled Queries
-- 2. Create new scheduled query
-- 3. Copy this SQL
-- 4. Set schedule: Every day at 06:00 (or your preferred time)
-- 5. Set timezone: America/New_York (or your preferred timezone)
-- 6. Set destination: None (this is just a procedure call)

CALL `onyga-482313.OI.SP_ORCHESTRATE_DAILY_REFRESH`();
