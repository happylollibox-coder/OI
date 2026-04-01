-- =============================================
-- OI Database Project - V_SRC_AmazonAds_negative_keyword
-- =============================================
--
-- Purpose: Negative keyword management for preventing unwanted impressions
-- Business Logic: Consolidates negative keywords with status filtering
-- Dependencies: fivetran-hl.amazon_ads.negative_keyword_history, fivetran-hl.amazon_ads.sb_negative_keyword
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2025-01-01
--
-- =============================================

DROP VIEW IF EXISTS `OI.V_SRC_AmazonAds_negative_keyword`;
CREATE VIEW `onyga-482313.OI.V_SRC_AmazonAds_negative_keyword`
AS 


SELECT 
	CAST(id AS STRING) negative_id,
	CAST(campaign_id AS STRING) campaign_id,
    CAST(ad_group_id AS STRING) AS ad_group_id,
keyword_text, state,
match_type,
last_updated_date, creation_date, `_fivetran_synced`
FROM `fivetran-hl`.amazon_ads.negative_keyword_history
where serving_status='TARGETING_CLAUSE_STATUS_LIVE'and state ='ENABLED'
union all

SELECT 
	CAST(id AS STRING) negative_id,
	CAST(campaign_id AS STRING) campaign_id,
    CAST(ad_group_id AS STRING) AS ad_group_id,
keyword_text, state,
match_type,
null last_updated_date,null creation_date, `_fivetran_synced`
FROM `fivetran-hl`.amazon_ads.sb_negative_keyword
where  state ='enabled' and `_fivetran_deleted` =false