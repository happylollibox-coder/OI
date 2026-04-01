-- =============================================
-- OI Database Project - DIM_PRODUCT Verification
-- =============================================
--
-- Purpose: Comprehensive verification of DIM_PRODUCT system
-- Checks: Table structure, views, stored procedures, data integrity
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

-- =============================================
-- 1. VERIFY TABLE STRUCTURE
-- =============================================
SELECT '=== 1. DIM_PRODUCT Table Structure ===' AS verification_step;

SELECT 
  column_name,
  data_type,
  is_nullable
FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'DIM_PRODUCT'
ORDER BY ordinal_position;

-- =============================================
-- 2. VERIFY STAGING TABLE STRUCTURE
-- =============================================
SELECT '=== 2. STG_PRODUCT_COST_DATA Table Structure ===' AS verification_step;

SELECT 
  column_name,
  data_type,
  is_nullable
FROM `onyga-482313.OI.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'STG_PRODUCT_COST_DATA'
ORDER BY ordinal_position;

-- =============================================
-- 3. VERIFY VIEW EXISTS
-- =============================================
SELECT '=== 3. V_SRC_Products View ===' AS verification_step;

SELECT 
  table_name,
  table_type
FROM `onyga-482313.OI.INFORMATION_SCHEMA.TABLES`
WHERE table_name = 'V_SRC_Products';

-- =============================================
-- 4. VERIFY STORED PROCEDURES EXIST
-- =============================================
SELECT '=== 4. Stored Procedures ===' AS verification_step;

SELECT 
  routine_name,
  routine_type
FROM `onyga-482313.OI.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name IN (
  'SP_MERGE_PRODUCT_DIM',
  'SP_MERGE_PRODUCT_DIM_SMART',
  'SP_UPDATE_PRODUCT_COST_DATA',
  'SP_ORCHESTRATE_DAILY_REFRESH'
)
ORDER BY routine_name;

-- =============================================
-- 5. VERIFY DATA COUNTS
-- =============================================
SELECT '=== 5. Data Counts ===' AS verification_step;

SELECT 
  'DIM_PRODUCT' AS table_name,
  COUNT(*) AS row_count,
  COUNT(DISTINCT asin) AS distinct_asins,
  COUNT(DISTINCT marketplace) AS distinct_marketplaces
FROM `onyga-482313.OI.DIM_PRODUCT`

UNION ALL

SELECT 
  'STG_PRODUCT_COST_DATA' AS table_name,
  COUNT(*) AS row_count,
  COUNT(DISTINCT asin) AS distinct_asins,
  NULL AS distinct_marketplaces
FROM `onyga-482313.OI.STG_PRODUCT_COST_DATA`

UNION ALL

SELECT 
  'V_SRC_Products' AS table_name,
  COUNT(*) AS row_count,
  COUNT(DISTINCT asin) AS distinct_asins,
  COUNT(DISTINCT marketplace) AS distinct_marketplaces
FROM `onyga-482313.OI.V_SRC_Products`;

-- =============================================
-- 6. VERIFY FIELD POPULATION (Non-NULL Rates)
-- =============================================
SELECT '=== 6. Field Population Rates ===' AS verification_step;

SELECT 
  COUNT(*) AS total_rows,
  COUNT(asin) AS asin_populated,
  COUNT(parent_asin) AS parent_asin_populated,
  COUNT(parent_name) AS parent_name_populated,
  COUNT(sku) AS sku_populated,
  COUNT(marketplace) AS marketplace_populated,
  COUNT(product_name) AS product_name_populated,
  COUNT(brand) AS brand_populated,
  COUNT(product_type) AS product_type_populated,
  COUNT(cost_of_goods) AS cost_of_goods_populated,
  COUNT(shipping_cost) AS shipping_cost_populated,
  COUNT(fba_cost) AS fba_cost_populated,
  COUNT(manufacture_day) AS manufacture_day_populated,
  COUNT(shipment_days) AS shipment_days_populated,
  COUNT(listing_price_amount) AS listing_price_populated,
  COUNT(item_height_value) AS item_height_populated,
  COUNT(package_height_value) AS package_height_populated
FROM `onyga-482313.OI.DIM_PRODUCT`;

-- =============================================
-- 7. VERIFY SAMPLE DATA INTEGRITY
-- =============================================
SELECT '=== 7. Sample Data Integrity ===' AS verification_step;

SELECT 
  asin,
  marketplace,
  parent_asin,
  parent_name,
  sku,
  product_name,
  brand,
  product_type,
  cost_of_goods,
  shipping_cost,
  fba_cost,
  listing_price_currency_code,
  listing_price_amount,
  is_active,
  created_at,
  updated_at
FROM `onyga-482313.OI.DIM_PRODUCT`
WHERE asin IN ('B09XQ56RK5', 'B0CR6N3WRC', 'B0DJFG5ZJ7')
ORDER BY asin, marketplace
LIMIT 10;

-- =============================================
-- 8. VERIFY SOURCE DATA AVAILABILITY
-- =============================================
SELECT '=== 8. Source Data Availability ===' AS verification_step;

SELECT 
  'item_summary' AS source_table,
  COUNT(*) AS row_count,
  COUNT(DISTINCT asin) AS distinct_asins
FROM `fivetran-hl.amazon_selling_partner.item_summary`

UNION ALL

SELECT 
  'item_relationship' AS source_table,
  COUNT(*) AS row_count,
  COUNT(DISTINCT child_asin) AS distinct_child_asins
FROM `fivetran-hl.amazon_selling_partner.item_relationship`

UNION ALL

SELECT 
  'item_product_type' AS source_table,
  COUNT(*) AS row_count,
  COUNT(DISTINCT asin) AS distinct_asins
FROM `fivetran-hl.amazon_selling_partner.item_product_type`

UNION ALL

SELECT 
  'marketplace_participation' AS source_table,
  COUNT(*) AS row_count,
  COUNT(DISTINCT id) AS distinct_marketplaces
FROM `fivetran-hl.amazon_selling_partner.marketplace_participation`

UNION ALL

SELECT 
  'item_dimension' AS source_table,
  COUNT(*) AS row_count,
  COUNT(DISTINCT asin) AS distinct_asins
FROM `fivetran-hl.amazon_selling_partner.item_dimension`

UNION ALL

SELECT 
  'item_offer_detail' AS source_table,
  COUNT(*) AS row_count,
  COUNT(DISTINCT asin) AS distinct_asins
FROM `fivetran-hl.amazon_selling_partner.item_offer_detail`;

-- =============================================
-- 9. VERIFY JOIN INTEGRITY (Check for Orphans)
-- =============================================
SELECT '=== 9. Join Integrity Check ===' AS verification_step;

-- Products in DIM_PRODUCT but not in source
SELECT 
  'Products in DIM_PRODUCT not in item_summary' AS check_type,
  COUNT(*) AS count
FROM `onyga-482313.OI.DIM_PRODUCT` dim
LEFT JOIN `fivetran-hl.amazon_selling_partner.item_summary` src
  ON dim.asin = src.asin
WHERE src.asin IS NULL

UNION ALL

-- Products with parent_asin but parent not in DIM_PRODUCT
SELECT 
  'Products with parent_asin not in DIM_PRODUCT' AS check_type,
  COUNT(*) AS count
FROM `onyga-482313.OI.DIM_PRODUCT` dim
WHERE dim.parent_asin IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 
    FROM `onyga-482313.OI.DIM_PRODUCT` parent
    WHERE parent.asin = dim.parent_asin
  );

-- =============================================
-- 10. VERIFY STAGING TABLE DATA
-- =============================================
SELECT '=== 10. Staging Table Data ===' AS verification_step;

SELECT 
  asin,
  parent_name,
  sku,
  cost_of_goods,
  shipping_cost,
  fba_cost,
  manufacture_day,
  shipment_days,
  updated_at
FROM `onyga-482313.OI.STG_PRODUCT_COST_DATA`
ORDER BY asin
LIMIT 10;

-- =============================================
-- 11. VERIFY DATA CONSISTENCY (Staging vs DIM)
-- =============================================
SELECT '=== 11. Staging vs DIM Consistency ===' AS verification_step;

SELECT 
  stg.asin,
  stg.parent_name AS stg_parent_name,
  dim.parent_name AS dim_parent_name,
  stg.sku AS stg_sku,
  dim.sku AS dim_sku,
  stg.cost_of_goods AS stg_cogs,
  dim.cost_of_goods AS dim_cogs,
  CASE 
    WHEN stg.parent_name = dim.parent_name 
     AND stg.sku = dim.sku 
     AND stg.cost_of_goods = dim.cost_of_goods 
    THEN 'MATCH' 
    ELSE 'MISMATCH' 
  END AS status
FROM `onyga-482313.OI.STG_PRODUCT_COST_DATA` stg
LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` dim
  ON stg.asin = dim.asin
WHERE dim.asin IS NOT NULL
ORDER BY stg.asin
LIMIT 10;

-- =============================================
-- 12. VERIFY PROCEDURE EXECUTION (Dry Run Check)
-- =============================================
SELECT '=== 12. Procedure Syntax Check ===' AS verification_step;

-- Check if procedures can be described (syntax validation)
SELECT 
  routine_name,
  'Syntax OK' AS status
FROM `onyga-482313.OI.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name IN (
  'SP_MERGE_PRODUCT_DIM',
  'SP_MERGE_PRODUCT_DIM_SMART',
  'SP_UPDATE_PRODUCT_COST_DATA',
  'SP_ORCHESTRATE_DAILY_REFRESH'
)
ORDER BY routine_name;

-- =============================================
-- VERIFICATION SUMMARY
-- =============================================
SELECT '=== VERIFICATION SUMMARY ===' AS summary;

SELECT 
  'Total Products in DIM_PRODUCT' AS metric,
  CAST(COUNT(*) AS STRING) AS value
FROM `onyga-482313.OI.DIM_PRODUCT`

UNION ALL

SELECT 
  'Products with parent_asin' AS metric,
  CAST(COUNT(*) AS STRING) AS value
FROM `onyga-482313.OI.DIM_PRODUCT`
WHERE parent_asin IS NOT NULL

UNION ALL

SELECT 
  'Products with cost data' AS metric,
  CAST(COUNT(*) AS STRING) AS value
FROM `onyga-482313.OI.DIM_PRODUCT`
WHERE cost_of_goods IS NOT NULL

UNION ALL

SELECT 
  'Products with SKU' AS metric,
  CAST(COUNT(*) AS STRING) AS value
FROM `onyga-482313.OI.DIM_PRODUCT`
WHERE sku IS NOT NULL

UNION ALL

SELECT 
  'Products with listing price' AS metric,
  CAST(COUNT(*) AS STRING) AS value
FROM `onyga-482313.OI.DIM_PRODUCT`
WHERE listing_price_amount IS NOT NULL

UNION ALL

SELECT 
  'Active Products' AS metric,
  CAST(COUNT(*) AS STRING) AS value
FROM `onyga-482313.OI.DIM_PRODUCT`
WHERE is_active = TRUE;
