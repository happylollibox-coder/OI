-- =============================================
-- OI Database Project - V_EXPERIMENT_TERM_RECOMMENDATIONS View
-- =============================================
--
-- Purpose: Per search term, per ASIN, per strategy: should you START, KEEP, or STOP?
--          Includes HERO ASIN context: is the advertised child the best one for this term?
--
-- Two sections (recommendation_type):
--   ACTIVE_TERM: terms currently targeted by experiment campaigns
--     → signals: KEEP, STOP, REDUCE_BID, PROMOTE_TO_EXACT, MONITOR
--   OPPORTUNITY: SQP terms with purchases NOT targeted by any experiment
--     → signal: START (with hero_asin = which child to advertise)
--
-- Hero ASIN columns:
--   hero_asin          = the child with highest organic potential for this term
--   hero_product_name  = human-readable name
--   hero_score         = blended_cvr × sqp_ctr × margin / 10000
--   is_hero_match      = TRUE if you're already advertising the hero
--
-- Dependencies:
--   DIM_EXPERIMENT, DIM_EXPERIMENT_CAMPAIGN, DIM_STRATEGY_TEMPLATE,
--   FACT_AMAZON_ADS, FACT_SEARCH_QUERY,
--   DIM_PRODUCT, DIM_COSTS_HISTORY, V_SEARCH_TERM_SEGMENT,
--   V_PARENT_HERO_ASIN
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_EXPERIMENT_TERM_RECOMMENDATIONS`
AS
WITH
-- =============================================
-- Unit economics per ASIN
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
),

active_experiments AS (
  SELECT
    e.experiment_id,
    e.experiment_name,
    e.strategy_id,
    e.start_date,
    st.strategy_name
  FROM `onyga-482313.OI.DIM_EXPERIMENT` e
  LEFT JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st ON e.strategy_id = st.strategy_id
  WHERE e.status = 'ACTIVE'
),

-- =============================================
-- Hero ASIN per search term (GLOBAL cross-parent ranking)
-- Ranked by Net ROAS, gated by ≥4 orders AND ROAS ≥ 1.0
-- =============================================
term_hero AS (
  SELECT
    search_term,
    parent_name as hero_parent_name,
    asin as hero_asin,
    product_short_name as hero_product_name,
    hero_score,
    sqp_cvr_pct as hero_sqp_cvr_pct,
    ads_cvr_pct as hero_ads_cvr_pct,
    ads_net_roas as hero_net_roas,
    total_orders as hero_total_orders,
    ads_ctr_pct as hero_ads_ctr_pct,
    confidence as hero_confidence
  FROM `onyga-482313.OI.V_PARENT_HERO_ASIN`
  WHERE global_hero_rank = 1
    AND qualifies_as_hero = TRUE
),

-- =============================================
-- SECTION A: ACTIVE TERMS
-- Ads performance per search term for experiment campaigns (60-day window)
-- =============================================
experiment_term_ads AS (
  SELECT
    ec.experiment_id,
    ec.campaign_id,
    fa.campaign_name,
    COALESCE(fa.campaign_type, 'SP') as campaign_type,
    'Unassigned' as portfolio_name,
    ae.strategy_id,
    ae.strategy_name,
    ae.start_date,
    fa.advertised_asins as asin,
    LOWER(fa.search_term) as search_term,
    -- Pick latest ad_group_id for this campaign×term (SP campaigns typically have 1 ad group)
    ANY_VALUE(fa.ad_group_id HAVING MAX fa.date) as ad_group_id,
    SUM(fa.Ads_cost) as ads_spend,
    SUM(fa.Ads_orders) as ads_orders,
    SUM(fa.Ads_units) as ads_units,
    SUM(fa.Ads_clicks) as ads_clicks,
    SUM(CASE WHEN fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 5 DAY) THEN fa.Ads_clicks ELSE 0 END) as ads_clicks_recent,
    SUM(fa.Ads_impressions) as ads_impressions,
    SUM(fa.Ads_sales) as ads_revenue,
    COUNT(DISTINCT fa.date) as days_with_data,
    MIN(fa.date) as first_seen,
    MAX(fa.date) as last_seen
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN active_experiments ae ON ec.experiment_id = ae.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON ec.campaign_id = fa.campaign_id
    AND fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)


  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
    AND fa.advertised_asins IS NOT NULL
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
),

-- =============================================
-- Short-window aggregates for weighted ROAS
-- Excluding last 3 days (attribution lag)
-- =============================================
ads_1w AS (
  SELECT
    ec.experiment_id,
    ec.campaign_id,
    fa.advertised_asins as asin,
    LOWER(fa.search_term) as search_term,
    SUM(fa.Ads_cost) as spend_1w,
    SUM(fa.Ads_orders) as orders_1w,
    SUM(fa.Ads_clicks) as clicks_1w
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN active_experiments ae ON ec.experiment_id = ae.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON ec.campaign_id = fa.campaign_id
    AND fa.date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 10 DAY)
                     AND DATE_SUB(CURRENT_DATE(), INTERVAL 4 DAY)
  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
    AND fa.advertised_asins IS NOT NULL
  GROUP BY 1, 2, 3, 4
),

ads_4w AS (
  SELECT
    ec.experiment_id,
    ec.campaign_id,
    fa.advertised_asins as asin,
    LOWER(fa.search_term) as search_term,
    SUM(fa.Ads_cost) as spend_4w,
    SUM(fa.Ads_orders) as orders_4w,
    SUM(fa.Ads_clicks) as clicks_4w
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN active_experiments ae ON ec.experiment_id = ae.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON ec.campaign_id = fa.campaign_id
    AND fa.date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 31 DAY)
                     AND DATE_SUB(CURRENT_DATE(), INTERVAL 4 DAY)
  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
    AND fa.advertised_asins IS NOT NULL
  GROUP BY 1, 2, 3, 4
),

sqp_recent AS (
  SELECT
    LOWER(fsq.query_text) as search_term,
    fsq.ASIN as asin,
    SUM(fsq.conversions) as sqp_purchases,
    SUM(fsq.clicks) as sqp_clicks,
    SUM(fsq.impressions) as sqp_impressions,
    COUNT(DISTINCT fsq.week_end_date) as sqp_weeks,
    ROUND(AVG(fsq.estimated_organic_rank), 1) as sqp_organic_rank,
    ROUND(AVG(fsq.search_query_volume), 0) as sqp_search_volume
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
  WHERE fsq.data_source = 'SQP'
    AND fsq.week_end_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 56 DAY)
  GROUP BY 1, 2
),

-- SQP 1-week window (matches ads_1w date range for weighted ROAS)
sqp_1w AS (
  SELECT
    LOWER(fsq.query_text) as search_term,
    fsq.ASIN as asin,
    SUM(fsq.conversions) as sqp_purchases_1w
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
  WHERE fsq.data_source = 'SQP'
    AND fsq.week_end_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 10 DAY)
    AND fsq.week_end_date <= DATE_SUB(CURRENT_DATE(), INTERVAL 4 DAY)
  GROUP BY 1, 2
),

-- SQP 4-week window (matches ads_4w date range for weighted ROAS)
sqp_4w AS (
  SELECT
    LOWER(fsq.query_text) as search_term,
    fsq.ASIN as asin,
    SUM(fsq.conversions) as sqp_purchases_4w
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
  WHERE fsq.data_source = 'SQP'
    AND fsq.week_end_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 31 DAY)
    AND fsq.week_end_date <= DATE_SUB(CURRENT_DATE(), INTERVAL 4 DAY)
  GROUP BY 1, 2
),

term_classification AS (
  SELECT
    LOWER(search_term) as search_term,
    asin,
    experiment_segment,
    intent_segment,
    occasion,
    amazon_avg_weekly_orders,
    your_orders_share_pct,
    is_best_asin_for_term
  FROM `onyga-482313.OI.V_SEARCH_TERM_SEGMENT`
),

-- Today's occasion peak phases (single row from DIM_TIME)
today_phases AS (
  SELECT
    occasion_valentines_phase,
    occasion_easter_phase,
    occasion_christmas_phase,
    occasion_back_to_school_phase
  FROM `onyga-482313.OI.DIM_TIME`
  WHERE full_date = CURRENT_DATE()
),

-- Terms already targeted by exact or brand defense campaigns
-- These should NOT be promoted again
-- EXACT_BOOST: block all terms (already exact-targeted)
-- BRAND_DEFENSE: block only terms containing brand keywords
already_targeted_exact AS (
  SELECT DISTINCT LOWER(fa.search_term) as search_term
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.DIM_EXPERIMENT` e ON ec.experiment_id = e.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec.campaign_id = fa.campaign_id
  WHERE e.status = 'ACTIVE'
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND (
      e.strategy_id = 'EXACT_BOOST'
      OR (
        e.strategy_id = 'BRAND_DEFENSE'
        AND (
          LOWER(fa.search_term) LIKE '%happy lolli%'
          OR LOWER(fa.search_term) LIKE '%lollibox%'
          OR LOWER(fa.search_term) LIKE '%lollime%'
          OR LOWER(fa.search_term) LIKE '%lolli box%'
          OR LOWER(fa.search_term) LIKE '%lolli me%'
        )
      )
    )
),

-- Campaign configuration from bulksheet (latest snapshot)
-- Provides: current keyword bids, ad group default bids, placement adjustments
campaign_config AS (
  SELECT
    k.campaign_id,
    LOWER(k.keyword_text) as keyword_text,
    k.bid as keyword_bid,
    k.match_type as keyword_match_type,
    ag.ad_group_default_bid,
    ba.top_of_search_pct,
    ba.product_page_pct,
    ba.rest_of_search_pct,
    ba.amazon_business_pct
  FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG` k
  LEFT JOIN (
    SELECT campaign_id, ad_group_default_bid
    FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`
    WHERE entity_type = 'AD_GROUP'
      AND snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`)
  ) ag ON k.campaign_id = ag.campaign_id
  LEFT JOIN (
    SELECT campaign_id,
      MAX(CASE WHEN placement = 'Placement Top' THEN placement_percentage END) as top_of_search_pct,
      MAX(CASE WHEN placement = 'Placement Product Page' THEN placement_percentage END) as product_page_pct,
      MAX(CASE WHEN placement = 'Placement Rest Of Search' THEN placement_percentage END) as rest_of_search_pct,
      MAX(CASE WHEN placement = 'Placement Amazon Business' THEN placement_percentage END) as amazon_business_pct
    FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`
    WHERE entity_type = 'BIDDING_ADJUSTMENT'
      AND snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`)
    GROUP BY 1
  ) ba ON k.campaign_id = ba.campaign_id
  WHERE k.entity_type = 'KEYWORD'
    AND k.snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`)
),

-- Ad group default bids for auto campaigns (no keyword entity)
campaign_config_ag AS (
  SELECT
    ag.campaign_id,
    ag.ad_group_default_bid,
    ba.top_of_search_pct,
    ba.product_page_pct,
    ba.rest_of_search_pct,
    ba.amazon_business_pct
  FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG` ag
  LEFT JOIN (
    SELECT campaign_id,
      MAX(CASE WHEN placement = 'Placement Top' THEN placement_percentage END) as top_of_search_pct,
      MAX(CASE WHEN placement = 'Placement Product Page' THEN placement_percentage END) as product_page_pct,
      MAX(CASE WHEN placement = 'Placement Rest Of Search' THEN placement_percentage END) as rest_of_search_pct,
      MAX(CASE WHEN placement = 'Placement Amazon Business' THEN placement_percentage END) as amazon_business_pct
    FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`
    WHERE entity_type = 'BIDDING_ADJUSTMENT'
      AND snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`)
    GROUP BY 1
  ) ba ON ag.campaign_id = ba.campaign_id
  WHERE ag.entity_type = 'AD_GROUP'
    AND ag.snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`)
),

-- Negative keywords blacklist per campaign (ad-group + campaign level)
campaign_negatives AS (
  SELECT
    campaign_id,
    LOWER(keyword_text) as neg_keyword
  FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`
  WHERE entity_type IN ('NEGATIVE_KEYWORD', 'CAMPAIGN_NEGATIVE_KEYWORD')
    AND snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`)
),

-- Auto-targeting bids per campaign (close-match, substitutes, etc.)
campaign_auto_bids AS (
  SELECT
    campaign_id,
    MAX(CASE WHEN product_targeting_expression = 'close-match' THEN pt_bid END) as close_match_bid,
    MAX(CASE WHEN product_targeting_expression = 'loose-match' THEN pt_bid END) as loose_match_bid,
    MAX(CASE WHEN product_targeting_expression = 'substitutes' THEN pt_bid END) as substitutes_bid,
    MAX(CASE WHEN product_targeting_expression = 'complements' THEN pt_bid END) as complements_bid
  FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`
  WHERE entity_type = 'PRODUCT_TARGETING'
    AND snapshot_date = (SELECT MAX(snapshot_date) FROM `onyga-482313.OI.FACT_CAMPAIGN_CONFIG`)
  GROUP BY 1
),

active_term_rows AS (
  SELECT
    'ACTIVE_TERM' as recommendation_type,
    eta.experiment_id,
    eta.campaign_id,
    eta.ad_group_id,
    eta.campaign_name,
    eta.campaign_type,
    eta.portfolio_name,
    eta.strategy_id,
    eta.strategy_name,
    eta.asin,
    ue.product_short_name,
    eta.search_term,

    -- Current bid from bulksheet config
    COALESCE(cc.keyword_bid, ccag.ad_group_default_bid) as current_bid,
    ccag.ad_group_default_bid,
    COALESCE(cc.top_of_search_pct, ccag.top_of_search_pct, 0) as top_of_search_pct,
    COALESCE(cc.product_page_pct, ccag.product_page_pct, 0) as product_page_pct,
    COALESCE(cc.rest_of_search_pct, ccag.rest_of_search_pct, 0) as rest_of_search_pct,
    COALESCE(cc.amazon_business_pct, ccag.amazon_business_pct, 0) as amazon_business_pct,

    -- Blacklist: is this search term already a negative keyword in this campaign?
    CASE WHEN cn.neg_keyword IS NOT NULL THEN TRUE ELSE FALSE END as is_negated,
    -- Exact targeting: does this term already have an EXACT_BOOST or BRAND_DEFENSE campaign?
    CASE WHEN ate.search_term IS NOT NULL THEN TRUE ELSE FALSE END as has_exact_targeting,

    -- Auto-targeting bids (for auto campaigns)
    cab.close_match_bid,
    cab.loose_match_bid,
    cab.substitutes_bid,
    cab.complements_bid,

    ROUND(eta.ads_spend, 2) as ads_spend,
    eta.ads_orders,
    eta.ads_units,
    eta.ads_clicks,
    eta.ads_clicks_recent,
    eta.ads_impressions,
    ROUND(SAFE_DIVIDE(eta.ads_spend, NULLIF(eta.ads_clicks, 0)), 2) as cpc,
    ROUND(SAFE_DIVIDE(eta.ads_orders, NULLIF(eta.ads_clicks, 0)) * 100, 2) as ads_cvr_pct,
    ROUND(SAFE_DIVIDE(eta.ads_spend, NULLIF(eta.ads_orders, 0)), 2) as cost_per_order,

    ROUND(ue.margin_per_unit, 2) as margin_per_unit,
    ROUND(eta.ads_orders * ue.margin_per_unit, 2) as ads_gross_margin,
    ROUND(eta.ads_orders * ue.margin_per_unit - eta.ads_spend, 2) as ads_net_profit,
    ROUND(SAFE_DIVIDE(eta.ads_orders * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)), 2) as ads_net_roas,

    -- ══════════════════════════════════════════
    -- Weighted Total Net ROAS (THE single metric for all decisions)
    -- = time-weighted (ads + organic) margin / spend
    -- Each window: total_orders_Nw = ads_orders_Nw + MAX(0, sqp_purchases_Nw - ads_orders_Nw)
    -- Recency factors: 1w=0.5, 4w=0.3, 8w=0.2
    -- Click-weighted: high-volume weeks get more influence
    -- ══════════════════════════════════════════
    ROUND(
      CASE
        WHEN eta.ads_spend < 5 THEN NULL
        -- Age-aware: < 14 days → use 1w at 100%
        WHEN eta.days_with_data < 14 AND COALESCE(a1.spend_1w, 0) > 0 THEN
          SAFE_DIVIDE(
            (COALESCE(a1.orders_1w, 0) + GREATEST(0, COALESCE(s1.sqp_purchases_1w, 0) - COALESCE(a1.orders_1w, 0))) * ue.margin_per_unit,
            a1.spend_1w
          )
        -- Age-aware: 14-28 days → hybrid 1w + 8w
        WHEN eta.days_with_data < 28 AND COALESCE(a1.spend_1w, 0) > 0 THEN
          SAFE_DIVIDE(
            SAFE_DIVIDE(
              (COALESCE(a1.orders_1w, 0) + GREATEST(0, COALESCE(s1.sqp_purchases_1w, 0) - COALESCE(a1.orders_1w, 0))) * ue.margin_per_unit,
              a1.spend_1w
            ) * 0.5 * COALESCE(a1.clicks_1w, 0)
            + SAFE_DIVIDE(
              (eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit,
              eta.ads_spend
            ) * 0.2 * eta.ads_clicks,
            NULLIF(0.5 * COALESCE(a1.clicks_1w, 0) + 0.2 * eta.ads_clicks, 0)
          )
        -- Mature: >= 28 days → full 3-window hybrid
        ELSE
          SAFE_DIVIDE(
            CASE WHEN COALESCE(a1.spend_1w, 0) > 0 THEN
              SAFE_DIVIDE(
                (COALESCE(a1.orders_1w, 0) + GREATEST(0, COALESCE(s1.sqp_purchases_1w, 0) - COALESCE(a1.orders_1w, 0))) * ue.margin_per_unit,
                a1.spend_1w
              ) * 0.5 * COALESCE(a1.clicks_1w, 0)
            ELSE 0 END
            + CASE WHEN COALESCE(a4.spend_4w, 0) > 0 THEN
              SAFE_DIVIDE(
                (COALESCE(a4.orders_4w, 0) + GREATEST(0, COALESCE(s4.sqp_purchases_4w, 0) - COALESCE(a4.orders_4w, 0))) * ue.margin_per_unit,
                a4.spend_4w
              ) * 0.3 * COALESCE(a4.clicks_4w, 0)
            ELSE 0 END
            + SAFE_DIVIDE(
              (eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit,
              eta.ads_spend
            ) * 0.2 * eta.ads_clicks,
            NULLIF(
              CASE WHEN COALESCE(a1.spend_1w, 0) > 0 THEN 0.5 * COALESCE(a1.clicks_1w, 0) ELSE 0 END
              + CASE WHEN COALESCE(a4.spend_4w, 0) > 0 THEN 0.3 * COALESCE(a4.clicks_4w, 0) ELSE 0 END
              + 0.2 * eta.ads_clicks
            , 0)
          )
      END
    , 2) as weighted_total_net_roas,

    COALESCE(sqp.sqp_purchases, 0) as sqp_purchases,
    GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders) as sqp_organic_orders,
    COALESCE(sqp.sqp_clicks, 0) as sqp_clicks,
    COALESCE(sqp.sqp_impressions, 0) as sqp_impressions,
    COALESCE(sqp.sqp_weeks, 0) as sqp_weeks,
    COALESCE(sqp.sqp_organic_rank, 0) as sqp_organic_rank,
    COALESCE(sqp.sqp_search_volume, 0) as sqp_search_volume,

    tc.experiment_segment,
    tc.intent_segment,
    tc.occasion,
    -- Peak phase: map term's occasion → today's phase from DIM_TIME
    CASE tc.occasion
      WHEN 'VALENTINES' THEN tp.occasion_valentines_phase
      WHEN 'EASTER' THEN tp.occasion_easter_phase
      WHEN 'CHRISTMAS' THEN tp.occasion_christmas_phase
      WHEN 'BACK_TO_SCHOOL' THEN tp.occasion_back_to_school_phase
      ELSE 'ALWAYS_ON'  -- BIRTHDAY, SLEEPOVER, PARTY, etc. = no seasonal phase
    END as peak_phase,
    tc.amazon_avg_weekly_orders as market_weekly_orders,
    tc.your_orders_share_pct,
    COALESCE(tc.is_best_asin_for_term, FALSE) as is_best_asin_for_term,

    eta.days_with_data,
    eta.first_seen,
    eta.last_seen,

    CASE
      WHEN eta.ads_spend < 5 THEN 'INSUFFICIENT_DATA'
      WHEN eta.ads_orders = 0 AND GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders) = 0
        AND eta.ads_clicks >= 20 AND eta.ads_clicks_recent > 0 THEN 'WASTED_SPEND'
      WHEN eta.ads_orders = 0 AND GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders) > 0 THEN 'ORGANIC_ONLY'
      WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 1.5 THEN 'STRONG'
      WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 1.2 THEN 'PROFITABLE'
      WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 0.7 THEN 'MARGINAL'
      ELSE 'UNPROFITABLE'
    END as ads_signal,

    -- ══════════════════════════════════════════
    -- ACTION DECISION TREE
    -- Uses weighted_total_net_roas (ads+organic, time-weighted)
    -- Evaluated top-to-bottom, first match wins
    -- ══════════════════════════════════════════
    CASE
      -- R1: Skip defensive strategies
      WHEN eta.strategy_id IN ('PRODUCT_DEFENSE', 'BRAND_DEFENSE') THEN 'MONITOR'

      -- R2: Not enough data to decide
      WHEN eta.ads_spend < 5 THEN 'MONITOR'

      -- R3: Zero total orders + enough clicks = wasted spend → stop
      WHEN (eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) = 0
        AND eta.ads_clicks >= 20 AND eta.ads_clicks_recent > 0 THEN 'STOP'

      -- R4: EXACT_BOOST with < 20 clicks all-time → increase bid to gather data
      -- "I promoted this to exact. Give it 20 clicks before judging."
      WHEN eta.strategy_id = 'EXACT_BOOST'
        AND eta.ads_clicks < 20
        AND eta.ads_clicks_recent > 0
        THEN 'INCREASE_BID'

      -- R5: SWITCH_HERO — wrong ASIN in EXACT campaign
      -- Override INCREASE_BID/KEEP: switch product before scaling
      WHEN th.hero_asin IS NOT NULL
        AND COALESCE(eta.asin = th.hero_asin, FALSE) = FALSE
        AND eta.strategy_id = 'EXACT_BOOST'
        AND eta.ads_clicks >= 15
        THEN 'SWITCH_HERO'

      -- R6: PROMOTE from broad/auto → exact
      -- total_orders ≥ 4, weighted_total_net_roas ≥ 1.4, SQP volume > 1500, not already exact
      WHEN eta.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
        AND (eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) >= 4
        AND COALESCE(sqp.sqp_search_volume, 0) > 1500
        AND ate.search_term IS NULL THEN 'PROMOTE_TO_EXACT'

      -- R7: Organic-only PROMOTE — ads didn't convert but organic proves demand
      -- organic ≥ 3, SQP volume > 1500, not already exact
      WHEN eta.ads_orders = 0
        AND GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders) >= 3
        AND COALESCE(sqp.sqp_search_volume, 0) > 1500
        AND ate.search_term IS NULL
        THEN 'PROMOTE_TO_EXACT'

      -- R8: Strong ROAS + top organic rank ≤ 5 → KEEP (defend position, don't overbid)
      WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 1.5
        AND eta.ads_clicks >= 15
        AND COALESCE(sqp.sqp_organic_rank, 999) <= 5 THEN 'KEEP'

      -- R9: Strong ROAS → INCREASE_BID to scale winners
      WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 1.5
        AND eta.ads_clicks >= 15 THEN 'INCREASE_BID'

      -- R10: Profitable (≥ 1.2x) → KEEP
      WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 1.2 THEN 'KEEP'

      -- R11: Heavy loss (< 0.5x) + enough data → STOP
      WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) < 0.5
        AND eta.ads_clicks >= 20 AND eta.ads_clicks_recent > 0 THEN 'STOP'

      -- R12: Below profitability (< 1.2x) + enough data → REDUCE_BID
      WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) < 1.2
        AND eta.ads_clicks >= 15 AND eta.ads_clicks_recent > 0 THEN 'REDUCE_BID'

      ELSE 'MONITOR'
    END as action,

    -- 🛡️ Top-of-page defense flag
    CASE
      WHEN COALESCE(sqp.sqp_organic_rank, 0) > 0 AND COALESCE(sqp.sqp_organic_rank, 999) <= 5 THEN TRUE
      ELSE FALSE
    END as is_top_of_page_organic,

    -- Decision Trace: JSON array capturing each check step for frontend rendering
    -- The frontend renders this directly — no re-simulation needed
    TO_JSON_STRING([
      STRUCT(
        'confidence_volume' as id,
        'Confidence Volume Check' as label,
        'Clicks >= 20' as rule,
        (eta.ads_clicks >= 20) as pass,
        CONCAT(CAST(eta.ads_clicks AS STRING), ' Clicks') as value
      ),
      STRUCT(
        'wasted_spend' as id,
        'Has Conversions' as label,
        'Orders > 0' as rule,
        (eta.ads_orders > 0 OR GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders) > 0) as pass,
        CONCAT(CAST(eta.ads_orders AS STRING), ' Ads Ord + ', CAST(GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders) AS STRING), ' Organic Ord') as value
      ),
      STRUCT(
        'active_status' as id,
        'Active Status' as label,
        'Active in last 3 days' as rule,
        (eta.ads_clicks_recent > 0) as pass,
        CASE WHEN eta.ads_clicks_recent > 0 THEN 'Active' ELSE 'Inactive' END as value
      ),
      STRUCT(
        'promote_check' as id,
        'Scale Up Check' as label,
        'Total Ord >= 4 & SQP Vol > 1500 & Not in Exact' as rule,
        (eta.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
         AND (eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) >= 4
         AND COALESCE(sqp.sqp_search_volume, 0) > 1500
         AND ate.search_term IS NULL) as pass,
        CONCAT(CAST((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) AS STRING), ' Total Ord, SQP Vol ', CAST(COALESCE(sqp.sqp_search_volume, 0) AS STRING)) as value
      ),
      STRUCT(
        'growth_scaling' as id,
        'Growth Scaling Check' as label,
        'Total ROAS >= 1.5 & Clicks >= 15' as rule,
        (SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 1.5
         AND eta.ads_clicks >= 15) as pass,
        CONCAT('Total ROAS: ', CAST(ROUND(SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)), 2) AS STRING), ', ', CAST(eta.ads_clicks AS STRING), ' Clicks') as value
      ),
      STRUCT(
        'profitability_check' as id,
        'Profitability Check' as label,
        'Total ROAS >= 1.2' as rule,
        (SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 1.2) as pass,
        CONCAT('Total ROAS: ', CAST(ROUND(SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)), 2) AS STRING)) as value
      ),
      STRUCT(
        'heavy_loss_check' as id,
        'Heavy Loss Check' as label,
        'Total ROAS < 0.5' as rule,
        (SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) < 0.5) as pass,
        CONCAT('Total ROAS: ', CAST(ROUND(SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)), 2) AS STRING)) as value
      ),
      STRUCT(
        'reduce_bid_check' as id,
        'Below Profitability Check' as label,
        'Total ROAS < 1.2 & Clicks >= 15' as rule,
        (SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) < 1.2
         AND eta.ads_clicks >= 15 AND eta.ads_clicks_recent > 0) as pass,
        CONCAT('Total ROAS: ', CAST(ROUND(SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)), 2) AS STRING), ', ', CAST(eta.ads_clicks AS STRING), ' Clicks') as value
      )
    ]) as decision_trace,

    -- Suggested bid: graduated % based on ROAS distance from target
    -- INCREASE: +10% (1.5-2x), +20% (2-3x), +30% (3-5x), +40% (5x+)
    -- REDUCE:   -15% (0.5-0.7x), -25% (0.3-0.5x), -35% (<0.3x)
    -- STOP/PROMOTE/KEEP/MONITOR: no change
    ROUND(
      CASE
        -- Exclude STOP / insufficient data conditions
        WHEN eta.ads_spend < 5 THEN NULL
        WHEN (eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) = 0
          AND eta.ads_clicks >= 20 AND eta.ads_clicks_recent > 0 THEN NULL
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) < 0.5
          AND eta.ads_clicks >= 20 AND eta.ads_clicks_recent > 0 THEN NULL
        -- Exclude PROMOTE_TO_EXACT
        WHEN eta.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
          AND (eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) >= 4
          AND COALESCE(sqp.sqp_search_volume, 0) > 1500
          AND ate.search_term IS NULL THEN NULL
        -- Exclude Organic-only PROMOTE
        WHEN eta.ads_orders = 0
          AND GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders) >= 3
          AND COALESCE(sqp.sqp_search_volume, 0) > 1500
          AND ate.search_term IS NULL THEN NULL
        -- Exclude SWITCH_HERO
        WHEN th.hero_asin IS NOT NULL
          AND COALESCE(eta.asin = th.hero_asin, FALSE) = FALSE
          AND eta.strategy_id = 'EXACT_BOOST'
          AND eta.ads_clicks >= 15 THEN NULL
        -- EXACT_BOOST needs volume: +20% (clicks < 20 all-time)
        WHEN eta.strategy_id = 'EXACT_BOOST'
          AND eta.ads_clicks < 20
          AND eta.ads_clicks_recent > 0
          THEN LEAST(
            COALESCE(cc.keyword_bid, ccag.ad_group_default_bid, 0.5) * 1.20,
            GREATEST(ue.margin_per_unit * 0.5, 0.3)
          )
        -- Graduated INCREASE: ROAS 5x+ → +40%
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 5.0
          AND eta.ads_clicks >= 15
          THEN LEAST(
            COALESCE(cc.keyword_bid, ccag.ad_group_default_bid, 0.5) * 1.40,
            GREATEST(ue.margin_per_unit * 0.5, 0.3)
          )
        -- Graduated INCREASE: ROAS 3-5x → +30%
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 3.0
          AND eta.ads_clicks >= 15
          THEN LEAST(
            COALESCE(cc.keyword_bid, ccag.ad_group_default_bid, 0.5) * 1.30,
            GREATEST(ue.margin_per_unit * 0.5, 0.3)
          )
        -- Graduated INCREASE: ROAS 2-3x → +20%
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 2.0
          AND eta.ads_clicks >= 15
          THEN LEAST(
            COALESCE(cc.keyword_bid, ccag.ad_group_default_bid, 0.5) * 1.20,
            GREATEST(ue.margin_per_unit * 0.5, 0.3)
          )
        -- Graduated INCREASE: ROAS 1.5-2x → +10%
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 1.5
          AND eta.ads_clicks >= 15
          THEN LEAST(
            COALESCE(cc.keyword_bid, ccag.ad_group_default_bid, 0.5) * 1.10,
            GREATEST(ue.margin_per_unit * 0.5, 0.3)
          )
        -- Graduated REDUCE: ROAS < 0.3 → -35%
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) < 0.3
          AND eta.ads_clicks >= 15 AND eta.ads_clicks_recent > 0
          THEN GREATEST(COALESCE(cc.keyword_bid, ccag.ad_group_default_bid, 0.5) * 0.65, 0.10)
        -- Graduated REDUCE: ROAS 0.3-0.5 → -25%
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) < 0.5
          AND eta.ads_clicks >= 15 AND eta.ads_clicks_recent > 0
          THEN GREATEST(COALESCE(cc.keyword_bid, ccag.ad_group_default_bid, 0.5) * 0.75, 0.10)
        -- Graduated REDUCE: ROAS 0.5-0.7 → -15%
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) < 0.7
          AND eta.ads_clicks >= 15 AND eta.ads_clicks_recent > 0
          THEN GREATEST(COALESCE(cc.keyword_bid, ccag.ad_group_default_bid, 0.5) * 0.85, 0.10)
        -- Graduated REDUCE: ROAS 0.7-1.2 → -10%
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) < 1.2
          AND eta.ads_clicks >= 15 AND eta.ads_clicks_recent > 0
          THEN GREATEST(COALESCE(cc.keyword_bid, ccag.ad_group_default_bid, 0.5) * 0.90, 0.10)
        ELSE NULL
      END
    , 2) as suggested_bid,

    -- Bid change percentage (graduated)
    ROUND(
      CASE
        -- Exclude STOP / insufficient data / PROMOTE conditions
        WHEN eta.ads_spend < 5 THEN NULL
        WHEN (eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) = 0
          AND eta.ads_clicks >= 20 AND eta.ads_clicks_recent > 0 THEN NULL
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) < 0.5
          AND eta.ads_clicks >= 20 AND eta.ads_clicks_recent > 0 THEN NULL
        WHEN eta.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
          AND (eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) >= 4
          AND COALESCE(sqp.sqp_search_volume, 0) > 1500
          AND ate.search_term IS NULL THEN NULL
        -- Exclude Organic-only PROMOTE
        WHEN eta.ads_orders = 0
          AND GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders) >= 3
          AND COALESCE(sqp.sqp_search_volume, 0) > 1500
          AND ate.search_term IS NULL THEN NULL
        -- Exclude SWITCH_HERO
        WHEN th.hero_asin IS NOT NULL
          AND COALESCE(eta.asin = th.hero_asin, FALSE) = FALSE
          AND eta.strategy_id = 'EXACT_BOOST'
          AND eta.ads_clicks >= 15 THEN NULL
        -- EXACT_BOOST volume rule: fixed +20% (clicks < 20 all-time)
        WHEN eta.strategy_id = 'EXACT_BOOST'
          AND eta.ads_clicks < 20
          AND eta.ads_clicks_recent > 0
          THEN 20.0
        -- Graduated INCREASE
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 5.0
          AND eta.ads_clicks >= 15 THEN 40.0
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 3.0
          AND eta.ads_clicks >= 15 THEN 30.0
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 2.0
          AND eta.ads_clicks >= 15 THEN 20.0
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 1.5
          AND eta.ads_clicks >= 15 THEN 10.0
        -- Graduated REDUCE
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) < 0.3
          AND eta.ads_clicks >= 15 AND eta.ads_clicks_recent > 0 THEN -35.0
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) < 0.5
          AND eta.ads_clicks >= 15 AND eta.ads_clicks_recent > 0 THEN -25.0
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) < 0.7
          AND eta.ads_clicks >= 15 AND eta.ads_clicks_recent > 0 THEN -15.0
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) < 1.2
          AND eta.ads_clicks >= 15 AND eta.ads_clicks_recent > 0 THEN -10.0
        ELSE NULL
      END
    , 1) as bid_change_pct,

    ROUND(
      CASE
        WHEN eta.ads_orders = 0 AND GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders) = 0
          AND eta.ads_clicks >= 20 AND eta.ads_clicks_recent > 0 THEN eta.ads_spend * 10
        WHEN SAFE_DIVIDE(eta.ads_orders * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) < 0.5
          AND eta.ads_clicks >= 20 AND eta.ads_clicks_recent > 0 THEN eta.ads_spend * 5
        WHEN eta.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
          AND eta.ads_orders >= 4 AND ate.search_term IS NULL
          THEN eta.ads_orders * 50.0
        -- INCREASE_BID priority based on ROAS gap
        WHEN SAFE_DIVIDE((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 1.5
          AND eta.ads_clicks >= 15
          THEN eta.ads_orders * 30.0
        ELSE 0
      END
    , 0) as priority_score,

    -- Reason: combines performance analysis + hero ASIN guidance
    -- Note: Ads data uses 60d window, SQP uses 56d — both labelled as (8w)
    CONCAT(
      -- Performance reason
      CASE
        WHEN eta.ads_spend < 5
          THEN CONCAT('Only $', CAST(ROUND(eta.ads_spend, 2) AS STRING), ' Ads Spend(8w). Need more data.')
        WHEN eta.ads_orders = 0 AND GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders) = 0 AND eta.ads_clicks >= 20 AND eta.ads_clicks_recent > 0
          THEN CONCAT(CAST(eta.ads_clicks AS STRING), ' Clicks on "', eta.search_term, '" with zero Orders. (Active in last 3 days).')
        WHEN eta.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
          AND (eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) >= 4
          AND COALESCE(sqp.sqp_search_volume, 0) > 1500
          AND ate.search_term IS NULL
          THEN CONCAT('"', eta.search_term, '" converts in broad/auto (',
                       CAST((eta.ads_orders + GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders)) AS STRING),
                       ' Total Orders(8w), SQP Vol ',
                       CAST(COALESCE(sqp.sqp_search_volume, 0) AS STRING),
                       '). Promote to EXACT_BOOST.')
        WHEN eta.ads_orders = 0
          AND GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders) >= 3
          AND COALESCE(sqp.sqp_search_volume, 0) > 1500
          AND ate.search_term IS NULL
          THEN CONCAT('"', eta.search_term, '" has ',
                       CAST(GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders) AS STRING),
                       ' organic orders(8w) with SQP Vol ',
                       CAST(COALESCE(sqp.sqp_search_volume, 0) AS STRING),
                       '. Promote to EXACT_BOOST based on organic demand.')
        WHEN th.hero_asin IS NOT NULL
          AND COALESCE(eta.asin = th.hero_asin, FALSE) = FALSE
          AND eta.strategy_id = 'EXACT_BOOST'
          AND eta.ads_clicks >= 15
          THEN CONCAT('Wrong ASIN: Switch from ', ue.product_short_name, ' to ', th.hero_product_name, ' (hero) for "', eta.search_term, '".')
        WHEN SAFE_DIVIDE(eta.ads_orders * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 1.2
          THEN CONCAT('Profitable: $', CAST(ROUND(eta.ads_orders * ue.margin_per_unit - eta.ads_spend, 0) AS STRING),
                       ' Net Profit(8w) on $', CAST(ROUND(eta.ads_spend, 0) AS STRING),
                       ' Ads Spend(8w) (Net ROAS(8w) ', CAST(ROUND(SAFE_DIVIDE(eta.ads_orders * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)), 2) AS STRING), ').')
        WHEN SAFE_DIVIDE(eta.ads_orders * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) < 1.2
          AND GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders) >= 2
          AND SAFE_DIVIDE(GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders) * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) >= 0.8
          THEN CONCAT('Ads lose money (Net ROAS(8w) ', CAST(ROUND(SAFE_DIVIDE(eta.ads_orders * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)), 2) AS STRING),
                       ') but ', CAST(GREATEST(0, COALESCE(sqp.sqp_purchases, 0) - eta.ads_orders) AS STRING), ' organic orders(8w) justify keeping it.')
        WHEN SAFE_DIVIDE(eta.ads_orders * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) < 0.5 AND eta.ads_clicks >= 20 AND eta.ads_clicks_recent > 0
          THEN CONCAT('Losing $', CAST(ROUND(ABS(eta.ads_orders * ue.margin_per_unit - eta.ads_spend), 0) AS STRING),
                       ' on ', CAST(eta.ads_clicks AS STRING), ' Clicks (Net ROAS(8w) ',
                       CAST(ROUND(SAFE_DIVIDE(eta.ads_orders * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)), 2) AS STRING), '). Still receiving clicks.')
        WHEN SAFE_DIVIDE(eta.ads_orders * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)) < 1.2 AND eta.ads_clicks >= 15 AND eta.ads_clicks_recent > 0
          THEN CONCAT('Net ROAS(8w) ', CAST(ROUND(SAFE_DIVIDE(eta.ads_orders * ue.margin_per_unit, NULLIF(eta.ads_spend, 0)), 2) AS STRING),
                       ' — below 1.2x profitability threshold. Reduce bid.')
        ELSE CONCAT(CAST(eta.ads_clicks AS STRING), ' Clicks, ', CAST(eta.ads_orders AS STRING), ' Orders. Monitoring (Not actively bleeding or below action threshold).')
      END,
      -- Hero ASIN context
      CASE
        WHEN th.hero_asin IS NULL THEN ''
        WHEN eta.asin = th.hero_asin THEN CONCAT(' [HERO MATCH: ', ue.product_short_name, ' IS the best child for this term',
          CASE WHEN COALESCE(th.hero_ads_cvr_pct, 0) > 0 THEN CONCAT(' (Ads CVR ', CAST(ROUND(th.hero_ads_cvr_pct, 1) AS STRING), '%)') ELSE '' END,
          CASE WHEN COALESCE(th.hero_sqp_cvr_pct, 0) > 0 THEN CONCAT(' (SQP CVR ', CAST(ROUND(th.hero_sqp_cvr_pct, 1) AS STRING), '%)') ELSE '' END,
          ']')
        ELSE CONCAT(' [WRONG ASIN: ', th.hero_product_name, ' is the hero for "', eta.search_term, '"',
          CASE WHEN COALESCE(th.hero_ads_cvr_pct, 0) > 0 THEN CONCAT(' (Ads CVR ', CAST(ROUND(th.hero_ads_cvr_pct, 1) AS STRING), '%)') ELSE '' END,
          CASE WHEN COALESCE(th.hero_sqp_cvr_pct, 0) > 0 THEN CONCAT(' (SQP CVR ', CAST(ROUND(th.hero_sqp_cvr_pct, 1) AS STRING), '%)') ELSE '' END,
          '. Switch ad to ', th.hero_product_name, '.]')
      END
    ) as reason,

    -- Hero ASIN columns
    th.hero_asin,
    th.hero_product_name,
    th.hero_score,
    th.hero_sqp_cvr_pct,
    th.hero_ads_cvr_pct,
    th.hero_confidence,
    th.hero_net_roas,
    th.hero_total_orders,
    th.hero_ads_ctr_pct,
    COALESCE(eta.asin = th.hero_asin, FALSE) as is_hero_match

  FROM experiment_term_ads eta
  JOIN asin_unit_economics ue ON eta.asin = ue.asin
  LEFT JOIN ads_1w a1
    ON eta.experiment_id = a1.experiment_id AND eta.campaign_id = a1.campaign_id
    AND eta.search_term = a1.search_term AND eta.asin = a1.asin
  LEFT JOIN ads_4w a4
    ON eta.experiment_id = a4.experiment_id AND eta.campaign_id = a4.campaign_id
    AND eta.search_term = a4.search_term AND eta.asin = a4.asin
  LEFT JOIN sqp_recent sqp
    ON eta.search_term = sqp.search_term AND eta.asin = sqp.asin
  LEFT JOIN sqp_1w s1
    ON eta.search_term = s1.search_term AND eta.asin = s1.asin
  LEFT JOIN sqp_4w s4
    ON eta.search_term = s4.search_term AND eta.asin = s4.asin
  LEFT JOIN term_classification tc
    ON eta.search_term = tc.search_term AND eta.asin = tc.asin
  LEFT JOIN already_targeted_exact ate
    ON eta.search_term = ate.search_term
  LEFT JOIN term_hero th
    ON eta.search_term = th.search_term
  LEFT JOIN campaign_config cc
    ON eta.campaign_id = cc.campaign_id AND eta.search_term = cc.keyword_text
  LEFT JOIN campaign_config_ag ccag
    ON eta.campaign_id = ccag.campaign_id
  LEFT JOIN campaign_negatives cn
    ON eta.campaign_id = cn.campaign_id AND eta.search_term = cn.neg_keyword
  LEFT JOIN campaign_auto_bids cab
    ON eta.campaign_id = cab.campaign_id
  CROSS JOIN today_phases tp
),

-- =============================================
-- SECTION B: OPPORTUNITY TERMS
-- SQP terms with purchases NOT targeted by any active experiment
-- =============================================
all_experiment_targeted AS (
  SELECT DISTINCT
    LOWER(fa.search_term) as search_term,
    fa.advertised_asins as asin
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN active_experiments ae ON ec.experiment_id = ae.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec.campaign_id = fa.campaign_id
  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
    AND fa.advertised_asins IS NOT NULL
),

sqp_with_purchases AS (
  SELECT
    LOWER(fsq.query_text) as search_term,
    fsq.ASIN as asin,
    SUM(fsq.conversions) as sqp_purchases,
    SUM(fsq.clicks) as sqp_clicks,
    SUM(fsq.impressions) as sqp_impressions,
    COUNT(DISTINCT fsq.week_end_date) as sqp_weeks
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
  WHERE fsq.data_source = 'SQP'
    AND fsq.week_end_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 56 DAY)
    AND fsq.conversions > 0
  GROUP BY 1, 2
  HAVING SUM(fsq.conversions) >= 1
),

opportunity_rows AS (
  SELECT
    'OPPORTUNITY' as recommendation_type,
    CAST(NULL AS STRING) as experiment_id,
    CAST(NULL AS STRING) as campaign_id,
    CAST(NULL AS STRING) as ad_group_id,
    CAST(NULL AS STRING) as campaign_name,
    CAST(NULL AS STRING) as campaign_type,
    'Unassigned' as portfolio_name,
    CASE
      WHEN tc.experiment_segment = 'BRAND' THEN 'BRAND_DEFENSE'
      WHEN tc.intent_segment = 'COMPETITOR' THEN 'CATEGORY_CONQUEST'
      WHEN sp.sqp_purchases >= 3 AND sp.sqp_weeks >= 2 THEN 'EXACT_BOOST'
      WHEN sp.sqp_purchases >= 2 THEN 'EXACT_BOOST'
      ELSE 'HUNTER'
    END as strategy_id,
    CAST(NULL AS STRING) as strategy_name,
    COALESCE(th.hero_asin, sp.asin) as asin,
    COALESCE(th.hero_product_name, ue.product_short_name) as product_short_name,
    sp.search_term,

    -- No config data for opportunity terms (not yet targeted)
    CAST(NULL AS FLOAT64) as current_bid,
    CAST(NULL AS FLOAT64) as ad_group_default_bid,
    0.0 as top_of_search_pct,
    0.0 as product_page_pct,
    0.0 as rest_of_search_pct,
    0.0 as amazon_business_pct,

    -- No negation or auto-targeting data for opportunity terms
    FALSE as is_negated,
    FALSE as has_exact_targeting,
    CAST(NULL AS FLOAT64) as close_match_bid,
    CAST(NULL AS FLOAT64) as loose_match_bid,
    CAST(NULL AS FLOAT64) as substitutes_bid,
    CAST(NULL AS FLOAT64) as complements_bid,

    0.0 as ads_spend,
    0 as ads_orders,
    0 as ads_units,
    0 as ads_clicks,
    0 as ads_clicks_recent,
    0 as ads_impressions,
    CAST(NULL AS FLOAT64) as cpc,
    CAST(NULL AS FLOAT64) as ads_cvr_pct,
    CAST(NULL AS FLOAT64) as cost_per_order,

    ROUND(COALESCE(hero_ue.margin_per_unit, ue.margin_per_unit), 2) as margin_per_unit,
    0.0 as ads_gross_margin,
    0.0 as ads_net_profit,
    CAST(NULL AS FLOAT64) as ads_net_roas,
    CAST(NULL AS FLOAT64) as weighted_total_net_roas,

    sp.sqp_purchases,
    sp.sqp_purchases as sqp_organic_orders,
    sp.sqp_clicks,
    sp.sqp_impressions,
    sp.sqp_weeks,
    0 as sqp_organic_rank,
    CAST(NULL AS FLOAT64) as sqp_search_volume,

    tc.experiment_segment,
    tc.intent_segment,
    tc.occasion,
    CASE tc.occasion
      WHEN 'VALENTINES' THEN tp.occasion_valentines_phase
      WHEN 'EASTER' THEN tp.occasion_easter_phase
      WHEN 'CHRISTMAS' THEN tp.occasion_christmas_phase
      WHEN 'BACK_TO_SCHOOL' THEN tp.occasion_back_to_school_phase
      ELSE 'ALWAYS_ON'
    END as peak_phase,
    tc.amazon_avg_weekly_orders as market_weekly_orders,
    tc.your_orders_share_pct,
    COALESCE(tc.is_best_asin_for_term, FALSE) as is_best_asin_for_term,

    CAST(NULL AS INT64) as days_with_data,
    CAST(NULL AS DATE) as first_seen,
    CAST(NULL AS DATE) as last_seen,

    'NOT_TARGETED' as ads_signal,
    'START' as action,

    -- Must match column order of active_term_rows (is_top_of_page_organic, decision_trace after action)
    FALSE as is_top_of_page_organic,
    CAST(NULL AS STRING) as decision_trace,

    CAST(NULL AS FLOAT64) as suggested_bid,
    CAST(NULL AS FLOAT64) as bid_change_pct,

    ROUND(
      sp.sqp_purchases * ue.margin_per_unit
      + COALESCE(tc.amazon_avg_weekly_orders, 0) * 0.5
      + sp.sqp_weeks * 10.0
    , 0) as priority_score,

    CONCAT(
      CAST(sp.sqp_purchases AS STRING), ' SQP Orders(8w) for "', sp.search_term,
      '". No ads target this term.',
      CASE
        WHEN th.hero_asin IS NOT NULL AND th.hero_asin != sp.asin
          THEN CONCAT(' Advertise ', th.hero_product_name, ' (hero',
            CASE WHEN COALESCE(th.hero_ads_cvr_pct, 0) > 0 THEN CONCAT(', Ads CVR ', CAST(ROUND(th.hero_ads_cvr_pct, 1) AS STRING), '%') ELSE '' END,
            CASE WHEN COALESCE(th.hero_sqp_cvr_pct, 0) > 0 THEN CONCAT(', SQP CVR ', CAST(ROUND(th.hero_sqp_cvr_pct, 1) AS STRING), '%') ELSE '' END,
            ', score ', CAST(th.hero_score AS STRING), ').')
        WHEN th.hero_asin IS NOT NULL
          THEN CONCAT(' Advertise ', th.hero_product_name, ' (hero',
            CASE WHEN COALESCE(th.hero_ads_cvr_pct, 0) > 0 THEN CONCAT(', Ads CVR ', CAST(ROUND(th.hero_ads_cvr_pct, 1) AS STRING), '%') ELSE '' END,
            CASE WHEN COALESCE(th.hero_sqp_cvr_pct, 0) > 0 THEN CONCAT(', SQP CVR ', CAST(ROUND(th.hero_sqp_cvr_pct, 1) AS STRING), '%') ELSE '' END,
            ').')
        ELSE CONCAT(' Advertise ', ue.product_short_name, ' (SQP Orders(8w) detected on this ASIN).')
      END
    ) as reason,

    th.hero_asin,
    th.hero_product_name,
    th.hero_score,
    th.hero_sqp_cvr_pct,
    th.hero_ads_cvr_pct,
    th.hero_confidence,
    th.hero_net_roas,
    th.hero_total_orders,
    th.hero_ads_ctr_pct,
    COALESCE(sp.asin = th.hero_asin, FALSE) as is_hero_match

  FROM sqp_with_purchases sp
  JOIN asin_unit_economics ue ON sp.asin = ue.asin
  LEFT JOIN all_experiment_targeted aet
    ON sp.search_term = aet.search_term AND sp.asin = aet.asin
  LEFT JOIN term_classification tc
    ON sp.search_term = tc.search_term AND sp.asin = tc.asin
  LEFT JOIN term_hero th
    ON sp.search_term = th.search_term
  LEFT JOIN asin_unit_economics hero_ue ON th.hero_asin = hero_ue.asin
  CROSS JOIN today_phases tp
  WHERE aet.search_term IS NULL
),

-- =============================================
-- FINAL OUTPUT: Phase-Aware Bid Overrides
-- ==============================================
-- Wraps both active + opportunity terms and applies seasonal phase modifiers
-- Phase priorities:
--   POST_PEAK:  STOP seasonal exact keywords (shipping cutoff, demand cliff)
--   OFF_SEASON: Override INCREASE→REDUCE -30% for seasonal terms
--   PRE_PEAK:   MONITOR only (research clicks, ignore bad ROAS, don't boost)
--   BOOST:      Push bids harder (×1.3 multiplier on bid changes)
--   PEAK:       No change (normal graduated ROAS logic)
--   ALWAYS_ON:  No change (non-seasonal terms like BIRTHDAY, NO_OCCASION)

combined AS (
  SELECT * FROM active_term_rows
  UNION ALL
  SELECT * FROM opportunity_rows
)

SELECT
  * EXCEPT (action, suggested_bid, bid_change_pct),

  -- Phase-aware ACTION override
  CASE
    -- POST_PEAK: stop seasonal keywords (demand cliff after shipping cutoff)
    WHEN peak_phase = 'POST_PEAK'
      AND occasion IN ('VALENTINES', 'EASTER', 'CHRISTMAS', 'BACK_TO_SCHOOL')
      AND action NOT IN ('STOP', 'NOT_TARGETED')
      THEN 'STOP'
    -- OFF_SEASON: don't increase bids on seasonal terms (override to REDUCE)
    WHEN peak_phase = 'OFF_SEASON'
      AND occasion IN ('VALENTINES', 'EASTER', 'CHRISTMAS', 'BACK_TO_SCHOOL')
      AND action = 'INCREASE_BID'
      THEN 'REDUCE_BID'
    -- PRE_PEAK: research phase — don't act on bids, just monitor
    WHEN peak_phase = 'PRE_PEAK'
      AND occasion IN ('VALENTINES', 'EASTER', 'CHRISTMAS', 'BACK_TO_SCHOOL')
      AND action IN ('INCREASE_BID', 'REDUCE_BID')
      THEN 'MONITOR'
    -- BOOST / PEAK / ALWAYS_ON: normal logic
    ELSE action
  END as action,

  -- Phase-aware SUGGESTED_BID override
  CASE
    -- BOOST: push bids harder (×1.3)
    WHEN peak_phase = 'BOOST'
      AND occasion IN ('VALENTINES', 'EASTER', 'CHRISTMAS', 'BACK_TO_SCHOOL')
      AND suggested_bid IS NOT NULL
      AND action = 'INCREASE_BID'
      THEN ROUND(suggested_bid * 1.3, 2)
    -- POST_PEAK / OFF_SEASON overrides: clear suggested bid
    WHEN peak_phase IN ('POST_PEAK', 'OFF_SEASON')
      AND occasion IN ('VALENTINES', 'EASTER', 'CHRISTMAS', 'BACK_TO_SCHOOL')
      AND action IN ('INCREASE_BID', 'KEEP')
      THEN NULL
    -- OFF_SEASON: set reduce bid to -30% of current
    WHEN peak_phase = 'OFF_SEASON'
      AND occasion IN ('VALENTINES', 'EASTER', 'CHRISTMAS', 'BACK_TO_SCHOOL')
      AND action = 'INCREASE_BID'
      AND suggested_bid IS NOT NULL
      THEN ROUND(suggested_bid * 0.54, 2)  -- roughly current_bid * 0.70 (reduce 30%)
    -- PRE_PEAK: clear bid changes (monitor only)
    WHEN peak_phase = 'PRE_PEAK'
      AND occasion IN ('VALENTINES', 'EASTER', 'CHRISTMAS', 'BACK_TO_SCHOOL')
      THEN NULL
    ELSE suggested_bid
  END as suggested_bid,

  -- Phase-aware BID_CHANGE_PCT override
  CASE
    -- BOOST: amplify bid change by ×1.3
    WHEN peak_phase = 'BOOST'
      AND occasion IN ('VALENTINES', 'EASTER', 'CHRISTMAS', 'BACK_TO_SCHOOL')
      AND bid_change_pct IS NOT NULL
      AND bid_change_pct > 0
      THEN ROUND(bid_change_pct * 1.3, 1)
    -- POST_PEAK: clear bid pct (STOP action has no bid change)
    WHEN peak_phase = 'POST_PEAK'
      AND occasion IN ('VALENTINES', 'EASTER', 'CHRISTMAS', 'BACK_TO_SCHOOL')
      THEN NULL
    -- OFF_SEASON: override INCREASE to -30%
    WHEN peak_phase = 'OFF_SEASON'
      AND occasion IN ('VALENTINES', 'EASTER', 'CHRISTMAS', 'BACK_TO_SCHOOL')
      AND action = 'INCREASE_BID'
      THEN -30.0
    -- PRE_PEAK: clear bid pct (monitor only)
    WHEN peak_phase = 'PRE_PEAK'
      AND occasion IN ('VALENTINES', 'EASTER', 'CHRISTMAS', 'BACK_TO_SCHOOL')
      THEN NULL
    ELSE bid_change_pct
  END as bid_change_pct,

  -- Negate instruction: only negate from BROAD/AUTO AFTER exact campaign exists and converts
  CASE
    -- Already negated: nothing to do
    WHEN is_negated = TRUE THEN NULL
    -- STOP action + exact campaign exists → safe to negate (traffic flows through exact)
    WHEN action = 'STOP' AND has_exact_targeting = TRUE THEN 'NEGATIVE_EXACT'
    -- STOP action from POST_PEAK override + exact exists → seasonal negate
    WHEN peak_phase = 'POST_PEAK'
      AND occasion IN ('VALENTINES', 'EASTER', 'CHRISTMAS', 'BACK_TO_SCHOOL')
      AND has_exact_targeting = TRUE THEN 'NEGATIVE_EXACT'
    -- STOP action but NO exact campaign yet → must promote to exact first
    WHEN action = 'STOP' AND has_exact_targeting = FALSE THEN 'PROMOTE_FIRST'
    -- POST_PEAK override but no exact → promote first
    WHEN peak_phase = 'POST_PEAK'
      AND occasion IN ('VALENTINES', 'EASTER', 'CHRISTMAS', 'BACK_TO_SCHOOL')
      AND has_exact_targeting = FALSE THEN 'PROMOTE_FIRST'
    -- All other actions (INCREASE_BID, REDUCE_BID, KEEP, MONITOR): no negate
    ELSE NULL
  END as negate_as,

  -- Decision tree explanation: human-readable trace of WHY this action is recommended
  CASE
    -- ══════════════════════════════════════════
    -- Phase overrides (these take priority)
    -- ══════════════════════════════════════════
    WHEN peak_phase = 'POST_PEAK'
      AND occasion IN ('VALENTINES', 'EASTER', 'CHRISTMAS', 'BACK_TO_SCHOOL')
      AND action = 'STOP'
      THEN CONCAT(
        '⏹ POST_PEAK override → STOP seasonal keyword.',
        ' Phase: ', occasion, ' ended (POST_PEAK = shipping cutoff passed).',
        ' Demand cliff: seasonal shoppers stop buying after the holiday.',
        CASE WHEN has_exact_targeting THEN ' ✅ Exact campaign exists → safe to add NEGATIVE_EXACT to this campaign.'
             ELSE ' ⚠ No exact campaign yet → PROMOTE_FIRST: create exact targeting, verify it converts, then negate.'
        END
      )
    WHEN peak_phase = 'OFF_SEASON'
      AND occasion IN ('VALENTINES', 'EASTER', 'CHRISTMAS', 'BACK_TO_SCHOOL')
      AND action = 'INCREASE_BID'  -- original action (gets overridden to REDUCE_BID)
      THEN CONCAT(
        '📉 OFF_SEASON override: INCREASE_BID overridden to REDUCE_BID -30%.',
        ' Phase: ', occasion, ' is OFF_SEASON (next season not started yet).',
        ' Originally profitable (Weighted Total ROAS ', COALESCE(CAST(weighted_total_net_roas AS STRING), '?'), ') but seasonal demand is low.',
        ' Reduce bids instead of wasting budget on out-of-season terms.'
      )
    WHEN peak_phase = 'PRE_PEAK'
      AND occasion IN ('VALENTINES', 'EASTER', 'CHRISTMAS', 'BACK_TO_SCHOOL')
      AND action IN ('INCREASE_BID', 'REDUCE_BID')  -- original actions that get overridden to MONITOR
      THEN CONCAT(
        '👁 PRE_PEAK override: ', action, ' overridden to MONITOR.',
        ' Phase: ', occasion, ' PRE_PEAK (research phase, shoppers click but do not buy yet).',
        ' Do not adjust bids now - wait for BOOST phase when orders start.'
      )
    WHEN peak_phase = 'BOOST'
      AND occasion IN ('VALENTINES', 'EASTER', 'CHRISTMAS', 'BACK_TO_SCHOOL')
      AND action = 'INCREASE_BID'
      AND bid_change_pct IS NOT NULL AND bid_change_pct > 0
      THEN CONCAT(
        '🚀 BOOST phase → ×1.3 bid multiplier.',
        ' Phase: ', occasion, ' BOOST (orders starting to flow).',
        ' Original bid change +', CAST(ROUND(bid_change_pct / 1.3, 0) AS STRING), '% amplified to +', CAST(ROUND(bid_change_pct, 0) AS STRING), '%.',
        ' Push harder now to capture early-season momentum.'
      )

    -- ══════════════════════════════════════════
    -- STOP actions (non-phase)
    -- ══════════════════════════════════════════
    WHEN action = 'STOP' AND ads_signal = 'WASTED_SPEND'
      THEN CONCAT(
        '⛔ STOP: Wasted spend.',
        ' $', CAST(ROUND(ads_spend, 0) AS STRING), ' spent, 0 orders in 8 weeks, ', CAST(ads_clicks AS STRING), ' clicks.',
        ' Decision: clicks ≥ 20 with recent activity but zero conversions → stop spending.',
        CASE WHEN has_exact_targeting THEN ' ✅ Exact campaign exists → add NEGATIVE_EXACT to this ' || strategy_id || ' campaign.'
             ELSE ' ⚠ No exact campaign → PROMOTE_FIRST: create exact, verify conversions, then negate.'
        END
      )
    WHEN action = 'STOP' AND ads_signal = 'HEAVY_LOSS'
      THEN CONCAT(
        '⛔ STOP: Heavy loss.',
        ' $', CAST(ROUND(ads_spend, 0) AS STRING), ' spent, Weighted Total ROAS ', COALESCE(CAST(weighted_total_net_roas AS STRING), '0'),
        ' (threshold < 0.5). ', CAST(ads_clicks AS STRING), ' clicks.',
        ' Decision: ROAS too low with enough data to be confident → stop.',
        CASE WHEN has_exact_targeting THEN ' ✅ Exact campaign exists → add NEGATIVE_EXACT.'
             ELSE ' ⚠ No exact campaign → PROMOTE_FIRST.'
        END
      )

    -- ══════════════════════════════════════════
    -- Bid change actions
    -- ══════════════════════════════════════════
    WHEN action = 'INCREASE_BID'
      THEN CONCAT(
        '📈 INCREASE_BID +', COALESCE(CAST(ROUND(bid_change_pct, 0) AS STRING), '?'), '%.',
        ' Weighted Total ROAS ', COALESCE(CAST(weighted_total_net_roas AS STRING), '?'),
        CASE
          WHEN weighted_total_net_roas >= 5.0 THEN ' (excellent, >=5x -> graduated +40%)'
          WHEN weighted_total_net_roas >= 3.0 THEN ' (strong, >=3x -> graduated +30%)'
          WHEN weighted_total_net_roas >= 2.0 THEN ' (good, >=2x -> graduated +20%)'
          WHEN weighted_total_net_roas >= 1.5 THEN ' (profitable, >=1.5x -> graduated +10%)'
          ELSE ''
        END,
        '. ', CAST(ads_clicks AS STRING), ' clicks, ', CAST(ads_orders AS STRING), ' orders.',
        ' Decision: profitable with enough clicks → scale up.'
      )
    WHEN action = 'REDUCE_BID'
      THEN CONCAT(
        '📉 REDUCE_BID ', COALESCE(CAST(ROUND(bid_change_pct, 0) AS STRING), '?'), '%.',
        ' Weighted Total ROAS ', COALESCE(CAST(weighted_total_net_roas AS STRING), '?'),
        CASE
          WHEN weighted_total_net_roas < 0.3 THEN ' (very poor, <0.3x → graduated -35%)'
          WHEN weighted_total_net_roas < 0.5 THEN ' (poor, <0.5x → graduated -25%)'
          WHEN weighted_total_net_roas < 0.7 THEN ' (marginal, <0.7x → graduated -15%)'
          WHEN weighted_total_net_roas < 1.2 THEN ' (below threshold, <1.2x → graduated -10%)'
          ELSE ''
        END,
        '. ', CAST(ads_clicks AS STRING), ' clicks, $', CAST(ROUND(ads_spend, 0) AS STRING), ' spent.',
        ' Decision: below 1.2x profitability → reduce bid.'
      )
    WHEN action = 'PROMOTE_TO_EXACT'
      THEN CONCAT(
        '🎯 PROMOTE_TO_EXACT.',
        ' ', CAST((ads_orders + sqp_organic_orders) AS STRING), ' total orders, Weighted Total ROAS ', COALESCE(CAST(weighted_total_net_roas AS STRING), '?'), '.',
        ' SQP Vol: ', CAST(sqp_search_volume AS STRING), '.',
        ' Decision: ≥4 total orders, SQP volume >1500, no exact campaign yet → create exact targeting.'
      )
    WHEN action = 'SWITCH_HERO'
      THEN CONCAT(
        '🔄 SWITCH_HERO: Wrong ASIN in EXACT campaign.',
        ' Current: ', product_short_name, '. Hero: ', COALESCE(hero_product_name, '?'), '.',
        ' Hero ROAS: ', COALESCE(CAST(hero_net_roas AS STRING), '?'),
        '. Switch product before scaling.'
      )

    -- ══════════════════════════════════════════
    -- Passive actions
    -- ══════════════════════════════════════════
    WHEN action = 'KEEP'
      THEN 'KEEP: Profitable (ROAS ≥ 1.2) but not strong enough to scale. No bid change needed.'
    WHEN action = 'MONITOR'
      THEN CONCAT(
        'MONITOR: ',
        CASE
          WHEN ads_spend < 5 THEN 'Not enough spend yet ($' || CAST(ROUND(ads_spend, 0) AS STRING) || '). Need more data.'
          WHEN ads_clicks < 15 THEN 'Not enough clicks yet (' || CAST(ads_clicks AS STRING) || '). Need ≥15 to decide.'
          ELSE 'No clear signal yet. Continue monitoring.'
        END
      )
    WHEN action = 'START'
      THEN 'START: SQP data shows organic purchases but no ads targeting this term. Consider starting ads.'
    WHEN action = 'NOT_TARGETED'
      THEN 'NOT_TARGETED: No active campaign targets this search term.'
    ELSE NULL
  END as action_explanation,

  -- ══════════════════════════════════════════
  -- Hero mismatch action: should you switch the advertised ASIN?
  -- Gates: hero exists + wrong ASIN + actionable (not STOP/MONITOR)
  -- ══════════════════════════════════════════
  CASE
    WHEN hero_asin IS NULL THEN NULL
    WHEN is_hero_match = TRUE THEN NULL
    WHEN action IN ('STOP', 'MONITOR', 'NOT_TARGETED', 'START', 'SWITCH_HERO') THEN NULL
    ELSE 'SWITCH_HERO'
  END as hero_action,

  -- Hero mismatch explanation: full decision tree
  CASE
    WHEN hero_asin IS NULL THEN NULL
    WHEN is_hero_match = TRUE THEN CONCAT(
      '✅ Correct hero: ', product_short_name, ' IS the best ASIN for "', search_term, '".',
      ' Hero Net ROAS: ', COALESCE(CAST(hero_net_roas AS STRING), '?'),
      ', ', CAST(COALESCE(hero_total_orders, 0) AS STRING), ' orders.'
    )
    WHEN action IN ('STOP', 'MONITOR', 'NOT_TARGETED', 'START') THEN NULL
    ELSE CONCAT(
      '🔄 SWITCH_HERO: You are advertising ', product_short_name,
      ' but ', hero_product_name, ' is the hero for "', search_term, '".',
      ' Hero Net ROAS: ', COALESCE(CAST(hero_net_roas AS STRING), '?'),
      ' vs current ROAS: ', COALESCE(CAST(ROUND(weighted_total_net_roas, 2) AS STRING), '?'), '.',
      ' Hero orders: ', CAST(COALESCE(hero_total_orders, 0) AS STRING),
      ', Hero Ads CVR: ', COALESCE(CAST(hero_ads_cvr_pct AS STRING), '?'), '%.',
      CASE
        WHEN has_exact_targeting = TRUE
          THEN CONCAT(
            ' Step 1: Add "', search_term, '" to ', hero_product_name, ' exact campaign.',
            ' Step 2: Negate "', search_term, '" from this ', strategy_id, ' campaign.'
          )
        ELSE CONCAT(
            ' Step 1: Create exact campaign for ', hero_product_name, ' with "', search_term, '".',
            ' Step 2: Once converting, negate from this ', strategy_id, ' campaign.'
          )
      END
    )
  END as hero_action_explanation

FROM combined;
