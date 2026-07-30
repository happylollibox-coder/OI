-- V_TARGET_DAILY — every targetable entity at (date, target) grain: keywords AND auto targeting groups.
--
-- Why this exists: V_KEYWORD_DAILY sources ONLY targeting_keyword_report, which carries keywords and
-- nothing else — a 90-day scan returns zero rows for Automatic campaigns. The launch ramp
-- (V_CAMPAIGN_LAUNCH_RAMP) has to step bids on auto campaigns' targets, so it needs a grain that
-- includes them. targeting_report carries the four predefined auto groups (close-match / loose-match /
-- substitutes / complements) plus product/ASIN targets, with the same columns.
--
-- The two source reports are DISJOINT (verified 2026-07-16): targeting_keyword_report holds keywords;
-- targeting_report holds only TARGETING_EXPRESSION_PREDEFINED (auto) and TARGETING_EXPRESSION
-- (product/ASIN). Their keyword_id spaces do not collide (0 shared ids over 90d), so the UNION ALL
-- neither double-counts rows nor merges two entities onto one id.
--
-- target_type: KEYWORD (a real keyword) / AUTO (a predefined auto group) / PRODUCT (ASIN or category).
-- campaign_budget_amount is carried through — it is the campaign's actual daily budget on Amazon that
-- day, which is what the ramp's `spend(d) >= budget(d)` test needs.
--
-- Shape mirrors V_KEYWORD_DAILY so callers can migrate onto it. NOTE: AUTO/PRODUCT rows have no
-- keyword_history entry, so anything joining on keyword_text rather than keyword_id will not match them.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_TARGET_DAILY` AS
WITH camp_parent AS (   -- dominant family per campaign, by spend (same rule as V_KEYWORD_DAILY)
  SELECT campaign_id, parent_name FROM (
    SELECT a.campaign_id, p.parent_name,
      ROW_NUMBER() OVER (PARTITION BY a.campaign_id ORDER BY SUM(a.Ads_cost) DESC) rn
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
    JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = a.ASIN_BY_CAMPAIGN_NAME
    WHERE a.date >= DATE('2025-09-23') GROUP BY a.campaign_id, p.parent_name
  ) WHERE rn = 1
),
kh AS (
  -- 2026-07-30: consolidated source (V_DIM_CAMPAIGN_CURRENT / DIM_*) per prefer-DIM/FACT rule; was fivetran-hl.amazon_ads.keyword_history
  SELECT keyword_id,
         ANY_VALUE(keyword_text) AS keyword_text, ANY_VALUE(match_type) AS match_type
  FROM `onyga-482313.OI.DIM_KEYWORD` WHERE is_current = TRUE GROUP BY 1
),
raw AS (
  -- keywords
  SELECT r.date, r.campaign_id, r.ad_group_id, r.keyword_id,
         'KEYWORD' AS target_type,
         COALESCE(kh.keyword_text, r.targeting) AS target_text,
         UPPER(COALESCE(kh.match_type, r.match_type)) AS match_type,
         r.keyword_bid, r.campaign_budget_amount,
         r.impressions, r.clicks, r.cost, r.cost_per_click, r.click_through_rate,
         r.top_of_search_impression_share, r.units_sold_clicks_14_d, r.sales_14_d, r.ad_keyword_status
  FROM `fivetran-hl.amazon_ads.targeting_keyword_report` r
  LEFT JOIN kh ON kh.keyword_id = CAST(r.keyword_id AS STRING)
  WHERE r.date >= DATE('2025-09-23')

  UNION ALL

  -- auto groups + product/ASIN targets
  SELECT t.date, t.campaign_id, t.ad_group_id, t.keyword_id,
         IF(t.keyword_type = 'TARGETING_EXPRESSION_PREDEFINED'
            AND LOWER(t.targeting) IN ('close-match', 'loose-match', 'substitutes', 'complements'),
            'AUTO', 'PRODUCT') AS target_type,
         t.targeting AS target_text,
         UPPER(t.match_type) AS match_type,
         t.keyword_bid, t.campaign_budget_amount,
         t.impressions, t.clicks, t.cost, t.cost_per_click, t.click_through_rate,
         t.top_of_search_impression_share, t.units_sold_clicks_14_d, t.sales_14_d, t.ad_keyword_status
  FROM `fivetran-hl.amazon_ads.targeting_report` t
  WHERE t.date >= DATE('2025-09-23')
)
SELECT
  r.date,
  CAST(r.campaign_id AS STRING) AS campaign_id,
  CAST(r.ad_group_id AS STRING) AS ad_group_id,
  CAST(r.keyword_id  AS STRING) AS keyword_id,
  cp.parent_name,
  r.target_type,
  r.target_text,
  r.target_text                       AS keyword_text,   -- V_KEYWORD_DAILY parity
  r.match_type,
  r.keyword_bid,
  r.campaign_budget_amount            AS campaign_budget,
  r.impressions, r.clicks, r.cost, r.cost_per_click,
  r.click_through_rate                AS ctr,
  r.top_of_search_impression_share    AS tos_share,
  r.units_sold_clicks_14_d            AS units_14d,
  r.sales_14_d                        AS sales_14d,
  r.ad_keyword_status,
  (r.sales_14_d - r.cost)             AS net_proxy,
  (r.impressions = 0)                 AS no_traffic
FROM raw r
LEFT JOIN camp_parent cp ON cp.campaign_id = CAST(r.campaign_id AS STRING);
