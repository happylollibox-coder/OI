-- =============================================
-- OI Database Project - SP_LOAD_FACT_SEARCH_QUERY Stored Procedure
-- =============================================
--
-- Purpose: Load FACT_SEARCH_QUERY with SQP data from SRC_ACC_SQP_WEEKLY
--          and delta records (SCP - SUM(SQP))
-- Pattern: TRUNCATE + INSERT (full refresh)
-- Source: SRC_ACC_SQP_WEEKLY (manual uploads, most up-to-date SQP source)
-- Project: onyga-482313
-- Dataset: OI
--
-- Logic:
-- 1. TRUNCATE FACT_SEARCH_QUERY
-- 2. INSERT all SQP data from SRC_ACC_SQP_WEEKLY with data_source = 'SQP'
-- 3. Calculate delta (SCP - SUM(SQP)) per ASIN+Year+Week and insert with query_text = 'OTHER'
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_FACT_SEARCH_QUERY`()
OPTIONS (
  description = "Load FACT_SEARCH_QUERY from SRC_ACC_SQP_WEEKLY (primary SQP source) plus delta records (SCP - SUM(SQP)). Full refresh via TRUNCATE + INSERT."
)
BEGIN
  DECLARE sqp_count INT64 DEFAULT 0;
  DECLARE delta_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  TRUNCATE TABLE `onyga-482313.OI.FACT_SEARCH_QUERY`;

  -- Step 2: INSERT SQP data from SRC_ACC_SQP_WEEKLY with column mapping
  --         Includes organic rank estimation: show_rate = impr / search_volume
  --         Formula calibrated from manual rank checks (Feb 2026):
  --           estimated_rank = 52 - 0.85 * show_rate_pct
  --         Accuracy: ±4 positions on 5 confirmed data points
  INSERT INTO `onyga-482313.OI.FACT_SEARCH_QUERY` (
    query_text,
    ASIN,
    Year,
    Week,
    ob_date,
    week_start_date,
    week_end_date,
    impressions,
    clicks,
    click_through_rate,
    cart_adds,
    conversions,
    conversion_rate,
    sales_amount,
    sales_currency_code,
    TOTAL_IMPRESSIONS,
    TOTAL_CLICKS,
    TOTAL_CART_ADDS,
    TOTAL_PURCHASES,
    total_median_click_price,
    asin_median_click_price,
    query_rank,
    avg_position,
    search_query_volume,
    impression_share_pct,
    show_rate_pct,
    estimated_organic_rank,
    organic_rank_zone,
    ob_file_name,
    ob_marketplace_id,
    ob_seller_id,
    ob_transaction_id,
    ob_modified_date,
    ob_processed_at,
    data_source
  )
  SELECT
    src.Search_Query as query_text,
    src.ASIN,
    EXTRACT(YEAR FROM src.Reporting_Date) as Year,
    EXTRACT(WEEK FROM src.Reporting_Date) as Week,
    src.Reporting_Date as ob_date,
    DATE_SUB(src.Reporting_Date, INTERVAL 6 DAY) as week_start_date,
    src.Reporting_Date as week_end_date,
    CAST(src.Impressions_ASIN_Count AS INT64) as impressions,
    CAST(src.Clicks_ASIN_Count AS INT64) as clicks,
    SAFE_CAST(src.Clicks_Click_Rate AS FLOAT64) as click_through_rate,
    CAST(src.Cart_Adds_ASIN_Count AS INT64) as cart_adds,
    CAST(src.Purchases_ASIN_Count AS INT64) as conversions,
    SAFE_CAST(src.Purchases_Purchase_Rate AS FLOAT64) as conversion_rate,
    CASE
      WHEN SAFE_CAST(src.Purchases_ASIN_Count AS INT64) > 0
        AND SAFE_CAST(src.Purchases_ASIN_Price_Median AS FLOAT64) IS NOT NULL
      THEN SAFE_CAST(src.Purchases_ASIN_Count AS INT64) * SAFE_CAST(src.Purchases_ASIN_Price_Median AS FLOAT64)
      ELSE NULL
    END as sales_amount,
    'USD' as sales_currency_code,
    CAST(src.Impressions_Total_Count AS INT64) as TOTAL_IMPRESSIONS,
    CAST(src.Clicks_Total_Count AS INT64) as TOTAL_CLICKS,
    CAST(src.Cart_Adds_Total_Count AS INT64) as TOTAL_CART_ADDS,
    CAST(src.Purchases_Total_Count AS INT64) as TOTAL_PURCHASES,
    SAFE_CAST(src.Clicks_Price_Median AS FLOAT64) as total_median_click_price,
    SAFE_CAST(src.Clicks_ASIN_Price_Median AS FLOAT64) as asin_median_click_price,
    CAST(NULL AS INT64) as query_rank,
    CAST(NULL AS FLOAT64) as avg_position,
    CAST(src.Search_Query_Volume AS INT64) as search_query_volume,
    ROUND(SAFE_DIVIDE(
      CAST(src.Impressions_ASIN_Count AS FLOAT64),
      NULLIF(CAST(src.Impressions_Total_Count AS FLOAT64), 0)
    ) * 100, 2) as impression_share_pct,
    ROUND(SAFE_DIVIDE(
      CAST(src.Impressions_ASIN_Count AS FLOAT64),
      NULLIF(CAST(src.Search_Query_Volume AS FLOAT64), 0)
    ) * 100, 1) as show_rate_pct,
    ROUND(52 - 0.85 * SAFE_DIVIDE(
      CAST(src.Impressions_ASIN_Count AS FLOAT64),
      NULLIF(CAST(src.Search_Query_Volume AS FLOAT64), 0)
    ) * 100, 0) as estimated_organic_rank,
    CASE
      WHEN SAFE_DIVIDE(
        CAST(src.Impressions_ASIN_Count AS FLOAT64),
        NULLIF(CAST(src.Search_Query_Volume AS FLOAT64), 0)
      ) * 100 > 35 THEN 'upper_p1'
      WHEN SAFE_DIVIDE(
        CAST(src.Impressions_ASIN_Count AS FLOAT64),
        NULLIF(CAST(src.Search_Query_Volume AS FLOAT64), 0)
      ) * 100 BETWEEN 25 AND 35 THEN 'mid_p1'
      WHEN SAFE_DIVIDE(
        CAST(src.Impressions_ASIN_Count AS FLOAT64),
        NULLIF(CAST(src.Search_Query_Volume AS FLOAT64), 0)
      ) * 100 BETWEEN 15 AND 25 THEN 'lower_p1'
      WHEN SAFE_DIVIDE(
        CAST(src.Impressions_ASIN_Count AS FLOAT64),
        NULLIF(CAST(src.Search_Query_Volume AS FLOAT64), 0)
      ) * 100 BETWEEN 5 AND 15 THEN 'bottom_p1'
      ELSE 'page_2_plus'
    END as organic_rank_zone,
    src.source_file as ob_file_name,
    CAST(NULL AS STRING) as ob_marketplace_id,
    CAST(NULL AS STRING) as ob_seller_id,
    CAST(NULL AS STRING) as ob_transaction_id,
    CAST(NULL AS DATETIME) as ob_modified_date,
    CAST(src.processed_at AS STRING) as ob_processed_at,
    'SQP' as data_source
  FROM `onyga-482313.OI.SRC_ACC_SQP_WEEKLY` src
  WHERE src.Search_Query IS NOT NULL
    AND src.ASIN IS NOT NULL;

  SET sqp_count = @@row_count;

  -- Step 3: Calculate and INSERT delta records (SCP - SUM(SQP)) per ASIN+Year+Week
  INSERT INTO `onyga-482313.OI.FACT_SEARCH_QUERY` (
    query_text,
    ASIN,
    Year,
    Week,
    ob_date,
    week_start_date,
    week_end_date,
    impressions,
    clicks,
    click_through_rate,
    cart_adds,
    conversions,
    conversion_rate,
    sales_amount,
    sales_currency_code,
    TOTAL_IMPRESSIONS,
    TOTAL_CLICKS,
    TOTAL_CART_ADDS,
    TOTAL_PURCHASES,
    total_median_click_price,
    asin_median_click_price,
    query_rank,
    avg_position,
    search_query_volume,
    impression_share_pct,
    show_rate_pct,
    estimated_organic_rank,
    organic_rank_zone,
    ob_file_name,
    ob_marketplace_id,
    ob_seller_id,
    ob_transaction_id,
    ob_modified_date,
    ob_processed_at,
    data_source
  )
  WITH sqp_aggregated AS (
    SELECT
      ASIN,
      EXTRACT(YEAR FROM Reporting_Date) as Year,
      EXTRACT(WEEK FROM Reporting_Date) as Week,
      SUM(SAFE_CAST(Impressions_ASIN_Count AS INT64)) as sqp_impressions,
      SUM(SAFE_CAST(Clicks_ASIN_Count AS INT64)) as sqp_clicks,
      SUM(SAFE_CAST(Cart_Adds_ASIN_Count AS INT64)) as sqp_cart_adds,
      SUM(SAFE_CAST(Purchases_ASIN_Count AS INT64)) as sqp_conversions,
      SUM(
        CASE
          WHEN SAFE_CAST(Purchases_ASIN_Count AS INT64) > 0
            AND SAFE_CAST(Purchases_ASIN_Price_Median AS FLOAT64) IS NOT NULL
          THEN SAFE_CAST(Purchases_ASIN_Count AS INT64) * SAFE_CAST(Purchases_ASIN_Price_Median AS FLOAT64)
          ELSE 0
        END
      ) as sqp_sales_amount
    FROM `onyga-482313.OI.SRC_ACC_SQP_WEEKLY`
    WHERE ASIN IS NOT NULL
    GROUP BY ASIN, Year, Week
  )
  SELECT
    'OTHER' as query_text,
    scp.ASIN,
    scp.Year,
    scp.Week,
    scp.ob_date,
    scp.week_start_date,
    scp.week_end_date,
    scp.impressions - COALESCE(sqp.sqp_impressions, 0) as impressions,
    scp.clicks - COALESCE(sqp.sqp_clicks, 0) as clicks,
    CASE
      WHEN (scp.impressions - COALESCE(sqp.sqp_impressions, 0)) > 0
      THEN ((scp.clicks - COALESCE(sqp.sqp_clicks, 0)) / (scp.impressions - COALESCE(sqp.sqp_impressions, 0))) * 100.0
      ELSE 0.0
    END as click_through_rate,
    scp.cart_adds - COALESCE(sqp.sqp_cart_adds, 0) as cart_adds,
    scp.conversions - COALESCE(sqp.sqp_conversions, 0) as conversions,
    CASE
      WHEN (scp.clicks - COALESCE(sqp.sqp_clicks, 0)) > 0
      THEN ((scp.conversions - COALESCE(sqp.sqp_conversions, 0)) / (scp.clicks - COALESCE(sqp.sqp_clicks, 0))) * 100.0
      ELSE 0.0
    END as conversion_rate,
    scp.sales_amount - COALESCE(sqp.sqp_sales_amount, 0) as sales_amount,
    scp.sales_currency_code,
    CAST(NULL AS INT64) as TOTAL_IMPRESSIONS,
    CAST(NULL AS INT64) as TOTAL_CLICKS,
    CAST(NULL AS INT64) as TOTAL_CART_ADDS,
    CAST(NULL AS INT64) as TOTAL_PURCHASES,
    CAST(NULL AS FLOAT64) as total_median_click_price,
    CAST(NULL AS FLOAT64) as asin_median_click_price,
    CAST(NULL AS INT64) as query_rank,
    CAST(NULL AS FLOAT64) as avg_position,
    CAST(NULL AS INT64) as search_query_volume,
    CAST(NULL AS FLOAT64) as impression_share_pct,
    CAST(NULL AS FLOAT64) as show_rate_pct,
    CAST(NULL AS FLOAT64) as estimated_organic_rank,
    CAST(NULL AS STRING) as organic_rank_zone,
    scp.ob_file_name,
    scp.ob_marketplace_id,
    scp.ob_seller_id,
    scp.ob_transaction_id,
    scp.ob_modified_date,
    scp.ob_processed_at,
    'SCP' as data_source
  FROM `onyga-482313.OI.STG_SCP_WEEKLY` scp
  LEFT JOIN sqp_aggregated sqp
    ON scp.ASIN = sqp.ASIN
    AND scp.Year = sqp.Year
    AND scp.Week = sqp.Week
  WHERE
    (scp.impressions - COALESCE(sqp.sqp_impressions, 0)) != 0
    OR (scp.clicks - COALESCE(sqp.sqp_clicks, 0)) != 0
    OR (scp.cart_adds - COALESCE(sqp.sqp_cart_adds, 0)) != 0
    OR (scp.conversions - COALESCE(sqp.sqp_conversions, 0)) != 0
    OR (scp.sales_amount - COALESCE(sqp.sqp_sales_amount, 0)) != 0;

  SET delta_count = @@row_count;
  SET end_time = CURRENT_TIMESTAMP();

  SELECT FORMAT(
    'SP_LOAD_FACT_SEARCH_QUERY completed:\n' ||
    '  SQP records inserted: %d (from SRC_ACC_SQP_WEEKLY)\n' ||
    '  Delta records inserted: %d (SCP - SQP)\n' ||
    '  Total records: %d\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    sqp_count,
    delta_count,
    sqp_count + delta_count,
    TIMESTAMP_DIFF(end_time, start_time, SECOND),
    CAST(end_time AS STRING)
  ) as operation_summary;
END;
