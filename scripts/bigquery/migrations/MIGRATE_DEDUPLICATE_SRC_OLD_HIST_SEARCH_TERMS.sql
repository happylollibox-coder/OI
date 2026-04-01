-- =============================================
-- Deduplicate SRC_OLD_HIST_SP_SEARCH_TERMS and SRC_OLD_HIST_SB_SEARCH_TERMS
-- =============================================
--
-- Approach: Create temp tables with GROUP BY + SUM(metrics), copy back to original, drop temp.
--
-- Run: bq query --use_legacy_sql=false < MIGRATE_DEDUPLICATE_SRC_OLD_HIST_SEARCH_TERMS.sql
-- After this, run SP_LOAD_STG_AMAZON_ADS and SP_FACT_AMAZON_ADS.
--
-- =============================================

BEGIN
  -- =============================================================================
  -- SRC_OLD_HIST_SP_SEARCH_TERMS
  -- =============================================================================

  -- Step 1: Create temp table with deduplicated rows (GROUP BY + SUM metrics)
  CREATE OR REPLACE TABLE `onyga-482313.OI._TEMP_SRC_OLD_HIST_SP_SEARCH_TERMS` AS
  SELECT
    date,
    ANY_VALUE(portfolio_name) AS portfolio_name,
    ANY_VALUE(currency) AS currency,
    campaign_name,
    ad_group_name,
    targeting,
    match_type,
    search_term,
    SUM(impressions) AS impressions,
    SUM(clicks) AS clicks,
    SAFE_DIVIDE(SUM(clicks), NULLIF(SUM(impressions), 0)) * 100 AS ctr,
    SAFE_DIVIDE(SUM(spend), NULLIF(SUM(clicks), 0)) AS cpc,
    SUM(spend) AS spend,
    SUM(sales_7d) AS sales_7d,
    SAFE_DIVIDE(SUM(spend), NULLIF(SUM(sales_7d), 0)) * 100 AS acos,
    SAFE_DIVIDE(SUM(sales_7d), NULLIF(SUM(spend), 0)) AS roas,
    SUM(orders_7d) AS orders_7d,
    SUM(units_7d) AS units_7d,
    SAFE_DIVIDE(SUM(orders_7d), NULLIF(SUM(clicks), 0)) * 100 AS cvr_7d,
    SUM(advertised_sku_units_7d) AS advertised_sku_units_7d,
    SUM(other_sku_units_7d) AS other_sku_units_7d,
    SUM(advertised_sku_sales_7d) AS advertised_sku_sales_7d,
    SUM(other_sku_sales_7d) AS other_sku_sales_7d
  FROM `onyga-482313.OI.SRC_OLD_HIST_SP_SEARCH_TERMS`
  GROUP BY date, campaign_name, ad_group_name, targeting, match_type, search_term;

  -- Step 2: Truncate original and copy back
  TRUNCATE TABLE `onyga-482313.OI.SRC_OLD_HIST_SP_SEARCH_TERMS`;

  INSERT INTO `onyga-482313.OI.SRC_OLD_HIST_SP_SEARCH_TERMS`
  SELECT * FROM `onyga-482313.OI._TEMP_SRC_OLD_HIST_SP_SEARCH_TERMS`;

  -- Step 3: Drop temp table
  DROP TABLE IF EXISTS `onyga-482313.OI._TEMP_SRC_OLD_HIST_SP_SEARCH_TERMS`;


-- =============================================================================
-- SRC_OLD_HIST_SB_SEARCH_TERMS
-- =============================================================================

  -- Step 1: Create temp table with deduplicated rows (GROUP BY + SUM metrics)
  CREATE OR REPLACE TABLE `onyga-482313.OI._TEMP_SRC_OLD_HIST_SB_SEARCH_TERMS` AS
  SELECT
    date,
    ANY_VALUE(portfolio_name) AS portfolio_name,
    ANY_VALUE(currency) AS currency,
    campaign_name,
    ad_group_name,
    targeting,
    match_type,
    search_term,
    ANY_VALUE(cost_type) AS cost_type,
    SUM(impressions) AS impressions,
    SUM(viewable_impressions) AS viewable_impressions,
    SUM(clicks) AS clicks,
    SAFE_DIVIDE(SUM(clicks), NULLIF(SUM(impressions), 0)) * 100 AS ctr,
    SUM(spend) AS spend,
    SAFE_DIVIDE(SUM(spend), NULLIF(SUM(clicks), 0)) AS cpc,
    SAFE_DIVIDE(SUM(spend), NULLIF(SUM(impressions), 0)) * 1000 AS vcpm,
    SAFE_DIVIDE(SUM(spend), NULLIF(SUM(sales_14d), 0)) * 100 AS acos,
    SAFE_DIVIDE(SUM(sales_14d), NULLIF(SUM(spend), 0)) AS roas,
    SUM(sales_14d) AS sales_14d,
    SUM(orders_14d) AS orders_14d,
    SUM(units_14d) AS units_14d,
    SAFE_DIVIDE(SUM(orders_14d), NULLIF(SUM(clicks), 0)) * 100 AS cvr_14d,
    SAFE_DIVIDE(SUM(spend), NULLIF(SUM(orders_14d_click), 0)) * 100 AS acos_click,
    SAFE_DIVIDE(SUM(sales_14d_click), NULLIF(SUM(spend), 0)) AS roas_click,
    SUM(sales_14d_click) AS sales_14d_click,
    SUM(orders_14d_click) AS orders_14d_click,
    SUM(units_14d_click) AS units_14d_click
  FROM `onyga-482313.OI.SRC_OLD_HIST_SB_SEARCH_TERMS`
  GROUP BY date, campaign_name, ad_group_name, targeting, match_type, search_term;

  -- Step 2: Truncate original and copy back
  TRUNCATE TABLE `onyga-482313.OI.SRC_OLD_HIST_SB_SEARCH_TERMS`;

  INSERT INTO `onyga-482313.OI.SRC_OLD_HIST_SB_SEARCH_TERMS`
  SELECT * FROM `onyga-482313.OI._TEMP_SRC_OLD_HIST_SB_SEARCH_TERMS`;

  -- Step 3: Drop temp table
  DROP TABLE IF EXISTS `onyga-482313.OI._TEMP_SRC_OLD_HIST_SB_SEARCH_TERMS`;

END;
