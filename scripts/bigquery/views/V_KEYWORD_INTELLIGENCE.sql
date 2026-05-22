-- =============================================
-- OI Database Project - V_KEYWORD_INTELLIGENCE View
-- =============================================
--
-- Purpose: Per SEARCH TERM cross-campaign intelligence.
--   - How many campaigns/products target this keyword?
--   - Who has been the hero each month over 12 months?
--   - How stable is the hero? How fragmented is spend?
--   - Complexity score: should a human review before acting?
--
-- Grain: One row per search_term
--
-- Usage: Powers the Keyword Intelligence inline panel in the
--        Coach Priority Queue — only loaded for complex keywords.
--
-- Dependencies:
--   FACT_AMAZON_ADS, DIM_PRODUCT, DIM_COSTS_HISTORY,
--   V_PARENT_HERO_ASIN, V_EXPERIMENT_TERM_RECOMMENDATIONS
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_KEYWORD_INTELLIGENCE`
AS
WITH
-- =============================================
-- Only process keywords that appear in term recommendations
-- (avoids scanning 44K+ monitor terms)
-- =============================================
active_keywords AS (
  SELECT DISTINCT search_term
  FROM `onyga-482313.OI.V_EXPERIMENT_TERM_RECOMMENDATIONS`
  WHERE action != 'MONITOR'
),

-- =============================================
-- Unit economics per ASIN
-- =============================================
asin_economics AS (
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
  WHERE p.asin IS NOT NULL AND p.asin != 'UNKNOWN'
),

-- =============================================
-- Current period aggregate: per search_term × ASIN (4 weeks)
-- =============================================
current_4w AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    COUNT(DISTINCT fa.campaign_id) as campaign_count,
    ROUND(SUM(fa.Ads_cost), 2) as spend,
    SUM(fa.Ads_orders) as orders,
    SUM(fa.Ads_clicks) as clicks,
    SUM(fa.Ads_impressions) as impressions
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2
),

-- =============================================
-- Current keyword-level aggregate (4 weeks)
-- =============================================
keyword_4w AS (
  SELECT
    c.search_term,
    SUM(c.spend) as total_spend,
    SUM(c.orders) as total_orders,
    SUM(c.clicks) as total_clicks,
    COUNT(DISTINCT c.asin) as product_count,
    SUM(c.campaign_count) as total_campaign_count
  FROM current_4w c
  JOIN active_keywords ak ON c.search_term = ak.search_term
  GROUP BY 1
),

-- =============================================
-- Monthly hero history (12 months)
-- Who was the #1 ASIN each month by orders (then CVR)?
-- =============================================
monthly_asin_perf AS (
  SELECT
    FORMAT_DATE('%Y-%m', fa.date) as month,
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    COUNT(DISTINCT fa.campaign_id) as campaign_count,
    SUM(fa.Ads_orders) as orders,
    SUM(fa.Ads_clicks) as clicks,
    ROUND(SAFE_DIVIDE(SUM(fa.Ads_orders), NULLIF(SUM(fa.Ads_clicks), 0)) * 100, 1) as cvr_pct,
    ROUND(SUM(fa.Ads_cost), 2) as spend
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  JOIN active_keywords ak ON LOWER(fa.search_term) = ak.search_term
  WHERE fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2, 3
),

monthly_hero AS (
  SELECT
    search_term,
    month,
    asin,
    orders,
    clicks,
    cvr_pct,
    spend,
    ROW_NUMBER() OVER (
      PARTITION BY search_term, month
      ORDER BY orders DESC, cvr_pct DESC, spend DESC
    ) as hero_rank
  FROM monthly_asin_perf
  WHERE clicks >= 3 -- minimum confidence for hero detection
),

-- =============================================
-- Hero stability: how many months was the current hero #1?
-- =============================================
current_hero AS (
  SELECT
    search_term,
    asin as current_hero_asin,
    product_short_name as current_hero_name,
    ads_net_roas as current_hero_roas,
    ads_cvr_pct as current_hero_cvr
  FROM `onyga-482313.OI.V_PARENT_HERO_ASIN`
  WHERE global_hero_rank = 1
),

hero_stability AS (
  SELECT
    ch.search_term,
    ch.current_hero_asin,
    ch.current_hero_name,
    ch.current_hero_roas,
    ch.current_hero_cvr,
    COUNT(DISTINCT mh.month) as months_with_data,
    COUNTIF(mh.asin = ch.current_hero_asin) as months_as_hero,
    ROUND(SAFE_DIVIDE(
      COUNTIF(mh.asin = ch.current_hero_asin),
      NULLIF(COUNT(DISTINCT mh.month), 0)
    ) * 100, 0) as hero_stability_pct,
    -- First month the current hero had data
    MIN(CASE WHEN mh.asin = ch.current_hero_asin THEN mh.month END) as hero_first_month,
    -- Number of distinct months with data for current hero
    COUNT(DISTINCT CASE WHEN mh.asin = ch.current_hero_asin THEN mh.month END) as hero_data_months
  FROM current_hero ch
  LEFT JOIN monthly_hero mh ON ch.search_term = mh.search_term AND mh.hero_rank = 1
  GROUP BY 1, 2, 3, 4, 5
),

-- =============================================
-- Product breakdown JSON: per search_term, list each ASIN's metrics
-- =============================================
product_breakdown AS (
  SELECT
    c.search_term,
    TO_JSON_STRING(ARRAY_AGG(
      STRUCT(
        c.asin,
        COALESCE(e.product_short_name, 'Unknown') as product_name,
        c.spend,
        c.orders,
        c.clicks,
        ROUND(SAFE_DIVIDE(c.orders, NULLIF(c.clicks, 0)) * 100, 1) as cvr_pct,
        ROUND(c.orders * COALESCE(e.margin_per_unit, 0) - c.spend, 2) as net_profit,
        CASE WHEN hs.current_hero_asin = c.asin THEN TRUE ELSE FALSE END as is_hero,
        c.campaign_count
      )
      ORDER BY c.spend DESC
    )) as product_breakdown_json
  FROM current_4w c
  JOIN active_keywords ak ON c.search_term = ak.search_term
  LEFT JOIN asin_economics e ON c.asin = e.asin
  LEFT JOIN hero_stability hs ON c.search_term = hs.search_term
  GROUP BY 1
),

-- =============================================
-- Monthly heroes JSON: timeline of hero shifts
-- =============================================
monthly_heroes_json AS (
  SELECT
    mh.search_term,
    TO_JSON_STRING(ARRAY_AGG(
      STRUCT(
        mh.month,
        mh.asin as hero_asin,
        COALESCE(e.product_short_name, 'Unknown') as hero_product,
        mh.orders,
        mh.cvr_pct,
        mh.spend
      )
      ORDER BY mh.month
    )) as monthly_heroes_json
  FROM monthly_hero mh
  LEFT JOIN asin_economics e ON mh.asin = e.asin
  WHERE mh.hero_rank = 1
  GROUP BY 1
),

-- =============================================
-- Product breakdown JSON (12 months)
-- =============================================
product_breakdown_12m AS (
  SELECT
    search_term,
    TO_JSON_STRING(ARRAY_AGG(
      STRUCT(
        asin,
        product_name,
        spend,
        orders,
        clicks,
        cvr_pct,
        net_profit,
        is_hero,
        campaign_count
      )
      ORDER BY spend DESC
    )) as product_breakdown_12m_json
  FROM (
    SELECT
      c.search_term,
      c.asin,
      COALESCE(e.product_short_name, 'Unknown') as product_name,
      SUM(c.spend) as spend,
      SUM(c.orders) as orders,
      SUM(c.clicks) as clicks,
      ROUND(SAFE_DIVIDE(SUM(c.orders), NULLIF(SUM(c.clicks), 0)) * 100, 1) as cvr_pct,
      ROUND(SUM(c.orders) * COALESCE(e.margin_per_unit, 0) - SUM(c.spend), 2) as net_profit,
      CASE WHEN MAX(hs.current_hero_asin) = c.asin THEN TRUE ELSE FALSE END as is_hero,
      MAX(c.campaign_count) as campaign_count
    FROM monthly_asin_perf c
    LEFT JOIN asin_economics e ON c.asin = e.asin
    LEFT JOIN hero_stability hs ON c.search_term = hs.search_term
    GROUP BY 1, 2, e.product_short_name, e.margin_per_unit
  )
  GROUP BY 1
),

-- =============================================
-- Product breakdown JSON (by month)
-- =============================================
product_breakdown_by_month AS (
  SELECT
    search_term,
    TO_JSON_STRING(ARRAY_AGG(
      STRUCT(
        month as month,
        products as products
      )
      ORDER BY month DESC
    )) as product_breakdown_by_month_json
  FROM (
    SELECT
      c.search_term,
      c.month,
      ARRAY_AGG(
        STRUCT(
          c.asin,
          COALESCE(e.product_short_name, 'Unknown') as product_name,
          c.spend,
          c.orders,
          c.clicks,
          c.cvr_pct,
          ROUND(c.orders * COALESCE(e.margin_per_unit, 0) - c.spend, 2) as net_profit,
          CASE WHEN hs.current_hero_asin = c.asin THEN TRUE ELSE FALSE END as is_hero,
          c.campaign_count
        )
        ORDER BY c.spend DESC
      ) as products
    FROM monthly_asin_perf c
    LEFT JOIN asin_economics e ON c.asin = e.asin
    LEFT JOIN hero_stability hs ON c.search_term = hs.search_term
    GROUP BY 1, 2
  )
  GROUP BY 1
),

-- =============================================
-- Hero spend allocation (what % goes to hero vs non-hero)
-- =============================================
hero_spend AS (
  SELECT
    c.search_term,
    ROUND(SUM(CASE WHEN c.asin = hs.current_hero_asin THEN c.spend ELSE 0 END), 2) as hero_spend,
    ROUND(SAFE_DIVIDE(
      SUM(CASE WHEN c.asin = hs.current_hero_asin THEN c.spend ELSE 0 END),
      NULLIF(SUM(c.spend), 0)
    ) * 100, 0) as hero_spend_pct
  FROM current_4w c
  JOIN active_keywords ak ON c.search_term = ak.search_term
  LEFT JOIN hero_stability hs ON c.search_term = hs.search_term
  GROUP BY 1
)

-- =============================================
-- Final output: one row per search_term
-- =============================================
SELECT
  kw.search_term,

  -- Scale metrics
  kw.total_spend,
  kw.total_orders,
  kw.total_clicks,
  kw.product_count,
  kw.total_campaign_count as campaign_count,

  -- Current hero
  hs.current_hero_asin as hero_asin,
  hs.current_hero_name as hero_product_name,
  COALESCE(hs.current_hero_roas, 0) as hero_net_roas,
  COALESCE(hs.current_hero_cvr, 0) as hero_cvr_pct,

  -- Hero stability
  COALESCE(hs.hero_stability_pct, 0) as hero_stability_pct,
  COALESCE(hs.hero_data_months, 0) as hero_data_months,
  COALESCE(hs.months_with_data, 0) as months_with_data,

  -- Spend allocation
  COALESCE(hsp.hero_spend, 0) as hero_spend,
  COALESCE(hsp.hero_spend_pct, 0) as hero_spend_pct,

  -- Complexity scoring
  -- 0 = simple, 1-2 = review recommended, 3+ = must review
  (
    CASE WHEN kw.total_campaign_count >= 5 THEN 2
         WHEN kw.total_campaign_count >= 3 THEN 1
         ELSE 0 END
    + CASE WHEN COALESCE(hs.hero_stability_pct, 100) < 60 THEN 2 ELSE 0 END
    + CASE WHEN COALESCE(hs.hero_data_months, 99) < 4 THEN 1 ELSE 0 END
    + CASE WHEN COALESCE(hsp.hero_spend_pct, 100) < 50 THEN 1 ELSE 0 END
  ) as complexity_score,

  -- Flags
  kw.total_campaign_count >= 3 as is_multi_campaign,
  COALESCE(hs.hero_stability_pct, 100) < 60 as is_hero_unstable,
  COALESCE(hs.hero_data_months, 99) < 4 as is_hero_unproven,
  COALESCE(hsp.hero_spend_pct, 100) < 50 as is_fragmented,

  -- JSON details for inline panel
  pb.product_breakdown_json as product_breakdown,
  mhj.monthly_heroes_json as monthly_heroes,
  pb12.product_breakdown_12m_json as product_breakdown_12m,
  pbm.product_breakdown_by_month_json as product_breakdown_by_month

FROM keyword_4w kw
LEFT JOIN hero_stability hs ON kw.search_term = hs.search_term
LEFT JOIN hero_spend hsp ON kw.search_term = hsp.search_term
LEFT JOIN product_breakdown pb ON kw.search_term = pb.search_term
LEFT JOIN monthly_heroes_json mhj ON kw.search_term = mhj.search_term
LEFT JOIN product_breakdown_12m pb12 ON kw.search_term = pb12.search_term
LEFT JOIN product_breakdown_by_month pbm ON kw.search_term = pbm.search_term;
