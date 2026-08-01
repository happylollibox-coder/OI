-- =============================================
-- OI Database Project - V_SRC_AmazonAds_negative_keyword
-- =============================================
--
-- Purpose: Negative keyword management for preventing unwanted impressions
-- Business Logic: Consolidates ALL frozen Fivetran negative-keyword sources:
--   SP ad-group level  (negative_keyword_history)
--   SP campaign level  (campaign_negative_keyword_history — ad_group_id NULL)
--   SB                 (sb_negative_keyword)
-- The Fivetran negative sync is FROZEN since 2026-01-03 — this view is a static
-- pre-freeze backstop only; DE_NEGATIVE_KEYWORDS is the live authority.
-- state='ENABLED' with NO serving-status filter: an ENABLED negative in a paused
-- campaign still exists on Amazon and must stay in already-negated blacklists
-- (re-negating it is a no-op upload error). History tables are NOT deduped here;
-- consumers dedupe to the latest row per negative_id.
-- Dependencies: fivetran-hl.amazon_ads.negative_keyword_history,
--               fivetran-hl.amazon_ads.campaign_negative_keyword_history,
--               fivetran-hl.amazon_ads.sb_negative_keyword
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2026-08-01
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_SRC_AmazonAds_negative_keyword`
AS

-- SP ad-group-level negatives
SELECT
	CAST(id AS STRING) negative_id,
	CAST(campaign_id AS STRING) campaign_id,
    CAST(ad_group_id AS STRING) AS ad_group_id,
keyword_text, state,
match_type,
last_updated_date, creation_date, `_fivetran_synced`
FROM `fivetran-hl`.amazon_ads.negative_keyword_history
where state ='ENABLED'
union all

-- SP campaign-level negatives (no ad group)
SELECT
	CAST(id AS STRING) negative_id,
	CAST(campaign_id AS STRING) campaign_id,
    CAST(NULL AS STRING) AS ad_group_id,
keyword_text, state,
match_type,
last_updated_date, creation_date, `_fivetran_synced`
FROM `fivetran-hl`.amazon_ads.campaign_negative_keyword_history
where state ='ENABLED'
union all

-- SB negatives
SELECT
	CAST(id AS STRING) negative_id,
	CAST(campaign_id AS STRING) campaign_id,
    CAST(ad_group_id AS STRING) AS ad_group_id,
keyword_text, state,
match_type,
null last_updated_date,null creation_date, `_fivetran_synced`
FROM `fivetran-hl`.amazon_ads.sb_negative_keyword
where  state ='enabled' and `_fivetran_deleted` =false
