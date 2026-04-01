-- =============================================
-- OI Database Project - V_EXPERIMENT_KEYWORD_COLLISIONS View
-- =============================================
--
-- Purpose: Detect search terms being targeted by multiple active experiments.
--          Bidding on the same keyword for different ASINs means bidding against yourself.
--
-- Use: Check before launching new experiments, and periodically review active ones.
--
-- Dependencies: DIM_EXPERIMENT, DIM_EXPERIMENT_CAMPAIGN, FACT_AMAZON_ADS
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_EXPERIMENT_KEYWORD_COLLISIONS`
AS
WITH active_experiment_terms AS (
  -- All search terms served by active experiment campaigns (last 14 days)
  SELECT
    e.experiment_id,
    e.experiment_name,
    e.strategy_id,
    ec.campaign_id,
    ec.campaign_name,
    LOWER(fa.search_term) as search_term,
    fa.advertised_asins as asin,
    SUM(fa.Ads_impressions) as impressions,
    SUM(fa.Ads_clicks) as clicks,
    SUM(fa.Ads_orders) as orders,
    SUM(fa.Ads_cost) as cost,
    SUM(fa.Ads_sales) as sales
  FROM `onyga-482313.OI.DIM_EXPERIMENT` e
  JOIN `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
    ON e.experiment_id = ec.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON ec.campaign_id = fa.campaign_id
    AND fa.date >= e.start_date
    AND (e.end_date IS NULL OR fa.date <= e.end_date)
  WHERE e.status = 'ACTIVE'
    AND fa.search_term IS NOT NULL
    AND fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
  GROUP BY 1, 2, 3, 4, 5, 6, 7
),

-- Find search terms appearing in more than one experiment
collision_terms AS (
  SELECT
    search_term,
    COUNT(DISTINCT experiment_id) as experiment_count,
    COUNT(DISTINCT asin) as asin_count,
    ARRAY_AGG(DISTINCT experiment_id) as experiment_ids,
    ARRAY_AGG(DISTINCT asin) as asins
  FROM active_experiment_terms
  GROUP BY 1
  HAVING COUNT(DISTINCT experiment_id) > 1
)

SELECT
  -- Key
  CONCAT(aet.search_term, '|', aet.experiment_id, '|', aet.asin) as row_key,

  -- Collision severity
  ct.experiment_count,
  ct.asin_count,
  CASE
    WHEN ct.asin_count > 1 THEN 'CROSS_ASIN'    -- Same keyword, different ASINs = bidding against yourself
    ELSE 'SAME_ASIN'                              -- Same keyword, same ASIN, different experiments = budget waste
  END as collision_type,

  -- Search term
  aet.search_term,

  -- Experiment detail
  aet.experiment_id,
  aet.experiment_name,
  aet.strategy_id,
  aet.asin,
  p.product_short_name,
  aet.campaign_id,
  aet.campaign_name,

  -- Recent performance in this experiment (last 14 days)
  aet.impressions,
  aet.clicks,
  aet.orders,
  ROUND(aet.cost, 2) as cost,
  ROUND(aet.sales, 2) as sales,
  ROUND(SAFE_DIVIDE(aet.orders, NULLIF(aet.clicks, 0)) * 100, 2) as conversion_rate_pct,
  ROUND(SAFE_DIVIDE(aet.sales, NULLIF(aet.cost, 0)), 2) as roas,

  -- All colliding experiments for this term
  ct.experiment_ids as all_colliding_experiments,
  ct.asins as all_colliding_asins

FROM active_experiment_terms aet
JOIN collision_terms ct ON aet.search_term = ct.search_term
LEFT JOIN `onyga-482313.OI.DIM_PRODUCT` p ON aet.asin = p.asin
ORDER BY ct.experiment_count DESC, aet.search_term, aet.cost DESC;
