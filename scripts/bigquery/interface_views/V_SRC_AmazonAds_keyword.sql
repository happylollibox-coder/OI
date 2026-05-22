
-- =============================================
-- OI Database Project - V_SRC_AmazonAds_keyword
-- =============================================
--
-- Purpose: Unified keyword targeting data across SP and SB campaigns
-- Business Logic: Consolidates keyword data from multiple sources
-- Dependencies: fivetran-hl.amazon_ads.keyword_history, fivetran-hl.amazon_ads.sb_keyword
-- Project: onyga-482313
-- Dataset: OI
-- Updated: 2026-04-09
--
-- =============================================

DROP VIEW IF EXISTS `OI.V_SRC_AmazonAds_keyword`;
CREATE VIEW `onyga-482313.OI.V_SRC_AmazonAds_keyword`
AS 
WITH expression_agg AS (
  SELECT 
    target_id,
    STRING_AGG(
      CASE 
        WHEN type = 'QUERY_HIGH_REL_MATCHES' THEN 'close-match'
        WHEN type = 'QUERY_BROAD_REL_MATCHES' THEN 'loose-match'
        WHEN type = 'ASIN_SUBSTITUTE_RELATED' THEN 'substitutes'
        WHEN type = 'ASIN_ACCESSORY_RELATED' THEN 'complements'
        WHEN type = 'ASIN_SAME_AS' THEN CONCAT('asin="', value, '"')
        WHEN type = 'ASIN_CATEGORY_SAME_AS' THEN CONCAT('category="', value, '"')
        WHEN type = 'ASIN_BRAND_SAME_AS' THEN CONCAT('brand="', value, '"')
        ELSE CONCAT(type, '="', COALESCE(value, ''), '"')
      END, ' AND ' ORDER BY type
    ) as keyword_text,
    MAX(
      CASE 
        WHEN type IN ('QUERY_HIGH_REL_MATCHES', 'QUERY_BROAD_REL_MATCHES', 'ASIN_SUBSTITUTE_RELATED', 'ASIN_ACCESSORY_RELATED') THEN 'Automatic'
        WHEN type LIKE 'ASIN_CATEGORY%' THEN 'Category'
        WHEN type LIKE 'ASIN_SAME_AS%' THEN 'ASIN'
        ELSE 'ASIN Expanded'
      END
    ) as match_type
  FROM `fivetran-hl.amazon_ads.targeting_expression`
  GROUP BY target_id
)
SELECT 
CAST(id AS STRING) keyword_id,
CAST(ad_group_id AS STRING) ad_group_id,
CAST(campaign_id AS STRING) campaign_id,
 keyword_text, 
 match_type,
 state,
native_language_keyword,
bid,
last_updated_date date,
`_fivetran_synced` 
FROM `fivetran-hl`.amazon_ads.keyword_history
UNION ALL
SELECT 
CAST(id AS STRING) keyword_id,
CAST(ad_group_id AS STRING) ad_group_id,
CAST(campaign_id AS STRING) campaign_id,
keyword_text,
match_type, 
state, 
native_language_keyword, 
bid, 
`_fivetran_synced` date,
`_fivetran_synced` 
FROM `fivetran-hl`.amazon_ads.sb_keyword
UNION ALL
SELECT 
  CAST(t.target_id AS STRING) as keyword_id,
  CAST(t.ad_group_id AS STRING) as ad_group_id,
  CAST(t.campaign_id AS STRING) as campaign_id,
  COALESCE(e.keyword_text, t.expression_type) as keyword_text,
  COALESCE(e.match_type, 'Targeting') as match_type,
  t.state,
  '' as native_language_keyword,
  t.bid,
  t.last_updated_date as date,
  t._fivetran_synced
FROM `fivetran-hl`.amazon_ads.targeting_clause_history t
LEFT JOIN expression_agg e ON CAST(t.target_id AS STRING) = CAST(e.target_id AS STRING);
