-- =============================================
-- OI Database Project - V_EXPERIMENT_EVALUATION View
-- =============================================
--
-- Purpose: READ-ONLY evaluation of each experiment against its
--          strategy template goals.
--          User reviews results → decides if learnings should
--          feed back into Ads Coach logic.
--
-- NOT used by Ads Coach. Purely for human review.
--
-- Dependencies:
--   DIM_EXPERIMENT, DIM_EXPERIMENT_CAMPAIGN, DIM_STRATEGY_TEMPLATE,
--   FACT_AMAZON_ADS, DIM_PRODUCT, DIM_COSTS_HISTORY
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_EXPERIMENT_EVALUATION`
AS
WITH

-- Unit economics
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
  WHERE p.asin IS NOT NULL
),

-- Experiment info with strategy template
experiments AS (
  SELECT
    e.experiment_id,
    e.experiment_name,
    e.strategy_id,
    e.status,
    e.start_date,
    e.end_date,
    e.description as experiment_description,
    st.strategy_name,
    st.description as strategy_goal,
    st.use_case,
    st.recommended_bid_min,
    st.recommended_bid_max,
    st.recommended_daily_budget,
    st.season_applicability,
    st.min_days_to_graduate
  FROM `onyga-482313.OI.DIM_EXPERIMENT` e
  LEFT JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st ON e.strategy_id = st.strategy_id
),

-- Ads performance per experiment (aggregated)
experiment_perf AS (
  SELECT
    ec.experiment_id,
    ROUND(SUM(fa.Ads_cost), 2) as total_spend,
    SUM(fa.Ads_orders) as total_orders,
    SUM(fa.Ads_units) as total_units,
    SUM(fa.Ads_clicks) as total_clicks,
    SUM(fa.Ads_impressions) as total_impressions,
    ROUND(SUM(fa.Ads_sales), 2) as total_sales,
    COUNT(DISTINCT fa.date) as days_with_data,
    COUNT(DISTINCT LOWER(fa.search_term)) as unique_terms,
    MIN(fa.date) as first_ad_date,
    MAX(fa.date) as last_ad_date,
    -- Converting term count
    COUNT(DISTINCT CASE WHEN fa.Ads_orders > 0 THEN LOWER(fa.search_term) END) as converting_terms,
    -- Wasted spend (terms with 0 orders and > $5 spend)
    0 as placeholder_wasted
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec.campaign_id = fa.campaign_id
  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
  GROUP BY ec.experiment_id
),

-- Wasted spend per experiment (terms with 0 orders and >= $5 spend)
wasted_agg AS (
  SELECT
    ec.experiment_id,
    ROUND(SUM(term_agg.term_cost), 2) as total_wasted_spend,
    COUNT(*) as total_wasted_terms
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN (
    SELECT campaign_id, LOWER(search_term) as search_term,
      SUM(Ads_cost) as term_cost
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`
    WHERE search_term IS NOT NULL AND search_term != ''
    GROUP BY campaign_id, LOWER(search_term)
    HAVING SUM(Ads_orders) = 0 AND SUM(Ads_cost) >= 5
  ) term_agg ON ec.campaign_id = term_agg.campaign_id
  GROUP BY ec.experiment_id
),

-- Terms that graduated to EXACT_BOOST
exact_boost_terms AS (
  SELECT DISTINCT LOWER(fa.search_term) as search_term
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.DIM_EXPERIMENT` e ON ec.experiment_id = e.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec.campaign_id = fa.campaign_id
  WHERE e.strategy_id = 'EXACT_BOOST' AND e.status IN ('ACTIVE', 'PAUSED')
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
),

-- Count graduated terms per experiment (discovery only)
graduated_per_exp AS (
  SELECT
    ec.experiment_id,
    COUNT(DISTINCT CASE WHEN ebt.search_term IS NOT NULL THEN LOWER(fa.search_term) END) as terms_graduated
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.DIM_EXPERIMENT` e ON ec.experiment_id = e.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec.campaign_id = fa.campaign_id
  LEFT JOIN exact_boost_terms ebt ON LOWER(fa.search_term) = ebt.search_term
  WHERE e.strategy_id IN ('LOW_COST_DISCOVERY', 'HUNTER', 'CATEGORY_CONQUEST')
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND fa.Ads_orders > 0
  GROUP BY ec.experiment_id
),

-- Top converting terms per experiment (JSON-like string)
top_terms AS (
  SELECT
    ec.experiment_id,
    ARRAY_TO_STRING(
      ARRAY_AGG(
        CONCAT(LOWER(fa_agg.search_term), ' (', CAST(fa_agg.term_orders AS STRING), ' orders, ROAS ', CAST(ROUND(SAFE_DIVIDE(fa_agg.term_sales, NULLIF(fa_agg.term_cost, 0)), 1) AS STRING), ')')
        ORDER BY fa_agg.term_orders DESC
        LIMIT 10
      ), ' | '
    ) as top_converting_terms
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN (
    SELECT campaign_id, LOWER(search_term) as search_term,
      SUM(Ads_orders) as term_orders, SUM(Ads_cost) as term_cost, SUM(Ads_sales) as term_sales
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`
    WHERE search_term IS NOT NULL AND search_term != ''
    GROUP BY campaign_id, LOWER(search_term)
    HAVING SUM(Ads_orders) >= 2
  ) fa_agg ON ec.campaign_id = fa_agg.campaign_id
  GROUP BY ec.experiment_id
),

-- Top wasted terms per experiment
top_wasted AS (
  SELECT
    ec.experiment_id,
    ARRAY_TO_STRING(
      ARRAY_AGG(
        CONCAT(LOWER(fa_agg.search_term), ' ($', CAST(ROUND(fa_agg.term_cost, 0) AS STRING), ')')
        ORDER BY fa_agg.term_cost DESC
        LIMIT 10
      ), ' | '
    ) as top_wasted_terms
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN (
    SELECT campaign_id, LOWER(search_term) as search_term,
      SUM(Ads_orders) as term_orders, SUM(Ads_cost) as term_cost
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`
    WHERE search_term IS NOT NULL AND search_term != ''
    GROUP BY campaign_id, LOWER(search_term)
    HAVING SUM(Ads_orders) = 0 AND SUM(Ads_cost) >= 10
  ) fa_agg ON ec.campaign_id = fa_agg.campaign_id
  GROUP BY ec.experiment_id
)

-- Final output
SELECT
  e.experiment_id,
  e.experiment_name,
  e.strategy_id,
  e.strategy_name,
  e.status,
  e.start_date,
  e.end_date,
  e.experiment_description,
  e.strategy_goal,
  e.use_case,

  -- Performance
  COALESCE(ep.total_spend, 0) as total_spend,
  COALESCE(ep.total_orders, 0) as total_orders,
  COALESCE(ep.total_clicks, 0) as total_clicks,
  COALESCE(ep.total_sales, 0) as total_sales,
  COALESCE(ep.days_with_data, 0) as days_with_data,
  COALESCE(ep.unique_terms, 0) as unique_terms,
  COALESCE(ep.converting_terms, 0) as converting_terms,
  ep.first_ad_date,
  ep.last_ad_date,

  -- Derived
  ROUND(SAFE_DIVIDE(ep.total_spend, NULLIF(ep.total_clicks, 0)), 2) as avg_cpc,
  ROUND(SAFE_DIVIDE(ep.total_orders, NULLIF(ep.total_clicks, 0)) * 100, 2) as cvr_pct,
  ROUND(SAFE_DIVIDE(ep.total_sales, NULLIF(ep.total_spend, 0)), 2) as gross_roas,

  -- Waste
  COALESCE(wa.total_wasted_spend, 0) as wasted_spend,
  COALESCE(wa.total_wasted_terms, 0) as wasted_terms,
  ROUND(SAFE_DIVIDE(COALESCE(wa.total_wasted_spend, 0), NULLIF(ep.total_spend, 0)) * 100, 1) as wasted_pct,

  -- Graduation (discovery strategies)
  COALESCE(gpe.terms_graduated, 0) as terms_graduated_to_exact,

  -- Evidence
  tt.top_converting_terms,
  tw.top_wasted_terms,

  -- Template
  e.recommended_bid_max,
  e.recommended_daily_budget,
  e.min_days_to_graduate,

  -- =============================================
  -- CHECKS
  -- =============================================
  -- CHECK 1: CPC in range
  CASE
    WHEN ep.total_clicks IS NULL OR ep.total_clicks = 0 THEN 'NO_DATA'
    WHEN SAFE_DIVIDE(ep.total_spend, ep.total_clicks) <= e.recommended_bid_max THEN 'PASS'
    ELSE 'FAIL'
  END as check_1_cpc,

  -- CHECK 2: Gross ROAS
  CASE
    WHEN ep.total_spend IS NULL OR ep.total_spend < 10 THEN 'NO_DATA'
    WHEN e.strategy_id = 'BRAND_DEFENSE' AND SAFE_DIVIDE(ep.total_sales, ep.total_spend) >= 5.0 THEN 'PASS'
    WHEN e.strategy_id = 'EXACT_BOOST' AND SAFE_DIVIDE(ep.total_sales, ep.total_spend) >= 2.0 THEN 'PASS'
    WHEN SAFE_DIVIDE(ep.total_sales, ep.total_spend) >= 1.5 THEN 'PASS'
    WHEN SAFE_DIVIDE(ep.total_sales, ep.total_spend) >= 1.0 THEN 'PARTIAL'
    ELSE 'FAIL'
  END as check_2_roas,

  -- CHECK 3: Enough data
  CASE
    WHEN COALESCE(ep.days_with_data, 0) >= COALESCE(e.min_days_to_graduate, 28) THEN 'PASS'
    WHEN COALESCE(ep.days_with_data, 0) >= 7 THEN 'PARTIAL'
    ELSE 'FAIL'
  END as check_3_data,

  -- CHECK 4: Discovery converting
  CASE
    WHEN e.strategy_id NOT IN ('LOW_COST_DISCOVERY', 'HUNTER', 'CATEGORY_CONQUEST') THEN 'N/A'
    WHEN COALESCE(ep.converting_terms, 0) >= 10 THEN 'PASS'
    WHEN COALESCE(ep.converting_terms, 0) >= 3 THEN 'PARTIAL'
    ELSE 'FAIL'
  END as check_4_discovery,

  -- CHECK 5: Terms graduated
  CASE
    WHEN e.strategy_id NOT IN ('LOW_COST_DISCOVERY', 'HUNTER', 'CATEGORY_CONQUEST') THEN 'N/A'
    WHEN COALESCE(gpe.terms_graduated, 0) >= 3 THEN 'PASS'
    WHEN COALESCE(gpe.terms_graduated, 0) > 0 THEN 'PARTIAL'
    ELSE 'FAIL'
  END as check_5_graduated,

  -- CHECK 6: Waste controlled
  CASE
    WHEN ep.total_spend IS NULL OR ep.total_spend < 10 THEN 'NO_DATA'
    WHEN SAFE_DIVIDE(COALESCE(wa.total_wasted_spend, 0), ep.total_spend) <= 0.3 THEN 'PASS'
    WHEN SAFE_DIVIDE(COALESCE(wa.total_wasted_spend, 0), ep.total_spend) <= 0.5 THEN 'PARTIAL'
    ELSE 'FAIL'
  END as check_6_waste,

  -- CHECK 7: CVR (exact strategies)
  CASE
    WHEN e.strategy_id NOT IN ('EXACT_BOOST', 'BRAND_DEFENSE') THEN 'N/A'
    WHEN ep.total_clicks IS NULL OR ep.total_clicks < 20 THEN 'NO_DATA'
    WHEN SAFE_DIVIDE(ep.total_orders, ep.total_clicks) * 100 >= 5.0 THEN 'PASS'
    WHEN SAFE_DIVIDE(ep.total_orders, ep.total_clicks) * 100 >= 2.0 THEN 'PARTIAL'
    ELSE 'FAIL'
  END as check_7_cvr,

  -- VERDICT
  CASE
    WHEN ep.total_spend IS NULL OR ep.total_spend < 10 THEN 'INSUFFICIENT_DATA'
    WHEN COALESCE(ep.days_with_data, 0) < 7 THEN 'INSUFFICIENT_DATA'
    WHEN (
      (CASE WHEN SAFE_DIVIDE(ep.total_spend, NULLIF(ep.total_clicks, 0)) <= e.recommended_bid_max THEN 1 ELSE 0 END)
      + (CASE WHEN SAFE_DIVIDE(ep.total_sales, NULLIF(ep.total_spend, 0)) >= 1.5 THEN 1 ELSE 0 END)
      + (CASE WHEN SAFE_DIVIDE(COALESCE(wa.total_wasted_spend, 0), NULLIF(ep.total_spend, 0)) <= 0.3 THEN 1 ELSE 0 END)
    ) >= 2 THEN 'SUCCESS'
    WHEN SAFE_DIVIDE(ep.total_sales, NULLIF(ep.total_spend, 0)) >= 1.0 THEN 'MIXED'
    ELSE 'FAILING'
  END as verdict,

  -- Verdict reason
  CONCAT(
    COALESCE(e.strategy_name, e.strategy_id), ': ',
    CAST(COALESCE(ep.days_with_data, 0) AS STRING), ' days, ',
    '$', CAST(ROUND(COALESCE(ep.total_spend, 0), 0) AS STRING), ' spent → ',
    CAST(COALESCE(ep.total_orders, 0) AS STRING), ' orders ',
    '(ROAS ', COALESCE(CAST(ROUND(SAFE_DIVIDE(ep.total_sales, NULLIF(ep.total_spend, 0)), 2) AS STRING), 'N/A'), '). ',
    'CPC $', COALESCE(CAST(ROUND(SAFE_DIVIDE(ep.total_spend, NULLIF(ep.total_clicks, 0)), 2) AS STRING), 'N/A'),
    ' vs max $', COALESCE(CAST(e.recommended_bid_max AS STRING), 'N/A'), '. ',
    'Waste: ', CAST(ROUND(SAFE_DIVIDE(COALESCE(wa.total_wasted_spend, 0), NULLIF(ep.total_spend, 0)) * 100, 0) AS STRING), '%.'
  ) as verdict_reason

FROM experiments e
LEFT JOIN experiment_perf ep ON e.experiment_id = ep.experiment_id
LEFT JOIN wasted_agg wa ON e.experiment_id = wa.experiment_id
LEFT JOIN graduated_per_exp gpe ON e.experiment_id = gpe.experiment_id
LEFT JOIN top_terms tt ON e.experiment_id = tt.experiment_id
LEFT JOIN top_wasted tw ON e.experiment_id = tw.experiment_id
ORDER BY
  CASE e.status WHEN 'ACTIVE' THEN 1 WHEN 'PAUSED' THEN 2 ELSE 3 END,
  COALESCE(ep.total_spend, 0) DESC;
