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
  -- is_manual: the Configure modal stamps notes with 'manual:' when a human assigns a campaign.
  -- That flag is what lets a DELIBERATE override beat derivation, while stale bulk-migrated rows
  -- (no note) stay ignored — see the strategy_category CASE below.
  SELECT CAST(ec.campaign_id AS STRING) AS campaign_id,
    ANY_VALUE(e.strategy_id) AS strategy_id,
    LOGICAL_OR(STARTS_WITH(COALESCE(ec.notes, ''), 'manual:')) AS is_manual
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.DIM_EXPERIMENT` e USING (experiment_id)
  GROUP BY 1
),
-- SB creative format per campaign, from the REAL creative_type. Ori 2026-07-23 made Broad
-- format-specific (Broad Video / Broad Spotlight are each required per family), so this decides
-- which Broad cell an SB campaign lands in. Resolves 16/16 enabled SB campaigns; camp_sig carries
-- a campaign-name fallback for anything this misses.
sb_format AS (
  -- Campaign-grain rollup of DIM_AD_GROUP.creative_type (canonical derivation in
  -- SP_LOAD_DIM_AD_GROUP — report creative_type + campaign-name fallback, no cost filter).
  SELECT campaign_id,
    CASE WHEN fmt IN ('BRAND_VIDEO', 'VIDEO') THEN 'VIDEO'
         WHEN fmt IN ('PRODUCT_COLLECTION', 'STORE_SPOTLIGHT') THEN 'SPOTLIGHT' END AS sb_format
  FROM (
    SELECT campaign_id, MAX(creative_type) AS fmt
    FROM `onyga-482313.OI.DIM_AD_GROUP`
    WHERE is_current AND creative_type IS NOT NULL
    GROUP BY 1
  )
),
camp_sig AS (   -- campaign_type + the targeting type that took the most clicks (last 90d)
  SELECT campaign_id,
    -- LOGICAL_OR, not ANY_VALUE: a campaign can have mixed/renamed rows in FACT_AMAZON_ADS and
    -- ANY_VALUE would pick non-deterministically, silently dropping SB campaigns into BROAD_SP.
    IF(LOGICAL_OR(UPPER(campaign_type) = 'SB'), 'SB', ANY_VALUE(campaign_type)) AS campaign_type,
    ARRAY_AGG(targeting_type IGNORE NULLS ORDER BY clicks DESC LIMIT 1)[SAFE_OFFSET(0)] AS targeting_type,
    CASE WHEN REGEXP_CONTAINS(UPPER(ANY_VALUE(campaign_name)), r'COLLECTION|SPOTLIGHT|SBS|STORE')
           THEN 'SPOTLIGHT' ELSE 'VIDEO' END AS sb_format_by_name
  FROM (
    SELECT CAST(campaign_id AS STRING) AS campaign_id, campaign_type, targeting_type, campaign_name,
           SUM(Ads_clicks) AS clicks
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`
    WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 90 DAY)
    GROUP BY 1, 2, 3, 4
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
    WHEN st.strategy_id = 'AUTO'            THEN 'AUTO'  -- explicit AUTO assignment (manual mapping)
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
  -- ── STRATEGY (9-value taxonomy, Ori 2026-07-23) ──────────────────────────────────────────
  -- Replaces the old INTENT / EXACT_BOOST pair, which conflated things that behave differently:
  --   INTENT was 100% broad-match, and is now split BY FORMAT (BROAD_SP / BROAD_VIDEO /
  --     BROAD_SPOTLIGHT) because all three are required per family and perform very differently.
  --   EXACT_BOOST was silently HALF PHRASE (4 phrase + 4 exact campaigns) — split into PHRASE and
  --     EXACT, which carry different bids and different scaling accuracy (~70% vs ~90%).
  -- Match type + format are DERIVED from the ad data, so Broad/Phrase/Exact need no manual mapping.
  -- Explicit assignment only wins for the four that CANNOT be derived from targeting (the defenses,
  -- Auto, Competitor) plus any new-taxonomy value set by hand. Legacy 'INTENT'/'EXACT_BOOST' rows
  -- are deliberately NOT honoured — they fall through to derivation, which supersedes them.
  CASE
    -- Explicit assignment always wins for the four that cannot be derived from targeting data.
    WHEN st.strategy_id IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE', 'AUTO', 'COMPETITOR')
      THEN st.strategy_id
    -- Broad/Phrase/Exact ARE derivable, so a stored value only wins when a human set it on purpose
    -- (notes 'manual:%'). That keeps stale BULK-MIGRATED rows from overriding the ad data — which
    -- had silently put SB video campaigns like FRESH-VIDEO/ BROAD into BROAD_SP — while still
    -- letting Ori reclassify a campaign by hand in the Configure modal and have it STICK
    -- (before this, a manual Phrase override was ignored and snapped back to the derived value).
    WHEN st.is_manual AND st.strategy_id IN ('BROAD_SP', 'BROAD_VIDEO', 'BROAD_SPOTLIGHT', 'PHRASE', 'EXACT')
      THEN st.strategy_id
    WHEN st.strategy_id IN ('CATEGORY_CONQUEST', 'COMPETITOR_CONQUEST') THEN 'COMPETITOR'
    WHEN UPPER(cs.targeting_type) = 'AUTOMATIC' THEN 'AUTO'
    WHEN UPPER(cs.targeting_type) IN ('ASIN', 'ASIN EXPANDED', 'CATEGORY') THEN 'COMPETITOR'
    WHEN UPPER(cs.targeting_type) = 'BROAD' THEN
      CASE WHEN UPPER(cs.campaign_type) = 'SB' AND COALESCE(sf.sb_format, cs.sb_format_by_name) = 'SPOTLIGHT' THEN 'BROAD_SPOTLIGHT'
           WHEN UPPER(cs.campaign_type) = 'SB'                                THEN 'BROAD_VIDEO'
           ELSE 'BROAD_SP' END
    WHEN UPPER(cs.targeting_type) = 'PHRASE' THEN 'PHRASE'
    WHEN UPPER(cs.targeting_type) = 'EXACT'  THEN 'EXACT'
    ELSE 'OTHER'
  END AS strategy_category
FROM camp_sig cs
LEFT JOIN camp_strategy st USING (campaign_id)
LEFT JOIN sb_format sf USING (campaign_id);
