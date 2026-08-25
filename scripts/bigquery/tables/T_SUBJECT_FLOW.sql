-- =============================================================================================
-- T_SUBJECT_FLOW — every forecastable subject with the CUSTOMER-PERSPECTIVE attributes its flows
-- are built from. v27.151 (2026-08-25). §2.0.4 / §2.0.5.
--
-- THE DIMENSIONS ARE THE CUSTOMER'S, NOT THE KEYWORD'S (Ori): time, family, intent, placement,
-- ads type — "he buys at a certain time for a certain intent, sees the advertisement in a certain
-- placement, and the ad looks like an ads type". The earlier set (subject_kind, term_kind, is_gift,
-- age_group, gender, product_type) described the KEYWORD, which is not the same thing.
--
-- PLACEMENT IS NOT HERE AS A LEVEL, and that is structural (§2.0.5): a keyword does not BELONG to a
-- placement, it is served across a mix set by the campaign's bid adjustments, and the placement
-- report carries no keyword column at all. What is carried instead is the campaign's top-of-search
-- SHARE, as a modifier — top of search converts at 5.49% against 0.41% off-Amazon, so the mix moves
-- the CVR and CPC links without ever partitioning a subject.
--
-- ADS TYPE is derived from the naming convention where creative_type is null, which covers 100%:
-- SP 860 campaigns, SB video 130, SB store 105, SB other 18.
--
-- Rebuilt, never accumulated — a derived lookup, not a record of what was said (cf. violation 6).
-- =============================================================================================
CREATE OR REPLACE TABLE `onyga-482313.OI.T_SUBJECT_FLOW`
OPTIONS (description = "Every forecastable subject with the CUSTOMER-PERSPECTIVE attributes its customer purchase flows are built from (THREE_LAYERS.md §2.0.4/§2.0.5): family, intent, ads type, and the campaign's top-of-search share as a placement MODIFIER. Time is not here because it is a property of the observation rather than the subject — it enters at member grain, where a member is a (subject x season) cell. Placement is a modifier and never a level: a keyword does not belong to a placement, it is served across a mix set by the campaign's bid adjustments, and the placement report carries no keyword column. Ads type is derived from the naming convention where creative_type is null, covering 100% of campaigns. Rebuilt by hand or by SP_BUILD_CUSTOMER_PURCHASE_FLOWS' upstream; read by that procedure.")
AS
WITH wm AS (SELECT MAX(report_date) AS w FROM `onyga-482313.OI.V_CAMPAIGN_PLACEMENT_REPORT`),
-- the campaign's placement MIX over the year: how much of its traffic reaches the placement that
-- actually converts. A modifier, not a partition.
place AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id,
         ROUND(SAFE_DIVIDE(SUM(IF(placement = 'TOP_OF_SEARCH', clicks, 0)),
                           NULLIF(SUM(clicks), 0)), 4) AS top_of_search_share,
         ROUND(SAFE_DIVIDE(SUM(IF(placement = 'DETAIL_PAGE', clicks, 0)),
                           NULLIF(SUM(clicks), 0)), 4) AS detail_page_share,
         SUM(clicks) AS placement_clicks
  FROM `onyga-482313.OI.V_CAMPAIGN_PLACEMENT_REPORT` CROSS JOIN wm
  WHERE report_date >= DATE_SUB(wm.w, INTERVAL 364 DAY)
  GROUP BY 1
),
ads AS (
  SELECT CAST(campaign_id AS STRING) AS campaign_id,
         CASE WHEN campaign_type = 'SP' THEN 'SP'
              WHEN REGEXP_CONTAINS(UPPER(campaign_name), r'VIDEO')          THEN 'SB_VIDEO'
              WHEN REGEXP_CONTAINS(UPPER(campaign_name), r'STORE|SPOTLIGHT') THEN 'SB_STORE'
              ELSE 'SB_OTHER' END AS ads_type
  FROM `onyga-482313.OI.DIM_CAMPAIGN` WHERE is_current
)
SELECT
  CAST(s.campaign_id AS STRING) AS campaign_id,
  CAST(s.keyword_id AS STRING)  AS keyword_id,
  LOWER(TRIM(s.target_text))    AS target_text,
  COALESCE(s.family, 'UNMAPPED') AS family,          -- MANDATORY level (§2.0.4)
  COALESCE(i.intent_key, 'UNSPECIFIED') AS intent,   -- earned level
  COALESCE(a.ads_type, 'SP')            AS ads_type, -- earned level
  p.top_of_search_share,                             -- placement MODIFIER (§2.0.5)
  p.detail_page_share,
  CURRENT_TIMESTAMP() AS built_at
FROM `onyga-482313.OI.FACT_KEYWORD_STATE` s
LEFT JOIN (
  SELECT LOWER(TRIM(search_term)) AS t, ANY_VALUE(intent_key) AS intent_key
  FROM `onyga-482313.OI.V_INTENT_RESOLVED`
  WHERE LOWER(TRIM(search_term)) IN (
    SELECT DISTINCT LOWER(TRIM(target_text)) FROM `onyga-482313.OI.FACT_KEYWORD_STATE`)
  GROUP BY 1
) i ON i.t = LOWER(TRIM(s.target_text))
LEFT JOIN ads a  ON a.campaign_id = CAST(s.campaign_id AS STRING)
LEFT JOIN place p ON p.campaign_id = CAST(s.campaign_id AS STRING);
