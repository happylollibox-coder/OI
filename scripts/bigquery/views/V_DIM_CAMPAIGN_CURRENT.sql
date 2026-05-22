-- =============================================
-- OI Database Project - V_DIM_CAMPAIGN_CURRENT View
-- =============================================
--
-- Purpose: Single source of truth for CURRENT campaign metadata.
--          One row per campaign_id with the latest values.
--          Prevents campaign rename splits across downstream views.
--
-- Grain: One row per campaign_id
-- Source: DIM_CAMPAIGN (SCD2, is_current = TRUE)
-- Used by: FACT_ADS_COACH_ACTIONS (campaign_name, state, budget)
--
-- Naming: V_DIM_ prefix = dimension view (read-only lookup)
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT`
AS
SELECT
  campaign_id,
  campaign_name,
  campaign_type,
  state as campaign_state,
  serving_status,
  daily_budget,
  bidding_strategy,
  portfolio_id,
  portfolio_name,
  creation_date,
  last_updated_date,
  effective_from
FROM `onyga-482313.OI.DIM_CAMPAIGN`
WHERE is_current = TRUE;
