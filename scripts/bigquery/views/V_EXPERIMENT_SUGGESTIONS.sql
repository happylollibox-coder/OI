-- =============================================
-- OI Database Project - V_EXPERIMENT_SUGGESTIONS View
-- =============================================
--
-- Purpose: For each ASIN with SQP data, suggest experiments ranked by opportunity.
--          Uses segment analysis, sibling ASIN learnings, and strategy templates
--          to recommend what to try next.
--
-- Output: One row per ASIN + suggested_strategy, ranked by priority_score.
--
-- Dependencies:
--   V_SEARCH_TERM_SEGMENT, V_ASIN_BEST_PRACTICES, V_EXPERIMENT_LEARNINGS,
--   DIM_STRATEGY_TEMPLATE, DIM_PRODUCT, DIM_EXPERIMENT
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_EXPERIMENT_SUGGESTIONS`
AS
WITH
-- =============================================
-- 0. Season awareness: is today inside a peak-season ramp-up window?
-- =============================================
current_season AS (
  SELECT
    CURRENT_DATE() as today,
    COUNTIF(CURRENT_DATE() BETWEEN pre_season_start AND holiday_date) > 0 as is_peak_season,
    MAX(CASE WHEN CURRENT_DATE() BETWEEN pre_season_start AND holiday_date THEN holiday_name END) as current_holiday,
    MIN(CASE WHEN pre_season_start > CURRENT_DATE() THEN pre_season_start END) as next_peak_starts,
    MIN(CASE WHEN pre_season_start > CURRENT_DATE() THEN holiday_name END) as next_holiday_name
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
),

-- =============================================
-- 0b. Map search term occasions to holidays (which occasions are seasonal?)
-- =============================================
occasion_holiday_map AS (
  SELECT 'CHRISTMAS' as occasion, 'Christmas' as holiday_name UNION ALL
  SELECT 'CHRISTMAS', 'Black Friday' UNION ALL
  SELECT 'CHRISTMAS', 'Cyber Monday' UNION ALL
  SELECT 'VALENTINES', 'Valentines Day' UNION ALL
  SELECT 'BACK_TO_SCHOOL', 'Back to School' UNION ALL
  SELECT 'EASTER', 'Easter'
  -- BIRTHDAY, SLEEPOVER, PARTY, GRADUATION, NO_OCCASION = always relevant
),

-- Which seasonal occasions are currently in their ramp-up window?
active_occasions AS (
  SELECT DISTINCT ohm.occasion
  FROM occasion_holiday_map ohm
  JOIN `onyga-482313.OI.DIM_US_HOLIDAYS` h ON ohm.holiday_name = h.holiday_name
  WHERE CURRENT_DATE() BETWEEN h.pre_season_start AND h.holiday_date
),

-- =============================================
-- 1. Per-ASIN SQP opportunity by experiment_segment
--    Only counts terms whose occasion is currently relevant
-- =============================================
asin_segment_opportunity AS (
  SELECT
    seg.asin,
    seg.experiment_segment,
    COUNT(DISTINCT seg.search_term) as term_count,
    ROUND(SUM(seg.amazon_avg_weekly_orders), 0) as total_market_weekly_orders,
    ROUND(AVG(seg.your_orders_share_pct), 2) as avg_your_orders_share_pct,
    ROUND(AVG(seg.your_impressions_share_pct), 2) as avg_your_impressions_share_pct,
    -- Addressable: market orders on terms where your share is below 5%
    ROUND(SUM(CASE WHEN COALESCE(seg.your_orders_share_pct, 0) < 5 THEN seg.amazon_avg_weekly_orders ELSE 0 END), 0) as addressable_weekly_orders,
    -- Your avg conversion rates (non-holiday, orders/clicks %)
    ROUND(SAFE_DIVIDE(SUM(seg.your_total_orders), NULLIF(SUM(seg.your_total_clicks), 0)) * 100, 2) as avg_your_conversion_rate_pct,
    ROUND(SAFE_DIVIDE(SUM(seg.ads_total_orders), NULLIF(SUM(seg.ads_total_clicks), 0)) * 100, 2) as avg_ads_conversion_rate_pct,
    -- Proven terms: 3+ orders (SQP or ads), 2+ weeks with orders, 50+ market orders/week
    -- For BRAND segment: volume threshold relaxed (brand terms are low-volume but high-intent)
    COUNTIF(
      (COALESCE(seg.your_total_orders, 0) + COALESCE(seg.ads_total_orders, 0)) >= 3
      AND COALESCE(seg.weeks_with_your_orders, 0) >= 2
      AND (seg.amazon_avg_weekly_orders > 50 OR seg.experiment_segment = 'BRAND')
    ) as proven_term_count,
    -- High-volume unproven: big market terms where ASIN has not proven itself yet
    COUNTIF(
      seg.amazon_avg_weekly_orders > 100
      AND (
        (COALESCE(seg.your_total_orders, 0) + COALESCE(seg.ads_total_orders, 0)) < 3
        OR COALESCE(seg.weeks_with_your_orders, 0) < 2
      )
    ) as high_volume_unproven_count,
    -- Average amazon conversion rate (high = purchase-intent segment)
    ROUND(AVG(seg.amazon_conversion_rate_pct), 2) as avg_amazon_conversion_rate_pct,
    -- Top opportunity terms (highest market * lowest share)
    ARRAY_AGG(
      STRUCT(seg.search_term, seg.amazon_avg_weekly_orders, seg.your_orders_share_pct, seg.occasion, seg.age_group, seg.product_match)
      ORDER BY COALESCE(seg.amazon_avg_weekly_orders, 0) * (1 - COALESCE(seg.your_orders_share_pct, 0) / 100) DESC
      LIMIT 5
    ) as top_opportunity_terms
  FROM `onyga-482313.OI.V_SEARCH_TERM_SEGMENT` seg
  WHERE seg.amazon_avg_weekly_orders > 0
    -- Only include terms whose occasion is either always-relevant or currently in-season
    AND (
      seg.occasion NOT IN ('CHRISTMAS', 'VALENTINES', 'BACK_TO_SCHOOL', 'EASTER')
      OR seg.occasion IN (SELECT occasion FROM active_occasions)
    )
  GROUP BY 1, 2
),

-- =============================================
-- 1b. Hero ASIN for BRAND segment
--     Brand defense should feature the ASIN with the most actual orders
--     on brand search terms (organic + ads). This is the product shoppers
--     buy when they search your brand name -- your flagship/best-seller.
-- =============================================
brand_hero AS (
  SELECT
    seg.asin,
    SUM(COALESCE(seg.your_total_orders, 0) + COALESCE(seg.ads_total_orders, 0)) AS brand_total_orders,
    ROW_NUMBER() OVER (
      ORDER BY SUM(COALESCE(seg.your_total_orders, 0) + COALESCE(seg.ads_total_orders, 0)) DESC
    ) as brand_rank
  FROM `onyga-482313.OI.V_SEARCH_TERM_SEGMENT` seg
  WHERE seg.experiment_segment = 'BRAND'
  GROUP BY 1
),

-- =============================================
-- 2. What experiments already exist per ASIN?
-- =============================================
existing_experiments AS (
  SELECT
    ar.asin,
    e.strategy_id,
    e.experiment_id,
    e.status,
    e.lifecycle_stage
  FROM `onyga-482313.OI.DIM_EXPERIMENT` e
  JOIN `onyga-482313.OI.V_EXPERIMENT_RESULTS_ASIN` ar ON e.experiment_id = ar.experiment_id
),

-- =============================================
-- 3. Sibling ASIN learnings (same product_type)
-- =============================================
sibling_wins AS (
  SELECT
    p_target.asin as target_asin,
    bp.asin as source_asin,
    bp.experiment_id as source_experiment_id,
    bp.strategy_id,
    bp.strategy_name,
    bp.campaign_type,
    bp.primary_match_type,
    bp.top_of_search_pct,
    bp.avg_keyword_bid,
    bp.asin_ads_roas,
    bp.segment_verdict,
    bp.experiment_segment as winning_segment
  FROM `onyga-482313.OI.V_ASIN_BEST_PRACTICES` bp
  JOIN `onyga-482313.OI.DIM_PRODUCT` p_source ON bp.asin = p_source.asin
  JOIN `onyga-482313.OI.DIM_PRODUCT` p_target
    ON p_source.product_type = p_target.product_type
    AND p_source.asin != p_target.asin
  WHERE bp.segment_verdict IN ('STRONG_WIN', 'MODERATE_WIN')
),

-- =============================================
-- 4. All active strategies
-- =============================================
strategies AS (
  SELECT
    strategy_id,
    strategy_name,
    recommended_campaign_type,
    recommended_match_type,
    recommended_bidding_strategy,
    recommended_top_of_search_pct,
    recommended_bid_min,
    recommended_bid_max,
    recommended_daily_budget,
    season_applicability
  FROM `onyga-482313.OI.DIM_STRATEGY_TEMPLATE`
  WHERE is_active = TRUE
),

-- =============================================
-- 5. Products with SQP data
-- =============================================
active_products AS (
  SELECT DISTINCT
    seg.asin,
    p.product_short_name,
    p.product_type,
    p.parent_asin,
    p.listing_price_amount,
    p.launch_date,
    DATE_DIFF(CURRENT_DATE(), p.launch_date, DAY) as days_since_launch
  FROM `onyga-482313.OI.V_SEARCH_TERM_SEGMENT` seg
  JOIN `onyga-482313.OI.DIM_PRODUCT` p ON seg.asin = p.asin
  WHERE p.asin IS NOT NULL AND p.asin != 'UNKNOWN'
),

-- =============================================
-- 6. Map strategy to experiment_segment
--    experiment_segment values: BRAND, PRODUCT, ACTIVITY, BIRTHDAY_KIDS, BIRTHDAY_TEEN,
--    BIRTHDAY_GENERAL, CHRISTMAS, EASTER, VALENTINES, BACK_TO_SCHOOL, GRADUATION,
--    GIFT_KIDS, GIFT_TEEN, GIFT_GENERAL
-- =============================================
strategy_segment_map AS (
  -- BRAND segment (your brand/product name searches): defense strategies
  SELECT 'BRAND_DEFENSE' as strategy_id, 'BRAND' as target_segment UNION ALL
  SELECT 'PRODUCT_DEFENSE', 'BRAND' UNION ALL

  -- PRODUCT segment (product-type matches, not brand searches): retargeting
  SELECT 'RETARGETING', 'PRODUCT' UNION ALL

  -- ACTIVITY segment (sleepover, party): exact + discovery
  SELECT 'EXACT_BOOST', 'ACTIVITY' UNION ALL
  SELECT 'TOS_DOMINATION', 'ACTIVITY' UNION ALL
  SELECT 'LOW_COST_DISCOVERY', 'ACTIVITY' UNION ALL

  -- BIRTHDAY_KIDS: proven high-intent, core audience
  SELECT 'EXACT_BOOST', 'BIRTHDAY_KIDS' UNION ALL
  SELECT 'TOS_DOMINATION', 'BIRTHDAY_KIDS' UNION ALL

  -- BIRTHDAY_TEEN: test audience for birthday terms
  SELECT 'EXACT_BOOST', 'BIRTHDAY_TEEN' UNION ALL
  SELECT 'TOS_DOMINATION', 'BIRTHDAY_TEEN' UNION ALL

  -- BIRTHDAY_GENERAL: discovery for birthday terms without age
  SELECT 'HUNTER', 'BIRTHDAY_GENERAL' UNION ALL
  SELECT 'LOW_COST_DISCOVERY', 'BIRTHDAY_GENERAL' UNION ALL

  -- SEASONAL occasions: push strategies during ramp-up windows
  SELECT 'SEASONAL_PUSH', 'CHRISTMAS' UNION ALL
  SELECT 'SEASONAL_PUSH', 'EASTER' UNION ALL
  SELECT 'SEASONAL_PUSH', 'VALENTINES' UNION ALL
  SELECT 'SEASONAL_PUSH', 'BACK_TO_SCHOOL' UNION ALL
  SELECT 'SEASONAL_PUSH', 'GRADUATION' UNION ALL

  -- GIFT_KIDS: general gift shoppers looking for kids
  SELECT 'EXACT_BOOST', 'GIFT_KIDS' UNION ALL
  SELECT 'TOS_DOMINATION', 'GIFT_KIDS' UNION ALL

  -- GIFT_TEEN: general gift shoppers looking for teens
  SELECT 'EXACT_BOOST', 'GIFT_TEEN' UNION ALL
  SELECT 'TOS_DOMINATION', 'GIFT_TEEN' UNION ALL

  -- GIFT_GENERAL: broad discovery for generic gift terms
  SELECT 'HUNTER', 'GIFT_GENERAL' UNION ALL
  SELECT 'LOW_COST_DISCOVERY', 'GIFT_GENERAL' UNION ALL
  SELECT 'CATEGORY_CONQUEST', 'GIFT_GENERAL' UNION ALL
  SELECT 'CATEGORY_CONQUEST', 'GIFT_KIDS' UNION ALL

  -- NEW_LAUNCH: applies to all segments (filtered by product age in scoring)
  SELECT 'NEW_LAUNCH', 'BRAND' UNION ALL
  SELECT 'NEW_LAUNCH', 'PRODUCT' UNION ALL
  SELECT 'NEW_LAUNCH', 'ACTIVITY' UNION ALL
  SELECT 'NEW_LAUNCH', 'BIRTHDAY_KIDS' UNION ALL
  SELECT 'NEW_LAUNCH', 'BIRTHDAY_TEEN' UNION ALL
  SELECT 'NEW_LAUNCH', 'BIRTHDAY_GENERAL' UNION ALL
  SELECT 'NEW_LAUNCH', 'GIFT_KIDS' UNION ALL
  SELECT 'NEW_LAUNCH', 'GIFT_TEEN' UNION ALL
  SELECT 'NEW_LAUNCH', 'GIFT_GENERAL' UNION ALL
  SELECT 'NEW_LAUNCH', 'CHRISTMAS' UNION ALL
  SELECT 'NEW_LAUNCH', 'EASTER' UNION ALL
  SELECT 'NEW_LAUNCH', 'VALENTINES' UNION ALL
  SELECT 'NEW_LAUNCH', 'BACK_TO_SCHOOL' UNION ALL
  SELECT 'NEW_LAUNCH', 'GRADUATION'
),

-- =============================================
-- 7. Generate suggestions: cross-join products x strategies, then score
-- =============================================
raw_suggestions AS (
  SELECT
    ap.asin,
    ap.product_short_name,
    ap.product_type,
    ap.listing_price_amount,
    ap.days_since_launch,
    s.strategy_id,
    s.strategy_name,
    ssm.target_segment as target_experiment_segment,
    s.recommended_campaign_type,
    s.recommended_match_type,
    s.recommended_bidding_strategy,
    s.recommended_top_of_search_pct,
    s.recommended_bid_min,
    s.recommended_bid_max,
    s.recommended_daily_budget,
    s.season_applicability,
    cs.is_peak_season,
    cs.current_holiday,
    cs.next_peak_starts,
    cs.next_holiday_name,
    -- Opportunity data for this ASIN + target segment
    aso.term_count,
    aso.total_market_weekly_orders,
    aso.avg_your_orders_share_pct,
    aso.addressable_weekly_orders,
    aso.top_opportunity_terms,
    aso.avg_your_conversion_rate_pct,
    aso.avg_ads_conversion_rate_pct,
    aso.proven_term_count,
    aso.high_volume_unproven_count,
    aso.avg_amazon_conversion_rate_pct,
    -- Already tried?
    ee.experiment_id as existing_experiment_id,
    ee.status as existing_experiment_status,
    -- Sibling win?
    sw.source_experiment_id as sibling_experiment_id,
    sw.source_asin as sibling_asin,
    sw.asin_ads_roas as sibling_roas,

    -- =============================================
    -- PRIORITY SCORING
    -- =============================================
    (
      -- =========================================
      -- HALF 1: Market Opportunity (capped at 500)
      -- Log-scaled so market size cannot dominate
      -- =========================================
      LEAST(
        LN(GREATEST(COALESCE(aso.addressable_weekly_orders, 0), 1)) * 50,
        500
      )

      -- =========================================
      -- HALF 2: Conversion Proof (up to ~500)
      -- =========================================
      -- Best conversion rate (your organic or ads), scaled 0-200
      + LEAST(
          GREATEST(
            COALESCE(aso.avg_your_conversion_rate_pct, 0),
            COALESCE(aso.avg_ads_conversion_rate_pct, 0)
          ) * 30,
          200
        )

      -- Proven term count: each proven term = 40 pts, cap at 5 = 200
      + LEAST(COALESCE(aso.proven_term_count, 0) * 40, 200)

      -- Conversion rate vs amazon baseline
      + CASE
          WHEN COALESCE(aso.avg_amazon_conversion_rate_pct, 0) > 0
            AND GREATEST(
                  COALESCE(aso.avg_your_conversion_rate_pct, 0),
                  COALESCE(aso.avg_ads_conversion_rate_pct, 0)
                ) >= aso.avg_amazon_conversion_rate_pct
          THEN 100  -- Converting at or above market rate
          WHEN GREATEST(
                 COALESCE(aso.avg_your_conversion_rate_pct, 0),
                 COALESCE(aso.avg_ads_conversion_rate_pct, 0)
               ) > 0
          THEN 50   -- Any conversion at all
          ELSE 0    -- Zero conversions
        END

      -- =========================================
      -- BOOSTS & PENALTIES (tiebreakers + filters)
      -- =========================================

      -- Boost: BRAND terms (brand/product name searches) with low defense = urgent
      + CASE WHEN ssm.target_segment = 'BRAND' AND COALESCE(aso.avg_your_orders_share_pct, 0) < 50 THEN 100 ELSE 0 END

      -- Boost: high-intent age-targeted segments with large addressable market
      + CASE WHEN ssm.target_segment IN ('BIRTHDAY_KIDS', 'GIFT_KIDS', 'BIRTHDAY_TEEN', 'GIFT_TEEN')
             AND COALESCE(aso.addressable_weekly_orders, 0) > 50 THEN 50 ELSE 0 END

      -- Boost: strategy proven on sibling ASIN
      + CASE WHEN sw.source_experiment_id IS NOT NULL THEN 75 ELSE 0 END

      -- Boost: strategy never tried for this ASIN
      + CASE WHEN ee.experiment_id IS NULL THEN 25 ELSE 0 END

      -- Penalty: strategy already tried and active
      - CASE WHEN ee.status = 'ACTIVE' THEN 200 ELSE 0 END

      -- Penalty: strategy already tried and completed
      - CASE WHEN ee.status = 'COMPLETED' THEN 50 ELSE 0 END

      -- Penalty: no market data for this segment
      - CASE WHEN aso.term_count IS NULL OR aso.term_count = 0 THEN 500 ELSE 0 END

      -- Season-awareness penalties/boosts
      -- PEAK_ONLY: eliminate when not in peak season
      - CASE WHEN s.season_applicability = 'PEAK_ONLY' AND NOT cs.is_peak_season THEN 99999 ELSE 0 END
      -- PEAK_PREFERRED: mild penalty when not in peak season
      - CASE WHEN s.season_applicability = 'PEAK_PREFERRED' AND NOT cs.is_peak_season THEN 150 ELSE 0 END
      -- OFF_SEASON_PREFERRED: boost when off-season, penalty when peak
      + CASE WHEN s.season_applicability = 'OFF_SEASON_PREFERRED' AND NOT cs.is_peak_season THEN 50 ELSE 0 END
      - CASE WHEN s.season_applicability = 'OFF_SEASON_PREFERRED' AND cs.is_peak_season THEN 150 ELSE 0 END
      -- PEAK_ONLY: boost when in peak season
      + CASE WHEN s.season_applicability = 'PEAK_ONLY' AND cs.is_peak_season THEN 100 ELSE 0 END
      -- PEAK_PREFERRED: boost when in peak season
      + CASE WHEN s.season_applicability = 'PEAK_PREFERRED' AND cs.is_peak_season THEN 50 ELSE 0 END

      -- NEW_LAUNCH: only for products launched within last 90 days
      - CASE WHEN s.strategy_id = 'NEW_LAUNCH'
             AND (ap.days_since_launch IS NULL OR ap.days_since_launch > 90)
             THEN 99999 ELSE 0 END
      -- NEW_LAUNCH: boost for genuinely new products
      + CASE WHEN s.strategy_id = 'NEW_LAUNCH'
             AND ap.days_since_launch IS NOT NULL AND ap.days_since_launch <= 90
             THEN 200 ELSE 0 END

      -- EXACT_BOOST: boost when ASIN has proven terms (3+ orders, 2+ weeks, big market)
      + CASE WHEN s.strategy_id = 'EXACT_BOOST'
             AND COALESCE(aso.proven_term_count, 0) >= 2
             THEN 100 + LEAST(COALESCE(aso.proven_term_count, 0) * 10, 50)  -- Up to +150
             ELSE 0 END
      -- EXACT_BOOST: bonus for high-intent segment (high amazon conversion)
      + CASE WHEN s.strategy_id = 'EXACT_BOOST'
             AND COALESCE(aso.avg_amazon_conversion_rate_pct, 0) > 8
             THEN 30 ELSE 0 END
      -- EXACT_BOOST: penalty if ASIN has no proven terms (not yet earned)
      - CASE WHEN s.strategy_id = 'EXACT_BOOST'
             AND COALESCE(aso.proven_term_count, 0) = 0
             THEN 200 ELSE 0 END

      -- LOW_COST_DISCOVERY: boost when many high-volume unproven terms exist
      + CASE WHEN s.strategy_id = 'LOW_COST_DISCOVERY'
             AND COALESCE(aso.high_volume_unproven_count, 0) >= 3
             THEN 75 + LEAST(COALESCE(aso.high_volume_unproven_count, 0) * 5, 50)  -- Up to +125
             ELSE 0 END
      -- LOW_COST_DISCOVERY: penalty if ASIN already has many proven terms (use EXACT_BOOST instead)
      - CASE WHEN s.strategy_id = 'LOW_COST_DISCOVERY'
             AND COALESCE(aso.proven_term_count, 0) >= 5
             THEN 100 ELSE 0 END

      -- BRAND_DEFENSE / PRODUCT_DEFENSE: only the hero ASIN (highest brand share) should run defense
      - CASE WHEN s.strategy_id IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE')
             AND COALESCE(bh.brand_rank, 999) > 1
             THEN 99999 ELSE 0 END
    ) as priority_score

  FROM active_products ap
  CROSS JOIN strategies s
  CROSS JOIN current_season cs
  JOIN strategy_segment_map ssm ON s.strategy_id = ssm.strategy_id
  LEFT JOIN asin_segment_opportunity aso
    ON ap.asin = aso.asin AND ssm.target_segment = aso.experiment_segment
  LEFT JOIN existing_experiments ee
    ON ap.asin = ee.asin AND s.strategy_id = ee.strategy_id
  LEFT JOIN (
    -- Pick best sibling win per target_asin + strategy
    SELECT DISTINCT
      target_asin, strategy_id, source_experiment_id, source_asin, asin_ads_roas,
      ROW_NUMBER() OVER (PARTITION BY target_asin, strategy_id ORDER BY asin_ads_roas DESC) as rn
    FROM sibling_wins
  ) sw ON ap.asin = sw.target_asin AND s.strategy_id = sw.strategy_id AND sw.rn = 1
  LEFT JOIN brand_hero bh ON ap.asin = bh.asin AND ssm.target_segment = 'BRAND'
)

SELECT
  -- Keys
  CONCAT(rs.asin, '|', rs.strategy_id, '|', rs.target_experiment_segment) as row_key,
  CONCAT(rs.asin, '|', rs.target_experiment_segment) as asin_segment_key,
  -- Ready-to-use experiment ID: copy-paste into DIM_EXPERIMENT and DIM_EXPERIMENT_CAMPAIGN
  CONCAT(
    UPPER(REPLACE(rs.product_short_name, ' ', '_')),
    '_', rs.strategy_id,
    '_', rs.target_experiment_segment
  ) as suggested_experiment_id,

  rs.asin,
  rs.product_short_name,
  rs.product_type,
  rs.listing_price_amount,
  rs.strategy_id as suggested_strategy_id,
  rs.strategy_name as suggested_strategy_name,
  rs.target_experiment_segment,
  rs.recommended_campaign_type as suggested_campaign_type,
  rs.recommended_match_type as suggested_match_type,
  rs.recommended_bidding_strategy as suggested_bidding_strategy,
  rs.recommended_top_of_search_pct as suggested_tos_pct,
  rs.recommended_bid_min as suggested_bid_min,
  rs.recommended_bid_max as suggested_bid_max,
  rs.recommended_daily_budget as suggested_daily_budget,
  ROUND(rs.priority_score, 0) as priority_score,

  -- Season context
  rs.is_peak_season,
  rs.current_holiday,
  rs.next_peak_starts,
  rs.next_holiday_name,
  rs.season_applicability,

  -- Opportunity context
  COALESCE(rs.term_count, 0) as target_term_count,
  COALESCE(rs.total_market_weekly_orders, 0) as target_market_weekly_orders,
  COALESCE(rs.avg_your_orders_share_pct, 0) as current_orders_share_pct,
  COALESCE(rs.addressable_weekly_orders, 0) as addressable_weekly_orders,
  -- Conversion proof metrics (non-holiday baseline)
  COALESCE(rs.avg_your_conversion_rate_pct, 0) as avg_your_conversion_rate_pct,
  COALESCE(rs.avg_ads_conversion_rate_pct, 0) as avg_ads_conversion_rate_pct,
  COALESCE(rs.proven_term_count, 0) as proven_term_count,
  COALESCE(rs.high_volume_unproven_count, 0) as high_volume_unproven_count,
  COALESCE(rs.avg_amazon_conversion_rate_pct, 0) as avg_amazon_conversion_rate_pct,
  rs.top_opportunity_terms,

  -- Learning context
  rs.existing_experiment_id,
  rs.existing_experiment_status,
  rs.sibling_experiment_id as learned_from_experiment_id,
  rs.sibling_asin as learned_from_asin,
  rs.sibling_roas as sibling_proven_roas,

  -- Reason summary
  CONCAT(
    CASE WHEN rs.season_applicability = 'PEAK_ONLY' AND NOT rs.is_peak_season THEN 'OFF_SEASON(next_peak=' || COALESCE(CAST(rs.next_peak_starts AS STRING), '?') || ' ' || COALESCE(rs.next_holiday_name, '') || ') ' ELSE '' END,
    CASE WHEN rs.season_applicability = 'PEAK_ONLY' AND rs.is_peak_season THEN 'PEAK_SEASON(' || COALESCE(rs.current_holiday, '') || ') ' ELSE '' END,
    CASE WHEN rs.season_applicability = 'PEAK_PREFERRED' AND rs.is_peak_season THEN 'PEAK_BOOST(' || COALESCE(rs.current_holiday, '') || ') ' ELSE '' END,
    CASE WHEN rs.existing_experiment_id IS NOT NULL THEN 'ALREADY_TRIED(' || rs.existing_experiment_status || ') ' ELSE '' END,
    CASE WHEN rs.sibling_experiment_id IS NOT NULL THEN 'SIBLING_WIN(ROAS=' || CAST(ROUND(rs.sibling_roas, 1) AS STRING) || ') ' ELSE '' END,
    CASE WHEN rs.target_experiment_segment = 'BRAND' AND COALESCE(rs.avg_your_orders_share_pct, 0) < 50 THEN 'LOW_BRAND_DEFENSE ' ELSE '' END,
    CASE WHEN COALESCE(rs.addressable_weekly_orders, 0) > 100 THEN 'HIGH_OPPORTUNITY(' || CAST(CAST(rs.addressable_weekly_orders AS INT64) AS STRING) || '/wk) ' ELSE '' END,
    CASE WHEN COALESCE(rs.addressable_weekly_orders, 0) > 0 AND COALESCE(rs.addressable_weekly_orders, 0) <= 100 THEN 'MODERATE_OPPORTUNITY(' || CAST(CAST(rs.addressable_weekly_orders AS INT64) AS STRING) || '/wk) ' ELSE '' END
  ) as reason

FROM raw_suggestions rs
WHERE rs.priority_score > -100  -- Filter out clearly bad suggestions
ORDER BY rs.asin, rs.priority_score DESC;
