-- =============================================
-- OI Database Project - SP_LOAD_DIM_AD_GROUP
-- =============================================
--
-- Purpose: SCD Type 2 load for DIM_AD_GROUP from V_SRC_AmazonAds_ad_group_history
-- Pattern: Close changed rows (set effective_to, is_current=FALSE), insert new versions
-- Tracked fields: ad_group_name, state, serving_status, default_bid
-- Type-1 derived attribute: creative_type (SB creative from V_SRC_AmazonAds_sb_ad_report;
--   refreshed in place across all versions, never cuts an SCD2 version)
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
  DECLARE creative_count INT64 DEFAULT 0;
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

  -- SB creative type per ad group — the CANONICAL ad_group -> creative_type derivation
  -- (was copy-pasted in V_ADS_COACH_DATA / V_WEEKLY_CELL_NET / V_INTENT_KEYWORDS /
  -- V_CAMPAIGN_ROLE; consolidated here 2026-07-30). Consumers read DIM_AD_GROUP.creative_type.
  -- Deliberately NO cost>0 filter: filtered vs unfiltered never disagree where both exist
  -- (0/58 spending ad groups, checked 2026-07-30), and the unfiltered read covers 23
  -- zero-spend ad groups (new/paused SB launches) the filter left NULL.
  CREATE TEMP TABLE _sb_creative AS
  SELECT CAST(ad_group_id AS STRING) AS ad_group_id,
    -- fall back to the campaign name when the source creative_type is NULL (some SB video
    -- campaigns don't populate it, e.g. FRESH-VIDEO/EXACT). '%VIDEO%' in the name is always
    -- video (validated). Store-spotlight ads carry NO creative_type in sb_ad_report at all
    -- (verified 2026-08-01: STORE-SPOTLIGHT's 5 rows all NULL — the enum only emits
    -- BRAND_VIDEO/PRODUCT_COLLECTION/VIDEO), so the name is the only signal for them.
    COALESCE(
      MAX(creative_type),
      CASE WHEN UPPER(ANY_VALUE(campaign_name)) LIKE '%VIDEO%'      THEN 'BRAND_VIDEO'
           WHEN UPPER(ANY_VALUE(campaign_name)) LIKE '%COLLECTION%' THEN 'PRODUCT_COLLECTION'
           WHEN UPPER(ANY_VALUE(campaign_name)) LIKE '%SPOTLIGHT%'  THEN 'STORE_SPOTLIGHT' END
    ) AS creative_type
  FROM `onyga-482313.OI.V_SRC_AmazonAds_sb_ad_report`
  GROUP BY ad_group_id;

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
    creative_type, effective_from, effective_to, is_current
  )
  SELECT
    src.ad_group_id, src.campaign_id, src.ad_group_name, src.state,
    src.serving_status, src.default_bid, src.campaign_type,
    src.creation_date, src.last_updated_date, src._fivetran_synced,
    sbc.creative_type, src.eff_from, CAST(NULL AS DATETIME), TRUE
  FROM _src_ad_group src
  LEFT JOIN _sb_creative sbc ON sbc.ad_group_id = src.ad_group_id
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

  -- Step 3: Type-1 refresh of creative_type across ALL versions (current + historical).
  -- creative_type is a derived attribute, not a tracked SCD2 field — a change here never
  -- cuts a version; late-arriving creative info (e.g. an ad group's first report rows)
  -- simply updates in place. Also serves as the one-time backfill after the 2026-07-30
  -- ALTER TABLE migration.
  UPDATE `onyga-482313.OI.DIM_AD_GROUP` dim
  SET creative_type = sbc.creative_type
  FROM _sb_creative sbc
  WHERE dim.ad_group_id = sbc.ad_group_id
    AND dim.creative_type IS DISTINCT FROM sbc.creative_type;

  SET creative_count = @@row_count;
  DROP TABLE IF EXISTS _src_ad_group;
  DROP TABLE IF EXISTS _sb_creative;

  SELECT FORMAT(
    'SP_LOAD_DIM_AD_GROUP completed: Closed %d rows, Inserted %d rows, Refreshed creative_type on %d rows, Duration: %d seconds',
    closed_count, inserted_count, creative_count,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) as operation_summary;
END;
