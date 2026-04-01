-- =============================================
-- Check FBA Inventory Summary Schema
-- =============================================
-- Run this query to see the actual schema of fba_inventory_summary
-- Use the results to adjust SP_UPDATE_FBA_INVENTORY_MONTHLY_SNAPSHOT.sql
-- =============================================

-- Get column names and types
SELECT 
  column_name,
  data_type,
  is_nullable,
  ordinal_position
FROM `fivetran-hl.amazon_selling_partner.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'fba_inventory_summary'
ORDER BY ordinal_position;

-- Sample data to understand structure
SELECT *
FROM `fivetran-hl.amazon_selling_partner.fba_inventory_summary`
WHERE granularity_id = 'ATVPDKIKX0DER'
LIMIT 5;

-- Check for granularity_id values
SELECT 
  granularity_id,
  COUNT(*) as record_count
FROM `fivetran-hl.amazon_selling_partner.fba_inventory_summary`
GROUP BY granularity_id
ORDER BY record_count DESC;
