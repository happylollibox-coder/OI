-- FN_COMPETITOR_CANDIDATE(win_start, win_end, peak_only) — competitor ASINs to PROMOTE.
--
-- Auto campaigns place ads on other people's product pages, so their search terms include raw ASINs.
-- Those are discovered competitor placements: if one converts profitably in Auto, it deserves its own
-- deliberate Competitor target instead of being left to Auto's discretion (Ori 2026-07-23 — "I saw in
-- an auto campaign an ASIN that can be a candidate"). This is the ASIN analogue of promoting a proven
-- search term from Broad into Exact.
--
-- Grain: parent_name × candidate ASIN.
-- Source: FACT_AMAZON_ADS search terms matching the ASIN shape, from DISCOVERY strategies only
--   (Auto + Broad). Competitor/Product-Defense rows are excluded — those are already deliberate.
-- EXCLUDED:
--   • our OWN ASINs — an Auto ad landing on our own listing is cross-sell (Product Defense), not a
--     competitor conquest, and promoting it into a Competitor campaign would attack ourselves.
--   • ASINs ALREADY targeted by a Competitor campaign — they're covered, not candidates.
-- net_roas / target_cpc use the same basis as everywhere else (units × family_gp, COMPETITOR floor
-- with a GLOBAL fallback). is_candidate = clears the floor on >=10 clicks, i.e. proven, not noise.
CREATE OR REPLACE TABLE FUNCTION `onyga-482313.OI.FN_COMPETITOR_CANDIDATE`(win_start DATE, win_end DATE, peak_only BOOL) AS (
WITH
peak_dates AS (
  SELECT DISTINCT d AS date
  FROM `onyga-482313`.OI.DIM_US_HOLIDAYS h, UNNEST(GENERATE_DATE_ARRAY(h.boost_start, h.cooldown_end)) d
  WHERE h.category = 'gift_season'
),
prod AS (
  SELECT dp.asin, dp.parent_name,
    ROUND(lc.price - COALESCE(ch.TOTAL_COST_PER_UNIT, 0), 2) AS gp_per_unit
  FROM `onyga-482313`.OI.DIM_PRODUCT dp
  LEFT JOIN (
    SELECT asin1, price FROM `onyga-482313`.OI.V_DIM_LISTING_CURRENT
    QUALIFY ROW_NUMBER() OVER (PARTITION BY asin1 ORDER BY price DESC) = 1
  ) lc ON lc.asin1 = dp.asin
  LEFT JOIN (
    SELECT asin, TOTAL_COST_PER_UNIT FROM `onyga-482313`.OI.DIM_COSTS_HISTORY
    WHERE end_date IS NULL OR end_date >= CURRENT_DATE()
    QUALIFY ROW_NUMBER() OVER (PARTITION BY asin ORDER BY start_date DESC) = 1
  ) ch ON ch.asin = dp.asin
  WHERE dp.parent_name IS NOT NULL AND dp.parent_name != 'UNKNOWN' AND dp.is_active = true
),
fam_gp AS (SELECT parent_name, AVG(gp_per_unit) AS gp FROM prod GROUP BY parent_name),
own_asins AS (SELECT DISTINCT UPPER(asin) AS asin FROM `onyga-482313`.OI.DIM_PRODUCT WHERE asin IS NOT NULL),
camp_fam AS (
  SELECT campaign_id, parent_name FROM (
    SELECT CAST(ap.campaign_id AS STRING) AS campaign_id, p.parent_name,
      ROW_NUMBER() OVER (PARTITION BY CAST(ap.campaign_id AS STRING) ORDER BY SUM(ap.cost) DESC) AS rn
    FROM `onyga-482313`.OI.V_SRC_AmazonAds_advertised_product ap
    JOIN prod p ON p.asin = ap.advertised_asin
    GROUP BY 1, 2
  ) WHERE rn = 1
),
-- Which of OUR variations won on this placement. Auto campaigns are ASIN-grain (one per variation),
-- so the campaign that discovered the placement identifies the product that converted there. Uses
-- advertised_product, whose asin<->campaign link is authoritative; FACT_AMAZON_ADS's ASIN columns
-- mis-attribute across families and must not be used for this. Where a campaign advertises several
-- ASINs, the units-dominant one wins (Ori 2026-07-23 — group competitor targets by winner variation,
-- because SB video/spotlight creative features a specific product).
camp_winner AS (
  SELECT campaign_id, asin AS winner_asin, product_short_name AS winner_variation FROM (
    SELECT CAST(ap.campaign_id AS STRING) AS campaign_id, ap.advertised_asin AS asin,
      dp.product_short_name,
      ROW_NUMBER() OVER (PARTITION BY CAST(ap.campaign_id AS STRING)
                         ORDER BY SUM(ap.units_7d) DESC, SUM(ap.cost) DESC) AS rn
    FROM `onyga-482313`.OI.V_SRC_AmazonAds_advertised_product ap
    JOIN `onyga-482313`.OI.DIM_PRODUCT dp ON dp.asin = ap.advertised_asin
    WHERE dp.parent_name IS NOT NULL AND dp.parent_name != 'UNKNOWN'
    GROUP BY 1, 2, 3
  ) WHERE rn = 1
),
floor AS (
  SELECT COALESCE(
    MAX(IF(strategy_id = 'COMPETITOR', CAST(threshold_value AS FLOAT64), NULL)),
    MAX(IF(strategy_id = 'GLOBAL',     CAST(threshold_value AS FLOAT64), NULL))
  ) AS v
  FROM `onyga-482313`.OI.DE_COACH_THRESHOLDS
  WHERE threshold_key = 'PROFITABLE_ROAS' AND strategy_id IN ('COMPETITOR', 'GLOBAL')
),
-- ASINs already deliberately targeted by a Competitor campaign -> covered, not candidates
already_targeted AS (
  -- SB competitor targets carry a NULL targeting_type but a populated `targeting` string, so
  -- gate on the string too — otherwise an ASIN we already conquer via an SB video campaign
  -- would be re-suggested as a fresh candidate.
  SELECT DISTINCT UPPER(REGEXP_REPLACE(targeting, r'^(asin|asin-expanded)="?|"?$', '')) AS asin
  FROM `onyga-482313`.OI.FACT_AMAZON_ADS a
  JOIN `onyga-482313`.OI.V_CAMPAIGN_ROLE v ON v.campaign_id = CAST(a.campaign_id AS STRING)
  WHERE v.strategy_category = 'COMPETITOR'
    AND (UPPER(a.targeting_type) IN ('ASIN', 'ASIN EXPANDED')
         OR (a.targeting_type IS NULL AND REGEXP_CONTAINS(LOWER(a.targeting), r'^asin')))

  UNION DISTINCT

  -- CONFIGURED but not yet delivering. The FACT-based half above only knows a target once it has
  -- reported, i.e. 1-2 days after creation — so an ASIN targeted this morning was still offered as
  -- a fresh candidate and would be uploaded a SECOND time into the same campaign (Ori 2026-07-24).
  -- V_SRC_AmazonAds_keyword is Amazon's config mirror: it carries product targets
  -- (match_type='ASIN', keyword_text='asin="B0…"') within minutes of creation, no performance
  -- needed. Latest row per keyword_id; ARCHIVED dropped so a retired target can be re-proposed.
  SELECT DISTINCT UPPER(REGEXP_REPLACE(k.keyword_text, r'^(asin|asin-expanded)="?|"?$', '')) AS asin
  FROM `onyga-482313`.OI.V_SRC_AmazonAds_keyword k
  JOIN `onyga-482313`.OI.V_CAMPAIGN_ROLE_BY_NAME nr
    ON nr.campaign_id = CAST(k.campaign_id AS STRING)
  WHERE nr.strategy_category = 'COMPETITOR'
    AND REGEXP_CONTAINS(LOWER(k.keyword_text), r'^asin')
    AND UPPER(COALESCE(k.state, '')) != 'ARCHIVED'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY k.keyword_id ORDER BY k.date DESC) = 1
),
-- One row per (family × candidate ASIN × discovering variation). Kept at variation grain
-- deliberately so the winner can be picked DETERMINISTICALLY below instead of by ANY_VALUE.
disc_var AS (
  SELECT cf.parent_name, UPPER(a.search_term) AS asin,
    cw.winner_variation, cw.winner_asin,
    CAST(SUM(a.Ads_clicks) AS INT64) AS clicks,
    SUM(a.Ads_cost) AS cost,
    CAST(SUM(a.Ads_units) AS INT64) AS units,
    STRING_AGG(DISTINCT v.strategy_category) AS found_in
  FROM `onyga-482313`.OI.FACT_AMAZON_ADS a
  JOIN `onyga-482313`.OI.V_CAMPAIGN_ROLE v ON v.campaign_id = CAST(a.campaign_id AS STRING)
  JOIN camp_fam cf ON cf.campaign_id = CAST(a.campaign_id AS STRING)
  LEFT JOIN camp_winner cw ON cw.campaign_id = CAST(a.campaign_id AS STRING)
  WHERE a.date BETWEEN win_start AND win_end
    AND (NOT peak_only OR a.date IN (SELECT date FROM peak_dates))
    AND v.strategy_category IN ('AUTO', 'BROAD_SP', 'BROAD_VIDEO', 'BROAD_SPOTLIGHT')
    AND REGEXP_CONTAINS(LOWER(a.search_term), r'^b0[a-z0-9]{8}$')
  GROUP BY 1, 2, 3, 4
),
-- WINNER PICK — units first, fully ordered, NEVER ANY_VALUE (fixed 2026-07-23).
-- The previous ANY_VALUE(cw.winner_variation) was NON-DETERMINISTIC: 49 of 62 LolliME
-- (family × ASIN × variation) rows had 2+ candidate variations, so the same query returned a
-- different split run to run (an earlier session recorded Purple 16 / Mint 13 / Pink 5; the very
-- same window later returned Mint 34 / 0 / 0). Anything that GROUPS by winner_variation — e.g.
-- FN_COMPETITOR_CAMPAIGN_PLAN's campaign chunking — would have reshuffled on every refresh.
-- Ordering by units DESC is not just a tiebreak, it is the definition: "which of our variations
-- actually SOLD on this competitor's page". Verified across all families that every candidate ASIN
-- has units > 0 under exactly ONE variation, so units alone decides it; clicks/cost/name only
-- break ties for the zero-unit rows that never reach is_candidate anyway.
win_pick AS (
  SELECT parent_name, asin, winner_variation, winner_asin
  FROM disc_var
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY parent_name, asin
    ORDER BY units DESC, clicks DESC, cost DESC, winner_variation
  ) = 1
),
disc AS (
  SELECT d.parent_name, d.asin,
    CAST(SUM(d.clicks) AS INT64) AS clicks,
    SUM(d.cost) AS cost,
    CAST(SUM(d.units) AS INT64) AS units,
    STRING_AGG(d.found_in, ',') AS found_raw,        -- re-DISTINCTed in the final SELECT
    ANY_VALUE(w.winner_variation) AS winner_variation,   -- constant per group (one row from win_pick)
    ANY_VALUE(w.winner_asin) AS winner_asin
  FROM disc_var d
  LEFT JOIN win_pick w ON w.parent_name = d.parent_name AND w.asin = d.asin
  GROUP BY 1, 2
)
SELECT
  d.parent_name,
  d.asin AS candidate_asin,
  (SELECT STRING_AGG(DISTINCT s ORDER BY s) FROM UNNEST(SPLIT(d.found_raw, ',')) s) AS found_in,
  d.winner_variation,
  d.winner_asin,
  d.clicks,
  ROUND(d.cost, 2) AS cost,
  ROUND(SAFE_DIVIDE(d.cost, NULLIF(d.clicks, 0)), 2) AS cpc,
  d.units,
  ROUND(SAFE_DIVIDE(d.units * fg.gp, NULLIF(d.cost, 0)), 2) AS net_roas,
  CASE
    WHEN d.clicks < 10 OR fg.gp IS NULL THEN NULL
    ELSE ROUND(SAFE_DIVIDE(d.units * fg.gp, d.clicks * (SELECT v FROM floor)), 2)
  END AS target_cpc,
  (d.clicks >= 10
   AND SAFE_DIVIDE(d.units * fg.gp, NULLIF(d.cost, 0)) >= (SELECT v FROM floor)) AS is_candidate,
  CONCAT('COMPETITOR|', d.parent_name) AS cell_key
FROM disc d
LEFT JOIN fam_gp fg ON fg.parent_name = d.parent_name
WHERE d.cost > 0
  AND d.asin NOT IN (SELECT asin FROM own_asins)
  AND d.asin NOT IN (SELECT asin FROM already_targeted)
);
