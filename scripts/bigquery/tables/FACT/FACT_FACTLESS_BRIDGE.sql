-- =============================================
-- OI Database Project - FACT_FACTLESS_BRIDGE Table
-- =============================================
--
-- Purpose: Factless fact table created via UNION of all fact table keys
--          Each fact contributes its own (date_key, asin) combinations
--          Uses -1 for missing key values
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE TABLE `onyga-482313.OI.FACT_FACTLESS_BRIDGE` (
  -- Time Dimension Key
  date_key INT64 NOT NULL,              -- Foreign key to TimeDIM.date_key (YYYYMMDD format), -1 if missing
  
  -- Product Identifier
  asin STRING NOT NULL,                 -- Product ASIN, 'UNKNOWN' if missing
  
  -- Factless Key
  factless_key STRING NOT NULL          -- Composite key: date_key - asin (e.g., '20240101-B0123456789')
)
PARTITION BY RANGE_BUCKET(
  date_key,
  GENERATE_ARRAY(20200101, 21000101, 10000)  -- Partition by year ranges (YYYYMMDD format)
)
CLUSTER BY date_key, asin;

-- =============================================
-- TABLE DESCRIPTION
-- =============================================
--
-- This factless fact table is created by UNION of all fact table keys.
-- Each fact table contributes its own (date_key, asin) rows.
-- DISTINCT is applied to the final UNION to ensure unique combinations.
-- Missing key values are represented as -1 for date_key or 'UNKNOWN' for asin.
--
-- Key Features:
-- - Simple UNION structure - no joins required
-- - Each fact contributes its own rows
-- - DISTINCT applied to final UNION result
-- - Only date_key and asin columns (minimal structure)
-- - Easy to extend by adding more UNION clauses
--
-- Population Strategy:
-- - Populated via stored procedure that UNIONs all fact table keys
-- - Each fact extracts (date_key, asin) from its own data
-- - Uses -1 for missing date_key, 'UNKNOWN' for missing asin
-- - DISTINCT applied to final result to remove duplicates
--
-- Usage Examples:
--
-- 1. Find all unique (date_key, asin) combinations:
--    SELECT date_key, asin
--    FROM FACT_FACTLESS_BRIDGE
--    WHERE date_key != -1 AND asin != 'UNKNOWN'
--
-- 2. Count total unique combinations:
--    SELECT COUNT(*) as total_combinations
--    FROM FACT_FACTLESS_BRIDGE
--
-- 3. Find all products for a specific date:
--    SELECT asin
--    FROM FACT_FACTLESS_BRIDGE
--    WHERE date_key = 20240101
--
-- Future Extensibility:
-- - Add new UNION ALL clause in stored procedure for new fact table
-- - Pattern: UNION ALL (SELECT date_key, asin FROM NEW_FACT_TABLE)
--
-- =============================================
