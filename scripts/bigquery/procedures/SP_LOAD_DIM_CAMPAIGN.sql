-- =============================================
-- OI Database Project - SP_LOAD_DIM_CAMPAIGN
-- =============================================
--
-- Purpose: SCD Type 2 load for DIM_CAMPAIGN from V_SRC_AmazonAds_campaign_history
-- Pattern: Close changed rows (set effective_to, is_current=FALSE), insert new versions
-- Tracked fields: campaign_name, campaign_type, state, serving_status,
--                 daily_budget, bidding_strategy, portfolio_id
-- Timing: effective_from = `date` column from source (last_updated_date)
-- Source: V_SRC_AmazonAds_campaign_history (Fivetran)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_LOAD_DIM_CAMPAIGN`()
OPTIONS (
  description = "SCD2 load for DIM_CAMPAIGN. Closes changed rows and inserts new versions from V_SRC_AmazonAds_campaign_history."
)
BEGIN
  DECLARE closed_count INT64 DEFAULT 0;
  DECLARE inserted_count INT64 DEFAULT 0;
  DECLARE start_time TIMESTAMP;

  SET start_time = CURRENT_TIMESTAMP();

  -- Deduplicate source: keep only the latest per campaign_id (by date column)
  CREATE TEMP TABLE _src_campaign AS
  SELECT
    ch.campaign_id,
    ch.campaign_name,
    ch.campaign_type,
    ch.state,
    ch.serving_status,
    ch.daily_budget,
    ch.bidding_strategy,
    ch.portfolio_id,
    p.portfolio_name,
    ch.profile_id,
    ch.creation_date,
    ch.date AS last_updated_date,
    ch._fivetran_synced,
    CAST(ch.date AS DATETIME) AS eff_from
  FROM `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` ch
  LEFT JOIN (
    -- Get the active portfolio name (where end date is in the future)
    SELECT portfolio_id, portfolio_name 
    FROM `onyga-482313.OI.V_SRC_AmazonAds_portfolio` 
    WHERE OI_end_date > CURRENT_TIMESTAMP()
  ) p ON ch.portfolio_id = p.portfolio_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ch.campaign_id ORDER BY ch.date DESC) = 1;

  -- Step 1: Close rows where tracked attributes changed
  UPDATE `onyga-482313.OI.DIM_CAMPAIGN` dim
  SET
    effective_to = src.eff_from,
    is_current = FALSE
  FROM _src_campaign src
  WHERE dim.campaign_id = src.campaign_id
    AND dim.is_current = TRUE
    AND (
      dim.campaign_name    IS DISTINCT FROM src.campaign_name
      OR dim.campaign_type IS DISTINCT FROM src.campaign_type
      OR dim.state         IS DISTINCT FROM src.state
      OR dim.serving_status IS DISTINCT FROM src.serving_status
      OR dim.daily_budget  IS DISTINCT FROM src.daily_budget
      OR dim.bidding_strategy IS DISTINCT FROM src.bidding_strategy
      OR dim.portfolio_id  IS DISTINCT FROM src.portfolio_id
      OR dim.portfolio_name IS DISTINCT FROM src.portfolio_name
    );

  SET closed_count = @@row_count;

  -- Step 2: Insert new versions for changed rows + entirely new campaigns
  INSERT INTO `onyga-482313.OI.DIM_CAMPAIGN` (
    campaign_id, campaign_name, campaign_type, state, serving_status,
    daily_budget, bidding_strategy, portfolio_id, portfolio_name, profile_id,
    creation_date, last_updated_date, _fivetran_synced,
    effective_from, effective_to, is_current
  )
  SELECT
    src.campaign_id,
    src.campaign_name,
    src.campaign_type,
    src.state,
    src.serving_status,
    src.daily_budget,
    src.bidding_strategy,
    src.portfolio_id,
    src.portfolio_name,
    src.profile_id,
    src.creation_date,
    src.last_updated_date,
    src._fivetran_synced,
    src.eff_from AS effective_from,
    CAST(NULL AS DATETIME) AS effective_to,
    TRUE AS is_current
  FROM _src_campaign src
  WHERE NOT EXISTS (
    SELECT 1
    FROM `onyga-482313.OI.DIM_CAMPAIGN` dim
    WHERE dim.campaign_id = src.campaign_id
      AND dim.is_current = TRUE
      AND dim.campaign_name    IS NOT DISTINCT FROM src.campaign_name
      AND dim.campaign_type    IS NOT DISTINCT FROM src.campaign_type
      AND dim.state            IS NOT DISTINCT FROM src.state
      AND dim.serving_status   IS NOT DISTINCT FROM src.serving_status
      AND dim.daily_budget     IS NOT DISTINCT FROM src.daily_budget
      AND dim.bidding_strategy IS NOT DISTINCT FROM src.bidding_strategy
      AND dim.portfolio_id     IS NOT DISTINCT FROM src.portfolio_id
      AND dim.portfolio_name   IS NOT DISTINCT FROM src.portfolio_name
  );

  SET inserted_count = @@row_count;

  DROP TABLE IF EXISTS _src_campaign;

  SELECT FORMAT(
    'SP_LOAD_DIM_CAMPAIGN completed: Closed %d rows, Inserted %d rows, Duration: %d seconds',
    closed_count, inserted_count,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), start_time, SECOND)
  ) as operation_summary;
END;
