-- =============================================
-- Inspect Source Table Structure
-- =============================================
-- 
-- Purpose: Query the source table structure to understand columns
-- Source: openbridge-482712.DB.sp_ba_search_query_by_week_v1
-- 
-- Run this query in BigQuery to see the actual column structure
-- Then adjust STG_SQP_WEEKLY.sql and SP_MERGE_SQP_WEEKLY.sql accordingly
--
-- =============================================

-- Get column information
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM `openbridge-482712.DB.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'sp_ba_search_query_by_week_v1'
ORDER BY ordinal_position;

-- Get sample data to understand structure
SELECT *
FROM `openbridge-482712.DB.sp_ba_search_query_by_week_v1`
LIMIT 5;

-- Count total rows
SELECT COUNT(*) as total_rows
FROM `openbridge-482712.DB.sp_ba_search_query_by_week_v1`;
