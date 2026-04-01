-- =============================================
-- OI Database Project - V_KEYWORD_STRATEGY_PREDICTIONS
-- =============================================
--
-- Purpose: Per (search_term, asin) — predict the Potential Net ROAS
--          based on 6 historical factors accumulated over the full data window.
--
-- Factors:
--   1. Product (margin + baseline CVR)
--   2. Seasonality (current month CVR vs trailing average)
--   3. Peak Events (upcoming DIM_TIME peak within 30 days)
--   4. CPC Trend (recent CPC vs older CPC — inflation adjustment)
--   5. TOS Reliance (Top-of-Search CVR boost from placement reports)
--   6. Organic Potential (SQP organic conversion velocity)
--
-- Output:
--   predicted_net_roas, base_cvr, predicted_cvr, base_cpc, predicted_cpc,
--   each multiplier, and a strategic_signal classification.
--
-- Dependencies:
--   FACT_AMAZON_ADS, FACT_SEARCH_QUERY, DIM_PRODUCT, DIM_COSTS_HISTORY,
--   DIM_TIME, fivetran-hl.amazon_ads.campaign_placement_report
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_KEYWORD_STRATEGY_PREDICTIONS`
AS
WITH

-- =============================================
-- 0. Unit economics per ASIN
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
  WHERE p.asin IS NOT NULL AND p.listing_price_amount > 0
),

-- =============================================
-- 1. FACTOR: Product Baseline (lifetime CVR & CPC per keyword+asin)
-- =============================================
lifetime_ads AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    fa.advertised_asins as asin,
    SUM(fa.Ads_clicks) as total_clicks,
    SUM(fa.Ads_orders) as total_orders,
    SUM(fa.Ads_cost) as total_spend,
    SUM(fa.Ads_impressions) as total_impressions,
    COUNT(DISTINCT fa.date) as days_with_data,
    MIN(fa.date) as first_seen,
    MAX(fa.date) as last_seen
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
    AND fa.advertised_asins IS NOT NULL
  GROUP BY 1, 2
  HAVING SUM(fa.Ads_clicks) >= 5  -- minimum data threshold
),

product_baseline AS (
  SELECT
    la.search_term,
    la.asin,
    ae.product_short_name,
    ae.parent_name,
    ae.margin_per_unit,
    la.total_clicks,
    la.total_orders,
    la.total_spend,
    la.total_impressions,
    la.days_with_data,
    la.first_seen,
    la.last_seen,
    -- Base CVR (lifetime)
    SAFE_DIVIDE(la.total_orders, la.total_clicks) as base_cvr,
    -- Base CPC (lifetime)
    SAFE_DIVIDE(la.total_spend, la.total_clicks) as base_cpc,
    -- Base Net ROAS (lifetime)
    SAFE_DIVIDE(la.total_orders * ae.margin_per_unit, NULLIF(la.total_spend, 0)) as lifetime_net_roas
  FROM lifetime_ads la
  JOIN asin_economics ae ON la.asin = ae.asin
),

-- =============================================
-- 2. FACTOR: Seasonality (current month CVR vs trailing average)
-- =============================================
monthly_cvr AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    fa.advertised_asins as asin,
    EXTRACT(MONTH FROM fa.date) as month_num,
    SUM(fa.Ads_clicks) as month_clicks,
    SUM(fa.Ads_orders) as month_orders,
    SAFE_DIVIDE(SUM(fa.Ads_orders), NULLIF(SUM(fa.Ads_clicks), 0)) as month_cvr
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
    AND fa.advertised_asins IS NOT NULL
    AND fa.Ads_clicks > 0
  GROUP BY 1, 2, 3
  HAVING SUM(fa.Ads_clicks) >= 3  -- minimum per-month threshold
),

seasonality_factor AS (
  SELECT
    mc.search_term,
    mc.asin,
    mc.month_num,
    mc.month_cvr,
    -- Average CVR across all months for this term
    AVG(mc.month_cvr) OVER (PARTITION BY mc.search_term, mc.asin) as avg_all_months_cvr,
    -- Seasonality multiplier: how much better/worse is current month vs average
    -- Capped between 0.5x and 1.8x to prevent extreme swings
    LEAST(1.8, GREATEST(0.5,
      SAFE_DIVIDE(mc.month_cvr, NULLIF(AVG(mc.month_cvr) OVER (PARTITION BY mc.search_term, mc.asin), 0))
    )) as seasonality_multiplier
  FROM monthly_cvr mc
),

current_month_seasonality AS (
  SELECT search_term, asin, seasonality_multiplier, month_cvr
  FROM seasonality_factor
  WHERE month_num = EXTRACT(MONTH FROM CURRENT_DATE())
),

-- Which month is the peak season for this keyword+ASIN?
peak_season_month AS (
  SELECT search_term, asin, month_num as best_season_month, month_cvr as best_season_month_cvr
  FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY search_term, asin ORDER BY month_cvr DESC) as rn
    FROM seasonality_factor
  )
  WHERE rn = 1
),

-- Which product (ASIN) converts best for each keyword?
hero_product AS (
  SELECT search_term, hero_asin, hero_product_name
  FROM (
    SELECT
      search_term,
      asin as hero_asin,
      product_short_name as hero_product_name,
      ROW_NUMBER() OVER (PARTITION BY search_term ORDER BY base_cvr DESC, total_orders DESC) as rn
    FROM product_baseline
    WHERE total_orders > 0
  )
  WHERE rn = 1
),

-- =============================================
-- 3. FACTOR: Peak Events (upcoming peak in next 30 days from DIM_TIME)
-- =============================================
upcoming_peak AS (
  SELECT
    MAX(traffic_multiplier) as peak_traffic_multiplier,
    MAX(expected_conversion_rate) as peak_expected_cvr,
    MAX(CASE WHEN is_peak_selling_period THEN 1 ELSE 0 END) as has_peak,
    MAX(peak_period_description) as peak_description
  FROM `onyga-482313.OI.DIM_TIME`
  WHERE full_date BETWEEN CURRENT_DATE() AND DATE_ADD(CURRENT_DATE(), INTERVAL 30 DAY)
    AND (is_peak_selling_period = TRUE OR traffic_multiplier > 1.2)
),

-- Peak factor: if a peak is coming, boost the prediction
peak_factor AS (
  SELECT
    CASE
      WHEN has_peak = 1 AND peak_traffic_multiplier > 1.0
        THEN LEAST(1.8, peak_traffic_multiplier)  -- cap at 1.8x
      ELSE 1.0
    END as peak_multiplier,
    peak_description
  FROM upcoming_peak
),

-- =============================================
-- 4. FACTOR: CPC Trend (recent 60d CPC vs older CPC — inflation)
-- =============================================
cpc_recent AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    fa.advertised_asins as asin,
    SAFE_DIVIDE(SUM(fa.Ads_cost), NULLIF(SUM(fa.Ads_clicks), 0)) as recent_cpc
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
    AND fa.advertised_asins IS NOT NULL
    AND fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
    AND fa.Ads_clicks > 0
  GROUP BY 1, 2
  HAVING SUM(fa.Ads_clicks) >= 3
),

cpc_older AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    fa.advertised_asins as asin,
    SAFE_DIVIDE(SUM(fa.Ads_cost), NULLIF(SUM(fa.Ads_clicks), 0)) as older_cpc
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
    AND fa.advertised_asins IS NOT NULL
    AND fa.date < DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
    AND fa.Ads_clicks > 0
  GROUP BY 1, 2
  HAVING SUM(fa.Ads_clicks) >= 3
),

cpc_trend AS (
  SELECT
    COALESCE(cr.search_term, co.search_term) as search_term,
    COALESCE(cr.asin, co.asin) as asin,
    cr.recent_cpc,
    co.older_cpc,
    -- CPC inflation ratio (>1 means CPC got more expensive)
    SAFE_DIVIDE(cr.recent_cpc, NULLIF(co.older_cpc, 0)) as cpc_inflation_ratio,
    -- Predicted CPC: use recent CPC (the market reality) not the historical average
    COALESCE(cr.recent_cpc, co.older_cpc) as predicted_cpc
  FROM cpc_recent cr
  FULL OUTER JOIN cpc_older co ON cr.search_term = co.search_term AND cr.asin = co.asin
),

-- =============================================
-- 5. FACTOR: TOS (Top-of-Search) CVR Boost
--    Campaign-level placement data → estimate keyword TOS advantage
-- =============================================
tos_by_campaign AS (
  SELECT
    campaign_id,
    -- TOS CVR (Using Search_Results as a proxy for TOS from FACT_AMAZON_ADS)
    SAFE_DIVIDE(
      SUM(CASE WHEN placement_type = 'Search_Results' THEN Ads_orders ELSE 0 END),
      NULLIF(SUM(CASE WHEN placement_type = 'Search_Results' THEN Ads_clicks ELSE 0 END), 0)
    ) as tos_cvr,
    -- Rest-of-search CVR
    SAFE_DIVIDE(
      SUM(CASE WHEN placement_type != 'Search_Results' THEN Ads_orders ELSE 0 END),
      NULLIF(SUM(CASE WHEN placement_type != 'Search_Results' THEN Ads_clicks ELSE 0 END), 0)
    ) as ros_cvr,
    -- TOS share of clicks
    SAFE_DIVIDE(
      SUM(CASE WHEN placement_type = 'Search_Results' THEN Ads_clicks ELSE 0 END),
      NULLIF(SUM(Ads_clicks), 0)
    ) as tos_click_share
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
    AND Ads_clicks > 0
  GROUP BY 1
  HAVING SUM(Ads_clicks) >= 10
),

-- Map keywords to campaigns, then inherit campaign TOS profile
keyword_tos AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    fa.advertised_asins as asin,
    -- Weighted average TOS CVR boost across all campaigns this keyword runs in
    SAFE_DIVIDE(
      SUM(tc.tos_cvr * tc.tos_click_share),
      NULLIF(SUM(tc.tos_click_share), 0)
    ) as weighted_tos_cvr,
    AVG(tc.ros_cvr) as avg_ros_cvr,
    AVG(tc.tos_click_share) as avg_tos_share,
    -- TOS CVR boost: how much better is TOS vs Rest-of-search
    -- Capped at 1.8x to prevent wild predictions
    LEAST(1.8, GREATEST(1.0,
      SAFE_DIVIDE(
        SAFE_DIVIDE(SUM(tc.tos_cvr * tc.tos_click_share), NULLIF(SUM(tc.tos_click_share), 0)),
        NULLIF(AVG(tc.ros_cvr), 0)
      )
    )) as tos_cvr_boost
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  JOIN tos_by_campaign tc ON fa.campaign_id = tc.campaign_id
  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
    AND fa.advertised_asins IS NOT NULL
    AND fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  GROUP BY 1, 2
),

-- =============================================
-- 6. FACTOR: Organic Potential (SQP organic conversion velocity)
-- =============================================
sqp_organic AS (
  SELECT
    LOWER(fsq.query_text) as search_term,
    fsq.ASIN as asin,
    SUM(fsq.conversions) as sqp_total_purchases,
    SUM(fsq.clicks) as sqp_total_clicks,
    SUM(fsq.impressions) as sqp_total_impressions,
    COUNT(DISTINCT fsq.week_end_date) as sqp_weeks_seen,
    -- Organic CVR
    SAFE_DIVIDE(SUM(fsq.conversions), NULLIF(SUM(fsq.clicks), 0)) as sqp_cvr,
    -- Average weekly purchases (organic velocity)
    SAFE_DIVIDE(SUM(fsq.conversions), NULLIF(COUNT(DISTINCT fsq.week_end_date), 0)) as organic_weekly_velocity
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
  WHERE fsq.data_source = 'SQP'
    AND fsq.conversions >= 0
  GROUP BY 1, 2
),

organic_factor AS (
  SELECT
    search_term,
    asin,
    sqp_total_purchases,
    sqp_total_clicks,
    sqp_total_impressions,
    sqp_weeks_seen,
    sqp_cvr,
    organic_weekly_velocity,
    -- Organic halo: if the keyword converts well organically,
    -- ads performance should be better because organic ranking reinforces ad clicks.
    -- Scale: 1.0 (no organic) → up to 1.3 (strong organic presence)
    LEAST(1.3, GREATEST(1.0,
      1.0 + (LEAST(organic_weekly_velocity, 5.0) / 5.0) * 0.3
    )) as organic_halo_multiplier
  FROM sqp_organic
),

-- =============================================
-- FINAL: Combine all 6 factors into Predicted Net ROAS
-- =============================================
predictions AS (
  SELECT
    pb.search_term,
    pb.asin,
    pb.product_short_name,
    pb.parent_name,
    pb.margin_per_unit,

    -- Raw lifetime metrics
    pb.total_clicks,
    pb.total_orders,
    pb.total_spend,
    pb.total_impressions,
    pb.days_with_data,
    pb.first_seen,
    pb.last_seen,

    -- Factor 1: Product baseline
    ROUND(pb.base_cvr, 4) as base_cvr,
    ROUND(pb.base_cpc, 2) as base_cpc,
    ROUND(pb.lifetime_net_roas, 2) as lifetime_net_roas,

    -- Factor 2: Seasonality
    CASE WHEN sm.seasonality_multiplier IS NOT NULL THEN TRUE ELSE FALSE END as has_seasonal_data,
    ROUND(COALESCE(sm.seasonality_multiplier, 1.0), 2) as seasonality_multiplier,
    ROUND(COALESCE(sm.month_cvr, pb.base_cvr), 4) as current_month_cvr,
    psm.best_season_month,
    ROUND(psm.best_season_month_cvr, 4) as best_season_month_cvr,

    -- Hero product: which product converts best for this keyword
    hp.hero_product_name,

    -- Factor 3: Peak
    ROUND(COALESCE(pf.peak_multiplier, 1.0), 2) as peak_multiplier,
    pf.peak_description,

    -- Factor 4: CPC Trend
    ROUND(COALESCE(ct.predicted_cpc, pb.base_cpc), 2) as predicted_cpc,
    ROUND(COALESCE(ct.cpc_inflation_ratio, 1.0), 2) as cpc_inflation_ratio,
    ROUND(ct.recent_cpc, 2) as recent_cpc,
    ROUND(ct.older_cpc, 2) as older_cpc,

    -- Factor 5: TOS
    ROUND(COALESCE(kt.tos_cvr_boost, 1.0), 2) as tos_cvr_boost,
    ROUND(kt.avg_tos_share, 2) as tos_click_share,
    ROUND(kt.weighted_tos_cvr, 4) as tos_cvr,

    -- Factor 6: Organic
    ROUND(COALESCE(org.organic_halo_multiplier, 1.0), 2) as organic_halo_multiplier,
    COALESCE(org.sqp_total_purchases, 0) as sqp_total_purchases,
    ROUND(COALESCE(org.organic_weekly_velocity, 0), 2) as organic_weekly_velocity,
    ROUND(org.sqp_cvr, 4) as sqp_cvr,

    -- ═══════════════════════════════════════════
    -- PREDICTED CVR: base × seasonality × peak × organic_halo
    -- Compound cap: max 1.8x total boost on CVR
    -- ═══════════════════════════════════════════
    ROUND(
      pb.base_cvr * LEAST(1.8,
        COALESCE(sm.seasonality_multiplier, 1.0)
        * COALESCE(pf.peak_multiplier, 1.0)
        * COALESCE(org.organic_halo_multiplier, 1.0)
      )
    , 4) as predicted_cvr,

    -- ═══════════════════════════════════════════
    -- PREDICTED NET ROAS:
    --   (predicted_cvr × margin_per_unit) / predicted_cpc
    -- ═══════════════════════════════════════════
    ROUND(
      SAFE_DIVIDE(
        pb.base_cvr
        * LEAST(1.8,
            COALESCE(sm.seasonality_multiplier, 1.0)
            * COALESCE(pf.peak_multiplier, 1.0)
            * COALESCE(org.organic_halo_multiplier, 1.0)
          )
        * pb.margin_per_unit,
        NULLIF(COALESCE(ct.predicted_cpc, pb.base_cpc), 0)
      )
    , 2) as predicted_net_roas

  FROM product_baseline pb
  LEFT JOIN current_month_seasonality sm
    ON pb.search_term = sm.search_term AND pb.asin = sm.asin
  CROSS JOIN peak_factor pf
  LEFT JOIN cpc_trend ct
    ON pb.search_term = ct.search_term AND pb.asin = ct.asin
  LEFT JOIN keyword_tos kt
    ON pb.search_term = kt.search_term AND pb.asin = kt.asin
  LEFT JOIN organic_factor org
    ON pb.search_term = org.search_term AND pb.asin = org.asin
  LEFT JOIN peak_season_month psm
    ON pb.search_term = psm.search_term AND pb.asin = psm.asin
  LEFT JOIN hero_product hp
    ON pb.search_term = hp.search_term
)

SELECT
  *,
  -- ═══════════════════════════════════════════
  -- STRATEGIC SIGNAL: classify based on predicted ROAS + context
  -- ═══════════════════════════════════════════
  CASE
    -- High predicted ROAS + strong history = scale aggressively
    WHEN predicted_net_roas >= 2.0 AND total_orders >= 5
      THEN 'SCALE_WINNER'
    -- Good predicted ROAS but seasonal boost is the main driver
    WHEN predicted_net_roas >= 1.5 AND seasonality_multiplier >= 1.3
      THEN 'SEASONAL_OPPORTUNITY'
    -- Profitable at current economics
    WHEN predicted_net_roas >= 1.0 AND predicted_net_roas < 2.0
      THEN 'PROFITABLE_HOLD'
    -- Marginal but could become profitable with organic halo
    WHEN predicted_net_roas >= 0.7 AND organic_halo_multiplier >= 1.1
      THEN 'ORGANIC_ASSISTED'
    -- CPC is inflating faster than CVR — declining economics
    WHEN predicted_net_roas < 0.7 AND cpc_inflation_ratio > 1.3
      THEN 'CPC_SQUEEZE'
    -- Low predicted ROAS, no organic safety net
    WHEN predicted_net_roas < 0.5
      THEN 'UNPROFITABLE'
    -- Default: marginal territory
    WHEN predicted_net_roas < 1.0
      THEN 'MARGINAL'
    ELSE 'MONITOR'
  END as strategic_signal,

  -- Confidence score: how much data backs this prediction (0-100)
  LEAST(100, ROUND(
    LEAST(total_clicks / 50.0, 1.0) * 40   -- click volume (max 40 pts)
    + LEAST(days_with_data / 60.0, 1.0) * 30  -- time coverage (max 30 pts)
    + CASE WHEN sqp_total_purchases > 0 THEN 15 ELSE 0 END  -- SQP data exists (15 pts)
    + CASE WHEN tos_cvr IS NOT NULL THEN 15 ELSE 0 END       -- TOS data exists (15 pts)
  , 0)) as prediction_confidence

FROM predictions;
