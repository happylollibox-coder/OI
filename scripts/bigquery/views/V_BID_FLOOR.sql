-- =============================================================================================
-- V_BID_FLOOR — every current ad group's platform/house bid floor, resolved once (v27.104, 2026-08-22).
--
-- The constants and the rule live in FN_BID_FLOOR (the ONE definition). This view does the
-- creative-type resolution — DIM_AD_GROUP.creative_type on the is_current row, ANY_VALUE over the
-- (rare) duplicate current rows exactly as V_LAUNCH_BID_LADDER's own ag CTE has always done — so a
-- caller that knows only (campaign_id, keyword_id) can join DIM_KEYWORD -> ad_group_id -> here and
-- never carry a private floor. SB ad groups with a NULL creative_type resolve to the video floor
-- ($0.25, conservative: a bid too high is recoverable, a rejected upload is not).
--
-- Grain: one row per current ad_group_id. Readers: SP_SNAPSHOT_KEYWORD_STATE (via DIM_KEYWORD),
-- tools/build_reprice_bulksheet.py. V_LAUNCH_BID_LADDER calls FN_BID_FLOOR directly because it
-- already resolves creative_type for its published creative_type column.
-- Spec: architecture/KEYWORD_STATE.md "The floors".
-- =============================================================================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_BID_FLOOR` AS
WITH ag AS (
  SELECT CAST(ad_group_id AS STRING) AS ad_group_id,
         ANY_VALUE(CAST(campaign_id AS STRING)) AS campaign_id,
         ANY_VALUE(campaign_type) AS channel,          -- 'SP' | 'SB' as DIM_AD_GROUP spells it
         ANY_VALUE(creative_type) AS creative_type
  FROM `onyga-482313.OI.DIM_AD_GROUP`
  WHERE is_current
  GROUP BY 1
)
SELECT
  ad_group_id,
  campaign_id,
  channel,
  creative_type,
  `onyga-482313.OI.FN_BID_FLOOR`(channel, creative_type).bid_floor        AS bid_floor,
  `onyga-482313.OI.FN_BID_FLOOR`(channel, creative_type).bid_floor_source AS bid_floor_source
FROM ag;
