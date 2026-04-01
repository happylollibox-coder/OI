-- BigQuery Scheduled Query for PRODUCT_DIM Updates
-- This query calls the smart stored procedure that only runs when source table changes
--
-- To set this up:
-- 1. Go to BigQuery Console → Scheduled Queries
-- 2. Create new scheduled query
-- 3. Copy this SQL
-- 4. Set schedule: Every 1 hour (or your preferred frequency)
-- 5. Set timezone: America/New_York (or your preferred timezone)
-- 6. Set destination: None (this is just a procedure call)
--
-- Recommended Schedule:
-- - Every 1 hour: For near real-time updates (if Fivetran syncs frequently)
-- - Every 6 hours: For regular updates (if Fivetran syncs daily)
-- - Every day at 06:00: For daily updates (if Fivetran syncs once per day)

CALL `onyga-482313.OI.SP_MERGE_PRODUCT_DIM_SMART`();

-- Expected output on success:
-- If changes detected:
--   "SP_MERGE_PRODUCT_DIM_SMART: Changes detected (source: 2025-01-15 10:30:00, dim: 2025-01-15 09:00:00). MERGE executed. Duration: X seconds"
--
-- If no changes:
--   "SP_MERGE_PRODUCT_DIM_SMART: No changes detected (source: 2025-01-15 10:30:00, dim: 2025-01-15 10:30:00). MERGE skipped. Duration: X seconds"
--
-- Note: The smart procedure checks _fivetran_synced timestamps to determine if the source
-- table has new or updated records. This avoids unnecessary MERGE operations when data hasn't changed.
