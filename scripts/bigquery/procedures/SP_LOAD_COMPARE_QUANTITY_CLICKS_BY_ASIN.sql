-- =============================================
-- OI Database Project - SP_LOAD_COMPARE_QUANTITY_CLICKS_BY_ASIN Stored Procedure
-- =============================================
--
-- Purpose: Load COMPARE_QUANTITY_CLICKS_BY_ASIN with comparison data
-- Pattern: TRUNCATE + INSERT (full refresh)
-- Project: onyga-482313
-- Dataset: OI
--
-- Logic:
-- 1. Aggregate STG_AMAZON_ADS by date and ASIN (split comma-separated advertised_asins)
--    - Sum ads_units and ads_clicks per ASIN+date
-- 2. Get sales & traffic data per ASIN+date
-- 3. FULL OUTER JOIN to capture all ASINs from both sources
-- 4. Calculate differences and ratios
-- 5. TRUNCATE and INSERT into comparison table
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_COMPARE_QUANTITY_CLICKS_BY_ASIN`()
OPTIONS (
  description = "Load COMPARE_QUANTITY_CLICKS_BY_ASIN with comparison data between Sales & Traffic and Amazon Ads metrics per ASIN and date. TRUNCATEs table and inserts all comparison records."
)
BEGIN
  -- Declare variables for logging
  DECLARE record_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- Step 1: TRUNCATE the comparison table
  TRUNCATE TABLE `onyga-482313.OI.COMPARE_QUANTITY_CLICKS_BY_ASIN`;

  -- Step 2: Aggregate and compare data
  INSERT INTO `onyga-482313.OI.COMPARE_QUANTITY_CLICKS_BY_ASIN` (
    asin,
    date,
    sales_quantity,
    traffic_clicks,
    ads_units,
    ads_clicks,
    quantity_minus_units,
    traffic_clicks_minus_ads_clicks,
    quantity_pct_of_units,
    traffic_clicks_pct_of_ads_clicks,
    data_source
  )
  WITH 
  -- Aggregate STG_AMAZON_ADS by date and ASIN (split comma-separated advertised_asins)
  stg_amazon_ads_by_asin AS (
    SELECT 
      date,
      TRIM(asin) AS asin,
      SUM(units) AS ads_units,
      SUM(clicks) AS ads_clicks
    FROM `onyga-482313.OI.STG_AMAZON_ADS`,
    UNNEST(SPLIT(COALESCE(advertised_asins, ''), ',')) AS asin
    WHERE advertised_asins IS NOT NULL
      AND advertised_asins != ''
      AND TRIM(asin) != ''
    GROUP BY date, TRIM(asin)
  ),
  -- Get sales and traffic data
  sales_traffic AS (
    SELECT 
      child_asin,
      date,
      SALES_QUANTITY,
      asin_sessions AS traffic_clicks
    FROM `onyga-482313.OI.V_SRC_sales_and_traffic_business_sku_report_daily`
    WHERE child_asin IS NOT NULL
  )
  -- Full outer join to compare both sides
  SELECT 
    COALESCE(st.child_asin, ads.asin) AS asin,
    COALESCE(st.date, ads.date) AS date,
    
    -- Sales & Traffic measures
    st.SALES_QUANTITY AS sales_quantity,
    st.traffic_clicks AS traffic_clicks,
    
    -- Amazon Ads measures
    ads.ads_units,
    ads.ads_clicks,
    
    -- Differences
    COALESCE(st.SALES_QUANTITY, 0) - COALESCE(ads.ads_units, 0) AS quantity_minus_units,
    COALESCE(st.traffic_clicks, 0) - COALESCE(ads.ads_clicks, 0) AS traffic_clicks_minus_ads_clicks,
    
    -- Ratios (percentages)
    CASE WHEN ads.ads_units > 0 
         THEN ROUND(st.SALES_QUANTITY * 100.0 / NULLIF(ads.ads_units, 0), 2)
         ELSE NULL END AS quantity_pct_of_units,
    
    CASE WHEN ads.ads_clicks > 0 
         THEN ROUND(st.traffic_clicks * 100.0 / NULLIF(ads.ads_clicks, 0), 2)
         ELSE NULL END AS traffic_clicks_pct_of_ads_clicks,
    
    -- Data source indicator
    CASE WHEN st.child_asin IS NULL THEN 'Ads Only' 
         WHEN ads.asin IS NULL THEN 'Sales Only'
         ELSE 'Both' END AS data_source

  FROM sales_traffic st
  FULL OUTER JOIN stg_amazon_ads_by_asin ads
    ON st.child_asin = ads.asin
    AND st.date = ads.date;

  SET record_count = @@row_count;
  SET end_time = CURRENT_TIMESTAMP();

  -- Log the operation results
  SELECT FORMAT(
    'SP_LOAD_COMPARE_QUANTITY_CLICKS_BY_ASIN completed:\n' ||
    '  Records inserted: %d\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    record_count,
    TIMESTAMP_DIFF(end_time, start_time, SECOND),
    CAST(end_time AS STRING)
  ) as operation_summary;
END;
