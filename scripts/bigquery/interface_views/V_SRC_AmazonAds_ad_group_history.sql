-- =============================================
-- OI Database Project - V_SRC_AmazonAds_ad_group_history
-- =============================================
--
-- Purpose: Ad group history with temporal versioning for tracking ad group changes over time
-- Business Logic: Tracks ad group changes over time with validity periods
--
-- KEY CONCEPTS:
-- - OI_start_date: When this version of the ad group became active
-- - OI_end_date: When this version was replaced (or current time if active)
-- - Uses window functions to create temporal validity ranges
--
-- Dependencies:
--   - fivetran-hl.amazon_ads.ad_group_history (Sponsored Products)
--   - fivetran-hl.amazon_ads.sb_ad_group_history (Sponsored Brands)
--
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2026-01-31
--
-- =============================================

DROP VIEW IF EXISTS `onyga-482313.OI.V_SRC_AmazonAds_ad_group_history`;
CREATE VIEW `onyga-482313.OI.V_SRC_AmazonAds_ad_group_history` AS

-- ============================================================================
-- SPONSORED PRODUCTS AD GROUPS
-- ============================================================================
WITH sp_ad_groups AS (
  SELECT
    -- Core ad group identifiers
    CAST(ag.id AS STRING) AS ad_group_id,
    ag.campaign_id,
    ag.last_updated_date,
    ag.serving_status,
    ag.name AS ad_group_name,
    ag.default_bid,
    ag.state,
    ag.creation_date,

    -- Temporal versioning logic
    -- OI_start_date: Ad group version start date
    -- OI_end_date: Ad group version end date
    CASE
      WHEN ag.last_updated_date = MIN(ag.last_updated_date) OVER (
        PARTITION BY ag.id
        ORDER BY ag.last_updated_date
      )
      THEN TIMESTAMP '1900-01-01 00:00:00'  -- Default for first version
      ELSE ag.last_updated_date
    END AS OI_start_date,

    -- End date is either next version's start date or current time
    TIMESTAMP_SUB(
      COALESCE(
        LEAD(ag.last_updated_date) OVER (
          PARTITION BY ag.id
          ORDER BY ag.last_updated_date
        ),
        TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
      ),
      INTERVAL 1 SECOND
    ) AS OI_end_date,

    'SP' AS campaign_type,  -- Source system identifier
    'SP' AS data_source     -- Explicit data source flag

  FROM `fivetran-hl`.amazon_ads.ad_group_history ag
),

-- ============================================================================
-- SPONSORED BRANDS AD GROUPS
-- ============================================================================
sb_ad_groups AS (
  SELECT
    -- Core ad group identifiers
    CAST(ag.id AS STRING) AS ad_group_id,
    ag.campaign_id,
    ag.last_update_date AS last_updated_date,
    ag.serving_status,
    ag.name AS ad_group_name,
    NULL AS default_bid,  -- SB ad groups don't have default_bid
    ag.state,
    ag.creation_date,

    -- Temporal versioning logic (same as SP)
    CASE
      WHEN ag.last_update_date = MIN(ag.last_update_date) OVER (
        PARTITION BY ag.id
        ORDER BY ag.last_update_date
      )
      THEN TIMESTAMP '1900-01-01 00:00:00'
      ELSE ag.last_update_date
    END AS OI_start_date,

    TIMESTAMP_SUB(
      COALESCE(
        LEAD(ag.last_update_date) OVER (
          PARTITION BY ag.id
          ORDER BY ag.last_update_date
        ),
        TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
      ),
      INTERVAL 1 SECOND
    ) AS OI_end_date,

    'SB' AS campaign_type,  -- Source system identifier
    'SB' AS data_source     -- Explicit data source flag

  FROM `fivetran-hl`.amazon_ads.sb_ad_group_history ag
)

-- ============================================================================
-- FINAL UNION OF SP AND SB AD GROUPS
-- ============================================================================
SELECT * FROM sp_ad_groups
UNION ALL
SELECT * FROM sb_ad_groups;
