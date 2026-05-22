-- =============================================
-- OI Database Project - SP_LOAD_DIM_AD_GROUP
-- =============================================
--
-- Purpose: SCD Type 2 load for DIM_AD_GROUP from V_SRC_AmazonAds_ad_group_history
-- Pattern: Close changed rows (set effective_to, is_current=FALSE), insert new versions
-- Tracked fields: ad_group_name, state, serving_status, default_bid
-- Timing: effective_from = `date` column from source (last_updated_date)
-- Source: V_SRC_AmazonAds_ad_group_history (Fivetran)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_DIM_AD_GROUP`()
OPTIONS (
  description = "SCD2 load for DIM_AD_GROUP. Closes changed rows and inserts new versions."
)
BEGIN
  DECLARE closed_count INT64 DEFAULT 0;
  DECLARE inserted_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- Deduplicate source: keep only the latest per ad_group_id (by date column)
  CREATE TEMP TABLE _src_ad_group AS
  SELECT
    CAST(ad_group_id AS STRING) AS ad_group_id,
    CAST(campaign_id AS STRING) AS campaign_id,
    ad_group_name, state, serving_status, default_bid,
    campaign_type, creation_date, last_updated_date, _fivetran_synced,
    CAST(date AS DATETIME) AS eff_from
  FROM `onyga-482313.OI.V_SRC_AmazonAds_ad_group_history`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ad_group_id ORDER BY date DESC) = 1;

  -- Step 1: Close changed rows
  UPDATE `onyga-482313.OI.DIM_AD_GROUP` dim
  SET effective_to = src.eff_from, is_current = FALSE
  FROM _src_ad_group src
  WHERE dim.ad_group_id = src.ad_group_id
    AND dim.is_current = TRUE
    AND (
      dim.ad_group_name  IS DISTINCT FROM src.ad_group_name
      OR dim.state       IS DISTINCT FROM src.state
      OR dim.serving_status IS DISTINCT FROM src.serving_status
      OR dim.default_bid IS DISTINCT FROM src.default_bid
    );

  SET closed_count = @@row_count;

  -- Step 2: Insert new versions + new ad groups
  INSERT INTO `onyga-482313.OI.DIM_AD_GROUP` (
    ad_group_id, campaign_id, ad_group_name, state, serving_status,
    default_bid, campaign_type, creation_date, last_updated_date, _fivetran_synced,
    effective_from, effective_to, is_current
  )
  SELECT
    src.ad_group_id, src.campaign_id, src.ad_group_name, src.state,
    src.serving_status, src.default_bid, src.campaign_type,
    src.creation_date, src.last_updated_date, src._fivetran_synced,
    src.eff_from, CAST(NULL AS DATETIME), TRUE
  FROM _src_ad_group src
  WHERE NOT EXISTS (
    SELECT 1 FROM `onyga-482313.OI.DIM_AD_GROUP` dim
    WHERE dim.ad_group_id = src.ad_group_id
      AND dim.is_current = TRUE
      AND dim.ad_group_name  IS NOT DISTINCT FROM src.ad_group_name
      AND dim.state          IS NOT DISTINCT FROM src.state
      AND dim.serving_status IS NOT DISTINCT FROM src.serving_status
      AND dim.default_bid    IS NOT DISTINCT FROM src.default_bid
  );

  SET inserted_count = @@row_count;
  DROP TABLE IF EXISTS _src_ad_group;

  SELECT FORMAT(
    'SP_LOAD_DIM_AD_GROUP completed: Closed %d rows, Inserted %d rows, Duration: %d seconds',
    closed_count, inserted_count,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) as operation_summary;
END;
