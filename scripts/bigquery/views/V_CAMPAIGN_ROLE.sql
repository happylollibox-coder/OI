-- V_CAMPAIGN_ROLE — one row per campaign: which Coverage role it plays.
-- Spec: architecture/CAMPAIGN_LAUNCH_RAMP.md · architecture/INTENT_CAMPAIGN_MODEL.md §F.
--
-- THE canonical role definition. Lifted verbatim (bar the case fix below) out of the camp_role CTE that
-- was inlined in /api/coverage, so the Coverage page and the Weekly Run strategy split cannot drift
-- apart, and so the rule lives in BigQuery rather than in Flask or React.
--
-- Role is first-match-wins, in this order:
--   BRAND_DEFENSE / PRODUCT_DEFENSE  — by strategy_id (an explicit assignment beats any inference)
--   SB_VIDEO                         — any Sponsored Brands campaign
--   AUTO                             — automatic targeting
--   COMPETITOR                       — conquest strategies, or ASIN / category targeting
--   EXACT / BROAD / PHRASE           — by dominant keyword match type
--   OTHER                            — unclassifiable
--
-- CASE NORMALIZATION: FACT_AMAZON_ADS.targeting_type is case-inconsistent — 'broad' (56.6k clicks/90d)
-- AND 'BROAD' (16.1k), 'exact'/'EXACT', 'phrase'/'phrase'. The Flask original compared 'Automatic',
-- 'ASIN' and 'Category' case-SENSITIVELY, which would silently misclassify if the feed ever changed
-- case. Everything here is compared UPPER-cased.
--
-- targeting_type is read at campaign grain only. Per the /api/coverage design note, FACT_AMAZON_ADS's
-- COALESCE(most_advertised_asin, ASIN_BY_CAMPAIGN_NAME) mis-attributes campaigns across families, so it
-- must never be used to attribute an ASIN — only to read campaign_type / targeting_type.
CREATE OR REPLACE VIEW `onyga-482313.OI.V_CAMPAIGN_ROLE` AS
WITH camp_strategy AS (
  SELECT CAST(ec.campaign_id AS STRING) AS campaign_id, ANY_VALUE(e.strategy_id) AS strategy_id
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.DIM_EXPERIMENT` e USING (experiment_id)
  GROUP BY 1
),
camp_sig AS (   -- campaign_type + the targeting type that took the most clicks (last 90d)
  SELECT campaign_id,
    ANY_VALUE(campaign_type) AS campaign_type,
    ARRAY_AGG(targeting_type IGNORE NULLS ORDER BY clicks DESC LIMIT 1)[SAFE_OFFSET(0)] AS targeting_type
  FROM (
    SELECT CAST(campaign_id AS STRING) AS campaign_id, campaign_type, targeting_type,
           SUM(Ads_clicks) AS clicks
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`
    WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 90 DAY)
    GROUP BY 1, 2, 3
  )
  GROUP BY campaign_id
)
SELECT
  cs.campaign_id,
  cs.campaign_type,
  cs.targeting_type,
  st.strategy_id,
  CASE
    WHEN st.strategy_id = 'BRAND_DEFENSE'   THEN 'BRAND_DEFENSE'
    WHEN st.strategy_id = 'PRODUCT_DEFENSE' THEN 'PRODUCT_DEFENSE'
    WHEN UPPER(cs.campaign_type) = 'SB'     THEN 'SB_VIDEO'
    WHEN UPPER(cs.targeting_type) = 'AUTOMATIC' THEN 'AUTO'
    -- COMPETITOR absorbed CATEGORY_CONQUEST + COMPETITOR_CONQUEST (MIGRATE_STRATEGY_CONSOLIDATION,
    -- 2026-07-17). The old ids are kept in the match list only so the view still classifies correctly
    -- if an unmigrated row ever reappears; they no longer exist in DIM_EXPERIMENT.
    WHEN st.strategy_id IN ('COMPETITOR', 'CATEGORY_CONQUEST', 'COMPETITOR_CONQUEST')
      OR UPPER(cs.targeting_type) IN ('ASIN', 'ASIN EXPANDED', 'CATEGORY') THEN 'COMPETITOR'
    WHEN UPPER(cs.targeting_type) = 'EXACT'  THEN 'EXACT'
    WHEN UPPER(cs.targeting_type) = 'BROAD'  THEN 'BROAD'
    WHEN UPPER(cs.targeting_type) = 'PHRASE' THEN 'PHRASE'
    ELSE 'OTHER'
  END AS role,
  -- TRUE for the six offense sub-roles: the strategy split in Weekly Run step 1 covers these only,
  -- since brand/product defense are separate PPC modes with their own budget panels.
  (CASE
    WHEN st.strategy_id IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE') THEN FALSE
    ELSE TRUE
  END) AS is_offense_role,
  -- STRATEGY grain for the Weekly Run "Budget by strategy" split (cross-pool, Ori 2026-07-18): the
  -- campaign's assigned STRATEGY, not the match-type coverage role above. Auto is split out from Intent
  -- by targeting type; the two defenses are explicit assignments and win over targeting.
  CASE
    WHEN st.strategy_id = 'BRAND_DEFENSE'   THEN 'BRAND_DEFENSE'
    WHEN st.strategy_id = 'PRODUCT_DEFENSE' THEN 'PRODUCT_DEFENSE'
    WHEN UPPER(cs.targeting_type) = 'AUTOMATIC' THEN 'AUTO'
    WHEN st.strategy_id = 'EXACT_BOOST'     THEN 'EXACT_BOOST'
    WHEN st.strategy_id IN ('COMPETITOR', 'CATEGORY_CONQUEST', 'COMPETITOR_CONQUEST')
      OR UPPER(cs.targeting_type) IN ('ASIN', 'ASIN EXPANDED', 'CATEGORY') THEN 'COMPETITOR'
    WHEN st.strategy_id = 'INTENT'          THEN 'INTENT'
    ELSE 'OTHER'
  END AS strategy_category
FROM camp_sig cs
LEFT JOIN camp_strategy st USING (campaign_id);
