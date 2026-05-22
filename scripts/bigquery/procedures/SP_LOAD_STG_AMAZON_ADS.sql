-- =============================================
-- OI Database Project - SP_LOAD_STG_AMAZON_ADS Stored Procedure
-- =============================================
--
-- Purpose: Load STG_AMAZON_ADS with search term data enriched with advertised product ASIN information
-- Pattern: TRUNCATE + INSERT (full refresh)
-- Project: onyga-482313
-- Dataset: OI
--
-- Logic:
-- 1. Aggregate ASINs from both SP and SB campaigns:
--    - SP: Aggregate V_SRC_AmazonAds_advertised_product by campaign_id+ad_group_id+date
--    - SB: Aggregate V_SRC_AmazonAds_sb_ad_report by campaign_id+ad_group_id+date
--    - Collect all ASINs (comma-separated, deduplicated)
--    - Count distinct ASINs
--    - Find ASIN with highest impressions, clicks, and orders/conversions
-- 2. Combine SP and SB ASIN data (UNION DISTINCT)
-- 3. LEFT JOIN aggregated data to V_SRC_AmazonAds_SearchTerms on campaign_id+ad_group_id+date
-- 4. TRUNCATE STG_AMAZON_ADS
-- 5. INSERT all search term records with enriched ASIN fields
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_STG_AMAZON_ADS`()
OPTIONS (
  description = "Load STG_AMAZON_ADS with search term data enriched with advertised product ASIN information. TRUNCATEs table and inserts all SearchTerms records with ASIN enrichment from both SP (advertised_product) and SB (sb_ad_report) aggregations, matched on campaign_id+ad_group_id+date."
)
BEGIN
  -- Declare variables for logging
  DECLARE record_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- Step 1: TRUNCATE the staging table
  TRUNCATE TABLE `onyga-482313.OI.STG_AMAZON_ADS`;

  -- Step 2: Aggregate advertised_product data (SP) and sb_ad_report data (SB), then join to SearchTerms
  INSERT INTO `onyga-482313.OI.STG_AMAZON_ADS` (
    date,
    campaign_id,
    campaign_name,
    campaign_type,
    inferred_sales_module,
    ad_group_id,
    keyword_id,
    ad_keyword_status,
    targeting,
    targeting_type,
    search_term,
    impressions,
    clicks,
    orders,
    units,
    cost,
    sales,
    placement_type,
    num_st_in_date_keyword,
    num_ad_groups_for_st,
    advertised_asins,
    advertised_asins_count,
    most_advertised_asin_impressions,
    most_advertised_asin_clicks,
    most_advertised_asin_purchased,
    most_advertised_mismatch,
    _fivetran_synced,
    source_table
  )
  WITH 
  -- SP campaigns: Aggregate from advertised_product
  sp_advertised_product_aggregated AS (
    SELECT 
      campaign_id,
      ad_group_id,
      date,
      STRING_AGG(DISTINCT advertised_asin, ', ' ORDER BY advertised_asin) as all_asins,
      COUNT(DISTINCT advertised_asin) as asin_count
    FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product`
    WHERE campaign_id IS NOT NULL
      AND ad_group_id IS NOT NULL
      AND date IS NOT NULL
      AND advertised_asin IS NOT NULL
    GROUP BY campaign_id, ad_group_id, date
  ),
  sp_most_asin_by_metric AS (
    SELECT 
      campaign_id,
      ad_group_id,
      date,
      ARRAY_AGG(advertised_asin ORDER BY impressions DESC, advertised_asin LIMIT 1)[OFFSET(0)] as most_asin_impressions,
      ARRAY_AGG(advertised_asin ORDER BY clicks DESC, advertised_asin LIMIT 1)[OFFSET(0)] as most_asin_clicks,
      ARRAY_AGG(advertised_asin ORDER BY orders_30d DESC, advertised_asin LIMIT 1)[OFFSET(0)] as most_asin_purchased
    FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product`
    WHERE campaign_id IS NOT NULL
      AND ad_group_id IS NOT NULL
      AND date IS NOT NULL
      AND advertised_asin IS NOT NULL
    GROUP BY campaign_id, ad_group_id, date
  ),
  -- SB campaigns: Aggregate from sb_ad_report
  sb_advertised_product_aggregated AS (
    SELECT 
      campaign_id,
      ad_group_id,
      date,
      STRING_AGG(DISTINCT advertised_asin, ', ' ORDER BY advertised_asin) as all_asins,
      COUNT(DISTINCT advertised_asin) as asin_count
    FROM `onyga-482313.OI.V_SRC_AmazonAds_sb_ad_report`
    WHERE campaign_id IS NOT NULL
      AND ad_group_id IS NOT NULL
      AND date IS NOT NULL
      AND advertised_asin IS NOT NULL
    GROUP BY campaign_id, ad_group_id, date
  ),
  sb_most_asin_by_metric AS (
    SELECT 
      campaign_id,
      ad_group_id,
      date,
      ARRAY_AGG(advertised_asin ORDER BY impressions DESC, advertised_asin LIMIT 1)[OFFSET(0)] as most_asin_impressions,
      ARRAY_AGG(advertised_asin ORDER BY clicks DESC, advertised_asin LIMIT 1)[OFFSET(0)] as most_asin_clicks,
      ARRAY_AGG(advertised_asin ORDER BY attributed_conversions_14_d DESC, advertised_asin LIMIT 1)[OFFSET(0)] as most_asin_purchased
    FROM `onyga-482313.OI.V_SRC_AmazonAds_sb_ad_report`
    WHERE campaign_id IS NOT NULL
      AND ad_group_id IS NOT NULL
      AND date IS NOT NULL
      AND advertised_asin IS NOT NULL
    GROUP BY campaign_id, ad_group_id, date
  ),
  -- Collect all individual ASINs from both SP and SB sources
  all_asins_individual AS (
    -- SP ASINs
    SELECT campaign_id, ad_group_id, date, advertised_asin
    FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product`
    WHERE campaign_id IS NOT NULL
      AND ad_group_id IS NOT NULL
      AND date IS NOT NULL
      AND advertised_asin IS NOT NULL
    UNION DISTINCT
    -- SB ASINs
    SELECT campaign_id, ad_group_id, date, advertised_asin
    FROM `onyga-482313.OI.V_SRC_AmazonAds_sb_ad_report`
    WHERE campaign_id IS NOT NULL
      AND ad_group_id IS NOT NULL
      AND date IS NOT NULL
      AND advertised_asin IS NOT NULL
  ),
  -- Combine SP and SB metric-based ASIN selections
  all_most_asin_by_metric AS (
    SELECT campaign_id, ad_group_id, date, most_asin_impressions, most_asin_clicks, most_asin_purchased FROM sp_most_asin_by_metric
    UNION ALL
    SELECT campaign_id, ad_group_id, date, most_asin_impressions, most_asin_clicks, most_asin_purchased FROM sb_most_asin_by_metric
  ),
  -- Final aggregation: Combine ASINs and select best metrics
  advertised_product_enriched AS (
    SELECT 
      ai.campaign_id,
      ai.ad_group_id,
      ai.date,
      -- Collect all distinct ASINs as comma-separated string
      STRING_AGG(DISTINCT ai.advertised_asin, ', ' ORDER BY ai.advertised_asin) as advertised_asins,
      COUNT(DISTINCT ai.advertised_asin) as advertised_asins_count,
      -- For metrics, take the first non-null value (prefer SP if both exist)
      ARRAY_AGG(m.most_asin_impressions IGNORE NULLS LIMIT 1)[OFFSET(0)] as most_advertised_asin_impressions,
      ARRAY_AGG(m.most_asin_clicks IGNORE NULLS LIMIT 1)[OFFSET(0)] as most_advertised_asin_clicks,
      ARRAY_AGG(m.most_asin_purchased IGNORE NULLS LIMIT 1)[OFFSET(0)] as most_advertised_asin_purchased
    FROM all_asins_individual ai
    LEFT JOIN all_most_asin_by_metric m
      ON ai.campaign_id = m.campaign_id
      AND ai.ad_group_id = m.ad_group_id
      AND ai.date = m.date
    GROUP BY ai.campaign_id, ai.ad_group_id, ai.date
  ),
  -- Calculate num_ad_groups_for_st: count of ad groups using same search term per date
  search_term_ad_group_count AS (
    SELECT 
      date,
      search_term,
      COUNT(DISTINCT ad_group_id) as num_ad_groups_for_st
    FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms`
    WHERE search_term IS NOT NULL
    GROUP BY date, search_term
  )
  SELECT 
    st.date,
    st.campaign_id,
    st.campaign_name,
    st.campaign_type,
    st.inferred_sales_module,
    st.ad_group_id,
    st.keyword_id,
    st.ad_keyword_status,
    st.targeting,
    k.match_type AS targeting_type,
    st.search_term,
    st.impressions,
    st.clicks,
    st.orders,
    st.units,
    st.cost,
    st.sales,
    st.placement_type,
    st.num_st_in_date_keyword,
    COALESCE(stag.num_ad_groups_for_st, 0) as num_ad_groups_for_st,
    -- ASIN fields from advertised_product (fall back to source asin_by_campaign_name)
    COALESCE(ap.advertised_asins, st.asin_by_campaign_name) as advertised_asins,
    COALESCE(ap.advertised_asins_count, CASE WHEN st.asin_by_campaign_name IS NOT NULL THEN 1 END) as advertised_asins_count,
    ap.most_advertised_asin_impressions,
    ap.most_advertised_asin_clicks,
    ap.most_advertised_asin_purchased,
    -- most_advertised_mismatch: status indicating if the three most_advertised_asin fields are equal
    CASE 
      WHEN ap.most_advertised_asin_impressions IS NULL 
        AND ap.most_advertised_asin_clicks IS NULL 
        AND ap.most_advertised_asin_purchased IS NULL 
      THEN 'No ASIN Data'
      WHEN ap.most_advertised_asin_impressions = ap.most_advertised_asin_clicks 
        AND ap.most_advertised_asin_clicks = ap.most_advertised_asin_purchased
        AND ap.most_advertised_asin_impressions IS NOT NULL
      THEN 'All Match'
      WHEN ap.most_advertised_asin_impressions = ap.most_advertised_asin_clicks
        AND ap.most_advertised_asin_impressions != ap.most_advertised_asin_purchased
      THEN 'Impressions=Clicks≠Purchased'
      WHEN ap.most_advertised_asin_impressions = ap.most_advertised_asin_purchased
        AND ap.most_advertised_asin_impressions != ap.most_advertised_asin_clicks
      THEN 'Impressions=Purchased≠Clicks'
      WHEN ap.most_advertised_asin_clicks = ap.most_advertised_asin_purchased
        AND ap.most_advertised_asin_clicks != ap.most_advertised_asin_impressions
      THEN 'Clicks=Purchased≠Impressions'
      ELSE 'All Different'
    END as most_advertised_mismatch,
    st._fivetran_synced,
    st.source_table
  FROM `onyga-482313.OI.V_SRC_AmazonAds_SearchTerms` st
  LEFT JOIN advertised_product_enriched ap
    ON st.campaign_id = ap.campaign_id
    AND st.ad_group_id = ap.ad_group_id
    AND st.date = ap.date
  LEFT JOIN search_term_ad_group_count stag
    ON st.date = stag.date
    AND st.search_term = stag.search_term
  LEFT JOIN (
    SELECT keyword_id, match_type
    FROM (
      SELECT keyword_id, match_type,
        ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY date DESC) as rn
      FROM `onyga-482313.OI.V_SRC_AmazonAds_keyword`
    )
    WHERE rn = 1
  ) k
    ON st.keyword_id = k.keyword_id
  WHERE st.campaign_id IS NOT NULL
    AND st.ad_group_id IS NOT NULL;

  SET record_count = @@row_count;
  SET end_time = CURRENT_TIMESTAMP();

  -- Log the operation results
  SELECT FORMAT(
    'SP_LOAD_STG_AMAZON_ADS completed:\n' ||
    '  Records inserted: %d\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    record_count,
    TIMESTAMP_DIFF(end_time, start_time, SECOND),
    CAST(end_time AS STRING)
  ) as operation_summary;
END;
