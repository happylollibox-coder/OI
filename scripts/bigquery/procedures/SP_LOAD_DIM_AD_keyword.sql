-- =============================================
-- OI Database Project - SP_LOAD_DIM_AD_keyword Stored Procedure
-- =============================================
--
-- Purpose: Load DIM_AD_keyword with keyword data from V_SRC_AmazonAds_keyword view
-- Pattern: TRUNCATE + INSERT (full refresh)
-- Project: onyga-482313
-- Dataset: OI
--
-- Logic:
-- 1. TRUNCATE DIM_AD_keyword
-- 2. INSERT records from V_SRC_AmazonAds_keyword (includes both SP and SB campaigns)
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_DIM_AD_keyword`()
OPTIONS (
  description = "Load DIM_AD_keyword with keyword data from V_SRC_AmazonAds_keyword view. TRUNCATEs table and inserts records."
)
BEGIN
  -- Declare variables for logging
  DECLARE record_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;
  DECLARE end_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- Step 1: TRUNCATE the dimension table
  TRUNCATE TABLE `onyga-482313.OI.DIM_AD_keyword`;

  -- Step 2: Load data from V_SRC_AmazonAds_keyword view
  INSERT INTO `onyga-482313.OI.DIM_AD_keyword` (
    keyword_id,
    ad_group_id,
    campaign_id,
    keyword_text,
    keyword_state,
    match_type,
    _fivetran_synced
  )
  SELECT
    v.keyword_id,
    CAST(v.ad_group_id AS STRING) AS ad_group_id,
    CAST(v.campaign_id AS STRING) AS campaign_id,
    v.keyword_text,
    v.state AS keyword_state,
    v.match_type,
    v._fivetran_synced
  FROM `onyga-482313.OI.V_SRC_AmazonAds_keyword` v;

  SET record_count = @@row_count;
  SET end_time = CURRENT_TIMESTAMP();

  -- Log the operation results
  SELECT FORMAT(
    'SP_LOAD_DIM_AD_keyword completed:\n' ||
    '  Records inserted: %d\n' ||
    '  Duration: %d seconds\n' ||
    '  Completed at: %s',
    record_count,
    TIMESTAMP_DIFF(end_time, start_time, SECOND),
    CAST(end_time AS STRING)
  ) as operation_summary;
END;
