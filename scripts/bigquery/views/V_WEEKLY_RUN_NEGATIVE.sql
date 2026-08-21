-- V_WEEKLY_RUN_NEGATIVE — the engine's NEGATE_TERM recommendations, one row per (campaign, keyword, term),
-- for Weekly Run Step-3 level 3 (negatives under each keyword). These are search terms the coacher already
-- decided to negate — irrelevant / money-wasting, and relevance/brand/seasonal-aware (NOT raw zero-order terms).
-- Also carries each term's PAST-PEAK performance (gift-season windows) so a seasonal converter isn't negated
-- by mistake — show peak orders/net beside the negate offer. Heavy → materialized to T_WEEKLY_RUN_NEGATIVE.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_WEEKLY_RUN_NEGATIVE` AS
WITH neg AS (
  SELECT
    parent_name, campaign_id, keyword_id, search_term,
    ANY_VALUE(campaign_name) AS campaign_name,
    ANY_VALUE(ad_group_id)   AS ad_group_id,
    ANY_VALUE(targeting)     AS targeting,
    ANY_VALUE(match_type)    AS match_type,
    ANY_VALUE(reason)        AS reason,
    -- hero (best-converting variant) for THIS term — drives the separate "add hero ASIN to ad group"
    -- action so a wrong-colour term can be fixed by advertising the right variant, not just negated.
    ANY_VALUE(hero_asin)         AS hero_asin,
    ANY_VALUE(hero_product_name) AS hero_product_name,
    ANY_VALUE(hero_ads_cvr_pct)  AS hero_cvr,
    LOGICAL_OR(COALESCE(hero_asin IS NOT NULL AND NOT is_hero_match, FALSE)) AS wrong_asin,
    MAX(priority_score)      AS priority_score,
    -- v27.99 (audit C4): the block's OWN evidence, published so the visible why-line can carry a
    -- number instead of a rule name. These are the ad-group-grain figures the v27.9x grain fix
    -- introduced — the grain an Amazon negative keyword actually switches off — so they are
    -- identical on every row of this group and MAX() reads them exactly. Nothing is divided here:
    -- clicks, orders and dollars only, so no ANY_VALUE pairing can drift.
    MAX(ng_clicks_8w)        AS block_clicks_8w,
    MAX(ng_orders_8w)        AS block_orders_8w,
    MAX(ng_net_profit_8w)    AS block_net_profit_8w,
    MAX(ng_lt_clicks)        AS block_lifetime_clicks,
    MAX(ng_lt_orders)        AS block_lifetime_orders
  FROM `onyga-482313.OI.V_ADS_COACH` vc
  WHERE vc.action = 'NEGATE_TERM'
    AND vc.search_term IS NOT NULL
    AND vc.keyword_id IS NOT NULL
    -- Skip terms ALREADY negated in this campaign (warehouse-owned registry, maintained by
    -- SP_SYNC_NEGATIVES from our uploads + bulksheet seed). Kills the Amazon "already exists"
    -- bounces and the coach re-suggesting negatives forever. Exact = same text; phrase = the
    -- existing negative phrase is contained in the term (that's how Amazon phrase negatives block).
    -- (outer table aliased vc — a bare campaign_id here would bind to nk and void the filter)
    AND NOT EXISTS (
      SELECT 1 FROM `onyga-482313.OI.DE_NEGATIVE_KEYWORDS` nk
      WHERE nk.campaign_id = CAST(vc.campaign_id AS STRING)
        AND nk.removed_at IS NULL
        AND UPPER(COALESCE(nk.state, 'ENABLED')) NOT IN ('ARCHIVED', 'REMOVED', 'PAUSED')
        AND (
          (UPPER(COALESCE(nk.match_type, '')) LIKE '%EXACT%' AND LOWER(nk.keyword_text) = LOWER(vc.search_term))
          OR (UPPER(COALESCE(nk.match_type, '')) LIKE '%PHRASE%' AND STRPOS(LOWER(vc.search_term), LOWER(nk.keyword_text)) > 0)
        )
    )
    -- Skip PRODUCT-target negatives already registered (DE_NEGATIVE_TARGETS). Auto-campaign substitute
    -- offers surface search_term = the competitor ASIN (e.g. 'b0csxzglpw'); the registry stores it as
    -- targeting_expression = 'asin="B0CSXZGLPW"'. Extract + case-fold both to compare. Parallels the
    -- keyword dedup above — kills the "NegativeTargetingClause ... already exists" bounces (report 13).
    AND NOT EXISTS (
      SELECT 1 FROM `onyga-482313.OI.DE_NEGATIVE_TARGETS` nt
      WHERE nt.campaign_id = CAST(vc.campaign_id AS STRING)
        AND nt.removed_at IS NULL
        AND UPPER(COALESCE(nt.state, 'ENABLED')) NOT IN ('ARCHIVED', 'REMOVED', 'PAUSED')
        AND UPPER(REGEXP_EXTRACT(nt.targeting_expression, r'(?i)asin="?([A-Za-z0-9]+)"?')) = UPPER(vc.search_term)
    )
  GROUP BY parent_name, campaign_id, keyword_id, search_term
),
peak_dates AS (  -- all days inside a gift-season boost→cooldown window (the peaks)
  SELECT DISTINCT d AS date
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h, UNNEST(GENERATE_DATE_ARRAY(h.boost_start, h.cooldown_end)) d
  WHERE h.category = 'gift_season'
),
peak AS (  -- the term's actual performance during past peaks, in the same campaign
  SELECT
    f.campaign_id, f.search_term,
    SUM(f.Ads_clicks)                AS peak_clicks,
    SUM(f.Ads_orders)                AS peak_orders,
    ROUND(SUM(f.GROSS_PROFIT - f.Ads_cost), 2) AS peak_net
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` f
  JOIN peak_dates pd ON pd.date = f.date
  WHERE f.search_term IS NOT NULL
  GROUP BY f.campaign_id, f.search_term
)
SELECT
  CONCAT(neg.campaign_id, '|', neg.keyword_id, '|', neg.search_term) AS id,
  neg.parent_name, neg.campaign_id, neg.keyword_id, neg.ad_group_id,
  neg.campaign_name, neg.targeting, neg.match_type, neg.search_term, neg.reason, neg.priority_score,
  neg.hero_asin, neg.hero_product_name, ROUND(neg.hero_cvr, 1) AS hero_cvr, neg.wrong_asin,
  neg.block_clicks_8w, neg.block_orders_8w,
  ROUND(neg.block_net_profit_8w, 2) AS block_net_profit_8w,
  neg.block_lifetime_clicks, neg.block_lifetime_orders,
  COALESCE(p.peak_clicks, 0) AS peak_clicks,
  COALESCE(p.peak_orders, 0) AS peak_orders,
  p.peak_net                 AS peak_net,
  -- converts in peak → keep/seasonal, don't negate
  (COALESCE(p.peak_orders, 0) > 0) AS peak_converts
FROM neg
LEFT JOIN peak p ON p.campaign_id = neg.campaign_id AND p.search_term = neg.search_term;
