-- =============================================
-- Table Merge Feasibility Analysis
-- =============================================
-- Purpose: Check if openbridge-482712.DB.sp_ba_search_catalog_by_week_v1
--          can be merged with OI.SCP_ASIN_View_Week
-- =============================================

-- ==========================================
-- 1. GET SCHEMA FOR SCP_ASIN_View_Week
-- ==========================================
SELECT 
    'SCP_ASIN_View_Week' as table_name,
    column_name,
    data_type,
    is_nullable,
    ordinal_position
FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'SCP_ASIN_View_Week'
ORDER BY ordinal_position;

-- ==========================================
-- 2. GET SCHEMA FOR openbridge table
-- ==========================================
SELECT 
    'sp_ba_search_catalog_by_week_v1' as table_name,
    column_name,
    data_type,
    is_nullable,
    ordinal_position
FROM `openbridge-482712.DB.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'sp_ba_search_catalog_by_week_v1'
ORDER BY ordinal_position;

-- ==========================================
-- 3. COMPARE SCHEMAS - FIND COMMON COLUMNS
-- ==========================================
WITH scp_columns AS (
  SELECT 
    column_name,
    data_type as scp_data_type,
    is_nullable as scp_nullable
  FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name = 'SCP_ASIN_View_Week'
),
openbridge_columns AS (
  SELECT 
    column_name,
    data_type as ob_data_type,
    is_nullable as ob_nullable
  FROM `openbridge-482712.DB.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name = 'sp_ba_search_catalog_by_week_v1'
)
SELECT 
    COALESCE(scp.column_name, ob.column_name) as column_name,
    scp.scp_data_type,
    ob.ob_data_type,
    scp.scp_nullable,
    ob.ob_nullable,
    CASE 
        WHEN scp.column_name IS NOT NULL AND ob.column_name IS NOT NULL THEN 'BOTH'
        WHEN scp.column_name IS NOT NULL THEN 'SCP_ONLY'
        WHEN ob.column_name IS NOT NULL THEN 'OPENBRIDGE_ONLY'
    END as column_presence,
    CASE 
        WHEN scp.column_name IS NOT NULL AND ob.column_name IS NOT NULL 
            AND scp.scp_data_type = ob.ob_data_type THEN 'SAME_TYPE'
        WHEN scp.column_name IS NOT NULL AND ob.column_name IS NOT NULL 
            AND scp.scp_data_type != ob.ob_data_type THEN 'DIFFERENT_TYPE'
        ELSE 'N/A'
    END as type_match
FROM scp_columns scp
FULL OUTER JOIN openbridge_columns ob 
  ON LOWER(scp.column_name) = LOWER(ob.column_name)
ORDER BY 
    CASE column_presence
        WHEN 'BOTH' THEN 1
        WHEN 'SCP_ONLY' THEN 2
        ELSE 3
    END,
    column_name;

-- ==========================================
-- 4. IDENTIFY POTENTIAL MERGE KEYS
-- ==========================================
-- Check for common key columns (Year, Week, ASIN, etc.)
WITH common_key_columns AS (
  SELECT column_name
  FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name = 'SCP_ASIN_View_Week'
    AND LOWER(column_name) IN ('year', 'week', 'asin', 'start_date', 'end_date', 'reporting_date')
  INTERSECT DISTINCT
  SELECT column_name
  FROM `openbridge-482712.DB.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name = 'sp_ba_search_catalog_by_week_v1'
    AND LOWER(column_name) IN ('year', 'week', 'asin', 'start_date', 'end_date', 'reporting_date')
)
SELECT 
    'Potential Merge Keys' as analysis_type,
    column_name,
    'Common to both tables' as status
FROM common_key_columns
ORDER BY 
    CASE LOWER(column_name)
        WHEN 'asin' THEN 1
        WHEN 'year' THEN 2
        WHEN 'week' THEN 3
        WHEN 'start_date' THEN 4
        WHEN 'end_date' THEN 5
        WHEN 'reporting_date' THEN 6
        ELSE 7
    END;

-- ==========================================
-- 5. SAMPLE DATA COMPARISON
-- ==========================================
-- Get sample rows to understand data structure

-- Sample from SCP_ASIN_View_Week
SELECT 
    'SCP_ASIN_View_Week' as source,
    Year,
    Week,
    ASIN,
    Start_date,
    End_Date,
    Reporting_Date,
    ASIN_Title,
    Category,
    Impressions_Impressions,
    Clicks_Clicks,
    Purchases_Purchases
FROM `onyga-482313.OI.SCP_ASIN_View_Week`
LIMIT 5;

-- Sample from openbridge table
SELECT 
    'sp_ba_search_catalog_by_week_v1' as source,
    Year,
    Week,
    ASIN,
    -- Add other key columns based on schema
    *
FROM `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1`
LIMIT 5;

-- ==========================================
-- 6. DATA VOLUME COMPARISON
-- ==========================================
SELECT 
    'SCP_ASIN_View_Week' as table_name,
    COUNT(*) as row_count,
    COUNT(DISTINCT ASIN) as unique_asins,
    COUNT(DISTINCT Year) as unique_years,
    COUNT(DISTINCT Week) as unique_weeks,
    MIN(Year) as min_year,
    MAX(Year) as max_year
FROM `onyga-482313.OI.SCP_ASIN_View_Week`
UNION ALL
SELECT 
    'sp_ba_search_catalog_by_week_v1' as table_name,
    COUNT(*) as row_count,
    COUNT(DISTINCT ASIN) as unique_asins,
    COUNT(DISTINCT Year) as unique_years,
    COUNT(DISTINCT Week) as unique_weeks,
    MIN(Year) as min_year,
    MAX(Year) as max_year
FROM `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1`;

-- ==========================================
-- 7. OVERLAP ANALYSIS (if keys exist)
-- ==========================================
-- Check ASIN overlap between tables
WITH scp_asins AS (
    SELECT DISTINCT ASIN, Year, Week
    FROM `onyga-482313.OI.SCP_ASIN_View_Week`
    WHERE ASIN IS NOT NULL
),
ob_asins AS (
    SELECT DISTINCT ASIN, Year, Week
    FROM `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1`
    WHERE ASIN IS NOT NULL
)
SELECT 
    'ASIN Overlap Analysis' as analysis_type,
    COUNT(DISTINCT scp.ASIN) as scp_unique_asins,
    COUNT(DISTINCT ob.ASIN) as ob_unique_asins,
    COUNT(DISTINCT CASE WHEN ob.ASIN IS NOT NULL THEN scp.ASIN END) as overlapping_asins,
    ROUND(COUNT(DISTINCT CASE WHEN ob.ASIN IS NOT NULL THEN scp.ASIN END) * 100.0 / 
          NULLIF(COUNT(DISTINCT scp.ASIN), 0), 2) as scp_overlap_pct,
    ROUND(COUNT(DISTINCT CASE WHEN ob.ASIN IS NOT NULL THEN scp.ASIN END) * 100.0 / 
          NULLIF(COUNT(DISTINCT ob.ASIN), 0), 2) as ob_overlap_pct
FROM scp_asins scp
LEFT JOIN ob_asins ob 
    ON scp.ASIN = ob.ASIN 
    AND scp.Year = ob.Year 
    AND scp.Week = ob.Week;

-- ==========================================
-- 8. MERGE FEASIBILITY ASSESSMENT
-- ==========================================
-- This query summarizes the merge feasibility based on common columns and keys
SELECT 
    'MERGE_FEASIBILITY_SUMMARY' as analysis_type,
    CASE 
        WHEN (SELECT COUNT(*) FROM (
            SELECT column_name FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
            WHERE table_name = 'SCP_ASIN_View_Week'
            INTERSECT DISTINCT
            SELECT column_name FROM `openbridge-482712.DB.INFORMATION_SCHEMA.COLUMNS`
            WHERE table_name = 'sp_ba_search_catalog_by_week_v1'
        )) > 3 THEN 'LIKELY_MERGEABLE'
        ELSE 'NEEDS_REVIEW'
    END as feasibility,
    (SELECT COUNT(*) FROM (
        SELECT column_name FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
        WHERE table_name = 'SCP_ASIN_View_Week'
        INTERSECT DISTINCT
        SELECT column_name FROM `openbridge-482712.DB.INFORMATION_SCHEMA.COLUMNS`
        WHERE table_name = 'sp_ba_search_catalog_by_week_v1'
    )) as common_column_count,
    'Run all queries above for detailed analysis' as next_steps;
