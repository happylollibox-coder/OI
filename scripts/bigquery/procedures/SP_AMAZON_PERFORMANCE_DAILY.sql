-- =============================================
-- OI Database Project - SP_AMAZON_PERFORMANCE_DAILY Stored Procedure
-- =============================================
--
-- Purpose: Load FACT_AMAZON_PERFORMANCE_DAILY with:
--          1) Ads purchased product rows from FACT_AMAZON_ADS (source of truth for ads sales)
--          2) Delta rows from STG_AMAZON_PERFORMANCE minus aggregated FACT_AMAZON_ADS
--
-- Ads module filter: Module #1 (text search) + Module #5 (ASIN/product page) to align SP
-- product-page placements that were previously excluded and caused performance vs ads discrepancies.
-- Pattern: TRUNCATE + INSERT (full refresh)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_AMAZON_PERFORMANCE_DAILY`()
OPTIONS (
  description = "Load FACT_AMAZON_PERFORMANCE_DAILY with Ads data from FACT_AMAZON_ADS and organic deltas from STG_AMAZON_PERFORMANCE. Requires FACT_AMAZON_ADS to run first."
)
BEGIN
  -- Declare variables for logging
  DECLARE ads_record_count INT64 DEFAULT 0;
  DECLARE delta_record_count INT64 DEFAULT 0;
  DECLARE ads_key_stub_record_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- Step 1: TRUNCATE the fact table
  TRUNCATE TABLE `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY`;

  -- Step 2: INSERT Ads purchased product rows from FACT_AMAZON_ADS (source of truth for ads sales)
  -- Aggregates by (date, campaign_id, ad_group_id, keyword_id, most_advertised_asin_purchased)
  INSERT INTO `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` (
    DATE,
    PURCHASED_ASIN,
    advertised_asin,
    campaign_id,
    ad_group_id,
    keyword_id,
    PURCHASED_ORDERS,
    PURCHASED_UNITS,
    PURCHASED_AMOUNT_USD,
    TOTAL_COST_PER_UNIT,
    GROSS_PROFIT,
    ASIN_SESSIONS,
    ASIN_PAGE_VIEWS,
    DATA_SOURCE,
    DATA_QUALITY_STATUS,
    Performance_TYPE,
    factless_key,
    Ads_key
  )
  SELECT
    ads.date AS DATE,
    ads.most_advertised_asin_purchased AS PURCHASED_ASIN,
    COALESCE(ads.most_advertised_asin_impressions, ads.most_advertised_asin_purchased) AS advertised_asin,
    ads.campaign_id,
    ads.ad_group_id,
    COALESCE(ads.keyword_id, '-1') AS keyword_id,
    SUM(ads.orders) AS PURCHASED_ORDERS,
    SUM(ads.units) AS PURCHASED_UNITS,
    SUM(ads.sales) AS PURCHASED_AMOUNT_USD,
    ANY_VALUE(cost.TOTAL_COST_PER_UNIT) AS TOTAL_COST_PER_UNIT,
    SUM(ads.sales) - COALESCE(ANY_VALUE(cost.TOTAL_COST_PER_UNIT), 0) * SUM(ads.units) AS GROSS_PROFIT,
    NULL AS ASIN_SESSIONS,
    NULL AS ASIN_PAGE_VIEWS,
    'FACT_AMAZON_ADS' AS DATA_SOURCE,
    'OK' AS DATA_QUALITY_STATUS,
    ads.campaign_type AS Performance_TYPE,
    CONCAT(CAST(FORMAT_DATE('%Y%m%d', ads.date) AS STRING), '-', COALESCE(ads.most_advertised_asin_purchased, 'UNKNOWN')) AS factless_key,
    ANY_VALUE(ads.Ads_key) AS Ads_key
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` ads
  LEFT JOIN (
    SELECT asin, start_date, end_date, TOTAL_COST_PER_UNIT
    FROM (
      SELECT asin, start_date, end_date, TOTAL_COST_PER_UNIT,
        ROW_NUMBER() OVER (PARTITION BY marketplace_id, asin, start_date, COALESCE(end_date, DATE '9999-12-31') ORDER BY COALESCE(sku, '')) AS rn
      FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
      WHERE marketplace_id = 'ATVPDKIKX0DER'
    )
    WHERE rn = 1
  ) cost ON cost.asin = ads.most_advertised_asin_purchased
    AND ads.date >= cost.start_date
    AND (cost.end_date IS NULL OR ads.date <= cost.end_date)
  WHERE ads.most_advertised_asin_purchased IS NOT NULL
    AND ads.inferred_sales_module IN (
      'Module #1 - Paid Search (Text Search Term)',
      'Module #5 - Other ASIN/Product Pages (ASIN Pattern)',
      'Module #5 - Other ASIN/Product Pages (ASIN Text)'
    )
  GROUP BY
    ads.date,
    ads.most_advertised_asin_purchased,
    ads.most_advertised_asin_impressions,
    ads.campaign_id,
    ads.ad_group_id,
    ads.keyword_id,
    ads.campaign_type;

  SET ads_record_count = @@row_count;

  -- Step 3: INSERT delta rows (STG_AMAZON_PERFORMANCE - aggregated FACT_AMAZON_ADS)
  INSERT INTO `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` (
    DATE,
    PURCHASED_ASIN,
    advertised_asin,
    campaign_id,
    ad_group_id,
    keyword_id,
    PURCHASED_ORDERS,
    PURCHASED_UNITS,
    PURCHASED_AMOUNT_USD,
    TOTAL_COST_PER_UNIT,
    GROSS_PROFIT,
    ASIN_SESSIONS,
    ASIN_PAGE_VIEWS,
    DATA_SOURCE,
    DATA_QUALITY_STATUS,
    Performance_TYPE,
    factless_key,
    Ads_key
  )
  WITH perf AS (
    SELECT
      DATE,
      PURCHASED_ASIN,
      PURCHASED_ORDERS,
      PURCHASED_UNITS,
      PURCHASED_AMOUNT_USD,
      ASIN_SESSIONS,
      ASIN_PAGE_VIEWS,
      IS_LOADED
    FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
  ),
  ads_agg AS (
    SELECT
      date AS DATE,
      most_advertised_asin_purchased AS PURCHASED_ASIN,
      SUM(orders) AS ads_orders,
      SUM(units) AS ads_units,
      SUM(sales) AS ads_amount
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`
    WHERE most_advertised_asin_purchased IS NOT NULL
      AND inferred_sales_module IN (
        'Module #1 - Paid Search (Text Search Term)',
        'Module #5 - Other ASIN/Product Pages (ASIN Pattern)',
        'Module #5 - Other ASIN/Product Pages (ASIN Text)'
      )
    GROUP BY date, most_advertised_asin_purchased
  ),
  delta_calc AS (
    SELECT
      perf.DATE,
      perf.PURCHASED_ASIN,
      perf.IS_LOADED,
      perf.PURCHASED_ORDERS,
      perf.PURCHASED_UNITS,
      perf.PURCHASED_AMOUNT_USD,
      perf.ASIN_SESSIONS,
      perf.ASIN_PAGE_VIEWS,
      COALESCE(ads_agg.ads_orders, 0) AS ads_orders,
      COALESCE(ads_agg.ads_units, 0) AS ads_units,
      COALESCE(ads_agg.ads_amount, 0) AS ads_amount,
      -- Raw deltas (before clamping)
      perf.PURCHASED_ORDERS - COALESCE(ads_agg.ads_orders, 0) AS raw_delta_orders,
      perf.PURCHASED_UNITS - COALESCE(ads_agg.ads_units, 0) AS raw_delta_units,
      perf.PURCHASED_AMOUNT_USD - COALESCE(ads_agg.ads_amount, 0) AS raw_delta_amount
    FROM perf
    LEFT JOIN ads_agg
      ON perf.DATE = ads_agg.DATE
     AND perf.PURCHASED_ASIN = ads_agg.PURCHASED_ASIN
  )
  SELECT
    delta_calc.DATE,
    delta_calc.PURCHASED_ASIN,
    CAST(NULL AS STRING) AS advertised_asin,
    CAST(NULL AS STRING) AS campaign_id,
    CAST(NULL AS STRING) AS ad_group_id,
    CAST(NULL AS STRING) AS keyword_id,
    GREATEST(0, raw_delta_orders) AS PURCHASED_ORDERS,
    GREATEST(0, raw_delta_units) AS PURCHASED_UNITS,
    GREATEST(0, raw_delta_amount) AS PURCHASED_AMOUNT_USD,
    cost.TOTAL_COST_PER_UNIT AS TOTAL_COST_PER_UNIT,
    GREATEST(0, raw_delta_amount) - COALESCE(cost.TOTAL_COST_PER_UNIT, 0) * GREATEST(0, raw_delta_units) AS GROSS_PROFIT,
    delta_calc.ASIN_SESSIONS,
    delta_calc.ASIN_PAGE_VIEWS,
    'STG_AMAZON_PERFORMANCE - FACT_AMAZON_ADS' AS DATA_SOURCE,
    -- Build DATA_QUALITY_STATUS with warnings
    CASE 
      WHEN TRIM(CONCAT(
        CASE WHEN delta_calc.IS_LOADED = FALSE THEN 'Missing Organic data; ' ELSE '' END,
        CASE WHEN raw_delta_orders < 0 THEN 'Negative delta for PURCHASED_ORDERS; ' ELSE '' END,
        CASE WHEN raw_delta_units < 0 THEN 'Negative delta for PURCHASED_UNITS; ' ELSE '' END,
        CASE WHEN raw_delta_amount < 0 THEN 'Negative delta for PURCHASED_AMOUNT_USD; ' ELSE '' END,
        CASE WHEN ads_orders > PURCHASED_ORDERS THEN 'Ads PURCHASED_ORDERS in ads greater than total; ' ELSE '' END,
        CASE WHEN ads_units > PURCHASED_UNITS THEN 'Ads PURCHASED_UNITS in ads greater than total; ' ELSE '' END,
        CASE WHEN ads_amount > PURCHASED_AMOUNT_USD THEN 'Ads PURCHASED_AMOUNT_USD in ads greater than total; ' ELSE '' END
      )) = '' THEN 'OK'
      ELSE TRIM(CONCAT(
        CASE WHEN delta_calc.IS_LOADED = FALSE THEN 'Missing Organic data; ' ELSE '' END,
        CASE WHEN raw_delta_orders < 0 THEN 'Negative delta for PURCHASED_ORDERS; ' ELSE '' END,
        CASE WHEN raw_delta_units < 0 THEN 'Negative delta for PURCHASED_UNITS; ' ELSE '' END,
        CASE WHEN raw_delta_amount < 0 THEN 'Negative delta for PURCHASED_AMOUNT_USD; ' ELSE '' END,
        CASE WHEN ads_orders > PURCHASED_ORDERS THEN 'Ads PURCHASED_ORDERS in ads greater than total; ' ELSE '' END,
        CASE WHEN ads_units > PURCHASED_UNITS THEN 'Ads PURCHASED_UNITS in ads greater than total; ' ELSE '' END,
        CASE WHEN ads_amount > PURCHASED_AMOUNT_USD THEN 'Ads PURCHASED_AMOUNT_USD in ads greater than total; ' ELSE '' END
      ))
    END AS DATA_QUALITY_STATUS,
    'Organic' AS Performance_TYPE,  -- Delta rows are Organic performance
    -- factless_key: YYYYMMDD-ASIN format
    CONCAT(CAST(FORMAT_DATE('%Y%m%d', delta_calc.DATE) AS STRING), '-', COALESCE(delta_calc.PURCHASED_ASIN, 'UNKNOWN')) AS factless_key,
    -- Ads_key: NULL for Organic rows (no ads context)
    CAST(NULL AS STRING) AS Ads_key
  FROM delta_calc
  LEFT JOIN (
    SELECT asin, start_date, end_date, TOTAL_COST_PER_UNIT
    FROM (
      SELECT asin, start_date, end_date, TOTAL_COST_PER_UNIT,
        ROW_NUMBER() OVER (PARTITION BY marketplace_id, asin, start_date, COALESCE(end_date, DATE '9999-12-31') ORDER BY COALESCE(sku, '')) AS rn
      FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
      WHERE marketplace_id = 'ATVPDKIKX0DER'
    )
    WHERE rn = 1
  ) cost ON cost.asin = delta_calc.PURCHASED_ASIN
    AND delta_calc.DATE >= cost.start_date
    AND (cost.end_date IS NULL OR delta_calc.DATE <= cost.end_date)
  WHERE
    -- Only keep rows where there is a non-zero delta in purchases or has sessions/page views
    raw_delta_orders <> 0
    OR raw_delta_units <> 0
    OR raw_delta_amount <> 0
    OR delta_calc.ASIN_SESSIONS IS NOT NULL
    OR delta_calc.ASIN_PAGE_VIEWS IS NOT NULL;

  SET delta_record_count = @@row_count;

  -- Step 3.5: Ensure FACT_AMAZON_PERFORMANCE_DAILY contains ALL Ads_key values from FACT_AMAZON_ADS logic
  -- Insert stub rows for Ads keys that exist in STG_AMAZON_ADS but have no matching Ads_key on the same date in the fact table.
  -- Measures are NULL and DATA_SOURCE is 'FACT_AMAZON_ADS'.
  INSERT INTO `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` (
    DATE,
    PURCHASED_ASIN,
    advertised_asin,
    campaign_id,
    ad_group_id,
    keyword_id,
    PURCHASED_ORDERS,
    PURCHASED_UNITS,
    PURCHASED_AMOUNT_USD,
    TOTAL_COST_PER_UNIT,
    GROSS_PROFIT,
    ASIN_SESSIONS,
    ASIN_PAGE_VIEWS,
    DATA_SOURCE,
    DATA_QUALITY_STATUS,
    Performance_TYPE,
    factless_key,
    Ads_key
  )
  WITH ads_keys AS (
    SELECT DISTINCT
      ads.date AS DATE,
      ads.campaign_id,
      ads.ad_group_id,
      -- Normalize keyword_id for SB campaigns to '-1' to ignore keyword_id
      CASE WHEN ads.campaign_type = 'SB' THEN '-1' ELSE COALESCE(ads.keyword_id, '-1') END AS keyword_id,
      ads.campaign_type AS Performance_TYPE,
      -- Ads_key: DYYYYMMDD-Ccampaign_id-Aad_group_id-Kkeyword_id (SB normalized to K-1)
      CONCAT(
        'D', CAST(FORMAT_DATE('%Y%m%d', ads.date) AS STRING), '-',
        'C', COALESCE(ads.campaign_id, 'NULL'), '-',
        'A', COALESCE(ads.ad_group_id, 'NULL'), '-',
        'K', CASE WHEN ads.campaign_type = 'SB' THEN '-1' ELSE COALESCE(ads.keyword_id, '-1') END
      ) AS Ads_key,
      -- Best-effort advertised_asin inference from STG_AMAZON_ADS enrichment fields
      COALESCE(
        ads.most_advertised_asin_purchased,
        ads.most_advertised_asin_clicks,
        ads.most_advertised_asin_impressions,
        NULLIF(SPLIT(ads.advertised_asins, ',')[SAFE_OFFSET(0)], '')
      ) AS advertised_asin
    FROM `onyga-482313.OI.STG_AMAZON_ADS` ads
    WHERE ads.campaign_id IS NOT NULL
      AND ads.ad_group_id IS NOT NULL
  )
  SELECT
    k.DATE,
    'UNKNOWN' AS PURCHASED_ASIN,
    k.advertised_asin,
    k.campaign_id,
    k.ad_group_id,
    k.keyword_id,
    CAST(NULL AS INT64) AS PURCHASED_ORDERS,
    CAST(NULL AS INT64) AS PURCHASED_UNITS,
    CAST(NULL AS FLOAT64) AS PURCHASED_AMOUNT_USD,
    CAST(NULL AS FLOAT64) AS TOTAL_COST_PER_UNIT,
    CAST(NULL AS FLOAT64) AS GROSS_PROFIT,
    CAST(NULL AS INT64) AS ASIN_SESSIONS,
    CAST(NULL AS INT64) AS ASIN_PAGE_VIEWS,
    'FACT_AMAZON_ADS' AS DATA_SOURCE,
    'Ads key exists in STG_AMAZON_ADS; no purchased ASIN attribution' AS DATA_QUALITY_STATUS,
    k.Performance_TYPE,
    CONCAT(CAST(FORMAT_DATE('%Y%m%d', k.DATE) AS STRING), '-', 'UNKNOWN') AS factless_key,
    k.Ads_key
  FROM ads_keys k
  LEFT JOIN `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` fact
    ON fact.DATE = k.DATE
   AND fact.Ads_key = k.Ads_key
  WHERE fact.Ads_key IS NULL;

  SET ads_key_stub_record_count = @@row_count;

  -- Step 4: Update DATA_QUALITY_STATUS for dates with missing organic data
  -- Update all rows (Ads and Delta) for dates where IS_LOADED = FALSE or date doesn't exist in STG_AMAZON_PERFORMANCE
  UPDATE `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` fact
  SET DATA_QUALITY_STATUS = 
    CASE 
      WHEN fact.DATA_QUALITY_STATUS IS NULL OR fact.DATA_QUALITY_STATUS = '' OR fact.DATA_QUALITY_STATUS = 'OK' 
        THEN 'Missing Organic data'
      WHEN fact.DATA_QUALITY_STATUS LIKE '%Missing Organic data%'
        THEN fact.DATA_QUALITY_STATUS  -- Already has it, don't duplicate
      ELSE CONCAT(fact.DATA_QUALITY_STATUS, '; Missing Organic data')
    END
  WHERE fact.DATE IN (
    SELECT DISTINCT DATE
    FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
    WHERE IS_LOADED = FALSE
  )
  OR fact.DATE IN (
    -- Dates that exist in FACT_AMAZON_ADS but not in STG_AMAZON_PERFORMANCE
    SELECT DISTINCT ads.date
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` ads
    LEFT JOIN `onyga-482313.OI.STG_AMAZON_PERFORMANCE` perf
      ON ads.date = perf.DATE
    WHERE perf.DATE IS NULL
  );

  -- Step 5: Update DATA_QUALITY_STATUS for dates where aggregated ads measures > total performance measures
  UPDATE `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` fact
  SET DATA_QUALITY_STATUS = 
    CASE 
      WHEN fact.DATA_QUALITY_STATUS IS NULL OR fact.DATA_QUALITY_STATUS = '' OR fact.DATA_QUALITY_STATUS = 'OK' 
        THEN agg.warning_message
      WHEN fact.DATA_QUALITY_STATUS LIKE CONCAT('%', agg.warning_message, '%')
        THEN fact.DATA_QUALITY_STATUS  -- Already has it, don't duplicate
      ELSE CONCAT(fact.DATA_QUALITY_STATUS, '; ', agg.warning_message)
    END
  FROM (
    SELECT DATE, warning_message
    FROM (
      SELECT 
        ads.DATE,
        TRIM(
          CONCAT(
            CASE WHEN ads.ads_units > COALESCE(perf.perf_units, 0) 
              THEN 'Ads PURCHASED_UNITS in ads greater than total; ' ELSE '' END,
            CASE WHEN ads.ads_sales > COALESCE(perf.perf_amount, 0) 
              THEN 'Ads PURCHASED_AMOUNT_USD in ads greater than total; ' ELSE '' END,
            CASE WHEN ads.ads_orders > COALESCE(perf.perf_orders, 0) 
              THEN 'Ads PURCHASED_ORDERS in ads greater than total; ' ELSE '' END
          )
        ) AS warning_message,
        ROW_NUMBER() OVER (PARTITION BY ads.DATE ORDER BY 1) AS rn
      FROM (
        SELECT date AS DATE, SUM(units) AS ads_units, SUM(sales) AS ads_sales, SUM(orders) AS ads_orders
        FROM `onyga-482313.OI.FACT_AMAZON_ADS`
        WHERE most_advertised_asin_purchased IS NOT NULL
          AND inferred_sales_module IN (
            'Module #1 - Paid Search (Text Search Term)',
            'Module #5 - Other ASIN/Product Pages (ASIN Pattern)',
            'Module #5 - Other ASIN/Product Pages (ASIN Text)'
          )
        GROUP BY date
      ) ads
      LEFT JOIN (
        SELECT DATE, SUM(PURCHASED_UNITS) AS perf_units, SUM(PURCHASED_AMOUNT_USD) AS perf_amount, SUM(PURCHASED_ORDERS) AS perf_orders
        FROM `onyga-482313.OI.STG_AMAZON_PERFORMANCE`
        GROUP BY DATE
      ) perf ON ads.DATE = perf.DATE
      WHERE ads.ads_units > COALESCE(perf.perf_units, 0)
        OR ads.ads_sales > COALESCE(perf.perf_amount, 0)
        OR ads.ads_orders > COALESCE(perf.perf_orders, 0)
    )
    WHERE rn = 1
  ) agg
  WHERE fact.DATE = agg.DATE
    AND agg.warning_message != '';

  -- Step 6: Enrich FACT_AMAZON_PERFORMANCE_DAILY with campaign attributes (MERGE)
  -- For each (factless_key, Ads_key) pick a single campaign_history row (deduplicate overlapping date ranges)
  MERGE `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` AS fact
  USING (
    SELECT * EXCEPT(rn) FROM (
      SELECT
        f.DATE,
        f.campaign_id,
        f.factless_key,
        f.Ads_key,
        c.serving_status,
        c.campaign_name,
        c.budget,
        c.brand_entity_id,
        CAST(c.profile_id AS STRING) AS profile_id,
        c.state,
        c.bidding_strategy,
        c.budget_type,
        c.campaign_type,
        CAST(c.portfolio_id AS STRING) AS portfolio_id,
        ROW_NUMBER() OVER (PARTITION BY f.factless_key, f.Ads_key ORDER BY c.OI_end_date DESC) AS rn
      FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` f
      JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` c
        ON f.campaign_id = c.campaign_id
       AND CAST(f.DATE AS TIMESTAMP) BETWEEN c.OI_start_date AND c.OI_end_date
      WHERE f.campaign_id IS NOT NULL
    )
    WHERE rn = 1
  ) AS src
  ON fact.factless_key = src.factless_key
 AND fact.Ads_key      = src.Ads_key
WHEN MATCHED THEN
  UPDATE SET
    fact.campaign_serving_status      = src.serving_status,
    fact.campaign_name                = src.campaign_name,
    fact.campaign_budget              = src.budget,
    fact.brand_entity_id              = src.brand_entity_id,
    fact.profile_id                   = src.profile_id,
    fact.campaign_state               = src.state,
    fact.campaign_bidding_strategy    = src.bidding_strategy,
    fact.campaign_budget_type         = src.budget_type,
    fact.campaign_type                = src.campaign_type,
    fact.portfolio_id                 = src.portfolio_id;

  -- Step 7: Enrich FACT_AMAZON_PERFORMANCE_DAILY with portfolio attributes (MERGE)
  -- For each (factless_key, Ads_key) pick a single portfolio row (deduplicate overlapping date ranges)
  MERGE `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` AS fact
  USING (
    SELECT * EXCEPT(rn) FROM (
      SELECT
        f.DATE,
        f.campaign_id,
        f.factless_key,
        f.Ads_key,
        p.portfolio_name,
        p.budget_amount,
        p.budget_policy,
        p.budget_start_date,
        p.budget_end_date,
        ROW_NUMBER() OVER (PARTITION BY f.factless_key, f.Ads_key ORDER BY p.OI_end_date DESC) AS rn
      FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` f
      LEFT JOIN `onyga-482313.OI.V_SRC_AmazonAds_portfolio` p
        ON p.portfolio_id = f.portfolio_id
       AND CAST(f.DATE AS TIMESTAMP) BETWEEN p.OI_start_date AND p.OI_end_date
      WHERE f.portfolio_id IS NOT NULL
    )
    WHERE rn = 1
  ) AS src
  ON fact.factless_key = src.factless_key
 AND fact.Ads_key      = src.Ads_key
WHEN MATCHED THEN
  UPDATE SET
    fact.portfolio_name               = src.portfolio_name,
    fact.portfolio_budget_amount      = src.budget_amount,
    fact.portfolio_budget_policy      = src.budget_policy,
    fact.portfolio_budget_start_date  = src.budget_start_date,
    fact.portfolio_budget_end_date    = src.budget_end_date;

  -- Step 8: Enrich FACT_AMAZON_PERFORMANCE_DAILY with ad group attributes (MERGE)
  -- For each (factless_key, Ads_key, DATA_SOURCE) pick a single ad_group_history row (deduplicate overlapping date ranges)
  MERGE `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` AS fact
  USING (
    SELECT * EXCEPT(rn) FROM (
      SELECT
        f.DATA_SOURCE,
        f.DATE,
        f.campaign_id,
        f.factless_key,
        f.Ads_key,
        f.ad_group_id,
        ag.ad_group_name,
        ag.state,
        ROW_NUMBER() OVER (PARTITION BY f.factless_key, f.Ads_key, f.DATA_SOURCE ORDER BY ag.OI_end_date DESC) AS rn
      FROM `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` f
      JOIN `onyga-482313.OI.V_SRC_AmazonAds_ad_group_history` ag
        ON f.ad_group_id = ag.ad_group_id
       AND f.campaign_id = CAST(ag.campaign_id AS STRING)
       AND CAST(f.DATE AS TIMESTAMP) BETWEEN ag.OI_start_date AND ag.OI_end_date
      WHERE f.ad_group_id IS NOT NULL
        AND f.campaign_id IS NOT NULL
    )
    WHERE rn = 1
  ) AS src
  ON fact.factless_key = src.factless_key
 AND fact.Ads_key      = src.Ads_key
 AND fact.DATA_SOURCE  = src.DATA_SOURCE
WHEN MATCHED THEN
  UPDATE SET
    fact.ad_group_name  = src.ad_group_name,
    fact.ad_group_state = src.state;

  SET end_time = CURRENT_TIMESTAMP();

  -- Log the operation results
  SELECT FORMAT(
    'SP_AMAZON_PERFORMANCE_DAILY completed:\n' ||
    '  Ads records inserted: %d\n' ||
    '  Delta records inserted: %d\n' ||
    '  Ads key stub records inserted: %d\n' ||
    '  Total records: %d\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    ads_record_count,
    delta_record_count,
    ads_key_stub_record_count,
    ads_record_count + delta_record_count + ads_key_stub_record_count,
    TIMESTAMP_DIFF(end_time, start_time, SECOND),
    CAST(end_time AS STRING)
  ) as operation_summary;
END;

