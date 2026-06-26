-- V_KEYWORD_DAILY — keyword×day from the true keyword report (impressions incl no-traffic, TOS share, set bid).
CREATE OR REPLACE VIEW `onyga-482313.OI.V_KEYWORD_DAILY` AS
WITH camp_parent AS (
  SELECT campaign_id, parent_name FROM (
    SELECT a.campaign_id, p.parent_name,
      ROW_NUMBER() OVER (PARTITION BY a.campaign_id ORDER BY SUM(a.Ads_cost) DESC) rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
    WHERE a.date >= DATE('2025-09-23') GROUP BY a.campaign_id, p.parent_name
  ) WHERE rn = 1
),
kh AS (
  SELECT CAST(id AS STRING) AS keyword_id,
         ANY_VALUE(keyword_text) AS keyword_text, ANY_VALUE(match_type) AS match_type
  FROM `fivetran-hl.amazon_ads.keyword_history` GROUP BY 1
)
SELECT
  r.date,
  CAST(r.campaign_id AS STRING) AS campaign_id,
  CAST(r.ad_group_id AS STRING) AS ad_group_id,
  CAST(r.keyword_id  AS STRING) AS keyword_id,
  cp.parent_name,
  kh.keyword_text,
  UPPER(kh.match_type) AS match_type,
  r.keyword_bid,
  r.impressions, r.clicks, r.cost, r.cost_per_click,
  r.click_through_rate                AS ctr,
  r.top_of_search_impression_share    AS tos_share,
  r.units_sold_clicks_14_d            AS units_14d,
  r.sales_14_d                        AS sales_14d,
  r.ad_keyword_status,
  (r.sales_14_d - r.cost)             AS net_proxy,
  (r.impressions = 0)                 AS no_traffic
FROM `fivetran-hl.amazon_ads.targeting_keyword_report` r
LEFT JOIN camp_parent cp ON cp.campaign_id = CAST(r.campaign_id AS STRING)
LEFT JOIN kh            ON kh.keyword_id   = CAST(r.keyword_id AS STRING)
WHERE r.date >= DATE('2025-09-23');
