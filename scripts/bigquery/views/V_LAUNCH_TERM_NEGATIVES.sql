-- V_LAUNCH_TERM_NEGATIVES — search terms to negate inside a campaign's launch window (phase 1).
-- Spec: architecture/CAMPAIGN_LAUNCH_RAMP.md §"Phase 1".
--
-- Phase 1 does NOT negate the KEYWORD/target — a target with no sale yet idles cheaply and waits (see
-- V_LAUNCH_PHASE1). But a specific SEARCH TERM (the customer query that matched) that has burned
-- >= launch_negate_clicks (15) clicks with ZERO orders is dead weight: negating that one query as a
-- Campaign Negative Exact stops the bleed WITHOUT killing the keyword that keeps learning on its other
-- queries. Keyword-alive, query-pruned — the two are different grains and do not conflict.
--
-- CUMULATIVE, not per-day: 15 clicks is a lifetime bar for the query, so this reads the campaign's whole
-- history, not a single day. Grain: (campaign, matched target, search_term).
--
-- Emits Campaign Negative Exact rows. tools/build_launch_phase1_bulksheet.py turns these into
-- Entity='Campaign Negative Keyword' / Operation='Create' / Match Type='NEGATIVE_EXACT' rows.
--
-- CAVEAT: the Amazon negative_keyword sync is frozen (see fact_oi_negative_keyword_sync_frozen), so we
-- cannot reliably tell whether a term is already negated. A re-run may re-propose an already-added
-- negative; Amazon dedups Create-of-existing, but review before upload.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_LAUNCH_TERM_NEGATIVES` AS
WITH cfg AS (
  SELECT COALESCE(MAX(IF(config_key='launch_negate_clicks', CAST(config_value AS INT64), NULL)), 15) AS negate_clicks
  FROM `onyga-482313.OI.DE_BUDGET_CONFIG`
),
ph1 AS (SELECT DISTINCT campaign_id FROM `onyga-482313.OI.V_LAUNCH_PHASE1`),
term AS (
  SELECT CAST(a.campaign_id AS STRING) AS campaign_id,
    ANY_VALUE(a.campaign_name) AS campaign_name,
    a.targeting AS matched_target,       -- the keyword/auto group the query matched
    a.SEARCH_TERM AS search_term,
    SUM(a.Ads_clicks) AS clicks,
    SUM(a.Ads_orders) AS orders,
    ROUND(SUM(a.Ads_cost), 2) AS spend
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` a
  JOIN ph1 ON ph1.campaign_id = CAST(a.campaign_id AS STRING)
  WHERE a.SEARCH_TERM IS NOT NULL AND a.SEARCH_TERM != ''
  GROUP BY 1, 3, 4
)
SELECT t.campaign_id, t.campaign_name, t.matched_target, t.search_term,
  t.clicks, t.orders, t.spend, 'NEGATE_TERM' AS action,
  CONCAT('search term "', t.search_term, '" spent $', CAST(t.spend AS STRING),
         ' over ', CAST(t.clicks AS STRING), ' clicks with 0 orders') AS reason
FROM term t CROSS JOIN cfg
WHERE t.clicks >= cfg.negate_clicks AND t.orders = 0
ORDER BY t.spend DESC;
