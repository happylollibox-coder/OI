-- =============================================
-- V_ADS_NEGATIVE_CONFLICTS
-- Pilot §8b + owner rules (2026-06-13): a product blocking its own proven converters.
-- Finds ENABLED NEGATIVE_EXACT keywords in a campaign whose advertised ASIN actually
-- CONVERTS on that exact term (SQP, last 365d, >= 3 orders — clear converters only).
--
-- Owner brand rule: brand search terms SHOULD be negated everywhere EXCEPT brand-defense
-- campaigns (only defense campaigns collect brand traffic). So:
--   • brand term negated in a NON-defense campaign  → CORRECT → excluded (not a conflict)
--   • non-brand term that converts, negated anywhere → SELF_BLOCK conflict
--   • brand term negated INSIDE a defense campaign   → BRAND_IN_DEFENSE conflict (defense should collect it)
--
-- Grain: one row per (campaign × negated_term × asin × negative_id) conflict. Surfaced as a
-- review card — the human decides (per-family judgment: the same term may run for >1 product).
-- Source of negatives: owned DE_NEGATIVE_KEYWORDS (Fivetran negative sync is frozen).
-- Carries the real Keyword ID so a conflict can be archived from the dashboard.
-- Context for the human: the negating campaign's ALL-TIME net ROAS (is the block on a healthy
-- campaign → suspicious?) and whether the campaign's advertised PRODUCT has changed (a negative
-- added for an old product may be stale).
-- v1 scope: NEGATIVE_EXACT only. Phrase/broad negatives = follow-up.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_NEGATIVE_CONFLICTS` AS
WITH neg AS (
  -- Owned registry (DE_NEGATIVE_KEYWORDS), not the frozen Fivetran source. Seeded from a
  -- bulksheet download + kept current by SP_SYNC_NEGATIVES. Carries the real Amazon
  -- Keyword ID / ad_group_id / match_type so a conflict can be archived from the dashboard.
  SELECT campaign_id, ad_group_id, negative_id, match_type, level,
         LOWER(TRIM(keyword_text)) AS term
  FROM `onyga-482313.OI.DE_NEGATIVE_KEYWORDS`
  WHERE state = 'ENABLED' AND match_type = 'NEGATIVE_EXACT'
    AND keyword_text IS NOT NULL AND TRIM(keyword_text) != ''
),
camp_asin AS (  -- ASINs each campaign actually advertised in the last 90 days
  SELECT DISTINCT campaign_id, advertised_asins AS asin
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 90 DAY)
    AND advertised_asins IS NOT NULL AND advertised_asins != 'UNKNOWN'
),
camp_perf AS (  -- the negating campaign's ALL-TIME ad performance + how many products it has run
  SELECT campaign_id,
    SAFE_DIVIDE(SUM(GROSS_PROFIT), NULLIF(SUM(Ads_cost), 0)) AS campaign_net_roas_all_time,
    SAFE_DIVIDE(SUM(Ads_sales),   NULLIF(SUM(Ads_cost), 0)) AS campaign_gross_roas_all_time,
    ROUND(SUM(Ads_cost), 0)                                  AS campaign_spend_all_time,
    COUNT(DISTINCT advertised_asins)                         AS campaign_distinct_asins
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE advertised_asins IS NOT NULL AND advertised_asins != 'UNKNOWN'
  GROUP BY campaign_id
),
conv AS (  -- SQP conversions per ASIN × term (product's market sales on the query)
  -- 12-month total = proven-converter / seasonality context; last-90-day = does it STILL
  -- convert now? A flat 12mo window over-flags stale negatives (term converted last year,
  -- then was negated, or the campaign's product since changed). The 90d figure gates that out.
  SELECT ASIN AS asin, LOWER(TRIM(query_text)) AS term,
    SUM(conversions)            AS converter_orders,
    SUM(clicks)                 AS converter_clicks,
    ROUND(SUM(sales_amount), 0) AS converter_sales,
    SUM(IF(week_end_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 90 DAY), conversions, 0)) AS converter_orders_90d,
    ROUND(SUM(IF(week_end_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 90 DAY), sales_amount, 0)), 0) AS converter_sales_90d
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY`
  WHERE week_end_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 365 DAY)
    AND query_text IS NOT NULL
  GROUP BY 1, 2
),
defense AS (  -- brand-/product-defense campaigns (the only ones that should collect brand terms)
  SELECT DISTINCT ec.campaign_id
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.DIM_EXPERIMENT` e USING (experiment_id)
  WHERE e.strategy_id IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE')
),
candidates AS (
  SELECT
    n.campaign_id, cc.campaign_name, n.term AS negated_term,
    n.negative_id, n.ad_group_id, n.match_type, n.level,
    ca.asin, p.product_short_name, p.parent_name,
    cv.converter_orders, cv.converter_clicks, cv.converter_sales,
    cv.converter_orders_90d, cv.converter_sales_90d,
    cp.campaign_net_roas_all_time, cp.campaign_gross_roas_all_time,
    cp.campaign_spend_all_time, cp.campaign_distinct_asins,
    (d.campaign_id IS NOT NULL) AS is_defense_campaign
  FROM neg n
  JOIN camp_asin ca USING (campaign_id)
  JOIN conv cv ON cv.asin = ca.asin AND cv.term = n.term
  JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = ca.asin
  LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` cc ON cc.campaign_id = n.campaign_id
  LEFT JOIN camp_perf cp ON cp.campaign_id = n.campaign_id
  LEFT JOIN defense d ON d.campaign_id = n.campaign_id
  -- Proven over the year (>=3) AND still converting recently (>=2 in last 90d) — the recency
  -- gate is what stops year-old/seasonal/pre-product-swap negatives being flagged as conflicts.
  WHERE cv.converter_orders >= 3 AND cv.converter_orders_90d >= 2
),
classified AS (
  SELECT c.*,
    EXISTS(
      SELECT 1 FROM `onyga-482313.OI.DIM_BRAND_PHRASES` b
      WHERE b.phrase_type IN ('BRAND', 'PRODUCT')
        AND c.negated_term LIKE CONCAT('%', LOWER(b.phrase), '%')
    ) AS is_brand_term,
    -- Seasonal/holiday term (matches a gift_season holiday name — same rule as the coacher's
    -- is_holiday_seasonal). The negative on a seasonal term is INTENTIONAL off-season: such terms
    -- belong in a dedicated seasonal campaign (enabled in BOOST, paused in COOLDOWN), handled by
    -- the coacher's NEW_SEASONAL / START_SEASONAL path — NOT by un-negating a general campaign.
    EXISTS(
      SELECT 1 FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
      WHERE h.category = 'gift_season'
        AND (STRPOS(c.negated_term, LOWER(h.holiday_name)) > 0
          OR STRPOS(c.negated_term, LOWER(REGEXP_REPLACE(h.holiday_name, r"'?s?\s+Day$", ''))) > 0)
    ) AS is_seasonal
  FROM candidates c
)
SELECT
  campaign_id, campaign_name, negated_term, negative_id, ad_group_id, match_type, level,
  asin, product_short_name, parent_name,
  converter_orders, converter_clicks, converter_sales,
  converter_orders_90d, converter_sales_90d,
  campaign_net_roas_all_time, campaign_gross_roas_all_time, campaign_spend_all_time,
  campaign_distinct_asins,
  (campaign_distinct_asins > 1) AS campaign_product_changed,
  is_defense_campaign, is_brand_term,
  CASE WHEN is_brand_term AND is_defense_campaign THEN 'BRAND_IN_DEFENSE' ELSE 'SELF_BLOCK' END AS conflict_type,
  'REMOVE_NEGATIVE' AS recommendation
FROM classified
-- Owner rule: a brand term negated in a non-defense campaign is intentional funnel control, not a conflict.
WHERE NOT (is_brand_term AND NOT is_defense_campaign)
  -- Seasonal terms are intentionally negated off-season — route them to a dedicated seasonal
  -- campaign (boost-enable / cooldown-pause), don't surface them as "remove the negative".
  AND NOT is_seasonal
ORDER BY converter_sales DESC;
