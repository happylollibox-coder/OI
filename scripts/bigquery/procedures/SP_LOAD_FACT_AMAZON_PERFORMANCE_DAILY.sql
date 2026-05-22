-- =============================================
-- OI Database Project - SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY Stored Procedure
-- =============================================
--
-- Purpose: Load FACT_AMAZON_PERFORMANCE_DAILY with Ads data from STG_AmazonAds_purchased_product and organic deltas from STG_AMAZON_PERFORMANCE
-- Pattern: TRUNCATE + INSERT (full refresh)
-- Project: onyga-482313
-- Dataset: OI
--
-- Logic:
-- 1. TRUNCATE FACT_AMAZON_PERFORMANCE_DAILY
-- 2. INSERT all rows from STG_AmazonAds_purchased_product with Performance_TYPE='Ads'
--    - Source measures (orders, units, sales) directly from purchased_product (accurate, deduplicated)
--    - Enrich with campaign_history, ad_group_history, portfolio for dimensional attributes
--    - Join DIM_COSTS_HISTORY for TOTAL_COST_PER_UNIT and compute GROSS_PROFIT
-- 3. INSERT missing Ads_keys from FACT_AMAZON_ADS not covered by purchased_product
--    - Aggregates search term rows by Ads_key, uses orders/units/sales from FACT_AMAZON_ADS
--    - DATA_SOURCE = 'FACT_AMAZON_ADS', DATA_QUALITY_STATUS = 'Fallback from FACT_AMAZON_ADS'
-- 4. Calculate and INSERT organic delta records (Performance - Ads) grouped by PURCHASED_ASIN/date
--    - Organic delta considers ALL Ads rows (purchased_product + fallback)
--    - Allows negative values when Ads > Performance (ensures FACT totals = STG totals)
--    - Includes rows where IS_LOADED=FALSE (sales arrived before traffic data);
--      these are flagged with DATA_QUALITY_STATUS='Missing traffic data'
-- 5. Update DATA_QUALITY_STATUS for Ads rows on dates with missing traffic data
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY`()
OPTIONS (
  description = "Load FACT_AMAZON_PERFORMANCE_DAILY with Ads data from STG_AmazonAds_purchased_product and organic delta calculations from STG_AMAZON_PERFORMANCE. TRUNCATEs table and inserts Ads records (orders/units/sales from purchased_product), then inserts fallback Ads from FACT_AMAZON_ADS, then calculates and inserts organic delta records, then updates DATA_QUALITY_STATUS."
)
BEGIN
  -- Declare variables for logging
  DECLARE ads_record_count INT64 DEFAULT 0;
  DECLARE ads_fallback_count INT64 DEFAULT 0;
  DECLARE sales_delta_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- Step 1: TRUNCATE the fact table
  TRUNCATE TABLE `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`;

  -- Step 2: INSERT all rows from STG_AmazonAds_purchased_product with Performance_TYPE='Ads'
  -- Source measures directly from purchased_product (accurate, deduplicated orders/units/sales)
  -- Enrich with campaign_history, ad_group_history, portfolio for dimensional attributes
  INSERT INTO `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` (
    date,
    PURCHASED_ASIN,
    advertised_asin,
    campaign_id,
    campaign_name,
    campaign_type,
    ad_group_id,
    ad_group_name,
    keyword_id,
    profile_id,
    portfolio_id,
    portfolio_name,
    PURCHASED_ORDERS,
    PURCHASED_UNITS,
    PURCHASED_AMOUNT_USD,
    DATA_SOURCE,
    DATA_QUALITY_STATUS,
    Performance_TYPE,
    factless_key,
    Ads_key,
    TOTAL_COST_PER_UNIT,
    GROSS_PROFIT
  )
  WITH cost_lookup AS (
    -- One row per (asin, date): join by asin and date between start_date and end_date; if multiple SKUs use first (by sku)
    SELECT asin, date, TOTAL_COST_PER_UNIT
    FROM (
      SELECT c.asin, d as date, c.TOTAL_COST_PER_UNIT, c.sku,
        ROW_NUMBER() OVER (PARTITION BY c.asin, d ORDER BY c.sku) as rn
      FROM `onyga-482313.OI.DIM_COSTS_HISTORY` c
      CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(c.start_date, COALESCE(c.end_date, CURRENT_DATE()))) as d
    )
    WHERE rn = 1
  )
  SELECT 
    pp.DATE,
    pp.PURCHASED_ASIN,
    pp.advertised_asin,
    pp.campaign_id,
    ch.campaign_name,
    ch.campaign_type,
    pp.ad_group_id,
    agh.ad_group_name,
    pp.keyword_id,
    CAST(ch.profile_id AS STRING) AS profile_id,
    ch.portfolio_id,
    pf.portfolio_name,
    pp.PURCHASED_ORDERS,
    pp.PURCHASED_UNITS,
    pp.PURCHASED_AMOUNT_USD,
    pp.data_source AS DATA_SOURCE,
    'OK' as DATA_QUALITY_STATUS,
    'Ads' as Performance_TYPE,
    CONCAT(
      CAST(CAST(FORMAT_DATE('%Y%m%d', pp.DATE) AS INT64) AS STRING), 
      '-', 
      COALESCE(pp.PURCHASED_ASIN, 'UNKNOWN')
    ) as factless_key,
    CONCAT(
      'D', FORMAT_DATE('%Y%m%d', pp.DATE),
      '-C', pp.campaign_id,
      '-A', pp.ad_group_id,
      '-K', pp.keyword_id
    ) as Ads_key,
    cost.TOTAL_COST_PER_UNIT,
    (pp.PURCHASED_AMOUNT_USD - (pp.PURCHASED_UNITS * COALESCE(cost.TOTAL_COST_PER_UNIT, 0))) as GROSS_PROFIT
  FROM `onyga-482313.OI.STG_AmazonAds_purchased_product` pp
  LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` ch
    ON pp.campaign_id = ch.campaign_id
    AND TIMESTAMP(pp.DATE) BETWEEN ch.OI_start_date AND ch.OI_end_date
  LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_ad_group_history` agh
    ON pp.ad_group_id = agh.ad_group_id
    AND pp.campaign_id = agh.campaign_id
    AND TIMESTAMP(pp.DATE) BETWEEN agh.OI_start_date AND agh.OI_end_date
  LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_portfolio` pf
    ON ch.portfolio_id = pf.portfolio_id
    AND TIMESTAMP(pp.DATE) BETWEEN pf.OI_start_date AND pf.OI_end_date
  LEFT JOIN cost_lookup cost
    ON cost.asin = pp.PURCHASED_ASIN
    AND cost.date = pp.DATE;

  SET ads_record_count = @@row_count;

  -- Step 3: INSERT missing (Ads_key, ASIN) combinations from FACT_AMAZON_ADS not covered by purchased_product
  -- These are keyword/ad_group/date combinations with conversions in the search term report
  -- but no corresponding row in STG_AmazonAds_purchased_product FOR THAT SPECIFIC ASIN
  INSERT INTO `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` (
    date,
    PURCHASED_ASIN,
    advertised_asin,
    campaign_id,
    campaign_name,
    campaign_type,
    ad_group_id,
    ad_group_name,
    keyword_id,
    profile_id,
    portfolio_id,
    portfolio_name,
    PURCHASED_ORDERS,
    PURCHASED_UNITS,
    PURCHASED_AMOUNT_USD,
    DATA_SOURCE,
    DATA_QUALITY_STATUS,
    Performance_TYPE,
    factless_key,
    Ads_key,
    TOTAL_COST_PER_UNIT,
    GROSS_PROFIT
  )
  WITH cost_lookup_fallback AS (
    SELECT asin, date, TOTAL_COST_PER_UNIT
    FROM (
      SELECT c.asin, d as date, c.TOTAL_COST_PER_UNIT, c.sku,
        ROW_NUMBER() OVER (PARTITION BY c.asin, d ORDER BY c.sku) as rn
      FROM `onyga-482313.OI.DIM_COSTS_HISTORY` c
      CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(c.start_date, COALESCE(c.end_date, CURRENT_DATE()))) as d
    )
    WHERE rn = 1
  ),
  -- Check Ads_key only — if purchased_product has ANY rows for an Ads_key,
  -- the campaign orders are already explained (possibly under different ASINs
  -- via cross-ASIN purchases). Only create fallback for truly missing Ads_keys.
  existing_ads_keys AS (
    SELECT DISTINCT Ads_key
    FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
    WHERE Performance_TYPE = 'Ads'
  ),
  missing_ads AS (
    -- Aggregate FACT_AMAZON_ADS by Ads_key for keys with NO purchased_product presence
    SELECT
      a.date,
      a.Ads_key,
      a.campaign_id,
      a.campaign_type,
      a.ad_group_id,
      CASE WHEN a.campaign_type = 'SB' THEN '-1' ELSE a.keyword_id END as keyword_id,
      MAX(COALESCE(a.most_advertised_asin_impressions, a.ASIN_BY_CAMPAIGN_NAME)) as advertised_asin,
      SUM(a.Ads_orders) as orders,
      SUM(a.Ads_units) as units,
      SUM(a.Ads_sales) as sales
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    WHERE NOT EXISTS (
      SELECT 1 FROM existing_ads_keys e
      WHERE e.Ads_key = a.Ads_key
    )
      AND (a.Ads_orders > 0 OR a.Ads_units > 0 OR a.Ads_sales > 0)
    GROUP BY a.date, a.Ads_key, a.campaign_id, a.campaign_type, a.ad_group_id,
      CASE WHEN a.campaign_type = 'SB' THEN '-1' ELSE a.keyword_id END
  )
  SELECT
    m.date,
    m.advertised_asin as PURCHASED_ASIN,
    m.advertised_asin,
    m.campaign_id,
    ch.campaign_name,
    COALESCE(ch.campaign_type, m.campaign_type) as campaign_type,
    m.ad_group_id,
    agh.ad_group_name,
    m.keyword_id,
    CAST(ch.profile_id AS STRING) AS profile_id,
    ch.portfolio_id,
    pf.portfolio_name,
    m.orders as PURCHASED_ORDERS,
    m.units as PURCHASED_UNITS,
    m.sales as PURCHASED_AMOUNT_USD,
    'FACT_AMAZON_ADS' as DATA_SOURCE,
    'Fallback from FACT_AMAZON_ADS' as DATA_QUALITY_STATUS,
    'Ads' as Performance_TYPE,
    CONCAT(
      CAST(CAST(FORMAT_DATE('%Y%m%d', m.date) AS INT64) AS STRING),
      '-',
      COALESCE(m.advertised_asin, 'UNKNOWN')
    ) as factless_key,
    m.Ads_key,
    cost.TOTAL_COST_PER_UNIT,
    (m.sales - (m.units * COALESCE(cost.TOTAL_COST_PER_UNIT, 0))) as GROSS_PROFIT
  FROM missing_ads m
  LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` ch
    ON m.campaign_id = ch.campaign_id
    AND TIMESTAMP(m.date) BETWEEN ch.OI_start_date AND ch.OI_end_date
  LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_ad_group_history` agh
    ON m.ad_group_id = agh.ad_group_id
    AND m.campaign_id = agh.campaign_id
    AND TIMESTAMP(m.date) BETWEEN agh.OI_start_date AND agh.OI_end_date
  LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_portfolio` pf
    ON ch.portfolio_id = pf.portfolio_id
    AND TIMESTAMP(m.date) BETWEEN pf.OI_start_date AND pf.OI_end_date
  LEFT JOIN cost_lookup_fallback cost
    ON cost.asin = m.advertised_asin
    AND cost.date = m.date;

  SET ads_fallback_count = @@row_count;

  -- Step 4: INSERT organic delta records (Performance - Ads) grouped by PURCHASED_ASIN/date
  -- ads_by_asin now includes BOTH purchased_product rows AND fallback rows from FACT_AMAZON_ADS
  INSERT INTO `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` (
    DATE,
    PURCHASED_ASIN,
    advertised_asin,
    campaign_id,
    campaign_name,
    campaign_type,
    ad_group_id,
    keyword_id,
    PURCHASED_ORDERS,
    PURCHASED_UNITS,
    PURCHASED_AMOUNT_USD,
    ASIN_SESSIONS,
    ASIN_PAGE_VIEWS,
    DATA_SOURCE,
    DATA_QUALITY_STATUS,
    Performance_TYPE,
    factless_key,
    TOTAL_COST_PER_UNIT,
    GROSS_PROFIT
  )
  WITH cost_lookup_organic AS (
    -- One row per (asin, date): join by asin and date between start_date and end_date; if multiple SKUs use first (by sku)
    SELECT asin, date, TOTAL_COST_PER_UNIT
    FROM (
      SELECT c.asin, d as date, c.TOTAL_COST_PER_UNIT, c.sku,
        ROW_NUMBER() OVER (PARTITION BY c.asin, d ORDER BY c.sku) as rn
      FROM `onyga-482313.OI.DIM_COSTS_HISTORY` c
      CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(c.start_date, COALESCE(c.end_date, CURRENT_DATE()))) as d
    )
    WHERE rn = 1
  ),
  ads_by_asin AS (
    -- Aggregate ALL ads data (purchased_product + fallback) by PURCHASED_ASIN and date
    SELECT 
      DATE,
      PURCHASED_ASIN,
      SUM(PURCHASED_ORDERS) as ads_orders,
      SUM(PURCHASED_UNITS) as ads_units,
      SUM(PURCHASED_AMOUNT_USD) as ads_sales
    FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`
    WHERE Performance_TYPE = 'Ads'
    GROUP BY DATE, PURCHASED_ASIN
  )
  SELECT 
    perf.DATE,
    perf.PURCHASED_ASIN,
    CAST(NULL AS STRING) as advertised_asin,
    CAST(NULL AS STRING) as campaign_id,
    CAST(NULL AS STRING) as campaign_name,
    CAST(NULL AS STRING) as campaign_type,
    CAST(NULL AS STRING) as ad_group_id,
    CAST(NULL AS STRING) as keyword_id,
    (perf.PURCHASED_ORDERS - COALESCE(ads.ads_orders, 0)) as PURCHASED_ORDERS,
    (perf.PURCHASED_UNITS - COALESCE(ads.ads_units, 0)) as PURCHASED_UNITS,
    (perf.PURCHASED_AMOUNT_USD - COALESCE(ads.ads_sales, 0)) as PURCHASED_AMOUNT_USD,
    perf.ASIN_SESSIONS,
    perf.ASIN_PAGE_VIEWS,
    'STG_AMAZON_PERFORMANCE' as DATA_SOURCE,
    -- Build DATA_QUALITY_STATUS with warnings
    -- Include 'Missing traffic data' when IS_LOADED=FALSE (sales arrived before traffic/sessions)
    CASE 
      WHEN perf.IS_LOADED = FALSE
        OR (perf.PURCHASED_UNITS - COALESCE(ads.ads_units, 0)) < 0 
        OR (perf.PURCHASED_AMOUNT_USD - COALESCE(ads.ads_sales, 0)) < 0 
        OR (perf.PURCHASED_ORDERS - COALESCE(ads.ads_orders, 0)) < 0
      THEN RTRIM(CONCAT(
        CASE WHEN perf.IS_LOADED = FALSE THEN 'Missing traffic data; ' ELSE '' END,
        CASE WHEN (perf.PURCHASED_UNITS - COALESCE(ads.ads_units, 0)) < 0 THEN 'Negative delta for UNITS; ' ELSE '' END,
        CASE WHEN (perf.PURCHASED_AMOUNT_USD - COALESCE(ads.ads_sales, 0)) < 0 THEN 'Negative delta for SALES; ' ELSE '' END,
        CASE WHEN (perf.PURCHASED_ORDERS - COALESCE(ads.ads_orders, 0)) < 0 THEN 'Negative delta for ORDERS; ' ELSE '' END
      ), '; ')
      ELSE 'OK'
    END as DATA_QUALITY_STATUS,
    'Organic' as Performance_TYPE,
    CONCAT(
      CAST(CAST(FORMAT_DATE('%Y%m%d', perf.DATE) AS INT64) AS STRING), 
      '-', 
      COALESCE(perf.PURCHASED_ASIN, 'UNKNOWN')
    ) as factless_key,
    cost_org.TOTAL_COST_PER_UNIT as TOTAL_COST_PER_UNIT,
    ((perf.PURCHASED_AMOUNT_USD - COALESCE(ads.ads_sales, 0)) - ((perf.PURCHASED_UNITS - COALESCE(ads.ads_units, 0)) * COALESCE(cost_org.TOTAL_COST_PER_UNIT, 0))) as GROSS_PROFIT
  FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE` perf
  LEFT JOIN ads_by_asin ads
    ON perf.DATE = ads.DATE
    AND perf.PURCHASED_ASIN = ads.PURCHASED_ASIN
  LEFT JOIN cost_lookup_organic cost_org
    ON cost_org.asin = perf.PURCHASED_ASIN
    AND cost_org.date = perf.DATE
  WHERE (
      (perf.PURCHASED_ORDERS - COALESCE(ads.ads_orders, 0)) != 0
      OR (perf.PURCHASED_UNITS - COALESCE(ads.ads_units, 0)) != 0
      OR (perf.PURCHASED_AMOUNT_USD - COALESCE(ads.ads_sales, 0)) != 0
      OR perf.ASIN_SESSIONS > 0
      OR perf.ASIN_PAGE_VIEWS > 0
    );

  SET sales_delta_count = @@row_count;

  -- Step 5: Update DATA_QUALITY_STATUS for Ads rows on dates with missing traffic data
  -- (Organic delta rows already flagged in Step 4 via IS_LOADED check)
  UPDATE `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` fact
  SET DATA_QUALITY_STATUS = 
    CASE 
      WHEN fact.DATA_QUALITY_STATUS IS NULL OR fact.DATA_QUALITY_STATUS = '' OR fact.DATA_QUALITY_STATUS = 'OK' 
        THEN 'Missing traffic data'
      ELSE CONCAT(fact.DATA_QUALITY_STATUS, '; Missing traffic data')
    END
  WHERE fact.DATE IN (
    SELECT DISTINCT DATE
    FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
    WHERE IS_LOADED = FALSE
  )
  AND fact.Performance_TYPE = 'Ads';

  SET end_time = CURRENT_TIMESTAMP();

  -- Log the operation results
  SELECT FORMAT(
    'SP_LOAD_FACT_AMAZON_PERFORMANCE_DAILY completed:\n' ||
    '  Ads records inserted (purchased_product): %d\n' ||
    '  Ads fallback records inserted (FACT_AMAZON_ADS): %d\n' ||
    '  Organic delta records inserted: %d\n' ||
    '  Total records: %d\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    ads_record_count,
    ads_fallback_count,
    sales_delta_count,
    ads_record_count + ads_fallback_count + sales_delta_count,
    TIMESTAMP_DIFF(end_time, start_time, SECOND),
    CAST(end_time AS STRING)
  ) as operation_summary;
END;
