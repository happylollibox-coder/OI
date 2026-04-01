-- =============================================
-- Quick Merge Feasibility Check
-- =============================================
-- Purpose: Check if openbridge-482712.DB.sp_ba_search_catalog_by_week_v1
--          can be merged with OI.SCP_ASIN_View_Week
-- =============================================
-- Run this in BigQuery to get a quick assessment
-- =============================================

-- ==========================================
-- SUMMARY: Merge Feasibility Assessment
-- ==========================================
WITH 
-- Get SCP table schema
scp_schema AS (
  SELECT 
    column_name,
    data_type as scp_type,
    is_nullable as scp_nullable
  FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name = 'SCP_ASIN_View_Week'
),
-- Get OpenBridge table schema
ob_schema AS (
  SELECT 
    column_name,
    data_type as ob_type,
    is_nullable as ob_nullable
  FROM `openbridge-482712.DB.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name = 'sp_ba_search_catalog_by_week_v1'
),
-- Find common columns
common_columns AS (
  SELECT 
    COALESCE(scp.column_name, ob.column_name) as column_name,
    scp.scp_type,
    ob.ob_type,
    CASE 
      WHEN scp.column_name IS NOT NULL AND ob.column_name IS NOT NULL THEN 'BOTH'
      WHEN scp.column_name IS NOT NULL THEN 'SCP_ONLY'
      WHEN ob.column_name IS NOT NULL THEN 'OPENBRIDGE_ONLY'
    END as presence,
    CASE 
      WHEN scp.column_name IS NOT NULL AND ob.column_name IS NOT NULL 
        AND scp.scp_type = ob.ob_type THEN 'SAME'
      WHEN scp.column_name IS NOT NULL AND ob.column_name IS NOT NULL 
        AND scp.scp_type != ob.ob_type THEN 'DIFFERENT'
      ELSE NULL
    END as type_match
  FROM scp_schema scp
  FULL OUTER JOIN ob_schema ob 
    ON LOWER(scp.column_name) = LOWER(ob.column_name)
),
-- Check for key columns
key_columns_check AS (
  SELECT 
    COUNTIF(LOWER(column_name) IN ('year', 'week', 'asin') AND presence = 'BOTH') as common_keys,
    COUNTIF(LOWER(column_name) = 'year' AND presence = 'BOTH') as has_year,
    COUNTIF(LOWER(column_name) = 'week' AND presence = 'BOTH') as has_week,
    COUNTIF(LOWER(column_name) = 'asin' AND presence = 'BOTH') as has_asin
  FROM common_columns
),
-- Count overlaps
overlap_stats AS (
  SELECT 
    COUNTIF(presence = 'BOTH') as common_col_count,
    COUNTIF(presence = 'BOTH' AND type_match = 'SAME') as same_type_count,
    COUNTIF(presence = 'BOTH' AND type_match = 'DIFFERENT') as diff_type_count,
    COUNTIF(presence = 'SCP_ONLY') as scp_only_count,
    COUNTIF(presence = 'OPENBRIDGE_ONLY') as ob_only_count
  FROM common_columns
)
SELECT 
  'MERGE FEASIBILITY SUMMARY' as analysis_type,
  CASE 
    WHEN kc.common_keys >= 3 AND os.common_col_count >= 5 THEN '✅ HIGHLY MERGEABLE'
    WHEN kc.common_keys >= 2 AND os.common_col_count >= 3 THEN '⚠️ MERGEABLE WITH MAPPING'
    WHEN kc.common_keys >= 1 THEN '⚠️ PARTIALLY MERGEABLE'
    ELSE '❌ NOT DIRECTLY MERGEABLE'
  END as feasibility_status,
  kc.has_year as has_year_key,
  kc.has_week as has_week_key,
  kc.has_asin as has_asin_key,
  os.common_col_count as common_columns,
  os.same_type_count as compatible_types,
  os.diff_type_count as needs_casting,
  os.scp_only_count as scp_unique_columns,
  os.ob_only_count as ob_unique_columns,
  CASE 
    WHEN kc.common_keys >= 3 THEN 'Use JOIN on Year, Week, ASIN'
    WHEN kc.common_keys >= 2 THEN 'Use JOIN with available keys + mapping'
    WHEN kc.common_keys >= 1 THEN 'Use UNION with column mapping'
    ELSE 'Need schema transformation first'
  END as recommended_merge_strategy
FROM key_columns_check kc
CROSS JOIN overlap_stats os;

-- ==========================================
-- DETAILED: Column-by-Column Comparison
-- ==========================================
SELECT 
  'COLUMN COMPARISON' as analysis_type,
  COALESCE(scp.column_name, ob.column_name) as column_name,
  scp.scp_type,
  ob.ob_type,
  CASE 
    WHEN scp.column_name IS NOT NULL AND ob.column_name IS NOT NULL THEN '✅ BOTH'
    WHEN scp.column_name IS NOT NULL THEN '📊 SCP_ONLY'
    WHEN ob.column_name IS NOT NULL THEN '📊 OPENBRIDGE_ONLY'
  END as presence,
  CASE 
    WHEN scp.column_name IS NOT NULL AND ob.column_name IS NOT NULL 
      AND scp.scp_type = ob.ob_type THEN '✅ SAME'
    WHEN scp.column_name IS NOT NULL AND ob.column_name IS NOT NULL 
      AND scp.scp_type != ob.ob_type THEN '⚠️ DIFFERENT'
    ELSE 'N/A'
  END as type_compatibility
FROM (
  SELECT column_name, data_type as scp_type
  FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name = 'SCP_ASIN_View_Week'
) scp
FULL OUTER JOIN (
  SELECT column_name, data_type as ob_type
  FROM `openbridge-482712.DB.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name = 'sp_ba_search_catalog_by_week_v1'
) ob ON LOWER(scp.column_name) = LOWER(ob.column_name)
ORDER BY 
  CASE 
    WHEN scp.column_name IS NOT NULL AND ob.column_name IS NOT NULL THEN 1
    WHEN scp.column_name IS NOT NULL THEN 2
    ELSE 3
  END,
  column_name;

-- ==========================================
-- DATA OVERLAP: Check ASIN/Year/Week overlap
-- ==========================================
WITH 
scp_keys AS (
  SELECT DISTINCT 
    ASIN, 
    Year, 
    Week
  FROM `onyga-482313.OI.SCP_ASIN_View_Week`
  WHERE ASIN IS NOT NULL
),
ob_keys AS (
  SELECT DISTINCT 
    ASIN, 
    Year, 
    Week
  FROM `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1`
  WHERE ASIN IS NOT NULL
)
SELECT 
  'DATA OVERLAP ANALYSIS' as analysis_type,
  (SELECT COUNT(DISTINCT ASIN) FROM scp_keys) as scp_unique_asins,
  (SELECT COUNT(DISTINCT ASIN) FROM ob_keys) as ob_unique_asins,
  (SELECT COUNT(DISTINCT s.ASIN) 
   FROM scp_keys s 
   INNER JOIN ob_keys o 
     ON s.ASIN = o.ASIN 
     AND s.Year = o.Year 
     AND s.Week = o.Week) as overlapping_records,
  (SELECT COUNT(DISTINCT s.ASIN) 
   FROM scp_keys s 
   INNER JOIN ob_keys o ON s.ASIN = o.ASIN) as overlapping_asins,
  ROUND(
    (SELECT COUNT(DISTINCT s.ASIN) 
     FROM scp_keys s 
     INNER JOIN ob_keys o ON s.ASIN = o.ASIN) * 100.0 / 
    NULLIF((SELECT COUNT(DISTINCT ASIN) FROM scp_keys), 0), 
    2
  ) as scp_overlap_pct,
  ROUND(
    (SELECT COUNT(DISTINCT s.ASIN) 
     FROM scp_keys s 
     INNER JOIN ob_keys o ON s.ASIN = o.ASIN) * 100.0 / 
    NULLIF((SELECT COUNT(DISTINCT ASIN) FROM ob_keys), 0), 
    2
  ) as ob_overlap_pct;

-- ==========================================
-- SAMPLE DATA: Compare actual data structure
-- ==========================================
-- Sample from SCP table
SELECT 
  'SCP_SAMPLE' as source,
  Year,
  Week,
  ASIN,
  Start_date,
  End_Date,
  Reporting_Date,
  ASIN_Title,
  Impressions_Impressions,
  Clicks_Clicks,
  Purchases_Purchases
FROM `onyga-482313.OI.SCP_ASIN_View_Week`
WHERE ASIN IS NOT NULL
ORDER BY Year DESC, Week DESC, ASIN
LIMIT 3;

-- Sample from OpenBridge table  
SELECT 
  'OPENBRIDGE_SAMPLE' as source,
  Year,
  Week,
  ASIN,
  -- Add other key columns as needed
  *
FROM `openbridge-482712.DB.sp_ba_search_catalog_by_week_v1`
WHERE ASIN IS NOT NULL
ORDER BY Year DESC, Week DESC, ASIN
LIMIT 3;
