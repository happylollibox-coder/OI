-- =============================================
-- OI Database Project - V_PARENT_HERO_ASIN View
-- =============================================
--
-- Purpose: Per SEARCH TERM, per parent family, rank each child ASIN by
--          organic growth potential. The Hero = the child Amazon's algorithm
--          most wants to promote FOR THAT SPECIFIC TERM.
--
-- Why per term: Amazon ranks ASINs per search term independently.
--   "journal for girls" might have a different hero than "teen girl gifts".
--   Advertising the right child on the right term maximizes organic rank.
--
-- Ranking logic (what Amazon's A9 algorithm cares about):
--   1. SQP CVR: shoppers who click actually buy (primary signal)
--   2. SQP CTR: shoppers want to click this listing (desirability)
--   3. Ads CVR: paid traffic also converts (cross-validation)
--   4. Margin: need to make money
--
-- hero_score = blended_cvr × sqp_ctr × margin / 10000
--   blended_cvr = 70% SQP CVR + 30% Ads CVR
--   Unit: expected $ margin per search impression
--
-- Grain: One row per search_term × parent_name × child ASIN
--        (rolling 8 weeks SQP + 60 days ads)
--
-- Dependencies:
--   DIM_PRODUCT, DIM_COSTS_HISTORY,
--   FACT_SEARCH_QUERY, FACT_AMAZON_ADS
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_PARENT_HERO_ASIN`
AS
WITH
-- =============================================
-- Unit economics per ASIN (only ASINs with a parent)
-- =============================================
asin_unit_economics AS (
  SELECT
    p.asin,
    p.product_short_name,
    p.parent_name,
    p.listing_price_amount - COALESCE(ch.TOTAL_COST_PER_UNIT, 0) as margin_per_unit
  FROM `onyga-482313.OI.DIM_PRODUCT` p
  LEFT JOIN (
    SELECT asin, TOTAL_COST_PER_UNIT,
      ROW_NUMBER() OVER (PARTITION BY asin ORDER BY end_date DESC) as rn
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  ) ch ON p.asin = ch.asin AND ch.rn = 1
  WHERE p.asin IS NOT NULL
    AND p.parent_name IS NOT NULL
    AND p.asin != 'UNKNOWN'
),

-- =============================================
-- SQP per search term per ASIN (rolling 8 weeks)
-- This is what Amazon's algorithm sees per term
-- =============================================
term_sqp AS (
  SELECT
    LOWER(fsq.query_text) as search_term,
    fsq.ASIN as asin,
    SUM(fsq.impressions) as sqp_impressions,
    SUM(fsq.clicks) as sqp_clicks,
    SUM(fsq.conversions) as sqp_conversions,
    ROUND(SAFE_DIVIDE(SUM(fsq.clicks), NULLIF(SUM(fsq.impressions), 0)) * 100, 2) as sqp_ctr_pct,
    ROUND(SAFE_DIVIDE(SUM(fsq.conversions), NULLIF(SUM(fsq.clicks), 0)) * 100, 2) as sqp_cvr_pct,
    COUNT(DISTINCT fsq.week_end_date) as sqp_weeks
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
  WHERE fsq.data_source = 'SQP'
    AND fsq.week_end_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 56 DAY)
  GROUP BY 1, 2
),

-- =============================================
-- Ads per search term per ASIN (rolling 60 days)
-- Cross-validates: does paid traffic also convert on this term?
-- =============================================
term_ads AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    fa.advertised_asins as asin,
    ROUND(SUM(fa.Ads_cost), 2) as ads_spend,
    SUM(fa.Ads_orders) as ads_orders,
    SUM(fa.Ads_clicks) as ads_clicks,
    SUM(fa.Ads_impressions) as ads_impressions,
    ROUND(SAFE_DIVIDE(SUM(fa.Ads_orders), NULLIF(SUM(fa.Ads_clicks), 0)) * 100, 2) as ads_cvr_pct
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
    AND fa.advertised_asins IS NOT NULL
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
  GROUP BY 1, 2
),

-- =============================================
-- All search term × ASIN combinations with data
-- (union of SQP and ads terms, filtered to family ASINs)
-- =============================================
all_term_asin AS (
  SELECT DISTINCT search_term, asin FROM term_sqp
  UNION DISTINCT
  SELECT DISTINCT search_term, asin FROM term_ads
),

-- =============================================
-- Market size per search term (total SQP impressions across all ASINs)
-- =============================================
term_market AS (
  SELECT
    LOWER(fsq.query_text) as search_term,
    SUM(fsq.TOTAL_IMPRESSIONS) as market_impressions,
    SUM(fsq.TOTAL_CLICKS) as market_clicks,
    SUM(fsq.TOTAL_PURCHASES) as market_purchases
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
  WHERE fsq.data_source = 'SQP'
    AND fsq.week_end_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 56 DAY)
  GROUP BY 1
),

-- =============================================
-- Score each search term × child ASIN combination
-- =============================================
scored AS (
  SELECT
    ue.parent_name,
    ta.search_term,
    ta.asin,
    ue.product_short_name,
    ROUND(ue.margin_per_unit, 2) as margin_per_unit,

    -- SQP signals for THIS term + THIS ASIN
    COALESCE(ts.sqp_impressions, 0) as sqp_impressions,
    COALESCE(ts.sqp_clicks, 0) as sqp_clicks,
    COALESCE(ts.sqp_conversions, 0) as sqp_conversions,
    ts.sqp_ctr_pct,
    ts.sqp_cvr_pct,
    COALESCE(ts.sqp_weeks, 0) as sqp_weeks,

    -- Ads signals for THIS term + THIS ASIN
    COALESCE(tad.ads_spend, 0) as ads_spend,
    COALESCE(tad.ads_orders, 0) as ads_orders,
    COALESCE(tad.ads_clicks, 0) as ads_clicks,
    COALESCE(tad.ads_impressions, 0) as ads_impressions,
    tad.ads_cvr_pct,

    -- Ad profitability for this term
    ROUND(COALESCE(tad.ads_orders, 0) * ue.margin_per_unit - COALESCE(tad.ads_spend, 0), 2) as ads_net_profit,
    ROUND(SAFE_DIVIDE(
      tad.ads_orders * ue.margin_per_unit,
      NULLIF(tad.ads_spend, 0)
    ), 2) as ads_net_roas,

    -- Market context
    COALESCE(tm.market_purchases, 0) as market_purchases,

    -- Blended CVR: 70% SQP + 30% Ads
    ROUND(
      CASE
        WHEN ts.sqp_cvr_pct IS NOT NULL AND tad.ads_cvr_pct IS NOT NULL
          THEN 0.7 * ts.sqp_cvr_pct + 0.3 * tad.ads_cvr_pct
        WHEN ts.sqp_cvr_pct IS NOT NULL
          THEN ts.sqp_cvr_pct
        WHEN tad.ads_cvr_pct IS NOT NULL
          THEN tad.ads_cvr_pct
        ELSE 0
      END
    , 2) as blended_cvr_pct,

    -- Hero score = blended_cvr × sqp_ctr × margin / 10000
    ROUND(
      CASE
        WHEN ts.sqp_cvr_pct IS NOT NULL AND tad.ads_cvr_pct IS NOT NULL
          THEN 0.7 * ts.sqp_cvr_pct + 0.3 * tad.ads_cvr_pct
        WHEN ts.sqp_cvr_pct IS NOT NULL
          THEN ts.sqp_cvr_pct
        WHEN tad.ads_cvr_pct IS NOT NULL
          THEN tad.ads_cvr_pct
        ELSE 0
      END
      * COALESCE(ts.sqp_ctr_pct, 0)
      * COALESCE(ue.margin_per_unit, 0)
      / 10000.0
    , 4) as hero_score,

    -- Confidence
    CASE
      WHEN ts.sqp_cvr_pct IS NOT NULL AND tad.ads_cvr_pct IS NOT NULL
        AND ts.sqp_clicks >= 10 AND tad.ads_clicks >= 10
        THEN 'HIGH'
      WHEN ts.sqp_cvr_pct IS NOT NULL AND ts.sqp_clicks >= 5
        THEN 'MEDIUM'
      WHEN ts.sqp_cvr_pct IS NOT NULL OR tad.ads_cvr_pct IS NOT NULL
        THEN 'LOW'
      ELSE 'NO_DATA'
    END as confidence

  FROM all_term_asin ta
  JOIN asin_unit_economics ue ON ta.asin = ue.asin
  LEFT JOIN term_sqp ts ON ta.search_term = ts.search_term AND ta.asin = ts.asin
  LEFT JOIN term_ads tad ON ta.search_term = tad.search_term AND ta.asin = tad.asin
  LEFT JOIN term_market tm ON ta.search_term = tm.search_term
),

-- =============================================
-- Rank per search term:
--   hero_rank     = within parent family (legacy)
--   global_rank   = cross-parent, best ASIN overall for this term
--
-- Ranking by: Net ROAS DESC (margin-adjusted profitability)
-- Gates: ≥4 total orders AND Net ROAS ≥ 1.0
-- =============================================
ranked AS (
  SELECT
    s.*,
    -- Total orders = ads + organic
    (COALESCE(s.ads_orders, 0) + COALESCE(s.sqp_conversions, 0)) as total_orders,
    -- Gates
    CASE WHEN (COALESCE(s.ads_orders, 0) + COALESCE(s.sqp_conversions, 0)) >= 4
          AND COALESCE(s.ads_net_roas, 0) >= 1.0
      THEN TRUE ELSE FALSE
    END as qualifies_as_hero,
    -- Per-parent ranking (legacy, by hero_score)
    COUNT(*) OVER (PARTITION BY s.parent_name, s.search_term) as siblings_on_term,
    ROW_NUMBER() OVER (
      PARTITION BY s.parent_name, s.search_term
      ORDER BY s.hero_score DESC
    ) as hero_rank,
    -- Global cross-parent ranking by Net ROAS (only qualified ASINs rank high)
    ROW_NUMBER() OVER (
      PARTITION BY s.search_term
      ORDER BY
        -- Qualified ASINs first
        CASE WHEN (COALESCE(s.ads_orders, 0) + COALESCE(s.sqp_conversions, 0)) >= 4
                  AND COALESCE(s.ads_net_roas, 0) >= 1.0
          THEN 0 ELSE 1
        END,
        -- Then rank by Net ROAS
        COALESCE(s.ads_net_roas, 0) DESC,
        -- Tie-break: more total orders
        (COALESCE(s.ads_orders, 0) + COALESCE(s.sqp_conversions, 0)) DESC
    ) as global_hero_rank
  FROM scored s
  WHERE s.hero_score > 0 OR s.ads_spend > 0 OR s.sqp_conversions > 0
)

SELECT
  search_term,
  parent_name,
  hero_rank,
  global_hero_rank,
  siblings_on_term,
  asin,
  product_short_name,

  hero_score,
  confidence,
  qualifies_as_hero,
  total_orders,

  -- SQP signals (what Amazon sees for this term + ASIN)
  sqp_cvr_pct,
  sqp_ctr_pct,
  sqp_impressions,
  sqp_clicks,
  sqp_conversions,

  -- Ads cross-validation (for this term + ASIN)
  ROUND(SAFE_DIVIDE(ads_clicks, NULLIF(ads_impressions, 0)) * 100, 1) as ads_ctr_pct,
  ads_cvr_pct,
  ads_spend,
  ads_orders,
  ads_clicks,

  -- Blended + margin
  blended_cvr_pct,
  margin_per_unit,

  -- Ad profitability on this term
  ads_net_profit,
  ads_net_roas,

  -- Market context
  market_purchases,

  -- Plain English reason
  CASE
    WHEN hero_score = 0 AND ads_spend > 0
      THEN CONCAT(product_short_name, ': spending $', CAST(ROUND(ads_spend, 0) AS STRING),
                   ' on "', search_term, '" but no SQP visibility. Amazon does not see organic demand for this ASIN on this term.')
    WHEN hero_score = 0
      THEN CONCAT(product_short_name, ': no data for "', search_term, '".')
    WHEN hero_rank = 1 AND siblings_on_term = 1
      THEN CONCAT('HERO (only child on this term): ', product_short_name,
                   ' on "', search_term, '". CVR ', CAST(COALESCE(sqp_cvr_pct, 0) AS STRING),
                   '%, CTR ', CAST(COALESCE(sqp_ctr_pct, 0) AS STRING), '%.',
                   CASE WHEN ads_cvr_pct IS NOT NULL
                     THEN CONCAT(' Ads CVR: ', CAST(ads_cvr_pct AS STRING), '%.')
                     ELSE '' END,
                   ' Score: ', CAST(hero_score AS STRING), '.')
    WHEN hero_rank = 1 AND confidence = 'HIGH'
      THEN CONCAT('HERO: ', product_short_name,
                   ' is the best child for "', search_term,
                   '". CVR ', CAST(sqp_cvr_pct AS STRING),
                   '%, CTR ', CAST(sqp_ctr_pct AS STRING), '%.',
                   ' Ads confirm: ', CAST(ads_cvr_pct AS STRING), '% CVR.',
                   ' Advertise THIS child on this term for maximum organic lift.',
                   ' Score: ', CAST(hero_score AS STRING), '.')
    WHEN hero_rank = 1 AND confidence IN ('MEDIUM', 'LOW')
      THEN CONCAT('HERO (', confidence, ' confidence): ', product_short_name,
                   ' leads on "', search_term, '".',
                   CASE WHEN sqp_cvr_pct IS NOT NULL
                     THEN CONCAT(' CVR ', CAST(sqp_cvr_pct AS STRING), '%, CTR ', CAST(COALESCE(sqp_ctr_pct, 0) AS STRING), '%.')
                     ELSE '' END,
                   CASE WHEN ads_cvr_pct IS NOT NULL
                     THEN CONCAT(' Ads CVR: ', CAST(ads_cvr_pct AS STRING), '%.')
                     ELSE '' END,
                   ' Score: ', CAST(hero_score AS STRING), '. Need more data.')
    WHEN hero_rank > 1 AND hero_score > 0
      THEN CONCAT(product_short_name, ' (#', CAST(hero_rank AS STRING),
                   ' of ', CAST(siblings_on_term AS STRING), ' siblings): ',
                   CASE WHEN sqp_cvr_pct IS NOT NULL
                     THEN CONCAT('CVR ', CAST(sqp_cvr_pct AS STRING), '%, CTR ', CAST(COALESCE(sqp_ctr_pct, 0) AS STRING), '%.')
                     ELSE '' END,
                   CASE WHEN ads_cvr_pct IS NOT NULL
                     THEN CONCAT(' Ads CVR: ', CAST(ads_cvr_pct AS STRING), '%.')
                     ELSE '' END,
                   ' Lower organic potential than hero on this term.',
                   ' Score: ', CAST(hero_score AS STRING), '.')
    ELSE CONCAT(product_short_name, ': insufficient data for "', search_term, '".')
  END as reason

FROM ranked
ORDER BY parent_name, search_term, hero_rank;
