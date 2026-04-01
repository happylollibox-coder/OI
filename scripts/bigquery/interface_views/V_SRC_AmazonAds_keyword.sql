
-- =============================================
-- OI Database Project - V_SRC_AmazonAds_keyword
-- =============================================
--
-- Purpose: Unified keyword targeting data across SP and SB campaigns
-- Business Logic: Consolidates keyword data from multiple sources
-- Dependencies: fivetran-hl.amazon_ads.keyword_history, fivetran-hl.amazon_ads.sb_keyword
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2025-01-01
--
-- =============================================

DROP VIEW IF EXISTS `OI.V_SRC_AmazonAds_keyword`;
CREATE VIEW `onyga-482313.OI.V_SRC_AmazonAds_keyword`
AS 

SELECT 
CAST(id AS STRING) keyword_id,
CAST(ad_group_id AS STRING) ad_group_id,
CAST(campaign_id AS STRING)campaign_id,
 keyword_text, 
 match_type,
 state,
native_language_keyword,
bid, 
`_fivetran_synced` 
FROM `fivetran-hl`.amazon_ads.keyword_history
union all

SELECT 
CAST(id AS STRING) keyword_id,
CAST(ad_group_id AS STRING) ad_group_id,
CAST(campaign_id AS STRING)campaign_id,
keyword_text,
match_type, 
state, 
native_language_keyword, 
bid, 
`_fivetran_synced` 
FROM `fivetran-hl`.amazon_ads.sb_keyword
union all

select 
keyword_id,ad_group_id,campaign_id, keyword_text,  match_type, state,native_language_keyword,bid  ,`_fivetran_synced`
from (
select 
CAST(keyword_id AS STRING) keyword_id,
CAST(ad_group_id AS STRING) ad_group_id,
CAST(campaign_id AS STRING)campaign_id,
targeting keyword_text,
case when targeting in ('close-match','loose-match','substitutes','complements') then 'Automatic' 
when targeting like '%expanded%' then 'ASIN Expended'
when targeting like 'category%' then 'Category'
else 'ASIN' end match_type, 

'' state, '' native_language_keyword, null bid, 
max(`_fivetran_synced`)`_fivetran_synced` ,
 from  `fivetran-hl`.amazon_ads.search_term_targeting_report   t  
group by keyword_id,ad_group_id,campaign_id,targeting ,targeting

)T 
group by keyword_id,ad_group_id,campaign_id,keyword_text,  match_type,state,native_language_keyword,bid,`_fivetran_synced`

