-- =============================================
-- OI Database Project - V_SRC_AmazonAds_campaign_history
-- =============================================
--
-- @dialect: bigquery
-- Language: BigQuery SQL
--
-- Purpose: Campaign performance history with temporal versioning
-- Business Logic: Tracks campaign changes over time with validity periods
--
-- KEY CONCEPTS:
-- - OI_start_date: When this version of the campaign became active
-- - OI_end_date: When this version was replaced (or current time if active)
-- - Uses window functions to create temporal validity ranges
--
-- Dependencies:
--   - fivetran-hl.amazon_ads.campaign_history (Sponsored Products)
--   - fivetran-hl.amazon_ads.sb_campaign_history (Sponsored Brands)
--
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2025-01-01
-- Fixed: Improved readability, formatting, and documentation
--
-- =============================================

DROP VIEW IF EXISTS `onyga-482313.OI.V_SRC_AmazonAds_campaign_history`;
CREATE VIEW `onyga-482313.OI.V_SRC_AmazonAds_campaign_history` AS

-- ============================================================================
-- SPONSORED PRODUCTS CAMPAIGNS
-- ============================================================================
WITH sp_campaigns AS (
  SELECT
    -- Core campaign identifiers
    CAST(c.id AS STRING) AS campaign_id,
    c.last_updated_date,
    c.serving_status,
    c.name AS campaign_name,
    c.budget,
    '-1' AS brand_entity_id,  -- SP campaigns don't have brand entity
    c.creation_date,
    c.portfolio_id,
    c.profile_id,
    c.state,
    c.bidding_strategy,
    c.budget_type,

    -- Temporal versioning logic
    -- OI_start_date: Campaign version start date
    -- OI_end_date: Campaign version end date
    CASE
      WHEN c.last_updated_date = MIN(c.last_updated_date) OVER (
        PARTITION BY c.id
        ORDER BY c.last_updated_date
      )
      THEN TIMESTAMP '1900-01-01 00:00:00'  -- Default for first version
      ELSE c.last_updated_date
    END AS OI_start_date,

    -- End date is either next version's start date or current time
    TIMESTAMP_SUB(
      COALESCE(
        LEAD(c.last_updated_date) OVER (
          PARTITION BY c.id
          ORDER BY c.last_updated_date
        ),
        TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
      ),
      INTERVAL 1 SECOND
    ) AS OI_end_date,

    'SP' AS campaign_type  -- Source system identifier

  FROM `fivetran-hl`.amazon_ads.campaign_history c
),

-- ============================================================================
-- SPONSORED BRANDS CAMPAIGNS
-- ============================================================================
sb_campaigns AS (
  SELECT
    -- Core campaign identifiers
    CAST(c.id AS STRING) AS campaign_id,
    c.last_update_date AS last_updated_date,
    c.serving_status,
    c.name AS campaign_name,
    c.budget,
    c.brand_entity_id,  -- SB campaigns have brand entity
    c.creation_date,
    c.portfolio_id,
    c.profile_id,
    c.state,
    '' AS bidding_strategy,  -- SB campaigns don't have bidding strategy
    c.budget_type,

    -- Temporal versioning logic (same as SP)
    CASE
      WHEN c.last_update_date = MIN(c.last_update_date) OVER (
        PARTITION BY c.id
        ORDER BY c.last_update_date
      )
      THEN TIMESTAMP '1900-01-01 00:00:00'
      ELSE c.last_update_date
    END AS OI_start_date,

    TIMESTAMP_SUB(
      COALESCE(
        LEAD(c.last_update_date) OVER (
          PARTITION BY c.id
          ORDER BY c.last_update_date
        ),
        TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
      ),
      INTERVAL 1 SECOND
    ) AS OI_end_date,

    'SB' AS campaign_type  -- Source system identifier

  FROM `fivetran-hl`.amazon_ads.sb_campaign_history c
)

-- ============================================================================
-- FINAL UNION OF SP AND SB CAMPAIGNS
-- ============================================================================
SELECT * FROM sp_campaigns
UNION ALL
SELECT * FROM sb_campaigns;
