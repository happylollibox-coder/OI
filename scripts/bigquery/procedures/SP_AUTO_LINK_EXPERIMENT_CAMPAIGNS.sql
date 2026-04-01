-- =============================================
-- OI Database Project - SP_AUTO_LINK_EXPERIMENT_CAMPAIGNS
-- =============================================
--
-- Purpose: Resolve PENDING campaign links in DIM_EXPERIMENT_CAMPAIGN.
--          When a new experiment is registered with expected campaign names
--          but campaigns haven't synced yet, campaign_id is set to 'PENDING_N'.
--          This procedure matches campaign_name to Fivetran-synced campaign data
--          and replaces the pending rows with real campaign_ids.
--
-- How it works:
--   1. Find DIM_EXPERIMENT_CAMPAIGN rows where campaign_id LIKE 'PENDING_%'
--   2. Match campaign_name to V_SRC_AmazonAds_campaign_history (current version)
--   3. INSERT new row with real campaign_id (preserving experiment_id, campaign_name, notes)
--   4. DELETE the PENDING row
--
-- Schedule: Daily via SP_ORCHESTRATE_DAILY_REFRESH (before SP_EXPERIMENT_DAILY_SNAPSHOT)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_AUTO_LINK_EXPERIMENT_CAMPAIGNS`()
OPTIONS (
  description = "Resolve PENDING campaign links by matching campaign_name to Fivetran data."
)
BEGIN
  DECLARE resolved_count INT64 DEFAULT 0;

  -- Step 1: Insert resolved rows (real campaign_id from Fivetran)
  INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`
    (experiment_id, campaign_id, campaign_name, notes)
  SELECT
    pending.experiment_id,
    CAST(ch.campaign_id AS STRING) as campaign_id,
    pending.campaign_name,
    REPLACE(pending.notes, 'PENDING AUTO-LINK. ', '') as notes
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` pending
  JOIN `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` ch
    ON ch.campaign_name = pending.campaign_name
    AND ch.OI_end_date >= CURRENT_TIMESTAMP()
  WHERE pending.campaign_id LIKE 'PENDING_%'
    -- Don't insert if already linked with real campaign_id
    AND NOT EXISTS (
      SELECT 1 FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` existing
      WHERE existing.experiment_id = pending.experiment_id
        AND existing.campaign_id = CAST(ch.campaign_id AS STRING)
    );

  SET resolved_count = @@row_count;

  -- Step 2: Delete PENDING rows that were resolved
  DELETE FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`
  WHERE campaign_id LIKE 'PENDING_%'
    AND EXISTS (
      SELECT 1 FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` resolved
      WHERE resolved.experiment_id = `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`.experiment_id
        AND resolved.campaign_name = `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`.campaign_name
        AND resolved.campaign_id NOT LIKE 'PENDING_%'
    );

  -- Log result
  IF resolved_count > 0 THEN
    SELECT FORMAT(
      'SP_AUTO_LINK_EXPERIMENT_CAMPAIGNS: Resolved %d pending campaign links.',
      resolved_count
    ) as log_message;
  ELSE
    -- Check if there are still unresolved pending links
    SELECT FORMAT(
      'SP_AUTO_LINK_EXPERIMENT_CAMPAIGNS: No new campaigns resolved. %d still pending.',
      (SELECT COUNT(*) FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` WHERE campaign_id LIKE 'PENDING_%')
    ) as log_message;
  END IF;

END;
