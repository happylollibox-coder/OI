-- =============================================
-- OI Database Project - SP_FACT_AMAZON_ADS Stored Procedure
-- =============================================
--
-- Purpose: Load FACT_AMAZON_ADS with data from STG_AMAZON_ADS
-- Pattern: TRUNCATE + INSERT (full refresh)
-- Source: STG_AMAZON_ADS
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_FACT_AMAZON_ADS`()
OPTIONS (
  description = "Load FACT_AMAZON_ADS with data from STG_AMAZON_ADS using TRUNCATE + INSERT. Adds Ads_key field."
)
BEGIN
  -- Declare variables for logging
  DECLARE record_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- Step 1: TRUNCATE the fact table
  TRUNCATE TABLE `onyga-482313.OI.FACT_AMAZON_ADS`;

  -- Step 2: INSERT all data from STG_AMAZON_ADS with Ads_key calculation and cost join
  INSERT INTO `onyga-482313.OI.FACT_AMAZON_ADS` (
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
    Ads_impressions,
    Ads_clicks,
    Ads_orders,
    Ads_units,
    Ads_cost,
    Ads_sales,
    TOTAL_COST_PER_UNIT,
    GROSS_PROFIT,
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
    source_table,
    ASIN_BY_CAMPAIGN_NAME,
    Ads_key
  )
  WITH cost_deduped AS (
    SELECT asin, start_date, end_date, TOTAL_COST_PER_UNIT
    FROM (
      SELECT asin, start_date, end_date, TOTAL_COST_PER_UNIT,
        ROW_NUMBER() OVER (PARTITION BY marketplace_id, asin, start_date, COALESCE(end_date, DATE '9999-12-31') ORDER BY COALESCE(sku, '')) AS rn
      FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
      WHERE marketplace_id = 'ATVPDKIKX0DER'
    )
    WHERE rn = 1
  )
  SELECT
    ads.date,
    ads.campaign_id,
    ads.campaign_name,
    ads.campaign_type,
    ads.inferred_sales_module,
    ads.ad_group_id,
    ads.keyword_id,
    ads.ad_keyword_status,
    ads.targeting,
    ads.targeting_type,
    ads.search_term,
    ads.impressions,
    ads.clicks,
    ads.orders,
    ads.units,
    ads.cost,
    ads.sales,
    -- Cost fallback chain: purchased ASIN → impressions ASIN → single advertised ASIN
    COALESCE(cost_purchased.TOTAL_COST_PER_UNIT, cost_impressions.TOTAL_COST_PER_UNIT, cost_advertised.TOTAL_COST_PER_UNIT) AS TOTAL_COST_PER_UNIT,
    ads.sales - COALESCE(cost_purchased.TOTAL_COST_PER_UNIT, cost_impressions.TOTAL_COST_PER_UNIT, cost_advertised.TOTAL_COST_PER_UNIT, 0) * ads.units AS GROSS_PROFIT,
    ads.placement_type,
    ads.num_st_in_date_keyword,
    ads.num_ad_groups_for_st,
    ads.advertised_asins,
    ads.advertised_asins_count,
    ads.most_advertised_asin_impressions,
    ads.most_advertised_asin_clicks,
    ads.most_advertised_asin_purchased,
    ads.most_advertised_mismatch,
    ads._fivetran_synced,
    ads.source_table,
    -- Derive ASIN from campaign_name for rows where ad-file ASINs are unavailable
    CASE
      -- Lollibox variants
      WHEN REGEXP_CONTAINS(UPPER(ads.campaign_name), r'LOLLIBOX|LOLLI.?BOX|^BOX') THEN
        CASE WHEN REGEXP_CONTAINS(UPPER(ads.campaign_name), r'WHITE|HEART|FROG') THEN 'B0C1VLXYBP'
             WHEN REGEXP_CONTAINS(UPPER(ads.campaign_name), r'PINK')             THEN 'B0CR6N3WRC'
             WHEN REGEXP_CONTAINS(UPPER(ads.campaign_name), r'PURPLE|PANDA')      THEN 'B09XQ56RK5'
             WHEN REGEXP_CONTAINS(UPPER(ads.campaign_name), r'BLUE')              THEN 'B0DJFG5ZJ7'
             ELSE 'B0C1VLXYBP' END
      -- LolliME variants
      WHEN REGEXP_CONTAINS(UPPER(ads.campaign_name), r'LOLLIME|LOLLI.?ME|^ME[- /]') THEN
        CASE WHEN REGEXP_CONTAINS(UPPER(ads.campaign_name), r'PINK')   THEN 'B0F9XFXQRW'
             WHEN REGEXP_CONTAINS(UPPER(ads.campaign_name), r'MINT')   THEN 'B0F9X95K5H'
             ELSE 'B0F9XDSVYB' END
      -- Fresh variants
      WHEN REGEXP_CONTAINS(UPPER(ads.campaign_name), r'FRESH') THEN
        CASE WHEN REGEXP_CONTAINS(UPPER(ads.campaign_name), r'BEIGE') THEN 'B0D7N2MLDP'
             ELSE 'B0D7N31M6S' END
      -- Bottle / Truth or Dare
      WHEN REGEXP_CONTAINS(UPPER(ads.campaign_name), r'TRUTH|BOTTLE|DARE') THEN 'B0F4KCCSWN'
      -- Brand / Generic → default White Lollibox
      ELSE 'B0C1VLXYBP'
    END AS ASIN_BY_CAMPAIGN_NAME,
    -- Ads_key: DYYYYMMDD-Ccampaign_id-Aad_group_id-Kkeyword_id (with date and prefix characters)
    -- For SP campaigns: use actual keyword_id
    -- For SB campaigns: normalize to '-1' (ignore keyword_id for matching)
    CONCAT(
      'D', CAST(FORMAT_DATE('%Y%m%d', ads.date) AS STRING), '-',
      'C', COALESCE(ads.campaign_id, 'NULL'), '-',
      'A', COALESCE(ads.ad_group_id, 'NULL'), '-',
      'K', CASE 
        WHEN ads.campaign_type = 'SB' THEN '-1'  -- SB campaigns: normalize keyword_id to '-1'
        ELSE COALESCE(ads.keyword_id, '-1')  -- SP campaigns: use actual keyword_id
      END
    ) AS Ads_key
  FROM `onyga-482313.OI.STG_AMAZON_ADS` ads
  -- 1st priority: cost from the ASIN that actually got purchased
  LEFT JOIN cost_deduped cost_purchased ON cost_purchased.asin = ads.most_advertised_asin_purchased
    AND ads.date >= cost_purchased.start_date
    AND (cost_purchased.end_date IS NULL OR ads.date <= cost_purchased.end_date)
  -- 2nd priority: cost from the ASIN with most impressions (populated from 2025+)
  LEFT JOIN cost_deduped cost_impressions ON cost_impressions.asin = ads.most_advertised_asin_impressions
    AND ads.date >= cost_impressions.start_date
    AND (cost_impressions.end_date IS NULL OR ads.date <= cost_impressions.end_date)
    AND ads.most_advertised_asin_purchased IS NULL
  -- 3rd priority: cost from advertised_asins (always populated; use only when single ASIN)
  LEFT JOIN cost_deduped cost_advertised ON cost_advertised.asin = ads.advertised_asins
    AND ads.date >= cost_advertised.start_date
    AND (cost_advertised.end_date IS NULL OR ads.date <= cost_advertised.end_date)
    AND ads.most_advertised_asin_purchased IS NULL
    AND ads.most_advertised_asin_impressions IS NULL
    AND ads.advertised_asins_count = 1;

  SET record_count = @@row_count;
  SET end_time = CURRENT_TIMESTAMP();

  -- Log the operation results
  SELECT FORMAT(
    'SP_FACT_AMAZON_ADS completed:\n' ||
    '  Records inserted: %d\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    record_count,
    TIMESTAMP_DIFF(end_time, start_time, SECOND),
    CAST(end_time AS STRING)
  ) as operation_summary;
END;
