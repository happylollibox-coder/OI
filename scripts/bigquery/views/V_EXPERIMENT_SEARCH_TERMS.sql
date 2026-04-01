-- =============================================
-- OI Database Project - V_EXPERIMENT_SEARCH_TERMS View
-- =============================================
--
-- Purpose: Auto-detect search terms served by experiment campaigns
--          Shows both experiment-only and total ads metrics with overlap detection
--          Includes ad format breakdown (SP vs SB Video vs SB Store) and
--          placement type breakdown (Search Results vs Product Page) per search term
-- Source: FACT_AMAZON_ADS (Amazon Ads API data)
-- Prefix: ads_ (all measures come from Amazon Ads)
-- Dependencies: DIM_EXPERIMENT, DIM_EXPERIMENT_CAMPAIGN, FACT_AMAZON_ADS
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_EXPERIMENT_SEARCH_TERMS`
AS
WITH experiment_ads AS (
  SELECT
    e.experiment_id,
    e.experiment_name,
    e.start_date,
    e.end_date,
    ec.campaign_id as exp_campaign_id,
    ec.campaign_name as exp_campaign_name,
    fa.search_term,
    fa.targeting,
    fa.advertised_asins as asin,
    fa.date,
    fa.Ads_impressions,
    fa.Ads_clicks,
    fa.Ads_orders,
    fa.Ads_units,
    fa.Ads_cost,
    fa.Ads_sales,
    fa.placement_type,
    fa.campaign_type,
    CASE
      WHEN fa.campaign_type = 'SP' THEN 'SP'
      WHEN UPPER(ec.campaign_name) LIKE '%VIDEO%' THEN 'SB_VIDEO'
      WHEN UPPER(ec.campaign_name) LIKE '%STORE%' THEN 'SB_STORE'
      ELSE 'SB_OTHER'
    END as ad_format
  FROM `onyga-482313.OI.DIM_EXPERIMENT` e
  JOIN `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
    ON e.experiment_id = ec.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON ec.campaign_id = fa.campaign_id
    AND fa.date >= e.start_date
    AND (e.end_date IS NULL OR fa.date <= e.end_date)
  WHERE e.status IN ('ACTIVE', 'COMPLETED')
),

exp_agg AS (
  SELECT
    experiment_id,
    experiment_name,
    start_date,
    end_date,
    search_term,
    asin,
    STRING_AGG(DISTINCT targeting, ', ') as targeted_keywords,
    STRING_AGG(DISTINCT exp_campaign_name, ', ') as experiment_campaigns,
    STRING_AGG(DISTINCT ad_format, ', ') as ad_formats,

    -- Overall totals
    SUM(Ads_impressions) as ads_exp_impressions,
    SUM(Ads_clicks) as ads_exp_clicks,
    SUM(Ads_orders) as ads_exp_orders,
    SUM(Ads_units) as ads_exp_units,
    SUM(Ads_cost) as ads_exp_cost,
    SUM(Ads_sales) as ads_exp_sales,
    COUNT(DISTINCT date) as ads_exp_days_active,

    -- SP breakdown
    SUM(CASE WHEN campaign_type = 'SP' THEN Ads_impressions END) as sp_impressions,
    SUM(CASE WHEN campaign_type = 'SP' THEN Ads_clicks END) as sp_clicks,
    SUM(CASE WHEN campaign_type = 'SP' THEN Ads_orders END) as sp_orders,
    SUM(CASE WHEN campaign_type = 'SP' THEN Ads_cost END) as sp_cost,
    SUM(CASE WHEN campaign_type = 'SP' THEN Ads_sales END) as sp_sales,

    -- SB Video breakdown
    SUM(CASE WHEN ad_format = 'SB_VIDEO' THEN Ads_impressions END) as sbv_impressions,
    SUM(CASE WHEN ad_format = 'SB_VIDEO' THEN Ads_clicks END) as sbv_clicks,
    SUM(CASE WHEN ad_format = 'SB_VIDEO' THEN Ads_orders END) as sbv_orders,
    SUM(CASE WHEN ad_format = 'SB_VIDEO' THEN Ads_cost END) as sbv_cost,
    SUM(CASE WHEN ad_format = 'SB_VIDEO' THEN Ads_sales END) as sbv_sales,

    -- SB Store breakdown
    SUM(CASE WHEN ad_format = 'SB_STORE' THEN Ads_impressions END) as sbs_impressions,
    SUM(CASE WHEN ad_format = 'SB_STORE' THEN Ads_clicks END) as sbs_clicks,
    SUM(CASE WHEN ad_format = 'SB_STORE' THEN Ads_orders END) as sbs_orders,
    SUM(CASE WHEN ad_format = 'SB_STORE' THEN Ads_cost END) as sbs_cost,
    SUM(CASE WHEN ad_format = 'SB_STORE' THEN Ads_sales END) as sbs_sales,

    -- Placement: Search Results
    SUM(CASE WHEN placement_type = 'Search_Results' THEN Ads_impressions END) as search_impressions,
    SUM(CASE WHEN placement_type = 'Search_Results' THEN Ads_clicks END) as search_clicks,
    SUM(CASE WHEN placement_type = 'Search_Results' THEN Ads_orders END) as search_orders,
    SUM(CASE WHEN placement_type = 'Search_Results' THEN Ads_cost END) as search_cost,
    SUM(CASE WHEN placement_type = 'Search_Results' THEN Ads_sales END) as search_sales,

    -- Placement: Product Page
    SUM(CASE WHEN placement_type = 'Product_Page' THEN Ads_impressions END) as pp_impressions,
    SUM(CASE WHEN placement_type = 'Product_Page' THEN Ads_clicks END) as pp_clicks,
    SUM(CASE WHEN placement_type = 'Product_Page' THEN Ads_orders END) as pp_orders,
    SUM(CASE WHEN placement_type = 'Product_Page' THEN Ads_cost END) as pp_cost,
    SUM(CASE WHEN placement_type = 'Product_Page' THEN Ads_sales END) as pp_sales

  FROM experiment_ads
  WHERE search_term IS NOT NULL
  GROUP BY 1, 2, 3, 4, 5, 6
),

all_ads AS (
  SELECT
    ea.experiment_id,
    fa.search_term,
    fa.advertised_asins as asin,
    SUM(fa.Ads_impressions) as ads_total_impressions,
    SUM(fa.Ads_clicks) as ads_total_clicks,
    SUM(fa.Ads_orders) as ads_total_orders,
    SUM(fa.Ads_cost) as ads_total_cost,
    SUM(fa.Ads_sales) as ads_total_sales,
    COUNT(DISTINCT fa.campaign_id) as ads_total_campaigns_count,
    COUNT(DISTINCT CASE WHEN fa.campaign_id NOT IN (
      SELECT campaign_id FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec2
      WHERE ec2.experiment_id = ea.experiment_id
    ) THEN fa.campaign_id END) as ads_other_campaigns_count
  FROM exp_agg ea
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON fa.search_term = ea.search_term
    AND fa.advertised_asins = ea.asin
    AND fa.date >= ea.start_date
    AND (ea.end_date IS NULL OR fa.date <= ea.end_date)
  GROUP BY 1, 2, 3
)

SELECT
  -- Keys
  CONCAT(ea.experiment_id, '|', ea.search_term, '|', ea.asin) as row_key,
  CONCAT(ea.search_term, '|', ea.asin) as search_term_key,
  CONCAT(ea.experiment_id, '|', ea.asin) as experiment_asin_key,

  ea.experiment_id,
  ea.experiment_name,
  ea.search_term,
  ea.asin,
  ea.targeted_keywords,
  ea.experiment_campaigns,
  ea.ad_formats,
  ea.ads_exp_days_active,

  -- Experiment campaign metrics (total across all formats)
  ea.ads_exp_impressions,
  ea.ads_exp_clicks,
  ea.ads_exp_orders,
  ea.ads_exp_units,
  ROUND(ea.ads_exp_cost, 2) as ads_exp_cost,
  ROUND(ea.ads_exp_sales, 2) as ads_exp_sales,

  -- All campaigns metrics (experiment + others)
  COALESCE(aa.ads_total_impressions, ea.ads_exp_impressions) as ads_total_impressions,
  COALESCE(aa.ads_total_clicks, ea.ads_exp_clicks) as ads_total_clicks,
  COALESCE(aa.ads_total_orders, ea.ads_exp_orders) as ads_total_orders,
  ROUND(COALESCE(aa.ads_total_cost, ea.ads_exp_cost), 2) as ads_total_cost,
  ROUND(COALESCE(aa.ads_total_sales, ea.ads_exp_sales), 2) as ads_total_sales,

  -- Overlap detection
  COALESCE(aa.ads_other_campaigns_count, 0) as ads_other_campaigns_count,
  COALESCE(aa.ads_other_campaigns_count, 0) > 0 as has_overlap,

  -- =============================================
  -- AD FORMAT BREAKDOWN: SP
  -- =============================================
  COALESCE(ea.sp_impressions, 0) as sp_impressions,
  COALESCE(ea.sp_clicks, 0) as sp_clicks,
  COALESCE(ea.sp_orders, 0) as sp_orders,
  ROUND(COALESCE(ea.sp_cost, 0), 2) as sp_cost,
  ROUND(COALESCE(ea.sp_sales, 0), 2) as sp_sales,
  ROUND(SAFE_DIVIDE(ea.sp_sales, NULLIF(ea.sp_cost, 0)), 2) as sp_roas,
  ROUND(SAFE_DIVIDE(ea.sp_orders, NULLIF(ea.sp_clicks, 0)) * 100, 2) as sp_conversion_rate_pct,
  ROUND(SAFE_DIVIDE(ea.sp_cost, NULLIF(ea.sp_clicks, 0)), 2) as sp_cpc,

  -- =============================================
  -- AD FORMAT BREAKDOWN: SB Video
  -- =============================================
  COALESCE(ea.sbv_impressions, 0) as sbv_impressions,
  COALESCE(ea.sbv_clicks, 0) as sbv_clicks,
  COALESCE(ea.sbv_orders, 0) as sbv_orders,
  ROUND(COALESCE(ea.sbv_cost, 0), 2) as sbv_cost,
  ROUND(COALESCE(ea.sbv_sales, 0), 2) as sbv_sales,
  ROUND(SAFE_DIVIDE(ea.sbv_sales, NULLIF(ea.sbv_cost, 0)), 2) as sbv_roas,
  ROUND(SAFE_DIVIDE(ea.sbv_orders, NULLIF(ea.sbv_clicks, 0)) * 100, 2) as sbv_conversion_rate_pct,
  ROUND(SAFE_DIVIDE(ea.sbv_cost, NULLIF(ea.sbv_clicks, 0)), 2) as sbv_cpc,

  -- =============================================
  -- AD FORMAT BREAKDOWN: SB Store
  -- =============================================
  COALESCE(ea.sbs_impressions, 0) as sbs_impressions,
  COALESCE(ea.sbs_clicks, 0) as sbs_clicks,
  COALESCE(ea.sbs_orders, 0) as sbs_orders,
  ROUND(COALESCE(ea.sbs_cost, 0), 2) as sbs_cost,
  ROUND(COALESCE(ea.sbs_sales, 0), 2) as sbs_sales,
  ROUND(SAFE_DIVIDE(ea.sbs_sales, NULLIF(ea.sbs_cost, 0)), 2) as sbs_roas,
  ROUND(SAFE_DIVIDE(ea.sbs_orders, NULLIF(ea.sbs_clicks, 0)) * 100, 2) as sbs_conversion_rate_pct,
  ROUND(SAFE_DIVIDE(ea.sbs_cost, NULLIF(ea.sbs_clicks, 0)), 2) as sbs_cpc,

  -- =============================================
  -- PLACEMENT TYPE: Search Results
  -- =============================================
  COALESCE(ea.search_impressions, 0) as search_impressions,
  COALESCE(ea.search_clicks, 0) as search_clicks,
  COALESCE(ea.search_orders, 0) as search_orders,
  ROUND(COALESCE(ea.search_cost, 0), 2) as search_cost,
  ROUND(COALESCE(ea.search_sales, 0), 2) as search_sales,
  ROUND(SAFE_DIVIDE(ea.search_sales, NULLIF(ea.search_cost, 0)), 2) as search_roas,
  ROUND(SAFE_DIVIDE(ea.search_orders, NULLIF(ea.search_clicks, 0)) * 100, 2) as search_conversion_rate_pct,

  -- =============================================
  -- PLACEMENT TYPE: Product Page
  -- =============================================
  COALESCE(ea.pp_impressions, 0) as product_page_impressions,
  COALESCE(ea.pp_clicks, 0) as product_page_clicks,
  COALESCE(ea.pp_orders, 0) as product_page_orders,
  ROUND(COALESCE(ea.pp_cost, 0), 2) as product_page_cost,
  ROUND(COALESCE(ea.pp_sales, 0), 2) as product_page_sales,
  ROUND(SAFE_DIVIDE(ea.pp_sales, NULLIF(ea.pp_cost, 0)), 2) as product_page_roas,
  ROUND(SAFE_DIVIDE(ea.pp_orders, NULLIF(ea.pp_clicks, 0)) * 100, 2) as product_page_conversion_rate_pct,

  -- =============================================
  -- BEST FORMAT / PLACEMENT (by ROAS, minimum $1 spend)
  -- =============================================
  CASE
    WHEN COALESCE(ea.sp_cost, 0) + COALESCE(ea.sbv_cost, 0) + COALESCE(ea.sbs_cost, 0) < 1 THEN NULL
    WHEN COALESCE(ea.sp_cost, 0) >= 1
      AND COALESCE(SAFE_DIVIDE(ea.sp_sales, ea.sp_cost), 0) >= COALESCE(SAFE_DIVIDE(ea.sbv_sales, ea.sbv_cost), 0)
      AND COALESCE(SAFE_DIVIDE(ea.sp_sales, ea.sp_cost), 0) >= COALESCE(SAFE_DIVIDE(ea.sbs_sales, ea.sbs_cost), 0) THEN 'SP'
    WHEN COALESCE(ea.sbv_cost, 0) >= 1
      AND COALESCE(SAFE_DIVIDE(ea.sbv_sales, ea.sbv_cost), 0) >= COALESCE(SAFE_DIVIDE(ea.sbs_sales, ea.sbs_cost), 0) THEN 'SB_VIDEO'
    WHEN COALESCE(ea.sbs_cost, 0) >= 1 THEN 'SB_STORE'
    ELSE NULL
  END as best_roas_ad_format,

  CASE
    WHEN COALESCE(ea.search_cost, 0) + COALESCE(ea.pp_cost, 0) < 1 THEN NULL
    WHEN COALESCE(ea.search_cost, 0) >= 1
      AND COALESCE(SAFE_DIVIDE(ea.search_sales, ea.search_cost), 0)
       >= COALESCE(SAFE_DIVIDE(ea.pp_sales, ea.pp_cost), 0) THEN 'SEARCH'
    WHEN COALESCE(ea.pp_cost, 0) >= 1 THEN 'PRODUCT_PAGE'
    ELSE NULL
  END as best_roas_placement

FROM exp_agg ea
LEFT JOIN all_ads aa
  ON ea.experiment_id = aa.experiment_id
  AND ea.search_term = aa.search_term
  AND ea.asin = aa.asin;
