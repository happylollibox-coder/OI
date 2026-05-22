-- =============================================
-- OI Database Project - V_SRC_AmazonAds_ad_group_history
-- =============================================
--
-- Purpose: Ad group history with temporal versioning for tracking changes over time
-- Business Logic: Tracks ad group changes with validity periods
--   - `date` column: used by SP_LOAD_DIM_AD_GROUP for SCD2 timing
--   - OI_start_date/OI_end_date: temporal columns for downstream point-in-time joins
-- Dependencies: fivetran-hl.amazon_ads.ad_group_history, fivetran-hl.amazon_ads.sb_ad_group_history
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2026-04-09
--
-- =============================================

DROP VIEW IF EXISTS `onyga-482313.OI.V_SRC_AmazonAds_ad_group_history`;
CREATE VIEW `onyga-482313.OI.V_SRC_AmazonAds_ad_group_history` AS

WITH sp_ad_groups AS (
  SELECT
    CAST(ag.id AS STRING) AS ad_group_id,
    ag.campaign_id,
    ag.last_updated_date,
    ag.serving_status,
    ag.name AS ad_group_name,
    ag.default_bid,
    ag.state,
    ag.creation_date,
    ag.last_updated_date AS date,
    ag._fivetran_synced,

    CASE
      WHEN ag.last_updated_date = MIN(ag.last_updated_date) OVER (PARTITION BY ag.id ORDER BY ag.last_updated_date)
      THEN TIMESTAMP '1900-01-01 00:00:00'
      ELSE ag.last_updated_date
    END AS OI_start_date,

    TIMESTAMP_SUB(
      COALESCE(
        LEAD(ag.last_updated_date) OVER (PARTITION BY ag.id ORDER BY ag.last_updated_date),
        TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
      ),
      INTERVAL 1 SECOND
    ) AS OI_end_date,

    'SP' AS campaign_type,
    'SP' AS data_source

  FROM `fivetran-hl`.amazon_ads.ad_group_history ag
),

sb_ad_groups AS (
  SELECT
    CAST(ag.id AS STRING) AS ad_group_id,
    ag.campaign_id,
    ag.last_update_date AS last_updated_date,
    ag.serving_status,
    ag.name AS ad_group_name,
    NULL AS default_bid,
    ag.state,
    ag.creation_date,
    ag.last_update_date AS date,
    ag._fivetran_synced,

    CASE
      WHEN ag.last_update_date = MIN(ag.last_update_date) OVER (PARTITION BY ag.id ORDER BY ag.last_update_date)
      THEN TIMESTAMP '1900-01-01 00:00:00'
      ELSE ag.last_update_date
    END AS OI_start_date,

    TIMESTAMP_SUB(
      COALESCE(
        LEAD(ag.last_update_date) OVER (PARTITION BY ag.id ORDER BY ag.last_update_date),
        TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
      ),
      INTERVAL 1 SECOND
    ) AS OI_end_date,

    'SB' AS campaign_type,
    'SB' AS data_source

  FROM `fivetran-hl`.amazon_ads.sb_ad_group_history ag
)

SELECT * FROM sp_ad_groups
UNION ALL
SELECT * FROM sb_ad_groups
