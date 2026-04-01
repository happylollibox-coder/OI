-- =============================================
-- OI Database Project - SP_LOAD_FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY
-- =============================================
--
-- Purpose: Load FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY with data from STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY
-- Method: TRUNCATE + INSERT (full refresh)
-- Source: STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`()
OPTIONS (
  description = "Load FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY with data from STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY using TRUNCATE + INSERT. Adds ad_key and factless_key fields."
)
BEGIN
  -- Declare variables for logging
  DECLARE record_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- Step 1: TRUNCATE the fact table
  TRUNCATE TABLE `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`;

  -- Step 2: INSERT all data from STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY with key calculations
  --         Includes organic rank estimation using AMAZON_IMPRESSIONS as search volume
  INSERT INTO `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` (
    Reporting_Date,
    ASIN,
    Search_Query,
    Search_Query_Score,
    DATA_SOURCE,
    Impressions,
    Clicks,
    Cart_Adds,
    ORDERS,
    AMAZON_IMPRESSIONS,
    AMAZON_Clicks,
    AMAZON_Cart_Adds,
    AMAZON_ORDERS,
    show_rate_pct,
    estimated_organic_rank,
    organic_rank_zone,
    ad_key,
    factless_key,
    ADS_Impressions,
    ADS_Clicks,
    ADS_Orders,
    ADS_Units,
    ORGANIC_ORDERS
  )
  SELECT
    Reporting_Date,
    ASIN,
    Search_Query,
    Search_Query_Score,
    DATA_SOURCE,
    Impressions,
    Clicks,
    Cart_Adds,
    ORDERS,
    AMAZON_IMPRESSIONS,
    AMAZON_Clicks,
    AMAZON_Cart_Adds,
    AMAZON_ORDERS,
    ROUND(SAFE_DIVIDE(CAST(Impressions AS FLOAT64), NULLIF(CAST(AMAZON_IMPRESSIONS AS FLOAT64), 0)) * 100, 1) AS show_rate_pct,
    ROUND(52 - 0.85 * SAFE_DIVIDE(CAST(Impressions AS FLOAT64), NULLIF(CAST(AMAZON_IMPRESSIONS AS FLOAT64), 0)) * 100, 0) AS estimated_organic_rank,
    CASE
      WHEN SAFE_DIVIDE(CAST(Impressions AS FLOAT64), NULLIF(CAST(AMAZON_IMPRESSIONS AS FLOAT64), 0)) * 100 > 35 THEN 'upper_p1'
      WHEN SAFE_DIVIDE(CAST(Impressions AS FLOAT64), NULLIF(CAST(AMAZON_IMPRESSIONS AS FLOAT64), 0)) * 100 BETWEEN 25 AND 35 THEN 'mid_p1'
      WHEN SAFE_DIVIDE(CAST(Impressions AS FLOAT64), NULLIF(CAST(AMAZON_IMPRESSIONS AS FLOAT64), 0)) * 100 BETWEEN 15 AND 25 THEN 'lower_p1'
      WHEN SAFE_DIVIDE(CAST(Impressions AS FLOAT64), NULLIF(CAST(AMAZON_IMPRESSIONS AS FLOAT64), 0)) * 100 BETWEEN 5 AND 15 THEN 'bottom_p1'
      ELSE 'page_2_plus'
    END AS organic_rank_zone,
    CONCAT(
      FORMAT_DATE('%Y%m%d', Reporting_Date),
      '-',
      COALESCE(ASIN, 'NULL'),
      '-',
      COALESCE(Search_Query, 'NULL')
    ) AS ad_key,
    CONCAT(
      FORMAT_DATE('%Y%m%d', Reporting_Date),
      '-',
      COALESCE(ASIN, 'NULL')
    ) AS factless_key,
    NULL AS ADS_Impressions,
    NULL AS ADS_Clicks,
    NULL AS ADS_Orders,
    NULL AS ADS_Units,
    NULL AS ORGANIC_ORDERS
  FROM `onyga-482313.OI.STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY`;

  -- Step 3: Prepare aggregated Ads metrics from V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY
  -- Only load dates that are <= max Reporting_Date in STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY.
  CREATE TEMP TABLE tmp_ads_metrics AS
  SELECT
    v.week_end_date AS Reporting_Date,
    v.asin AS ASIN,
    v.search_term AS Search_Query,
    v.ad_key,
    v.factless_key,
    SUM(v.impressions) AS ADS_Impressions,
    SUM(v.clicks) AS ADS_Clicks,
    SUM(v.orders) AS ADS_Orders,
    SUM(v.units) AS ADS_Units
  FROM `onyga-482313.OI.V_AMAZON_ADS_TOP_SEARCH_QUERY_TERMS_WEEKLY` v
  WHERE v.week_end_date <= (
    SELECT MAX(Reporting_Date)
    FROM `onyga-482313.OI.STG_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
  )
  GROUP BY
    Reporting_Date,
    ASIN,
    Search_Query,
    ad_key,
    factless_key;

  -- Step 4: Insert missing ad_key / factless_key combinations using Ads metrics
  -- These rows ensure referential integrity for ad_key / factless_key that exist in Ads but not in search performance.
  CREATE TEMP TABLE tmp_existing_ad_keys AS
  SELECT
    ad_key
  FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`;

  INSERT INTO `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` (
    Reporting_Date,
    ASIN,
    Search_Query,
    Search_Query_Score,
    DATA_SOURCE,
    Impressions,
    Clicks,
    Cart_Adds,
    ORDERS,
    AMAZON_IMPRESSIONS,
    AMAZON_Clicks,
    AMAZON_Cart_Adds,
    AMAZON_ORDERS,
    show_rate_pct,
    estimated_organic_rank,
    organic_rank_zone,
    ad_key,
    factless_key,
    ADS_Impressions,
    ADS_Clicks,
    ADS_Orders,
    ADS_Units,
    ORGANIC_ORDERS
  )
  SELECT
    m.Reporting_Date,
    m.ASIN,
    m.Search_Query,
    NULL AS Search_Query_Score,
    'ADS_TOP_SEARCH_QUERY_TERMS' AS DATA_SOURCE,
    NULL AS Impressions,
    NULL AS Clicks,
    NULL AS Cart_Adds,
    NULL AS ORDERS,
    NULL AS AMAZON_IMPRESSIONS,
    NULL AS AMAZON_Clicks,
    NULL AS AMAZON_Cart_Adds,
    NULL AS AMAZON_ORDERS,
    NULL AS show_rate_pct,
    NULL AS estimated_organic_rank,
    NULL AS organic_rank_zone,
    m.ad_key,
    m.factless_key,
    m.ADS_Impressions,
    m.ADS_Clicks,
    m.ADS_Orders,
    m.ADS_Units,
    NULL AS ORGANIC_ORDERS
  FROM tmp_ads_metrics m
  LEFT JOIN tmp_existing_ad_keys e
    ON e.ad_key = m.ad_key
  WHERE e.ad_key IS NULL;

  -- Step 5: Enrich all fact rows (including STG-based) with Ads metrics
  MERGE `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY` AS fact
  USING tmp_ads_metrics AS src
  ON fact.ad_key = src.ad_key
  WHEN MATCHED THEN
    UPDATE SET
      fact.ADS_Impressions = src.ADS_Impressions,
      fact.ADS_Clicks = src.ADS_Clicks,
      fact.ADS_Orders = src.ADS_Orders,
      fact.ADS_Units = src.ADS_Units;

  -- Step 6: Compute ORGANIC_ORDERS for all rows (Rule 9: row-grain measures in DB)
  UPDATE `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
  SET ORGANIC_ORDERS = GREATEST(COALESCE(ORDERS, 0) - COALESCE(ADS_Orders, 0), 0)
  WHERE TRUE;

  -- Capture total row count after all steps
  SET record_count = (
    SELECT COUNT(*) FROM `onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY`
  );
  SET end_time = CURRENT_TIMESTAMP();

  -- Log the operation results
  SELECT FORMAT(
    'SP_LOAD_FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY completed:\n' ||
    '  Records inserted: %d\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    record_count,
    TIMESTAMP_DIFF(end_time, start_time, SECOND),
    CAST(end_time AS STRING)
  ) as operation_summary;
END;
