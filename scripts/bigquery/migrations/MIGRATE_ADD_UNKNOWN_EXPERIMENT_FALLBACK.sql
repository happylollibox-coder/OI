-- Migration: Add UNKNOWN fallback experiment for unmapped campaigns
-- Date: 2026-05-23
-- Purpose: Ensures all ENABLED campaigns appear in the coach pipeline (and thus
--          in the Ad Strategy KPI card) by mapping unmapped ones to a fallback
--          "UNKNOWN" experiment. These campaigns show as "No Strategy" in the UI.

-- 1. Insert the UNKNOWN fallback experiment
INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT`
  (experiment_id, experiment_name, description, start_date, end_date,
   baseline_days, status, strategy_id, lifecycle_stage, season_context,
   created_at, updated_at)
VALUES
  ('UNKNOWN',
   'Unknown (Unmapped)',
   'Fallback experiment for campaigns not yet assigned to a real experiment. Auto-populated.',
   CURRENT_DATE(), NULL, 14, 'ACTIVE', NULL, 'ACTIVE', 'EVERGREEN',
   CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());

-- 2. Map all ENABLED campaigns that are not yet in DIM_EXPERIMENT_CAMPAIGN
INSERT INTO `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN`
  (experiment_id, campaign_id, campaign_name)
SELECT
  'UNKNOWN',
  d.campaign_id,
  d.campaign_name
FROM `onyga-482313.OI.DIM_CAMPAIGN` d
LEFT JOIN `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  ON d.campaign_id = ec.campaign_id
WHERE d.is_current = TRUE
  AND d.state = 'ENABLED'
  AND ec.campaign_id IS NULL;

-- 3. Refresh downstream materialized tables
CALL `onyga-482313.OI.SP_REFRESH_ADS_COACH_ACTIONS`();
CALL `onyga-482313.OI.SP_REFRESH_CUBE_TABLES`();
