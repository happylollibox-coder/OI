-- FN_COVERAGE_COMPETITOR_TARGET(win_start, win_end, peak_only) — competitor ASIN targets.
--
-- The Competitor strategy targets PRODUCTS, not keywords, so the Intent keyword panel is the wrong
-- evidence for it (Ori 2026-07-23). This is its equivalent: one row per (family × targeted ASIN)
-- with the same economics the keyword panel shows — net ROAS, current CPC, and the CPC that would
-- land the target on the profit floor.
--
-- Grain: parent_name × target (the competitor ASIN / category string from FACT_AMAZON_ADS.targeting).
-- Only ASIN / ASIN-Expanded / Category targeting rows, and only campaigns whose strategy resolves
-- to COMPETITOR, so this can never pick up a keyword campaign's spend.
--
-- net_roas   := SUM(units) × family_gp / SUM(cost) over the window.
-- target_cpc := cvr × family_gp / COMPETITOR floor = units × gp / (clicks × floor) — the CPC at
--   which the target hits the floor given ITS OWN conversion rate. NULL under 10 in-window clicks.
-- `is_winner` marks net_roas >= 1: those are the ones worth scaling / cloning into new targets.
--
-- family: taken from what the CAMPAIGN historically advertised (advertised_product is the
-- authoritative asin<->campaign link). FACT_AMAZON_ADS's own ASIN columns mis-attribute across
-- families and must never be used for this — see the note in FN_COVERAGE_CAMPAIGN.
CREATE OR REPLACE TABLE FUNCTION `onyga-482313.OI.FN_COVERAGE_COMPETITOR_TARGET`(win_start DATE, win_end DATE, peak_only BOOL) AS (
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
fam_gp AS (
  SELECT parent_name, AVG(gp_per_unit) AS gp FROM prod GROUP BY parent_name
),
-- campaign -> family. SP campaigns resolve via the authoritative advertised_product link.
-- SB campaigns NEVER appear in advertised_product (the reason FN_COVERAGE_SB exists), so a
-- pure-SP link silently dropped every Sponsored Brands competitor campaign — the whole SB
-- conquest portfolio was invisible to this panel (Ori 2026-07-23: a profitable SB competitor
-- target, BOX-VIDEO/COMPETE, showed as 0.00x because only its SP-campaign spillover survived).
-- SB is resolved the same way FN_COVERAGE_SB does: curated DE_CAMPAIGN_FAMILY first, else the
-- dominant PURCHASED product family. Restricted to real families in fam_gp so a 'Store' pin
-- (no products, no gp) can't drop the spend again. SP link wins on the rare id collision.
camp_fam AS (
  SELECT campaign_id, parent_name FROM (
    SELECT campaign_id, parent_name,
      ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY src_pri, w DESC) AS rn
    FROM (
      -- SP: authoritative advertised_product link (priority 1)
      SELECT CAST(ap.campaign_id AS STRING) AS campaign_id, p.parent_name,
        1 AS src_pri, SUM(ap.cost) AS w
      FROM `onyga-482313`.OI.V_SRC_AmazonAds_advertised_product ap
      JOIN prod p ON p.asin = ap.advertised_asin
      GROUP BY 1, 2
      UNION ALL
      -- SB curated pin: DE_CAMPAIGN_FAMILY (priority 2, huge weight so it beats halo split)
      SELECT CAST(dcf.campaign_id AS STRING) AS campaign_id, dcf.parent_name,
        2 AS src_pri, 1e18 AS w
      FROM `onyga-482313`.OI.DE_CAMPAIGN_FAMILY dcf
      WHERE dcf.parent_name IN (SELECT parent_name FROM fam_gp)
      UNION ALL
      -- SB dominant purchased family (priority 2, weight = units)
      SELECT CAST(pp.campaign_id AS STRING) AS campaign_id, p.parent_name,
        2 AS src_pri, SUM(pp.units_sold_14_d) AS w
      FROM `fivetran-hl.amazon_ads.sb_purchased_product` pp
      JOIN prod p ON p.asin = pp.purchased_asin
      WHERE pp.attribution_type = 'Promoted'
      GROUP BY 1, 2
    )
  ) WHERE rn = 1
),
-- COALESCE to GLOBAL: a missing per-strategy floor would make the whole target_cpc NULL rather
-- than fall back, which is exactly what happened here — DE_COACH_THRESHOLDS had no COMPETITOR row.
floor AS (
  SELECT COALESCE(
    MAX(IF(strategy_id = 'COMPETITOR', CAST(threshold_value AS FLOAT64), NULL)),
    MAX(IF(strategy_id = 'GLOBAL',     CAST(threshold_value AS FLOAT64), NULL))
  ) AS v
  FROM `onyga-482313`.OI.DE_COACH_THRESHOLDS
  WHERE threshold_key = 'PROFITABLE_ROAS' AND strategy_id IN ('COMPETITOR', 'GLOBAL')
),
tgt AS (
  SELECT
    cf.parent_name,
    -- strip the asin="…" / category="…" wrapper Amazon puts around the target
    REGEXP_REPLACE(a.targeting, r'^(asin|asin-expanded|category)="?|"?$', '') AS target,
    -- Sponsored Brands leaves targeting_type NULL while still populating the `targeting`
    -- string, so derive the type from the wrapper. This also merges an ASIN targeted on
    -- BOTH an SP and an SB campaign into one row (ASIN vs NULL no longer split them), giving
    -- the true "how is this competitor covered across all my campaigns" number.
    CASE
      WHEN UPPER(a.targeting_type) IN ('ASIN', 'ASIN EXPANDED') THEN 'ASIN'
      WHEN UPPER(a.targeting_type) = 'CATEGORY' THEN 'CATEGORY'
      WHEN REGEXP_CONTAINS(LOWER(a.targeting), r'^category=') THEN 'CATEGORY'
      ELSE 'ASIN'
    END AS target_type,
    CAST(SUM(a.Ads_clicks) AS INT64) AS clicks,
    SUM(a.Ads_cost) AS cost,
    CAST(SUM(a.Ads_units) AS INT64) AS units
  FROM `onyga-482313`.OI.FACT_AMAZON_ADS a
  JOIN `onyga-482313`.OI.V_CAMPAIGN_ROLE vcr ON vcr.campaign_id = CAST(a.campaign_id AS STRING)
  JOIN camp_fam cf ON cf.campaign_id = CAST(a.campaign_id AS STRING)
  WHERE a.date BETWEEN win_start AND win_end
    AND (NOT peak_only OR a.date IN (SELECT date FROM peak_dates))
    -- Accept typed product/category targets AND SB's NULL-typed rows whose targeting string
    -- is itself a product/category target (that is where the SB competitor spend lives).
    AND (
      UPPER(a.targeting_type) IN ('ASIN', 'ASIN EXPANDED', 'CATEGORY')
      OR (a.targeting_type IS NULL
          AND REGEXP_CONTAINS(LOWER(a.targeting), r'^(asin|asin-expanded|category)='))
    )
    AND vcr.strategy_category = 'COMPETITOR'
    AND a.targeting IS NOT NULL
  GROUP BY 1, 2, 3
)
SELECT
  t.parent_name,
  t.target,
  t.target_type,
  t.clicks,
  ROUND(t.cost, 2) AS cost,
  ROUND(SAFE_DIVIDE(t.cost, NULLIF(t.clicks, 0)), 2) AS cpc,
  t.units,
  ROUND(SAFE_DIVIDE(t.units * fg.gp, NULLIF(t.cost, 0)), 2) AS net_roas,
  CASE
    WHEN t.clicks < 10 OR fg.gp IS NULL THEN NULL
    ELSE ROUND(SAFE_DIVIDE(t.units * fg.gp, t.clicks * (SELECT v FROM floor)), 2)
  END AS target_cpc,
  COALESCE(SAFE_DIVIDE(t.units * fg.gp, NULLIF(t.cost, 0)) >= 1, FALSE) AS is_winner,
  CONCAT('COMPETITOR|', t.parent_name) AS cell_key
FROM tgt t
LEFT JOIN fam_gp fg ON fg.parent_name = t.parent_name
WHERE t.cost > 0
);
