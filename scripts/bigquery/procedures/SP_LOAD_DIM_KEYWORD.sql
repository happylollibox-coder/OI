-- =============================================
-- OI Database Project - SP_LOAD_DIM_KEYWORD
-- =============================================
--
-- Purpose: SCD Type 2 load for DIM_KEYWORD from V_SRC_AmazonAds_keyword
-- Pattern: Close changed rows (set effective_to, is_current=FALSE), insert new versions
-- Tracked fields: keyword_text, state, match_type, bid
-- Timing: effective_from = `date` column from source (last_updated_date / _fivetran_synced)
-- Source: V_SRC_AmazonAds_keyword (Fivetran — may contain duplicate keyword_ids)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_DIM_KEYWORD`()
OPTIONS (
  description = "SCD2 load for DIM_KEYWORD. Closes changed rows and inserts new versions from V_SRC_AmazonAds_keyword."
)
BEGIN
  DECLARE closed_count INT64 DEFAULT 0;
  DECLARE inserted_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- Deduplicate source: keep only the latest per keyword_id (by date column)
  CREATE TEMP TABLE _src_keyword AS
  SELECT
    CAST(keyword_id AS STRING) AS keyword_id,
    CAST(ad_group_id AS STRING) AS ad_group_id,
    CAST(campaign_id AS STRING) AS campaign_id,
    keyword_text,
    state,
    match_type,
    bid,
    _fivetran_synced,
    CAST(date AS DATETIME) AS eff_from
  FROM `onyga-482313.OI.V_SRC_AmazonAds_keyword`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY date DESC) = 1;

  -- Step 1: Close rows where tracked attributes changed
  --   effective_to = incoming version's date (eff_from)
  UPDATE `onyga-482313.OI.DIM_KEYWORD` dim
  SET
    effective_to = src.eff_from,
    is_current = FALSE
  FROM _src_keyword src
  WHERE dim.keyword_id = src.keyword_id
    AND dim.is_current = TRUE
    AND (
      dim.keyword_text IS DISTINCT FROM src.keyword_text
      OR dim.state     IS DISTINCT FROM src.state
      OR dim.match_type IS DISTINCT FROM src.match_type
      OR dim.bid       IS DISTINCT FROM src.bid
    );

  SET closed_count = @@row_count;

  -- Step 2: Insert new versions for changed rows + entirely new keywords
  INSERT INTO `onyga-482313.OI.DIM_KEYWORD` (
    keyword_id, ad_group_id, campaign_id,
    keyword_text, state, match_type, bid,
    _fivetran_synced,
    effective_from, effective_to, is_current
  )
  SELECT
    src.keyword_id,
    src.ad_group_id,
    src.campaign_id,
    src.keyword_text,
    src.state,
    src.match_type,
    src.bid,
    src._fivetran_synced,
    src.eff_from AS effective_from,
    CAST(NULL AS DATETIME) AS effective_to,
    TRUE AS is_current
  FROM _src_keyword src
  WHERE NOT EXISTS (
    SELECT 1
    FROM `onyga-482313.OI.DIM_KEYWORD` dim
    WHERE dim.keyword_id = src.keyword_id
      AND dim.is_current = TRUE
      AND dim.keyword_text IS NOT DISTINCT FROM src.keyword_text
      AND dim.state        IS NOT DISTINCT FROM src.state
      AND dim.match_type   IS NOT DISTINCT FROM src.match_type
      AND dim.bid          IS NOT DISTINCT FROM src.bid
  );

  SET inserted_count = @@row_count;

  DROP TABLE IF EXISTS _src_keyword;

  SELECT FORMAT(
    'SP_LOAD_DIM_KEYWORD completed: Closed %d rows, Inserted %d rows, Duration: %d seconds',
    closed_count, inserted_count,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) as operation_summary;
END;
