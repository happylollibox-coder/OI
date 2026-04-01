-- =============================================
-- OI Database Project - V_EXPERIMENT_LEARNINGS View
-- =============================================
--
-- Purpose: Pattern recognition from completed experiments
--          The "memory" of the system - learns what works and what doesn't
--          Aggregates results across 8 dimensions: overall, campaign_type,
--          match_type, season_context, strategy, bidding_strategy,
--          bid_range, top_of_search
--
-- Dependencies: DIM_EXPERIMENT, V_EXPERIMENT_SUMMARY, DIM_EXPERIMENT_CAMPAIGN,
--              DIM_US_HOLIDAYS, V_EXPERIMENT_CAMPAIGN_SETTINGS, DIM_STRATEGY_TEMPLATE
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_EXPERIMENT_LEARNINGS`
AS
WITH experiment_enriched AS (
  SELECT
    e.experiment_id,
    e.experiment_name,
    e.start_date,
    e.end_date,
    e.status,
    e.outcome_score,
    e.outcome_tags,
    e.strategy_id,

    -- Strategy name (from template)
    st.strategy_name,

    -- Derive campaign type from campaign names
    CASE
      WHEN EXISTS (
        SELECT 1 FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
        JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec.campaign_id = fa.campaign_id
        WHERE ec.experiment_id = e.experiment_id AND fa.campaign_type = 'SB'
        LIMIT 1
      ) THEN 'SB'
      ELSE 'SP'
    END as primary_campaign_type,

    -- Derive match type from campaign names
    CASE
      WHEN EXISTS (
        SELECT 1 FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
        WHERE ec.experiment_id = e.experiment_id AND UPPER(ec.campaign_name) LIKE '%EXACT%'
        LIMIT 1
      ) THEN 'EXACT'
      WHEN EXISTS (
        SELECT 1 FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
        WHERE ec.experiment_id = e.experiment_id AND UPPER(ec.campaign_name) LIKE '%BROAD%'
        LIMIT 1
      ) THEN 'BROAD'
      WHEN EXISTS (
        SELECT 1 FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
        WHERE ec.experiment_id = e.experiment_id AND UPPER(ec.campaign_name) LIKE '%AUTO%'
        LIMIT 1
      ) THEN 'AUTO'
      ELSE 'MIXED'
    END as match_type,

    -- Derive season from start_date
    CASE
      WHEN EXISTS (
        SELECT 1 FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
        WHERE h.category = 'gift_season'
          AND e.start_date BETWEEN h.pre_season_start AND h.holiday_date
        LIMIT 1
      ) THEN 'PRE_HOLIDAY'
      WHEN EXTRACT(MONTH FROM e.start_date) IN (11, 12) THEN 'HOLIDAY'
      WHEN EXTRACT(MONTH FROM e.start_date) IN (1, 2) THEN 'POST_HOLIDAY'
      ELSE 'OFF_SEASON'
    END as season_context,

    -- Campaign settings (aggregated across all campaigns in experiment)
    cs_agg.primary_bidding_strategy,
    cs_agg.avg_bid,
    cs_agg.bid_range_bucket,
    cs_agg.has_any_tos_boost,
    cs_agg.max_tos_pct,

    -- ASIN-level results (PERFORMANCE_ source via V_EXPERIMENT_SUMMARY)
    r.performance_total_orders_lift_pct as total_lift,
    r.performance_organic_units_lift_pct as organic_lift,
    r.ads_avg_roas as avg_roas,
    r.ads_total_spend as total_ad_spend,
    r.days_running

  FROM `onyga-482313.OI.DIM_EXPERIMENT` e
  LEFT JOIN `onyga-482313.OI.V_EXPERIMENT_SUMMARY` r ON e.experiment_id = r.experiment_id
  LEFT JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st ON e.strategy_id = st.strategy_id

  -- Aggregate campaign settings per experiment
  LEFT JOIN (
    SELECT
      experiment_id,
      -- Most common bidding strategy across campaigns
      ARRAY_AGG(bidding_strategy ORDER BY bidding_strategy LIMIT 1)[OFFSET(0)] as primary_bidding_strategy,
      -- Average bid across all campaigns
      ROUND(AVG(COALESCE(avg_keyword_bid, avg_default_bid)), 2) as avg_bid,
      -- Bid range bucket (from the dominant campaign)
      ARRAY_AGG(bid_range_bucket ORDER BY COALESCE(num_keywords, 0) DESC LIMIT 1)[OFFSET(0)] as bid_range_bucket,
      -- Any campaign has TOS boost
      LOGICAL_OR(has_top_of_search_boost) as has_any_tos_boost,
      -- Highest TOS percentage
      MAX(COALESCE(top_of_search_pct, 0)) as max_tos_pct
    FROM `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS`
    GROUP BY experiment_id
  ) cs_agg ON e.experiment_id = cs_agg.experiment_id

  WHERE e.status IN ('COMPLETED', 'ACTIVE')
)

-- =============================================
-- Aggregate learnings by 8 dimensions
-- =============================================

-- 1. Campaign type
SELECT
  CONCAT('campaign_type', '|', primary_campaign_type) as row_key,
  'campaign_type' as learning_dimension,
  primary_campaign_type as dimension_value,
  COUNT(*) as experiment_count,
  ROUND(AVG(organic_lift), 1) as avg_organic_lift_pct,
  ROUND(AVG(total_lift), 1) as avg_total_lift_pct,
  ROUND(AVG(avg_roas), 2) as avg_roas,
  ROUND(AVG(total_ad_spend), 2) as avg_ad_spend,
  ROUND(AVG(days_running), 0) as avg_days_running,
  COUNTIF(organic_lift > 0) as successful_count,
  COUNTIF(organic_lift <= 0) as unsuccessful_count
FROM experiment_enriched
GROUP BY 1, 2, 3, 3

UNION ALL

-- 2. Match type
SELECT
  CONCAT('match_type', '|', match_type),
  'match_type' as learning_dimension,
  match_type as dimension_value,
  COUNT(*),
  ROUND(AVG(organic_lift), 1),
  ROUND(AVG(total_lift), 1),
  ROUND(AVG(avg_roas), 2),
  ROUND(AVG(total_ad_spend), 2),
  ROUND(AVG(days_running), 0),
  COUNTIF(organic_lift > 0),
  COUNTIF(organic_lift <= 0)
FROM experiment_enriched
GROUP BY 1, 2, 3

UNION ALL

-- 3. Season context
SELECT
  CONCAT('season_context', '|', season_context),
  'season_context' as learning_dimension,
  season_context as dimension_value,
  COUNT(*),
  ROUND(AVG(organic_lift), 1),
  ROUND(AVG(total_lift), 1),
  ROUND(AVG(avg_roas), 2),
  ROUND(AVG(total_ad_spend), 2),
  ROUND(AVG(days_running), 0),
  COUNTIF(organic_lift > 0),
  COUNTIF(organic_lift <= 0)
FROM experiment_enriched
GROUP BY 1, 2, 3

UNION ALL

-- 4. Strategy (NEW)
SELECT
  CONCAT('strategy', '|', COALESCE(strategy_name, 'No Strategy')),
  'strategy' as learning_dimension,
  COALESCE(strategy_name, 'No Strategy') as dimension_value,
  COUNT(*),
  ROUND(AVG(organic_lift), 1),
  ROUND(AVG(total_lift), 1),
  ROUND(AVG(avg_roas), 2),
  ROUND(AVG(total_ad_spend), 2),
  ROUND(AVG(days_running), 0),
  COUNTIF(organic_lift > 0),
  COUNTIF(organic_lift <= 0)
FROM experiment_enriched
GROUP BY 1, 2, 3

UNION ALL

-- 5. Bidding strategy (NEW)
SELECT
  CONCAT('bidding_strategy', '|', COALESCE(primary_bidding_strategy, 'UNKNOWN')),
  'bidding_strategy' as learning_dimension,
  COALESCE(primary_bidding_strategy, 'UNKNOWN') as dimension_value,
  COUNT(*),
  ROUND(AVG(organic_lift), 1),
  ROUND(AVG(total_lift), 1),
  ROUND(AVG(avg_roas), 2),
  ROUND(AVG(total_ad_spend), 2),
  ROUND(AVG(days_running), 0),
  COUNTIF(organic_lift > 0),
  COUNTIF(organic_lift <= 0)
FROM experiment_enriched
GROUP BY 1, 2, 3

UNION ALL

-- 6. Bid range bucket (NEW)
SELECT
  CONCAT('bid_range', '|', COALESCE(bid_range_bucket, 'UNKNOWN')),
  'bid_range' as learning_dimension,
  COALESCE(bid_range_bucket, 'UNKNOWN') as dimension_value,
  COUNT(*),
  ROUND(AVG(organic_lift), 1),
  ROUND(AVG(total_lift), 1),
  ROUND(AVG(avg_roas), 2),
  ROUND(AVG(total_ad_spend), 2),
  ROUND(AVG(days_running), 0),
  COUNTIF(organic_lift > 0),
  COUNTIF(organic_lift <= 0)
FROM experiment_enriched
GROUP BY 1, 2, 3

UNION ALL

-- 7. Top-of-search boost (NEW)
SELECT
  CONCAT('top_of_search', '|', CASE
    WHEN has_any_tos_boost THEN CONCAT('TOS_BOOST (max ', CAST(max_tos_pct AS STRING), '%)')
    ELSE 'NO_TOS_BOOST'
  END),
  'top_of_search' as learning_dimension,
  CASE
    WHEN has_any_tos_boost THEN CONCAT('TOS_BOOST (max ', CAST(max_tos_pct AS STRING), '%)')
    ELSE 'NO_TOS_BOOST'
  END as dimension_value,
  COUNT(*),
  ROUND(AVG(organic_lift), 1),
  ROUND(AVG(total_lift), 1),
  ROUND(AVG(avg_roas), 2),
  ROUND(AVG(total_ad_spend), 2),
  ROUND(AVG(days_running), 0),
  COUNTIF(organic_lift > 0),
  COUNTIF(organic_lift <= 0)
FROM experiment_enriched
GROUP BY 1, 2, 3

UNION ALL

-- 8. Overall
SELECT
  'overall|ALL_EXPERIMENTS',
  'overall' as learning_dimension,
  'ALL_EXPERIMENTS' as dimension_value,
  COUNT(*),
  ROUND(AVG(organic_lift), 1),
  ROUND(AVG(total_lift), 1),
  ROUND(AVG(avg_roas), 2),
  ROUND(AVG(total_ad_spend), 2),
  ROUND(AVG(days_running), 0),
  COUNTIF(organic_lift > 0),
  COUNTIF(organic_lift <= 0)
FROM experiment_enriched

UNION ALL

-- 9. Per ASIN (what worked for this specific product)
SELECT
  CONCAT('asin', '|', bp.asin),
  'asin' as learning_dimension,
  bp.asin as dimension_value,
  COUNT(DISTINCT bp.experiment_id),
  ROUND(AVG(bp.asin_total_lift_pct), 1),
  ROUND(AVG(bp.asin_seasonal_total_lift_pct), 1),
  ROUND(AVG(bp.asin_ads_roas), 2),
  ROUND(SUM(bp.segment_ad_cost), 2),
  NULL,
  COUNTIF(bp.segment_verdict IN ('STRONG_WIN', 'MODERATE_WIN')),
  COUNTIF(bp.segment_verdict IN ('LOSS', 'BREAK_EVEN'))
FROM `onyga-482313.OI.V_ASIN_BEST_PRACTICES` bp
WHERE bp.intent_segment IS NOT NULL
GROUP BY 1, 2, 3

UNION ALL

-- 10. Per product_type (cross-ASIN learning)
SELECT
  CONCAT('product_type', '|', bp.product_type),
  'product_type' as learning_dimension,
  bp.product_type as dimension_value,
  COUNT(DISTINCT bp.experiment_id),
  ROUND(AVG(bp.asin_total_lift_pct), 1),
  ROUND(AVG(bp.asin_seasonal_total_lift_pct), 1),
  ROUND(AVG(bp.asin_ads_roas), 2),
  ROUND(SUM(bp.segment_ad_cost), 2),
  NULL,
  COUNTIF(bp.segment_verdict IN ('STRONG_WIN', 'MODERATE_WIN')),
  COUNTIF(bp.segment_verdict IN ('LOSS', 'BREAK_EVEN'))
FROM `onyga-482313.OI.V_ASIN_BEST_PRACTICES` bp
WHERE bp.product_type IS NOT NULL AND bp.intent_segment IS NOT NULL
GROUP BY 1, 2, 3

UNION ALL

-- 11. Per intent_segment (what strategies work for BRAND vs PRODUCT vs CATEGORY vs GIFT)
SELECT
  CONCAT('intent_segment', '|', bp.intent_segment),
  'intent_segment' as learning_dimension,
  bp.intent_segment as dimension_value,
  COUNT(DISTINCT bp.experiment_id),
  NULL,
  ROUND(AVG(bp.avg_normalized_total_lift_pct), 1),
  ROUND(AVG(bp.segment_ads_roas), 2),
  ROUND(SUM(bp.segment_ad_cost), 2),
  NULL,
  COUNTIF(bp.segment_verdict IN ('STRONG_WIN', 'MODERATE_WIN')),
  COUNTIF(bp.segment_verdict IN ('LOSS', 'BREAK_EVEN'))
FROM `onyga-482313.OI.V_ASIN_BEST_PRACTICES` bp
WHERE bp.intent_segment IS NOT NULL
GROUP BY 1, 2, 3

UNION ALL

-- 12. Per occasion (BIRTHDAY vs CHRISTMAS vs SLEEPOVER etc.)
SELECT
  CONCAT('occasion', '|', bp.occasion),
  'occasion' as learning_dimension,
  bp.occasion as dimension_value,
  COUNT(DISTINCT bp.experiment_id),
  NULL,
  ROUND(AVG(bp.avg_normalized_total_lift_pct), 1),
  ROUND(AVG(bp.segment_ads_roas), 2),
  ROUND(SUM(bp.segment_ad_cost), 2),
  NULL,
  COUNTIF(bp.segment_verdict IN ('STRONG_WIN', 'MODERATE_WIN')),
  COUNTIF(bp.segment_verdict IN ('LOSS', 'BREAK_EVEN'))
FROM `onyga-482313.OI.V_ASIN_BEST_PRACTICES` bp
WHERE bp.occasion IS NOT NULL
GROUP BY 1, 2, 3;
