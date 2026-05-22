-- =============================================
-- OI Database Project - V_SRC_AmazonAds_campaign_history
-- =============================================
--
-- Purpose: Unified campaign data across SP and SB campaigns
-- Business Logic: Consolidates campaign data from Fivetran history tables
--   - `date` column: used by SP_LOAD_DIM_CAMPAIGN for SCD2 timing
--   - OI_start_date/OI_end_date: temporal columns for downstream point-in-time joins
-- Dependencies: fivetran-hl.amazon_ads.campaign_history, fivetran-hl.amazon_ads.sb_campaign_history
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2026-04-09
--
-- =============================================

DROP VIEW IF EXISTS `onyga-482313.OI.V_SRC_AmazonAds_campaign_history`;
CREATE VIEW `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` AS

WITH sp_campaigns AS (
  SELECT
    CAST(c.id AS STRING) AS campaign_id,
    c.name AS campaign_name,
    'SP' AS campaign_type,
    c.state,
    c.serving_status,
    c.budget,
    c.budget AS daily_budget,
    c.bidding_strategy,
    c.budget_type,
    CAST(c.portfolio_id AS STRING) AS portfolio_id,
    CAST(c.profile_id AS STRING) AS profile_id,
    c.creation_date,
    c.last_updated_date AS date,
    c._fivetran_synced,

    -- Temporal columns (backward compat for downstream point-in-time joins)
    CASE
      WHEN c.last_updated_date = MIN(c.last_updated_date) OVER (PARTITION BY c.id ORDER BY c.last_updated_date)
      THEN TIMESTAMP '1900-01-01 00:00:00'
      ELSE c.last_updated_date
    END AS OI_start_date,

    TIMESTAMP_SUB(
      COALESCE(
        LEAD(c.last_updated_date) OVER (PARTITION BY c.id ORDER BY c.last_updated_date),
        TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
      ),
      INTERVAL 1 SECOND
    ) AS OI_end_date

  FROM `fivetran-hl`.amazon_ads.campaign_history c
),

sb_campaigns AS (
  SELECT
    CAST(c.id AS STRING) AS campaign_id,
    c.name AS campaign_name,
    'SB' AS campaign_type,
    c.state,
    c.serving_status,
    c.budget,
    c.budget AS daily_budget,
    '' AS bidding_strategy,
    c.budget_type,
    CAST(c.portfolio_id AS STRING) AS portfolio_id,
    CAST(c.profile_id AS STRING) AS profile_id,
    c.creation_date,
    c.last_update_date AS date,
    c._fivetran_synced,

    CASE
      WHEN c.last_update_date = MIN(c.last_update_date) OVER (PARTITION BY c.id ORDER BY c.last_update_date)
      THEN TIMESTAMP '1900-01-01 00:00:00'
      ELSE c.last_update_date
    END AS OI_start_date,

    TIMESTAMP_SUB(
      COALESCE(
        LEAD(c.last_update_date) OVER (PARTITION BY c.id ORDER BY c.last_update_date),
        TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
      ),
      INTERVAL 1 SECOND
    ) AS OI_end_date

  FROM `fivetran-hl`.amazon_ads.sb_campaign_history c
)

SELECT * FROM sp_campaigns
UNION ALL
SELECT * FROM sb_campaigns
