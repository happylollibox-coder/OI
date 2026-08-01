-- =============================================
-- OI Database Project - SP_LOAD_FACT_ADS_ADVERTISED_DAILY Stored Procedure
-- =============================================
--
-- Purpose: Load FACT_ADS_ADVERTISED_DAILY (advertised-ASIN-grain ads fact)
--          from V_SRC_AmazonAds_advertised_product.
-- Pattern: Idempotent MERGE over a rolling reload window.
--          - reload_days NULL  -> default 30-day rolling window (daily use)
--          - reload_days 10000 -> full-history reload
--          Rows inside the window are updated/inserted; rows inside the
--          window that no longer exist in the source (Fivetran restatement)
--          are deleted via NOT MATCHED BY SOURCE, scoped to the window.
--          Rows OUTSIDE the window are never touched.
-- Grain:   date x ad_id x advertised_asin (verified unique in source)
-- Timezone: Amazon reports date in the profile timezone (America/Los_Angeles
--          for the US profile) — already LA-local per the FACT layer
--          convention. Window anchor = CURRENT_DATE('America/Los_Angeles').
-- Enrichment: campaign/ad-group names from DIM_CAMPAIGN / DIM_AD_GROUP
--          current rows (preferred DIM_ sources, not raw fivetran history).
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_FACT_ADS_ADVERTISED_DAILY`(reload_days INT64)
OPTIONS (
  description = "Idempotent MERGE load of FACT_ADS_ADVERTISED_DAILY from V_SRC_AmazonAds_advertised_product. reload_days NULL = 30-day rolling window; pass 10000 for full history. Deletes window rows dropped by Fivetran restatement (NOT MATCHED BY SOURCE, window-scoped). LA-timezone window anchor."
)
BEGIN
  DECLARE effective_days INT64;
  DECLARE cutoff_date DATE;
  DECLARE merged_rows INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();
  SET effective_days = COALESCE(reload_days, 30);
  SET cutoff_date = DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL effective_days DAY);

  MERGE `onyga-482313.OI.FACT_ADS_ADVERTISED_DAILY` t
  USING (
    WITH dim_campaign_current AS (
      SELECT campaign_id, campaign_name, campaign_type
      FROM `onyga-482313.OI.DIM_CAMPAIGN`
      WHERE is_current = TRUE
      QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY effective_from DESC) = 1
    ),
    dim_ad_group_current AS (
      SELECT ad_group_id, ad_group_name
      FROM `onyga-482313.OI.DIM_AD_GROUP`
      WHERE is_current = TRUE
      QUALIFY ROW_NUMBER() OVER (PARTITION BY ad_group_id ORDER BY effective_from DESC) = 1
    )
    SELECT
      s.report_date AS date,
      s.campaign_id,
      dc.campaign_name,
      COALESCE(dc.campaign_type, 'SP') AS campaign_type,
      s.ad_group_id,
      dag.ad_group_name,
      s.ad_id,
      s.advertised_asin,
      s.advertised_sku,
      s.impressions AS Ads_impressions,
      s.clicks AS Ads_clicks,
      s.cost AS Ads_cost,
      s.orders_14d AS Ads_orders,
      s.units_14d AS Ads_units,
      s.sales_14_d AS Ads_sales,
      s.orders_same_sku_14d,
      s.units_same_sku_14d,
      s.sales_same_sku_14d,
      (s.orders_14d - s.orders_same_sku_14d) AS orders_other_sku_14d,
      (s.units_14d - s.units_same_sku_14d) AS units_other_sku_14d,
      (s.sales_14_d - s.sales_same_sku_14d) AS sales_other_sku_14d,
      s.orders_7d AS Ads_orders_7d,
      s.units_7d AS Ads_units_7d,
      s.sales_7_d AS Ads_sales_7d,
      s._fivetran_synced
    FROM `onyga-482313.OI.V_SRC_AmazonAds_advertised_product` s
    LEFT JOIN dim_campaign_current dc ON dc.campaign_id = s.campaign_id
    LEFT JOIN dim_ad_group_current dag ON dag.ad_group_id = s.ad_group_id
    WHERE s.report_date >= cutoff_date
      AND s.advertised_asin IS NOT NULL
  ) s
  ON  t.date = s.date
  AND t.ad_id = s.ad_id
  AND t.advertised_asin = s.advertised_asin
  AND t.date >= cutoff_date
  WHEN MATCHED THEN UPDATE SET
    campaign_id         = s.campaign_id,
    campaign_name       = s.campaign_name,
    campaign_type       = s.campaign_type,
    ad_group_id         = s.ad_group_id,
    ad_group_name       = s.ad_group_name,
    advertised_sku      = s.advertised_sku,
    Ads_impressions     = s.Ads_impressions,
    Ads_clicks          = s.Ads_clicks,
    Ads_cost            = s.Ads_cost,
    Ads_orders          = s.Ads_orders,
    Ads_units           = s.Ads_units,
    Ads_sales           = s.Ads_sales,
    orders_same_sku_14d = s.orders_same_sku_14d,
    units_same_sku_14d  = s.units_same_sku_14d,
    sales_same_sku_14d  = s.sales_same_sku_14d,
    orders_other_sku_14d = s.orders_other_sku_14d,
    units_other_sku_14d = s.units_other_sku_14d,
    sales_other_sku_14d = s.sales_other_sku_14d,
    Ads_orders_7d       = s.Ads_orders_7d,
    Ads_units_7d        = s.Ads_units_7d,
    Ads_sales_7d        = s.Ads_sales_7d,
    _fivetran_synced    = s._fivetran_synced,
    loaded_at           = CURRENT_TIMESTAMP()
  WHEN NOT MATCHED THEN INSERT (
    date, campaign_id, campaign_name, campaign_type,
    ad_group_id, ad_group_name, ad_id, advertised_asin, advertised_sku,
    Ads_impressions, Ads_clicks, Ads_cost,
    Ads_orders, Ads_units, Ads_sales,
    orders_same_sku_14d, units_same_sku_14d, sales_same_sku_14d,
    orders_other_sku_14d, units_other_sku_14d, sales_other_sku_14d,
    Ads_orders_7d, Ads_units_7d, Ads_sales_7d,
    _fivetran_synced, loaded_at
  ) VALUES (
    s.date, s.campaign_id, s.campaign_name, s.campaign_type,
    s.ad_group_id, s.ad_group_name, s.ad_id, s.advertised_asin, s.advertised_sku,
    s.Ads_impressions, s.Ads_clicks, s.Ads_cost,
    s.Ads_orders, s.Ads_units, s.Ads_sales,
    s.orders_same_sku_14d, s.units_same_sku_14d, s.sales_same_sku_14d,
    s.orders_other_sku_14d, s.units_other_sku_14d, s.sales_other_sku_14d,
    s.Ads_orders_7d, s.Ads_units_7d, s.Ads_sales_7d,
    s._fivetran_synced, CURRENT_TIMESTAMP()
  )
  -- Remove rows Fivetran restated away, but ONLY inside the reload window
  WHEN NOT MATCHED BY SOURCE AND t.date >= cutoff_date THEN DELETE;

  SET merged_rows = @@row_count;

  SELECT FORMAT(
    'SP_LOAD_FACT_ADS_ADVERTISED_DAILY completed:\n' ||
    '  Reload window: %d days (cutoff %t, LA)\n' ||
    '  Rows merged (insert+update+delete): %d\n' ||
    '  Duration: %d seconds',
    effective_days,
    cutoff_date,
    merged_rows,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) AS operation_summary;
END;
