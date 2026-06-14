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
-- Grain: one row per (campaign × negated_term × asin) conflict. Surfaced as a review card —
-- the human decides (per-family judgment: the same term may legitimately run for >1 product).
-- v1 scope: NEGATIVE_EXACT only. Phrase/broad negatives = follow-up.
-- =============================================
CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_NEGATIVE_CONFLICTS` AS
WITH neg AS (
  SELECT DISTINCT campaign_id, LOWER(TRIM(keyword_text)) AS term
  FROM `onyga-482313.OI.V_SRC_AmazonAds_negative_keyword`
  WHERE state = 'ENABLED' AND match_type = 'NEGATIVE_EXACT'
    AND keyword_text IS NOT NULL AND TRIM(keyword_text) != ''
),
camp_asin AS (  -- ASINs each campaign actually advertised in the last 90 days
  SELECT DISTINCT campaign_id, advertised_asins AS asin
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 90 DAY)
    AND advertised_asins IS NOT NULL AND advertised_asins != 'UNKNOWN'
),
conv AS (  -- SQP conversions per ASIN × term over the last year
  SELECT ASIN AS asin, LOWER(TRIM(query_text)) AS term,
    SUM(conversions)       AS converter_orders,
    SUM(clicks)            AS converter_clicks,
    ROUND(SUM(sales_amount), 0) AS converter_sales
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
    ca.asin, p.product_short_name, p.parent_name,
    cv.converter_orders, cv.converter_clicks, cv.converter_sales,
    (d.campaign_id IS NOT NULL) AS is_defense_campaign
  FROM neg n
  JOIN camp_asin ca USING (campaign_id)
  JOIN conv cv ON cv.asin = ca.asin AND cv.term = n.term
  JOIN `onyga-482313.OI.DIM_PRODUCT` p ON p.asin = ca.asin
  LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` cc ON cc.campaign_id = n.campaign_id
  LEFT JOIN defense d ON d.campaign_id = n.campaign_id
  WHERE cv.converter_orders >= 3
),
classified AS (
  SELECT c.*,
    EXISTS(
      SELECT 1 FROM `onyga-482313.OI.DIM_BRAND_PHRASES` b
      WHERE b.phrase_type IN ('BRAND', 'PRODUCT')
        AND c.negated_term LIKE CONCAT('%', LOWER(b.phrase), '%')
    ) AS is_brand_term
  FROM candidates c
)
SELECT
  campaign_id, campaign_name, negated_term, asin, product_short_name, parent_name,
  converter_orders, converter_clicks, converter_sales,
  is_defense_campaign, is_brand_term,
  CASE WHEN is_brand_term AND is_defense_campaign THEN 'BRAND_IN_DEFENSE' ELSE 'SELF_BLOCK' END AS conflict_type,
  'REMOVE_NEGATIVE' AS recommendation
FROM classified
-- Owner rule: a brand term negated in a non-defense campaign is intentional funnel control, not a conflict.
WHERE NOT (is_brand_term AND NOT is_defense_campaign)
ORDER BY converter_sales DESC;
