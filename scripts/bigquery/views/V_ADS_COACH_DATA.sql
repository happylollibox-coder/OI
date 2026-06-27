-- =============================================
-- OI Database Project - V_ADS_COACH_DATA View
-- =============================================
--
-- Purpose: PURE DATA — all metrics at campaign × asin × search_term grain.
--          NO decision logic. This view is the data foundation for V_ADS_COACH.
--
-- Grain: campaign_id × asin × search_term  (ACTIVE_TERM rows)
--        NULL campaign × asin × search_term (OPPORTUNITY rows — SQP only, no ads)
--
-- Dual-grain support:
--   • search_term grain: for NEGATE, PROMOTE_TO_EXACT decisions
--   • target keyword grain (via target_* columns): for INCREASE/REDUCE_BID, SCALE_UP
--
-- Windows provided per row:
--   • Per-campaign 8w ads metrics (search term level)
--   • Per-campaign 1w + 4w ads metrics (for weighted ROAS)
--   • Weighted Net ROAS = 1w×0.5 + 4w×0.3 + 8w×0.2
--   • Target keyword rollup (aggregate all search terms under same target)
--   • Recent 5d ads activity (bleeding detection)
--   • Cross-campaign 8w aggregates (same keyword across ALL campaigns)
--   • Lifetime (all-time) ads metrics
--   • LY Peak ads metrics (last year's matching holiday season)
--   • SQP 8w: your ASIN + Amazon market measures
--   • SQP LY Peak: your ASIN + Amazon market measures
--   • Hero ASIN context (best child for this keyword)
--   • Search term segment/classification
--   • Unit economics (margin)
--
-- Dependencies:
--   FACT_AMAZON_ADS, FACT_SEARCH_QUERY,
--   DIM_PRODUCT, DIM_COSTS_HISTORY, DIM_EXPERIMENT, DIM_EXPERIMENT_CAMPAIGN,
--   DIM_STRATEGY_TEMPLATE, DIM_US_HOLIDAYS,
--   V_PARENT_HERO_ASIN, V_SEARCH_TERM_SEGMENT,
--   DIM_CAMPAIGN
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_COACH_DATA`
AS
WITH

-- =============================================
-- Unit economics per ASIN
-- =============================================
asin_economics AS (
  SELECT
    p.asin,
    p.product_short_name,
    p.parent_name,
    p.listing_price_amount,
    COALESCE(ch.TOTAL_COST_PER_UNIT, 0) as total_cost_per_unit,
    p.listing_price_amount - COALESCE(ch.TOTAL_COST_PER_UNIT, 0) as margin_per_unit
  FROM `onyga-482313.OI.DIM_PRODUCT` p
  LEFT JOIN (
    SELECT asin, TOTAL_COST_PER_UNIT,
      ROW_NUMBER() OVER (PARTITION BY asin ORDER BY end_date DESC NULLS FIRST) as rn
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  ) ch ON p.asin = ch.asin AND ch.rn = 1
  WHERE p.asin IS NOT NULL
),

-- =============================================
-- Active experiments + campaigns → strategy mapping
-- =============================================
active_experiments AS (
  SELECT
    e.experiment_id,
    e.experiment_name,
    e.strategy_id,
    e.start_date,
    st.strategy_name,
    st.recommended_bid_min,
    st.recommended_bid_max
  FROM `onyga-482313.OI.DIM_EXPERIMENT` e
  LEFT JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st ON e.strategy_id = st.strategy_id
  WHERE e.status = 'ACTIVE'
),

campaign_experiment AS (
  SELECT
    ec.campaign_id,
    ae.experiment_id,
    ae.experiment_name,
    ae.strategy_id,
    ae.strategy_name,
    ae.start_date,
    ae.recommended_bid_max
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN active_experiments ae ON ec.experiment_id = ae.experiment_id
),

-- =============================================
-- Holiday BOOST/PEAK date ranges (for off-season ROAS exclusion)
-- Guardian mode should evaluate performance on off-season data only,
-- excluding dates that fall within BOOST or PEAK phases of any holiday.
-- =============================================
holiday_boost_peak_dates AS (
  SELECT
    boost_start as phase_start,
    COALESCE(cooldown_start, holiday_date) as phase_end  -- BOOST+PEAK ends when cooldown begins
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
  WHERE category = 'gift_season'
    AND boost_start IS NOT NULL
),

-- Last completed BOOST+PEAK holiday (most recent one that ended)
last_completed_peak AS (
  SELECT holiday_name, holiday_date, boost_start,
    COALESCE(cooldown_start, holiday_date) as peak_end
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
  WHERE category = 'gift_season'
    AND boost_start IS NOT NULL
    AND COALESCE(cooldown_start, holiday_date) < CURRENT_DATE('America/Los_Angeles')
  ORDER BY holiday_date DESC LIMIT 1
),

-- Last year's same-name holiday BOOST+PEAK range
-- e.g., if next holiday is Christmas 2026, this finds Christmas 2025
ly_same_holiday_peak AS (
  SELECT h.holiday_name, h.holiday_date, h.boost_start,
    COALESCE(h.cooldown_start, h.holiday_date) as peak_end
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
  -- Match to the next upcoming holiday (same logic as next_holiday CTE)
  JOIN (
    SELECT holiday_name FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
    WHERE category = 'gift_season' AND holiday_date >= CURRENT_DATE('America/Los_Angeles')
    ORDER BY holiday_date ASC LIMIT 1
  ) nh ON h.holiday_name = nh.holiday_name
  WHERE h.category = 'gift_season'
    AND h.boost_start IS NOT NULL
    AND h.holiday_date < CURRENT_DATE('America/Los_Angeles')
  ORDER BY h.holiday_date DESC LIMIT 1
),

-- =============================================
-- LY Peak date range (for both Ads and SQP)
-- =============================================
next_holiday AS (
  SELECT holiday_name, holiday_date, pre_season_start
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
  WHERE category = 'gift_season' AND holiday_date >= CURRENT_DATE('America/Los_Angeles')
  ORDER BY holiday_date ASC LIMIT 1
),
ly_holiday AS (
  SELECT h.*
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
  JOIN next_holiday nh ON h.holiday_name = nh.holiday_name
  WHERE h.category = 'gift_season' AND h.holiday_date < nh.holiday_date
  ORDER BY h.holiday_date DESC LIMIT 1
),

-- =============================================
-- Campaign config: current bids from SCD2 DIM tables (live Fivetran data)
-- =============================================
-- Deduplicated: DIM_KEYWORD may have multiple is_current rows per keyword_id
campaign_config AS (
  SELECT campaign_id, keyword_text, keyword_id, keyword_bid
  FROM (
    SELECT
      campaign_id,
      LOWER(keyword_text) as keyword_text,
      keyword_id,
      bid as keyword_bid,
      ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id ORDER BY bid DESC) as rn
    FROM `onyga-482313.OI.DIM_KEYWORD`
    WHERE is_current = TRUE
      AND match_type NOT IN ('Automatic', 'ASIN', 'ASIN Expended', 'Category')
      AND UPPER(state) = 'ENABLED'
  )
  WHERE rn = 1
),

-- Product targeting config: AUTO targeting groups + ASIN targets (from DIM_KEYWORD)
-- Deduplicated: DIM_KEYWORD may have multiple is_current rows per keyword_id
campaign_config_pt AS (
  SELECT campaign_id, product_targeting_id, product_targeting_expression, pt_bid
  FROM (
    SELECT
      campaign_id,
      keyword_id as product_targeting_id,
      LOWER(keyword_text) as product_targeting_expression,
      bid as pt_bid,
      ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id ORDER BY bid DESC) as rn
    FROM `onyga-482313.OI.DIM_KEYWORD`
    WHERE is_current = TRUE
      AND match_type IN ('Automatic', 'ASIN', 'ASIN Expanded', 'Category')
      AND UPPER(state) = 'ENABLED'
  )
  WHERE rn = 1
),

-- Deduplicated: campaigns with multiple ad groups pick the highest default bid
campaign_config_ag AS (
  SELECT campaign_id, ad_group_default_bid
  FROM (
    SELECT campaign_id, default_bid as ad_group_default_bid,
      ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY default_bid DESC) as rn
    FROM `onyga-482313.OI.DIM_AD_GROUP`
    WHERE is_current = TRUE
  )
  WHERE rn = 1
),

-- Deduplicated: same as campaign_config for SB
campaign_config_sb AS (
  SELECT campaign_id, keyword_id, keyword_text, keyword_bid
  FROM (
    SELECT
      campaign_id,
      keyword_id,
      LOWER(keyword_text) as keyword_text,
      bid as keyword_bid,
      ROW_NUMBER() OVER (PARTITION BY campaign_id, keyword_id ORDER BY bid DESC) as rn
    FROM `onyga-482313.OI.DIM_KEYWORD`
    WHERE is_current = TRUE
      AND match_type NOT IN ('Automatic', 'ASIN', 'ASIN Expended', 'Category')
      AND UPPER(state) = 'ENABLED'
  )
  WHERE rn = 1
),

-- =============================================
-- Campaign placement adjustments (current values from V_CAMPAIGN_PLACEMENT_BIDDING)
-- =============================================
campaign_placements AS (
  SELECT
    campaign_id,
    MAX(CASE WHEN placement = 'TOP_OF_SEARCH' THEN bid_adjustment_pct ELSE 0 END) as tos_pct,
    MAX(CASE WHEN placement = 'DETAIL_PAGE' THEN bid_adjustment_pct ELSE 0 END) as product_page_pct,
    MAX(CASE WHEN placement = 'AMAZON_BUSINESS' THEN bid_adjustment_pct ELSE 0 END) as b2b_pct
  FROM `onyga-482313.OI.V_CAMPAIGN_PLACEMENT_BIDDING`
  GROUP BY campaign_id
),

-- =============================================
-- Pre-peak snapshot (for Cooldown restore-to-baseline)
-- Joined by campaign × targeting to get pre-peak bid, adjustments, and CPC baseline
-- =============================================
pre_peak_snap AS (
  SELECT
    s.campaign_id,
    s.targeting,
    s.pre_peak_bid,
    s.tos_pct as pre_peak_tos_pct,
    s.product_page_pct as pre_peak_pp_pct,
    s.b2b_pct as pre_peak_b2b_pct,
    s.avg_cpc_30d as pre_peak_avg_cpc,
    s.avg_daily_spend_30d as pre_peak_avg_daily_spend,
    s.avg_daily_orders_30d as pre_peak_avg_daily_orders
  FROM `onyga-482313.OI.DE_PRE_PEAK_SNAPSHOT` s
  -- Use latest snapshot (closest holiday) that is still in Cooldown window
  QUALIFY ROW_NUMBER() OVER (PARTITION BY s.campaign_id, s.targeting ORDER BY s.holiday_date DESC) = 1
),

-- =============================================
-- Latest day CPC per campaign × targeting
-- =============================================
latest_day_cpc AS (
  SELECT
    campaign_id, targeting,
    ROUND(SAFE_DIVIDE(SUM(Ads_cost), NULLIF(SUM(Ads_clicks), 0)), 2) as last_day_cpc,
    MAX(date) as last_day_date
  FROM `onyga-482313.OI.FACT_AMAZON_ADS`
  WHERE date = (SELECT MAX(date) FROM `onyga-482313.OI.FACT_AMAZON_ADS`)
  GROUP BY campaign_id, targeting
),

-- =============================================
-- Campaign current budget (from latest campaign_history)
-- =============================================
campaign_current_budget AS (
  SELECT
    campaign_id,
    daily_budget as current_budget
  FROM `onyga-482313.OI.DIM_CAMPAIGN`
  WHERE state = 'ENABLED' AND is_current = TRUE
),

-- =============================================
-- Campaign current state (latest state from campaign_history, SP + SB)
-- Unlike campaign_current_budget, this includes ALL states (ENABLED, PAUSED, ARCHIVED)
-- =============================================
campaign_current_state AS (
  SELECT campaign_id, state as campaign_state, creation_date as campaign_creation_date
  FROM `onyga-482313.OI.DIM_CAMPAIGN`
  WHERE is_current = TRUE
),

-- =============================================
-- Campaign pre-peak budget (from before boost_start of nearest active holiday)
-- For campaigns created during/after boost, use their first recorded budget
-- =============================================
campaign_pre_peak_budget AS (
  SELECT
    ch.campaign_id,
    ch.daily_budget as pre_peak_budget
  FROM `onyga-482313.OI.DIM_CAMPAIGN` ch
  CROSS JOIN (
    -- Get the boost_start of the nearest holiday in cooldown now
    SELECT MIN(boost_start) as boost_start
    FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
    WHERE category = 'gift_season'
      AND CURRENT_DATE('America/New_York') BETWEEN cooldown_start AND cooldown_end
  ) h
  WHERE ch.state = 'ENABLED'
    -- Either before boost started, or the earliest record for newer campaigns
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY ch.campaign_id
    ORDER BY
      CASE WHEN ch.effective_from < DATETIME(TIMESTAMP(h.boost_start)) THEN 0 ELSE 1 END,
      CASE WHEN ch.effective_from < DATETIME(TIMESTAMP(h.boost_start)) THEN ch.effective_from END DESC,
      ch.effective_from ASC
  ) = 1
),

-- =============================================
-- Days since last bid change per keyword (from DIM_KEYWORD SCD2)
-- Finds the most recent row where the bid actually changed
-- =============================================
keyword_last_bid_change AS (
  SELECT keyword_id,
    DATE(effective_from) as last_bid_change_date,
    DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), DATE(effective_from), DAY) as days_since_last_bid_change
  FROM (
    SELECT keyword_id, bid, effective_from,
      LAG(bid) OVER (PARTITION BY keyword_id ORDER BY effective_from) as prev_bid
    FROM `onyga-482313.OI.DIM_KEYWORD`
  )
  WHERE bid != prev_bid OR prev_bid IS NULL  -- bid actually changed
  QUALIFY ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY effective_from DESC) = 1
),

-- =============================================
-- Days since WE last logged a change for a target / campaign (FACT_PPC_CHANGE_LOG = the
-- authoritative upload time; DIM_KEYWORD/DIM_CAMPAIGN SCD2 lags ~1-2d behind our uploads).
-- Drives the 3-day "no re-suggest" cooldown applied in V_ADS_COACH.
-- =============================================
suggestion_by_keyword AS (
  SELECT campaign_id, keyword_id,
    DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), MAX(DATE(applied_at, 'America/Los_Angeles')), DAY) AS days_since
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE keyword_id IS NOT NULL AND keyword_id != ''
  GROUP BY 1, 2
),
suggestion_by_targeting AS (
  SELECT campaign_id, LOWER(targeting) AS targeting_lc,
    DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), MAX(DATE(applied_at, 'America/Los_Angeles')), DAY) AS days_since
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE targeting IS NOT NULL AND targeting != ''
  GROUP BY 1, 2
),
suggestion_by_campaign AS (
  SELECT campaign_id,
    DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), MAX(DATE(applied_at, 'America/Los_Angeles')), DAY) AS days_since
  FROM `onyga-482313.OI.FACT_PPC_CHANGE_LOG`
  WHERE campaign_id IS NOT NULL AND campaign_id != ''
  GROUP BY 1
),

-- =============================================
-- Clicks accrued since the last bid change per keyword (launch-track batch gate)
-- Lets the launch loop fire a -20% reduce ONCE per 15-click batch, not every refresh.
-- =============================================
keyword_clicks_since_bid_change AS (
  SELECT fa.keyword_id,
    SUM(fa.Ads_clicks) as clicks_since_last_bid_change
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  JOIN keyword_last_bid_change klbc ON fa.keyword_id = klbc.keyword_id
  WHERE fa.keyword_id IS NOT NULL
    AND fa.date >= klbc.last_bid_change_date
    AND fa.date <= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY)
  GROUP BY 1
),

-- =============================================
-- Days since last budget change per campaign (from DIM_CAMPAIGN SCD2)
-- Finds the most recent row where the daily_budget actually changed
-- =============================================
campaign_last_budget_change AS (
  SELECT campaign_id,
    DATE_DIFF(CURRENT_DATE('America/Los_Angeles'), DATE(effective_from), DAY) as days_since_last_budget_change
  FROM (
    SELECT campaign_id, daily_budget, effective_from,
      LAG(daily_budget) OVER (PARTITION BY campaign_id ORDER BY effective_from) as prev_budget
    FROM `onyga-482313.OI.DIM_CAMPAIGN`
  )
  WHERE daily_budget != prev_budget OR prev_budget IS NULL  -- budget actually changed
  QUALIFY ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY effective_from DESC) = 1
),

-- =============================================
-- SECTION A: ACTIVE TERM DATA
-- Per campaign × asin × search_term
-- =============================================

-- Ads 8w: per campaign × asin × search_term (+ targeting/keyword_id)
ads_8w AS (
  SELECT
    ec.experiment_id,
    fa.campaign_id,
    ANY_VALUE(fa.ad_group_id HAVING MAX fa.date) as ad_group_id,
    -- Current campaign name from V_DIM_CAMPAIGN_CURRENT (prevents rename splits)
    dc_cur.campaign_name,
    fa.campaign_type,
    COALESCE(dc_cur.portfolio_name, 'Unassigned') as portfolio_name,
    ce.strategy_id,
    ce.strategy_name,
    ce.experiment_name,
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    -- Target keyword (what you bid on) — fallback to config keyword_text for SBV
    COALESCE(fa.targeting, LOWER(kw_lookup.keyword_text)) as targeting,
    fa.keyword_id,

    SUM(fa.Ads_cost) as ads_spend_8w,
    SUM(fa.Ads_orders) as ads_orders_8w,
    SUM(fa.Ads_units) as ads_units_8w,
    SUM(fa.Ads_clicks) as ads_clicks_8w,
    SUM(fa.Ads_impressions) as ads_impressions_8w,
    SUM(fa.Ads_sales) as ads_sales_8w,
    COUNT(DISTINCT fa.date) as ads_days_8w,
    MIN(fa.date) as first_seen_8w,
    MAX(fa.date) as last_seen_8w,
    -- Recent 5d bleeding detection
    SUM(CASE WHEN fa.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 5 DAY) THEN fa.Ads_clicks ELSE 0 END) as ads_clicks_recent_5d,
    -- Latest keyword status (ENABLED/PAUSED/ARCHIVED) per search_term
    UPPER(ANY_VALUE(fa.ad_keyword_status HAVING MAX fa.date)) as ad_keyword_status,
    -- Match type (latest) for the per-product strategy profile join
    UPPER(ANY_VALUE(fa.targeting_type HAVING MAX fa.date)) as targeting_type

  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN campaign_experiment ce ON ec.campaign_id = ce.campaign_id AND ec.experiment_id = ce.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON ec.campaign_id = fa.campaign_id
    AND fa.date BETWEEN DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 56 DAY)
                   AND DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY)
  -- Current campaign metadata — single source of truth
  LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` dc_cur ON fa.campaign_id = dc_cur.campaign_id

  -- Keyword text lookup for SBV campaigns where targeting is NULL (deduplicated)
  LEFT JOIN (
    SELECT keyword_id, keyword_text FROM (
      SELECT keyword_id, keyword_text,
        ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY keyword_text) as rn
      FROM `onyga-482313.OI.DIM_KEYWORD`
      WHERE is_current = TRUE AND keyword_text IS NOT NULL AND keyword_id IS NOT NULL
    ) WHERE rn = 1
  ) kw_lookup ON fa.keyword_id = kw_lookup.keyword_id
  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
),

-- Ads 1w: recent 7 complete days (skip 3d attribution lag)
-- Today=March 22 → 1w = March 12–18
ads_1w AS (
  SELECT
    fa.campaign_id,
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    fa.targeting,
    SUM(fa.Ads_cost) as ads_spend_1w,
    SUM(fa.Ads_orders) as ads_orders_1w,
    SUM(fa.Ads_units) as ads_units_1w,
    SUM(fa.Ads_clicks) as ads_clicks_1w,
    SUM(fa.Ads_impressions) as ads_impressions_1w,
    SUM(fa.Ads_sales) as ads_sales_1w
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.date BETWEEN DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)
                     AND DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2, 3, 4
),

-- Ads 4w: last 28 complete days (same attribution lag)
ads_4w AS (
  SELECT
    fa.campaign_id,
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    fa.targeting,
    SUM(fa.Ads_cost) as ads_spend_4w,
    SUM(fa.Ads_orders) as ads_orders_4w,
    SUM(fa.Ads_units) as ads_units_4w,
    SUM(fa.Ads_clicks) as ads_clicks_4w,
    SUM(fa.Ads_sales) as ads_sales_4w
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.date BETWEEN DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 28 DAY)
                     AND DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2, 3, 4
),

-- Target keyword rollup: aggregate all search terms under same target
-- This is what you actually bid on in Amazon
target_rollup AS (
  SELECT
    campaign_id,
    targeting,
    keyword_id,
    asin,
    SUM(ads_spend_8w) as target_spend_8w,
    SUM(ads_orders_8w) as target_orders_8w,
    SUM(ads_units_8w) as target_units_8w,
    SUM(ads_clicks_8w) as target_clicks_8w,
    SUM(ads_impressions_8w) as target_impressions_8w,
    SUM(ads_sales_8w) as target_sales_8w,
    COUNT(DISTINCT search_term) as target_search_term_count,
    SUM(ads_clicks_recent_5d) as target_clicks_recent_5d,
    -- Latest keyword status for this target (take the most recent non-null status)
    ANY_VALUE(ad_keyword_status HAVING MAX last_seen_8w) as target_keyword_status
  FROM ads_8w
  GROUP BY 1, 2, 3, 4
),

-- Target rollup 1w: for weighted ROAS at target level
target_rollup_1w AS (
  SELECT
    campaign_id, targeting, asin,
    SUM(ads_spend_1w) as target_spend_1w,
    SUM(ads_orders_1w) as target_orders_1w,
    SUM(ads_units_1w) as target_units_1w,
    SUM(ads_sales_1w) as target_sales_1w
  FROM ads_1w
  GROUP BY 1, 2, 3
),

-- Target rollup 4w: for weighted ROAS at target level
target_rollup_4w AS (
  SELECT
    campaign_id, targeting, asin,
    SUM(ads_spend_4w) as target_spend_4w,
    SUM(ads_orders_4w) as target_orders_4w,
    SUM(ads_clicks_4w) as target_clicks_4w,
    SUM(ads_units_4w) as target_units_4w,
    SUM(ads_sales_4w) as target_sales_4w
  FROM ads_4w
  GROUP BY 1, 2, 3
),

-- Clause-level 4w rollup at (campaign, targeting) — sums across ALL asins + search terms. An SP-Auto
-- auto-clause (loose-match etc.) bids once and serves every asin, so the launch track must judge the
-- whole clause; a per-asin slice (target_rollup_4w) can look profitable while the clause bleeds.
clause_rollup_4w AS (
  SELECT a4.campaign_id, a4.targeting,
    SUM(a4.ads_clicks_4w) as clause_clicks_4w,
    SUM(a4.ads_orders_4w) as clause_orders_4w,
    SUM(a4.ads_spend_4w) as clause_spend_4w,
    SUM(COALESCE(ae.margin_per_unit, 0) * COALESCE(a4.ads_units_4w, 0)) as clause_net_profit_4w
  FROM ads_4w a4
  JOIN asin_economics ae ON a4.asin = ae.asin
  GROUP BY 1, 2
),

-- Target rollup lag: the 3-day window excluded by the 4-day lag (today-3 to today-1)
-- Used as a "look-ahead safety check" before executing REDUCE_BID
target_rollup_lag AS (
  SELECT
    fa.campaign_id,
    COALESCE(fa.targeting, LOWER(kw_lookup.keyword_text)) as targeting,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    SUM(fa.Ads_cost) as target_lag_spend,
    SUM(fa.Ads_orders) as target_lag_orders,
    SUM(fa.Ads_units) as target_lag_units,
    SUM(fa.Ads_sales) as target_lag_sales
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  LEFT JOIN (
    SELECT keyword_id, keyword_text FROM (
      SELECT keyword_id, keyword_text,
        ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY keyword_text) as rn
      FROM `onyga-482313.OI.DIM_KEYWORD`
      WHERE is_current = TRUE AND keyword_text IS NOT NULL AND keyword_id IS NOT NULL
    ) WHERE rn = 1
  ) kw_lookup ON fa.keyword_id = kw_lookup.keyword_id
  WHERE fa.date BETWEEN DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 3 DAY)
                     AND DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2, 3
),

-- Term-level lag: same 3-day look-ahead but at search_term grain
-- Used for term negate safety check
ads_lag AS (
  SELECT
    fa.campaign_id,
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    COALESCE(fa.targeting, LOWER(kw_lookup.keyword_text)) as targeting,
    SUM(fa.Ads_cost) as lag_spend,
    SUM(fa.Ads_orders) as lag_orders,
    SUM(fa.Ads_units) as lag_units,
    SUM(fa.Ads_sales) as lag_sales
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  LEFT JOIN (
    SELECT keyword_id, keyword_text FROM (
      SELECT keyword_id, keyword_text,
        ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY keyword_text) as rn
      FROM `onyga-482313.OI.DIM_KEYWORD`
      WHERE is_current = TRUE AND keyword_text IS NOT NULL AND keyword_id IS NOT NULL
    ) WHERE rn = 1
  ) kw_lookup ON fa.keyword_id = kw_lookup.keyword_id
  WHERE fa.date BETWEEN DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 3 DAY)
                     AND DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2, 3, 4
),

-- Ads 3d: last 3 complete days (for BLITZ PEAK target decisions)
-- Uses days -6 to -4 (same 4-day attribution lag as all other windows)
ads_3d AS (
  SELECT
    fa.campaign_id,
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    fa.targeting,
    SUM(fa.Ads_cost) as ads_spend_3d,
    SUM(fa.Ads_orders) as ads_orders_3d,
    SUM(fa.Ads_units) as ads_units_3d,
    SUM(fa.Ads_clicks) as ads_clicks_3d,
    SUM(fa.Ads_sales) as ads_sales_3d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.date BETWEEN DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 3 DAY)
                     AND DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2, 3, 4
),

-- Ads 14d: last 14 complete days (for BLITZ BOOST term decisions)
ads_14d AS (
  SELECT
    fa.campaign_id,
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    fa.targeting,
    SUM(fa.Ads_cost) as ads_spend_14d,
    SUM(fa.Ads_orders) as ads_orders_14d,
    SUM(fa.Ads_units) as ads_units_14d,
    SUM(fa.Ads_clicks) as ads_clicks_14d,
    SUM(fa.Ads_sales) as ads_sales_14d
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.date BETWEEN DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
                     AND DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2, 3, 4
),

-- =============================================
-- OFF-SEASON aggregation: BOOST/PEAK days excluded
-- Used by GUARDIAN mode for cleaner ROAS evaluation
-- =============================================
ads_offseason AS (
  SELECT
    fa.campaign_id,
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    COALESCE(fa.targeting, LOWER(kw_lookup.keyword_text)) as targeting,
    -- 8w off-season
    SUM(fa.Ads_cost) as os_spend_8w,
    SUM(fa.Ads_orders) as os_orders_8w,
    SUM(fa.Ads_units) as os_units_8w,
    SUM(fa.Ads_sales) as os_sales_8w,
    SUM(fa.Ads_clicks) as os_clicks_8w,
    -- 4w off-season
    SUM(CASE WHEN fa.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 28 DAY) THEN fa.Ads_cost ELSE 0 END) as os_spend_4w,
    SUM(CASE WHEN fa.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 28 DAY) THEN fa.Ads_orders ELSE 0 END) as os_orders_4w,
    SUM(CASE WHEN fa.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 28 DAY) THEN fa.Ads_units ELSE 0 END) as os_units_4w,
    SUM(CASE WHEN fa.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 28 DAY) THEN fa.Ads_sales ELSE 0 END) as os_sales_4w,
    -- 1w off-season
    SUM(CASE WHEN fa.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY) THEN fa.Ads_cost ELSE 0 END) as os_spend_1w,
    SUM(CASE WHEN fa.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY) THEN fa.Ads_orders ELSE 0 END) as os_orders_1w,
    SUM(CASE WHEN fa.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY) THEN fa.Ads_units ELSE 0 END) as os_units_1w,
    SUM(CASE WHEN fa.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY) THEN fa.Ads_sales ELSE 0 END) as os_sales_1w

  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  -- Keyword text lookup for SBV campaigns
  LEFT JOIN (
    SELECT keyword_id, keyword_text FROM (
      SELECT keyword_id, keyword_text,
        ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY keyword_text) as rn
      FROM `onyga-482313.OI.DIM_KEYWORD`
      WHERE is_current = TRUE AND keyword_text IS NOT NULL AND keyword_id IS NOT NULL
    ) WHERE rn = 1
  ) kw_lookup ON fa.keyword_id = kw_lookup.keyword_id
  WHERE fa.date BETWEEN DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 56 DAY)
                     AND DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
    -- EXCLUDE all days that fall within BOOST or PEAK phases
    AND NOT EXISTS (
      SELECT 1 FROM holiday_boost_peak_dates h
      WHERE fa.date >= h.phase_start AND fa.date < h.phase_end
    )
  GROUP BY 1, 2, 3, 4
),

-- Off-season target-level rollup
target_rollup_offseason AS (
  SELECT
    campaign_id, targeting, asin,
    SUM(os_spend_8w) as target_os_spend_8w,
    SUM(os_orders_8w) as target_os_orders_8w,
    SUM(os_units_8w) as target_os_units_8w,
    SUM(os_sales_8w) as target_os_sales_8w,
    SUM(os_spend_4w) as target_os_spend_4w,
    SUM(os_orders_4w) as target_os_orders_4w,
    SUM(os_units_4w) as target_os_units_4w,
    SUM(os_sales_4w) as target_os_sales_4w,
    SUM(os_spend_1w) as target_os_spend_1w,
    SUM(os_orders_1w) as target_os_orders_1w,
    SUM(os_units_1w) as target_os_units_1w,
    SUM(os_sales_1w) as target_os_sales_1w
  FROM ads_offseason
  GROUP BY 1, 2, 3
),

-- Cross-campaign 8w: aggregate same keyword across ALL campaigns
-- (for reasoning: "does this keyword sell in OTHER campaigns?")
cross_campaign_8w AS (
  SELECT
    search_term,
    asin,
    SUM(ads_spend_8w) as xc_spend_8w,
    SUM(ads_orders_8w) as xc_orders_8w,
    SUM(ads_clicks_8w) as xc_clicks_8w,
    SUM(ads_impressions_8w) as xc_impressions_8w,
    SUM(ads_sales_8w) as xc_sales_8w,
    COUNT(DISTINCT campaign_id) as xc_campaign_count,
    COUNT(DISTINCT CASE WHEN ads_orders_8w > 0 THEN campaign_id END) as xc_selling_campaigns
  FROM ads_8w
  GROUP BY 1, 2
),

-- Ads lifetime: per term × ASIN (aggregated across all campaigns, all time)
ads_lifetime AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    SUM(fa.Ads_cost) as lt_spend,
    SUM(fa.Ads_orders) as lt_orders,
    SUM(fa.Ads_units) as lt_units,
    SUM(fa.Ads_clicks) as lt_clicks,
    SUM(fa.Ads_sales) as lt_sales,
    COUNT(DISTINCT fa.date) as lt_days,
    MIN(fa.date) as lt_first_seen,
    MAX(fa.date) as lt_last_seen
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2
),

-- Ads LY Peak: per term × ASIN
ads_ly_peak AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    SUM(fa.Ads_cost) as ly_spend,
    SUM(fa.Ads_orders) as ly_orders,
    SUM(fa.Ads_units) as ly_units,
    SUM(fa.Ads_clicks) as ly_clicks,
    SUM(fa.Ads_impressions) as ly_impressions,
    SUM(fa.Ads_sales) as ly_sales
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  CROSS JOIN ly_holiday lyh
  WHERE fa.date >= lyh.pre_season_start AND fa.date <= lyh.holiday_date
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2
),

-- =============================================
-- HOT-SEASON Components (for BLITZ / SEASONAL_PUSH ROAS)
-- Equally weighted: TY 14d + LY same holiday + Last peak
-- =============================================

-- Component 1: This Year last 14 days — CROSS-CAMPAIGN (term × asin)
ads_ty_14d AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    SUM(fa.Ads_cost) as ty14_spend,
    SUM(fa.Ads_orders) as ty14_orders,
    SUM(fa.Ads_units) as ty14_units,
    SUM(fa.Ads_sales) as ty14_sales,
    SUM(fa.Ads_clicks) as ty14_clicks
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.date BETWEEN DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 14 DAY)
                     AND DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 1 DAY)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2
),

-- Component 2: Last completed peak — CROSS-CAMPAIGN (term × asin)
ads_last_peak AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    SUM(fa.Ads_cost) as lp_spend,
    SUM(fa.Ads_orders) as lp_orders,
    SUM(fa.Ads_units) as lp_units,
    SUM(fa.Ads_sales) as lp_sales,
    SUM(fa.Ads_clicks) as lp_clicks
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  CROSS JOIN last_completed_peak lcp
  WHERE fa.date BETWEEN lcp.boost_start AND lcp.peak_end
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2
),

-- Component 3: LY same holiday (BOOST+PEAK of same-name holiday last year) — already cross-campaign
ads_ly_same_holiday AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    SUM(fa.Ads_cost) as lysh_spend,
    SUM(fa.Ads_orders) as lysh_orders,
    SUM(fa.Ads_units) as lysh_units,
    SUM(fa.Ads_sales) as lysh_sales,
    SUM(fa.Ads_clicks) as lysh_clicks
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  CROSS JOIN ly_same_holiday_peak lyshp
  WHERE fa.date BETWEEN lyshp.boost_start AND lyshp.peak_end
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2
),

-- =============================================
-- Q4 SEASONAL AUTO-DETECTION (cross-campaign, term-level)
-- Identifies terms profitable only during Q4 peak (BF/CM/Christmas)
-- =============================================
q4_seasonal_detection AS (
  SELECT
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    -- Q4 Peak metrics (all BF + CM + Christmas BOOST+PEAK phases, last 2 years)
    SUM(CASE WHEN EXISTS (
      SELECT 1 FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
      WHERE h.category = 'gift_season'
        AND h.holiday_name IN ('Black Friday', 'Cyber Monday', 'Christmas')
        AND fa.date BETWEEN h.boost_start AND h.cooldown_start
    ) THEN fa.Ads_cost ELSE 0 END) as q4_spend,
    SUM(CASE WHEN EXISTS (
      SELECT 1 FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
      WHERE h.category = 'gift_season'
        AND h.holiday_name IN ('Black Friday', 'Cyber Monday', 'Christmas')
        AND fa.date BETWEEN h.boost_start AND h.cooldown_start
    ) THEN fa.Ads_orders ELSE 0 END) as q4_orders,
    SUM(CASE WHEN EXISTS (
      SELECT 1 FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
      WHERE h.category = 'gift_season'
        AND h.holiday_name IN ('Black Friday', 'Cyber Monday', 'Christmas')
        AND fa.date BETWEEN h.boost_start AND h.cooldown_start
    ) THEN fa.Ads_sales ELSE 0 END) as q4_sales,
    SUM(CASE WHEN EXISTS (
      SELECT 1 FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
      WHERE h.category = 'gift_season'
        AND h.holiday_name IN ('Black Friday', 'Cyber Monday', 'Christmas')
        AND fa.date BETWEEN h.boost_start AND h.cooldown_start
    ) THEN fa.Ads_units ELSE 0 END) as q4_units,
    -- Off-season metrics (NOT in any BOOST+PEAK of any gift_season holiday)
    SUM(CASE WHEN NOT EXISTS (
      SELECT 1 FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
      WHERE h.category = 'gift_season'
        AND fa.date BETWEEN h.boost_start AND h.cooldown_end
    ) THEN fa.Ads_cost ELSE 0 END) as os_spend,
    SUM(CASE WHEN NOT EXISTS (
      SELECT 1 FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
      WHERE h.category = 'gift_season'
        AND fa.date BETWEEN h.boost_start AND h.cooldown_end
    ) THEN fa.Ads_orders ELSE 0 END) as os_orders,
    SUM(CASE WHEN NOT EXISTS (
      SELECT 1 FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
      WHERE h.category = 'gift_season'
        AND fa.date BETWEEN h.boost_start AND h.cooldown_end
    ) THEN fa.Ads_sales ELSE 0 END) as os_sales
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 18 MONTH)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2
),

-- Hot-season target-level rollup — CROSS-CAMPAIGN (targeting × asin)
target_rollup_hotseason AS (
  SELECT
    t14.search_term, t14.asin,
    SUM(t14.ty14_spend) as target_ty14_spend,
    SUM(t14.ty14_orders) as target_ty14_orders,
    SUM(t14.ty14_units) as target_ty14_units,
    SUM(t14.ty14_sales) as target_ty14_sales
  FROM ads_ty_14d t14
  GROUP BY 1, 2
),

target_rollup_last_peak AS (
  SELECT
    search_term, asin,
    SUM(lp_spend) as target_lp_spend,
    SUM(lp_orders) as target_lp_orders,
    SUM(lp_units) as target_lp_units,
    SUM(lp_sales) as target_lp_sales
  FROM ads_last_peak
  GROUP BY 1, 2
),

-- SQP 8w: Your ASIN + Amazon market measures
sqp_8w AS (
  SELECT
    LOWER(fsq.query_text) as search_term,
    fsq.ASIN as asin,
    -- Your ASIN measures
    SUM(fsq.impressions) as sqp_impressions_8w,
    SUM(fsq.clicks) as sqp_clicks_8w,
    SUM(fsq.cart_adds) as sqp_cart_adds_8w,
    SUM(fsq.conversions) as sqp_orders_8w,
    SUM(fsq.sales_amount) as sqp_sales_8w,
    AVG(fsq.show_rate_pct) as sqp_show_rate_8w,
    AVG(fsq.impression_share_pct) as sqp_impression_share_8w,
    AVG(fsq.estimated_organic_rank) as sqp_organic_rank_8w,
    -- Amazon market measures
    SUM(fsq.TOTAL_IMPRESSIONS) as sqp_amazon_impressions_8w,
    SUM(fsq.TOTAL_CLICKS) as sqp_amazon_clicks_8w,
    SUM(fsq.TOTAL_CART_ADDS) as sqp_amazon_cart_adds_8w,
    SUM(fsq.TOTAL_PURCHASES) as sqp_amazon_orders_8w,
    AVG(fsq.search_query_volume) as sqp_amazon_search_volume_8w,
    COUNT(DISTINCT fsq.week_end_date) as sqp_weeks_8w
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
  WHERE fsq.data_source = 'SQP' AND fsq.week_end_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 56 DAY)
  GROUP BY 1, 2
),

-- SQP LY Peak: Your ASIN + Amazon market measures
sqp_ly_peak AS (
  SELECT
    LOWER(fsq.query_text) as search_term,
    fsq.ASIN as asin,
    SUM(fsq.impressions) as sqp_ly_impressions,
    SUM(fsq.clicks) as sqp_ly_clicks,
    SUM(fsq.cart_adds) as sqp_ly_cart_adds,
    SUM(fsq.conversions) as sqp_ly_orders,
    SUM(fsq.sales_amount) as sqp_ly_sales,
    AVG(fsq.show_rate_pct) as sqp_ly_show_rate,
    AVG(fsq.impression_share_pct) as sqp_ly_impression_share,
    AVG(fsq.estimated_organic_rank) as sqp_ly_organic_rank,
    SUM(fsq.TOTAL_IMPRESSIONS) as sqp_ly_amazon_impressions,
    SUM(fsq.TOTAL_CLICKS) as sqp_ly_amazon_clicks,
    SUM(fsq.TOTAL_CART_ADDS) as sqp_ly_amazon_cart_adds,
    SUM(fsq.TOTAL_PURCHASES) as sqp_ly_amazon_orders,
    AVG(fsq.search_query_volume) as sqp_ly_amazon_search_volume
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
  CROSS JOIN ly_holiday lyh
  WHERE fsq.data_source = 'SQP'
    AND fsq.week_end_date >= lyh.pre_season_start AND fsq.week_end_date <= lyh.holiday_date
  GROUP BY 1, 2
),

-- Hero ASIN per search term × FAMILY (best product WITHIN each family).
-- Each family is an independent business unit: "birthday gifts" can have a Lollibox hero
-- AND a Truth-Or-Dare hero at once. is_hero_match means "best product in its OWN family".
-- ASINs with NULL parent_name match no hero row (LEFT JOIN → NULL hero_*) — intentional.
term_hero AS (
  SELECT
    search_term,
    asin as hero_asin,
    product_short_name as hero_product_name,
    parent_name as hero_parent_name,
    hero_score,
    sqp_cvr_pct as hero_sqp_cvr_pct,
    ads_cvr_pct as hero_ads_cvr_pct,
    confidence as hero_confidence
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY search_term, parent_name ORDER BY hero_score DESC) as family_rank
    FROM `onyga-482313.OI.V_PARENT_HERO_ASIN`
    WHERE hero_score > 0
  )
  WHERE family_rank = 1
),

-- Target-grain hero match: clicks-weighted majority of a keyword's search-term slices whose advertised
-- ASIN is the family hero. Lets the TARGET (bid) SWITCH_HERO branch judge the keyword as a whole instead
-- of fanning it into conflicting bid rows when individual queries diverge on hero (per-term hero
-- correction stays in the HERO/TERM action paths, which are legitimately search-term grained).
target_hero_match AS (
  SELECT
    a8.campaign_id,
    a8.targeting,
    a8.asin,
    COALESCE(
      SAFE_DIVIDE(
        SUM(CASE WHEN a8.asin = th.hero_asin THEN a8.ads_clicks_8w ELSE 0 END),
        NULLIF(SUM(a8.ads_clicks_8w), 0)
      ) >= 0.5, FALSE
    ) AS target_is_hero_match
  FROM ads_8w a8
  JOIN asin_economics ae ON a8.asin = ae.asin
  LEFT JOIN term_hero th ON a8.search_term = th.search_term AND ae.parent_name = th.hero_parent_name
  GROUP BY 1, 2, 3
),

-- Search term segment/classification
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

-- Check if term is already in an EXACT_BOOST experiment
exact_boost_terms AS (
  SELECT DISTINCT
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.DIM_EXPERIMENT` e ON ec.experiment_id = e.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec.campaign_id = fa.campaign_id
  WHERE e.strategy_id = 'EXACT_BOOST' AND e.status = 'ACTIVE'
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
),

-- =============================================
-- Per-family season for the product strategy profile join
-- PEAK = family has active BLITZ holiday right now (PRE_PEAK/BOOST/PEAK phase)
-- OFF  = everything else (GUARDIAN / COOLDOWN)
-- Mirrors the V_ADS_COACH coach_mode logic without creating a circular dependency.
-- =============================================
family_season AS (
  SELECT
    families.parent_name,
    CASE
      WHEN COUNT(fbm.parent_name) > 0 THEN 'PEAK'
      ELSE 'OFF'
    END AS profile_season
  FROM (
    SELECT DISTINCT COALESCE(p.parent_name, '') AS parent_name
    FROM `onyga-482313.OI.DIM_PRODUCT` p
    WHERE p.parent_name IS NOT NULL AND p.parent_name != ''
  ) families
  LEFT JOIN (
    -- Which (family, holiday) combos are in an active BLITZ phase right now?
    SELECT DISTINCT fhr.parent_name
    FROM (
      SELECT DISTINCT family AS parent_name, holiday_name
      FROM `onyga-482313.OI.V_PEAK_RELEVANCE` WHERE is_relevant_peak = TRUE
      UNION DISTINCT
      SELECT DISTINCT family AS parent_name, holiday_name
      FROM `onyga-482313.OI.DE_PEAK_OVERRIDES` WHERE force_relevant = TRUE
    ) fhr
    JOIN `onyga-482313.OI.DIM_US_HOLIDAYS` ah
      ON ah.holiday_name = fhr.holiday_name
      AND ah.category IN ('gift_season', 'prime_event')
      AND CURRENT_DATE('America/New_York') BETWEEN ah.pre_season_start AND ah.holiday_date
      -- B1 fix: NULL-safe cooldown exclusion. A holiday with NULL cooldown window (e.g. Prime Day)
      -- made `x NOT BETWEEN NULL AND NULL` evaluate to NULL (not TRUE), dropping the join row → EVERY
      -- family fell through to profile_season='OFF', clamping peak bids to off-season ceilings.
      AND NOT COALESCE(CURRENT_DATE('America/New_York') BETWEEN ah.cooldown_start AND ah.cooldown_end, FALSE)
  ) fbm ON LOWER(families.parent_name) = LOWER(fbm.parent_name)
  GROUP BY families.parent_name
),

-- =============================================
-- TOS 8w aggregate: lag-trimmed 8-week per-keyword TOS share + impression volume
-- from V_KEYWORD_DAILY (targeting_keyword_report). One row per keyword_id → no fan-out.
-- Window: today-58d to today-2d (excludes the 2-day attribution lag edge).
-- =============================================
tos_8w AS (
  SELECT keyword_id,
    SAFE_DIVIDE(SUM(tos_share * impressions), NULLIF(SUM(impressions), 0)) AS target_tos_share,
    SUM(impressions) AS target_impressions_8w_kw,
    SAFE_DIVIDE(COUNTIF(no_traffic), COUNT(*)) AS no_traffic_rate
  FROM `onyga-482313.OI.V_KEYWORD_DAILY`
  WHERE date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 58 DAY)
    AND date <  DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 2 DAY)
  GROUP BY keyword_id
),

-- ═══ PROBE inputs (Coacher C) — non-circular: read profile + V_KEYWORD_DAILY, not V_STRATEGY_GAPS ═══
pm_cpc AS (   -- per-match-type launch CPC = p50 real cost_per_click for this parent×match, capped
  SELECT parent_name, match_type,
         LEAST(APPROX_QUANTILES(cost_per_click, 100)[OFFSET(50)], 2.0) AS probe_launch_cpc
  FROM `onyga-482313.OI.V_KEYWORD_DAILY`
  WHERE clicks > 0 GROUP BY 1, 2
),
donor_ip AS (   -- a CONCLUSIVE cell sharing intent+parent (borrow ladder reachability)
  SELECT DISTINCT intent_class, parent_name
  FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE` WHERE confidence = 'CONCLUSIVE'
),
donor_im AS (   -- a CONCLUSIVE cell sharing intent+match
  SELECT DISTINCT intent_class, match_type
  FROM `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE` WHERE confidence = 'CONCLUSIVE'
),
probe_state AS (   -- active probe per keyword (graduated/exhausted ones drop out)
  SELECT keyword_id, status AS probe_status
  FROM `onyga-482313.OI.DE_PROBE_LOG` WHERE status = 'ACTIVE'
),

-- =============================================
-- ACTIVE TERM ROWS: assemble all windows at campaign × asin × keyword grain
-- Now includes targeting (target keyword) and weighted ROAS
-- =============================================
active_term_data AS (
  SELECT
    'ACTIVE_TERM' as recommendation_type,

    -- Identity (grain)
    a8.campaign_id,
    a8.ad_group_id,
    a8.campaign_name,
    a8.campaign_type,
    a8.portfolio_name,
    a8.asin,
    ae.product_short_name,
    ae.parent_name,
    a8.search_term,
    a8.experiment_id,
    a8.experiment_name,
    a8.strategy_id,
    a8.strategy_name,
    -- Target keyword (what you bid on in Amazon)
    a8.targeting,
    a8.keyword_id,

    -- Unit economics
    ROUND(COALESCE(
      ae.margin_per_unit,
      SAFE_DIVIDE(a8.ads_sales_8w, NULLIF(a8.ads_orders_8w, 0)) - COALESCE(ae.total_cost_per_unit, 0)
    ), 2) as margin_per_unit,

    -- Per-campaign 8w ads metrics
    ROUND(a8.ads_spend_8w, 2) as ads_spend_8w,
    a8.ads_orders_8w,
    a8.ads_units_8w,
    a8.ads_clicks_8w,
    a8.ads_impressions_8w,
    ROUND(a8.ads_sales_8w, 2) as ads_sales_8w,
    a8.ads_days_8w,
    a8.first_seen_8w,
    a8.last_seen_8w,
    -- Derived per-campaign
    ROUND(SAFE_DIVIDE(a8.ads_spend_8w, NULLIF(a8.ads_clicks_8w, 0)), 2) as ads_cpc_8w,
    ROUND(SAFE_DIVIDE(a8.ads_orders_8w, NULLIF(a8.ads_clicks_8w, 0)) * 100, 2) as ads_cvr_pct_8w,
    ROUND(SAFE_DIVIDE(a8.ads_spend_8w, NULLIF(a8.ads_orders_8w, 0)), 2) as ads_cost_per_order_8w,
    ROUND(
      COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a8.ads_sales_8w, NULLIF(a8.ads_orders_8w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
        * a8.ads_units_8w - a8.ads_spend_8w,
    2) as ads_net_profit_8w,
    ROUND(SAFE_DIVIDE(
      COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a8.ads_sales_8w, NULLIF(a8.ads_orders_8w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
        * a8.ads_units_8w,
      NULLIF(a8.ads_spend_8w, 0)
    ), 2) as ads_net_roas_8w,

    -- 1w window Net ROAS (skip 3d attribution lag: last 7 complete days)
    ROUND(COALESCE(a1.ads_spend_1w, 0), 2) as ads_spend_1w,
    COALESCE(a1.ads_orders_1w, 0) as ads_orders_1w,
    COALESCE(a1.ads_units_1w, 0) as ads_units_1w,
    COALESCE(a1.ads_clicks_1w, 0) as ads_clicks_1w,
    COALESCE(a1.ads_impressions_1w, 0) as ads_impressions_1w,
    ROUND(SAFE_DIVIDE(
      COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a1.ads_sales_1w, NULLIF(a1.ads_orders_1w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
        * COALESCE(a1.ads_units_1w, 0),
      NULLIF(COALESCE(a1.ads_spend_1w, 0), 0)
    ), 2) as ads_net_roas_1w,

    -- 4w window Net ROAS
    ROUND(COALESCE(a4.ads_spend_4w, 0), 2) as ads_spend_4w,
    COALESCE(a4.ads_orders_4w, 0) as ads_orders_4w,
    COALESCE(a4.ads_units_4w, 0) as ads_units_4w,
    COALESCE(a4.ads_clicks_4w, 0) as ads_clicks_4w,
    ROUND(SAFE_DIVIDE(
      COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a4.ads_sales_4w, NULLIF(a4.ads_orders_4w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
        * COALESCE(a4.ads_units_4w, 0),
      NULLIF(COALESCE(a4.ads_spend_4w, 0), 0)
    ), 2) as ads_net_roas_4w,

    -- Weighted Net ROAS = 1w×0.5 + 4w×0.3 + 8w×0.2
    -- Redistributes weights when a window has no spend
    ROUND(
      CASE
        WHEN COALESCE(a1.ads_spend_1w, 0) > 0 AND COALESCE(a4.ads_spend_4w, 0) > 0
        THEN
          SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a1.ads_sales_1w, NULLIF(a1.ads_orders_1w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
              * COALESCE(a1.ads_units_1w, 0),
            NULLIF(COALESCE(a1.ads_spend_1w, 0), 0)
          ) * 0.5
          + SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a4.ads_sales_4w, NULLIF(a4.ads_orders_4w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
              * COALESCE(a4.ads_units_4w, 0),
            NULLIF(COALESCE(a4.ads_spend_4w, 0), 0)
          ) * 0.3
          + SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a8.ads_sales_8w, NULLIF(a8.ads_orders_8w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
              * a8.ads_units_8w,
            NULLIF(a8.ads_spend_8w, 0)
          ) * 0.2
        WHEN COALESCE(a1.ads_spend_1w, 0) = 0 AND COALESCE(a4.ads_spend_4w, 0) > 0
        THEN
          SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a4.ads_sales_4w, NULLIF(a4.ads_orders_4w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
              * COALESCE(a4.ads_units_4w, 0),
            NULLIF(COALESCE(a4.ads_spend_4w, 0), 0)
          ) * 0.625
          + SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a8.ads_sales_8w, NULLIF(a8.ads_orders_8w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
              * a8.ads_units_8w,
            NULLIF(a8.ads_spend_8w, 0)
          ) * 0.375
        ELSE
          SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a8.ads_sales_8w, NULLIF(a8.ads_orders_8w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
              * a8.ads_units_8w,
            NULLIF(a8.ads_spend_8w, 0)
          )
      END
    , 2) as ads_weighted_net_roas,

    -- ═══ Simple Window ROAS (no weighting, for action-specific decisions) ═══

    -- 3d raw Net ROAS (for BLITZ PEAK target decisions)
    ROUND(COALESCE(a3.ads_spend_3d, 0), 2) as ads_spend_3d,
    COALESCE(a3.ads_orders_3d, 0) as ads_orders_3d,
    COALESCE(a3.ads_units_3d, 0) as ads_units_3d,
    ROUND(SAFE_DIVIDE(
      COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a3.ads_sales_3d, NULLIF(a3.ads_orders_3d, 0)) - COALESCE(ae.total_cost_per_unit, 0))
        * COALESCE(a3.ads_units_3d, 0),
      NULLIF(COALESCE(a3.ads_spend_3d, 0), 0)
    ), 2) as ads_net_roas_3d,

    -- 14d raw Net ROAS (for BLITZ BOOST term decisions)
    ROUND(COALESCE(a14.ads_spend_14d, 0), 2) as ads_spend_14d,
    COALESCE(a14.ads_orders_14d, 0) as ads_orders_14d,
    ROUND(SAFE_DIVIDE(
      COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a14.ads_sales_14d, NULLIF(a14.ads_orders_14d, 0)) - COALESCE(ae.total_cost_per_unit, 0))
        * COALESCE(a14.ads_units_14d, 0),
      NULLIF(COALESCE(a14.ads_spend_14d, 0), 0)
    ), 2) as ads_net_roas_14d,

    -- Recent 5d bleeding check
    a8.ads_clicks_recent_5d,

    -- Target keyword rollup (what you actually bid on)
    COALESCE(tr.target_spend_8w, a8.ads_spend_8w) as target_spend_8w,
    COALESCE(tr.target_orders_8w, a8.ads_orders_8w) as target_orders_8w,
    COALESCE(tr.target_clicks_8w, a8.ads_clicks_8w) as target_clicks_8w,
    COALESCE(tr.target_impressions_8w, a8.ads_impressions_8w) as target_impressions_8w,
    COALESCE(tr.target_search_term_count, 1) as target_search_term_count,
    COALESCE(tr.target_clicks_recent_5d, a8.ads_clicks_recent_5d) as target_clicks_recent_5d,
    -- Target keyword status: ENABLED/PAUSED/ARCHIVED (from latest FACT row)
    COALESCE(tr.target_keyword_status, UPPER(a8.ad_keyword_status)) as target_keyword_status,
    ROUND(SAFE_DIVIDE(
      COALESCE(ae.margin_per_unit, 0) * COALESCE(tr.target_units_8w, a8.ads_units_8w),
      NULLIF(COALESCE(tr.target_spend_8w, a8.ads_spend_8w), 0)
    ), 2) as target_net_roas_8w,

    -- Target 1w raw Net ROAS (for BLITZ BOOST target decisions)
    ROUND(SAFE_DIVIDE(
      COALESCE(ae.margin_per_unit, 0) * COALESCE(tr1.target_units_1w, 0),
      NULLIF(COALESCE(tr1.target_spend_1w, 0), 0)
    ), 2) as target_net_roas_1w,

    -- Target Weighted Net ROAS = 1w×0.5 + 4w×0.3 + 8w×0.2
    -- Same weighting as ads_weighted_net_roas but aggregated at target level
    ROUND(
      CASE
        WHEN COALESCE(tr1.target_spend_1w, 0) > 0 AND COALESCE(tr4.target_spend_4w, 0) > 0
        THEN
          SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, 0) * COALESCE(tr1.target_units_1w, 0),
            NULLIF(COALESCE(tr1.target_spend_1w, 0), 0)
          ) * 0.5
          + SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, 0) * COALESCE(tr4.target_units_4w, 0),
            NULLIF(COALESCE(tr4.target_spend_4w, 0), 0)
          ) * 0.3
          + SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, 0) * COALESCE(tr.target_units_8w, a8.ads_units_8w),
            NULLIF(COALESCE(tr.target_spend_8w, a8.ads_spend_8w), 0)
          ) * 0.2
        WHEN COALESCE(tr1.target_spend_1w, 0) = 0 AND COALESCE(tr4.target_spend_4w, 0) > 0
        THEN
          SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, 0) * COALESCE(tr4.target_units_4w, 0),
            NULLIF(COALESCE(tr4.target_spend_4w, 0), 0)
          ) * 0.625
          + SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, 0) * COALESCE(tr.target_units_8w, a8.ads_units_8w),
            NULLIF(COALESCE(tr.target_spend_8w, a8.ads_spend_8w), 0)
          ) * 0.375
        ELSE
          SAFE_DIVIDE(
            COALESCE(ae.margin_per_unit, 0) * COALESCE(tr.target_units_8w, a8.ads_units_8w),
            NULLIF(COALESCE(tr.target_spend_8w, a8.ads_spend_8w), 0)
          )
      END
    , 2) as target_weighted_net_roas,

    -- ═══ Lag Window Safety Check (last 3 days excluded by 4-day lag) ═══
    -- If this ROAS is high, REDUCE_BID should be deferred to MONITOR
    ROUND(SAFE_DIVIDE(
      COALESCE(ae.margin_per_unit, 0) * COALESCE(trl.target_lag_units, 0),
      NULLIF(COALESCE(trl.target_lag_spend, 0), 0)
    ), 2) as target_lag_net_roas,

    -- Term-level lag ROAS (search_term grain) — safety check before NEGATE_TERM
    ROUND(SAFE_DIVIDE(
      COALESCE(ae.margin_per_unit, 0) * COALESCE(alag.lag_units, 0),
      NULLIF(COALESCE(alag.lag_spend, 0), 0)
    ), 2) as ads_lag_net_roas,

    -- ═══ Off-Season ROAS (BOOST/PEAK days excluded) ═══
    -- GUARDIAN/COOLDOWN modes use these to avoid inflated ROAS from peak-season data.

    -- Search-term level off-season 1w Net ROAS (simple, no weighting)
    ROUND(SAFE_DIVIDE(
      ae.margin_per_unit * COALESCE(aos.os_units_1w, 0),
      NULLIF(COALESCE(aos.os_spend_1w, 0), 0)
    ), 2) as ads_net_roas_1w_os,

    -- Search-term level off-season weighted ROAS (legacy, kept for reference)
    ROUND(
      CASE
        WHEN COALESCE(aos.os_spend_8w, 0) = 0 THEN NULL  -- no off-season data
        WHEN COALESCE(aos.os_spend_1w, 0) > 0 AND COALESCE(aos.os_spend_4w, 0) > 0
        THEN
          SAFE_DIVIDE(ae.margin_per_unit * COALESCE(aos.os_units_1w, 0), NULLIF(aos.os_spend_1w, 0)) * 0.5
          + SAFE_DIVIDE(ae.margin_per_unit * COALESCE(aos.os_units_4w, 0), NULLIF(aos.os_spend_4w, 0)) * 0.3
          + SAFE_DIVIDE(ae.margin_per_unit * aos.os_units_8w, NULLIF(aos.os_spend_8w, 0)) * 0.2
        WHEN COALESCE(aos.os_spend_1w, 0) = 0 AND COALESCE(aos.os_spend_4w, 0) > 0
        THEN
          SAFE_DIVIDE(ae.margin_per_unit * COALESCE(aos.os_units_4w, 0), NULLIF(aos.os_spend_4w, 0)) * 0.625
          + SAFE_DIVIDE(ae.margin_per_unit * aos.os_units_8w, NULLIF(aos.os_spend_8w, 0)) * 0.375
        ELSE
          SAFE_DIVIDE(ae.margin_per_unit * aos.os_units_8w, NULLIF(aos.os_spend_8w, 0))
      END
    , 2) as ads_weighted_net_roas_offseason,

    -- Target level off-season 1w Net ROAS (simple, no weighting)
    ROUND(SAFE_DIVIDE(
      ae.margin_per_unit * COALESCE(tros.target_os_units_1w, 0),
      NULLIF(COALESCE(tros.target_os_spend_1w, 0), 0)
    ), 2) as target_net_roas_1w_os,

    -- Target level off-season weighted ROAS (legacy, kept for reference)
    ROUND(
      CASE
        WHEN COALESCE(tros.target_os_spend_8w, 0) = 0 THEN NULL  -- no off-season data
        WHEN COALESCE(tros.target_os_spend_1w, 0) > 0 AND COALESCE(tros.target_os_spend_4w, 0) > 0
        THEN
          SAFE_DIVIDE(ae.margin_per_unit * COALESCE(tros.target_os_units_1w, 0), NULLIF(tros.target_os_spend_1w, 0)) * 0.5
          + SAFE_DIVIDE(ae.margin_per_unit * COALESCE(tros.target_os_units_4w, 0), NULLIF(tros.target_os_spend_4w, 0)) * 0.3
          + SAFE_DIVIDE(ae.margin_per_unit * tros.target_os_units_8w, NULLIF(tros.target_os_spend_8w, 0)) * 0.2
        WHEN COALESCE(tros.target_os_spend_1w, 0) = 0 AND COALESCE(tros.target_os_spend_4w, 0) > 0
        THEN
          SAFE_DIVIDE(ae.margin_per_unit * COALESCE(tros.target_os_units_4w, 0), NULLIF(tros.target_os_spend_4w, 0)) * 0.625
          + SAFE_DIVIDE(ae.margin_per_unit * tros.target_os_units_8w, NULLIF(tros.target_os_spend_8w, 0)) * 0.375
        ELSE
          SAFE_DIVIDE(ae.margin_per_unit * tros.target_os_units_8w, NULLIF(tros.target_os_spend_8w, 0))
      END
    , 2) as target_weighted_net_roas_offseason,

    -- ═══ Hot-Season Weighted Net ROAS ═══
    -- Equal-weight average of 3 components (each 1/3 when all available):
    --   1. TY last 14 days (current momentum)
    --   2. LY same holiday BOOST+PEAK (historical same-season)
    --   3. Last completed peak BOOST+PEAK (most recent peak memory)
    -- Components with no data are excluded; denominator adjusts.
    -- Used for BLITZ mode and SEASONAL_PUSH evaluation.

    -- Search-term level hot-season ROAS
    ROUND(
      SAFE_DIVIDE(
        -- Sum of available component ROAS values
        COALESCE(SAFE_DIVIDE(ae.margin_per_unit * t14.ty14_units, NULLIF(t14.ty14_spend, 0)), 0)
        + COALESCE(SAFE_DIVIDE(ae.margin_per_unit * lysh.lysh_units, NULLIF(lysh.lysh_spend, 0)), 0)
        + COALESCE(SAFE_DIVIDE(ae.margin_per_unit * alp.lp_units, NULLIF(alp.lp_spend, 0)), 0),
        -- Number of components that had data (denominator)
        NULLIF(
          CASE WHEN t14.ty14_spend > 0 THEN 1 ELSE 0 END
          + CASE WHEN lysh.lysh_spend > 0 THEN 1 ELSE 0 END
          + CASE WHEN alp.lp_spend > 0 THEN 1 ELSE 0 END
        , 0)
      )
    , 2) as ads_weighted_net_roas_hotseason,

    -- Target level hot-season ROAS
    ROUND(
      SAFE_DIVIDE(
        COALESCE(SAFE_DIVIDE(ae.margin_per_unit * trh.target_ty14_units, NULLIF(trh.target_ty14_spend, 0)), 0)
        + COALESCE(SAFE_DIVIDE(ae.margin_per_unit * lysh.lysh_units, NULLIF(lysh.lysh_spend, 0)), 0)
        + COALESCE(SAFE_DIVIDE(ae.margin_per_unit * trlp.target_lp_units, NULLIF(trlp.target_lp_spend, 0)), 0),
        NULLIF(
          CASE WHEN trh.target_ty14_spend > 0 THEN 1 ELSE 0 END
          + CASE WHEN lysh.lysh_spend > 0 THEN 1 ELSE 0 END
          + CASE WHEN trlp.target_lp_spend > 0 THEN 1 ELSE 0 END
        , 0)
      )
    , 2) as target_weighted_net_roas_hotseason,

    -- ═══ Q4 Seasonal Detection ═══
    -- Cross-campaign, term-level: is this term profitable ONLY in Q4 peaks?
    COALESCE(q4s.q4_orders, 0) as q4_peak_orders,
    COALESCE(q4s.q4_units, 0) as q4_peak_units,
    ROUND(COALESCE(q4s.q4_spend, 0), 2) as q4_peak_spend,
    ROUND(SAFE_DIVIDE(ae.margin_per_unit * q4s.q4_orders, NULLIF(q4s.q4_spend, 0)), 2) as q4_peak_net_roas,
    COALESCE(q4s.os_orders, 0) as q4_os_orders,
    ROUND(COALESCE(q4s.os_spend, 0), 2) as q4_os_spend,
    ROUND(SAFE_DIVIDE(ae.margin_per_unit * q4s.os_orders, NULLIF(q4s.os_spend, 0)), 2) as q4_os_net_roas,
    -- Auto-detection flag: q4_roas > 1.2 AND os_roas < 0.7 AND q4_orders >= 3
    CASE WHEN q4s.q4_orders >= 3
      AND SAFE_DIVIDE(ae.margin_per_unit * q4s.q4_orders, NULLIF(q4s.q4_spend, 0)) > 1.2
      AND COALESCE(SAFE_DIVIDE(ae.margin_per_unit * q4s.os_orders, NULLIF(q4s.os_spend, 0)), 0) < 0.7
      THEN TRUE ELSE FALSE
    END as is_q4_seasonal,

    -- ═══ Holiday Seasonal Detection (non-Q4) ═══
    -- True if search_term contains any gift_season holiday name (Easter, Valentine, Christmas, etc.)
    CASE WHEN EXISTS (
      SELECT 1 FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
      WHERE h.category = 'gift_season'
        AND (
          STRPOS(LOWER(a8.search_term), LOWER(h.holiday_name)) > 0
          OR STRPOS(LOWER(a8.search_term), LOWER(REGEXP_REPLACE(h.holiday_name, r"'?s?\s+Day$", ''))) > 0
        )
    ) THEN TRUE ELSE FALSE
    END as is_holiday_seasonal,

    -- Cross-campaign 8w context
    ROUND(COALESCE(xc.xc_spend_8w, a8.ads_spend_8w), 2) as xc_spend_8w,
    COALESCE(xc.xc_orders_8w, a8.ads_orders_8w) as xc_orders_8w,
    COALESCE(xc.xc_clicks_8w, a8.ads_clicks_8w) as xc_clicks_8w,
    COALESCE(xc.xc_campaign_count, 1) as xc_campaign_count,
    COALESCE(xc.xc_selling_campaigns, CASE WHEN a8.ads_orders_8w > 0 THEN 1 ELSE 0 END) as xc_selling_campaigns,
    -- This campaign's share
    ROUND(SAFE_DIVIDE(a8.ads_spend_8w, NULLIF(xc.xc_spend_8w, 0)) * 100, 1) as spend_share_pct,
    ROUND(SAFE_DIVIDE(a8.ads_orders_8w, NULLIF(xc.xc_orders_8w, 0)) * 100, 1) as orders_share_pct,

    -- Lifetime
    ROUND(COALESCE(lt.lt_spend, a8.ads_spend_8w), 2) as lt_spend,
    COALESCE(lt.lt_orders, a8.ads_orders_8w) as lt_orders,
    COALESCE(lt.lt_units, a8.ads_units_8w) as lt_units,
    COALESCE(lt.lt_clicks, a8.ads_clicks_8w) as lt_clicks,
    COALESCE(lt.lt_days, a8.ads_days_8w) as lt_days,
    lt.lt_first_seen,
    lt.lt_last_seen,
    ROUND(SAFE_DIVIDE(
      COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a8.ads_sales_8w, NULLIF(a8.ads_orders_8w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
        * COALESCE(lt.lt_units, a8.ads_units_8w),
      NULLIF(COALESCE(lt.lt_spend, a8.ads_spend_8w), 0)
    ), 2) as lt_net_roas,

    -- LY Peak
    ROUND(COALESCE(lyp.ly_spend, 0), 2) as ly_spend,
    COALESCE(lyp.ly_orders, 0) as ly_orders,
    COALESCE(lyp.ly_units, 0) as ly_units,
    COALESCE(lyp.ly_clicks, 0) as ly_clicks,
    COALESCE(lyp.ly_impressions, 0) as ly_impressions,
    ROUND(SAFE_DIVIDE(COALESCE(lyp.ly_spend, 0), NULLIF(COALESCE(lyp.ly_clicks, 0), 0)), 2) as ly_cpc,
    ROUND(SAFE_DIVIDE(COALESCE(lyp.ly_orders, 0), NULLIF(COALESCE(lyp.ly_clicks, 0), 0)) * 100, 2) as ly_cvr_pct,
    ROUND(SAFE_DIVIDE(
      COALESCE(ae.margin_per_unit, 0) * COALESCE(lyp.ly_units, 0),
      NULLIF(COALESCE(lyp.ly_spend, 0), 0)
    ), 2) as ly_net_roas,

    -- SQP 8w: Your ASIN
    COALESCE(sq8.sqp_impressions_8w, 0) as sqp_impressions_8w,
    COALESCE(sq8.sqp_clicks_8w, 0) as sqp_clicks_8w,
    COALESCE(sq8.sqp_cart_adds_8w, 0) as sqp_cart_adds_8w,
    COALESCE(sq8.sqp_orders_8w, 0) as sqp_orders_8w,
    ROUND(COALESCE(sq8.sqp_sales_8w, 0), 2) as sqp_sales_8w,
    GREATEST(0, COALESCE(sq8.sqp_orders_8w, 0) - a8.ads_orders_8w) as sqp_organic_units_8w,
    ROUND(COALESCE(sq8.sqp_show_rate_8w, 0), 2) as sqp_show_rate_8w,
    ROUND(COALESCE(sq8.sqp_impression_share_8w, 0), 2) as sqp_impression_share_8w,
    ROUND(COALESCE(sq8.sqp_organic_rank_8w, 0), 1) as sqp_organic_rank_8w,
    -- SQP 8w: Amazon market
    COALESCE(sq8.sqp_amazon_impressions_8w, 0) as sqp_amazon_impressions_8w,
    COALESCE(sq8.sqp_amazon_clicks_8w, 0) as sqp_amazon_clicks_8w,
    COALESCE(sq8.sqp_amazon_cart_adds_8w, 0) as sqp_amazon_cart_adds_8w,
    COALESCE(sq8.sqp_amazon_orders_8w, 0) as sqp_amazon_orders_8w,
    ROUND(COALESCE(sq8.sqp_amazon_search_volume_8w, 0), 0) as sqp_amazon_search_volume_8w,

    -- SQP LY Peak: Your ASIN
    COALESCE(sqlp.sqp_ly_impressions, 0) as sqp_ly_impressions,
    COALESCE(sqlp.sqp_ly_clicks, 0) as sqp_ly_clicks,
    COALESCE(sqlp.sqp_ly_cart_adds, 0) as sqp_ly_cart_adds,
    COALESCE(sqlp.sqp_ly_orders, 0) as sqp_ly_orders,
    ROUND(COALESCE(sqlp.sqp_ly_sales, 0), 2) as sqp_ly_sales,
    ROUND(COALESCE(sqlp.sqp_ly_show_rate, 0), 2) as sqp_ly_show_rate,
    ROUND(COALESCE(sqlp.sqp_ly_impression_share, 0), 2) as sqp_ly_impression_share,
    ROUND(COALESCE(sqlp.sqp_ly_organic_rank, 0), 1) as sqp_ly_organic_rank,
    -- SQP LY Peak: Amazon market
    COALESCE(sqlp.sqp_ly_amazon_impressions, 0) as sqp_ly_amazon_impressions,
    COALESCE(sqlp.sqp_ly_amazon_clicks, 0) as sqp_ly_amazon_clicks,
    COALESCE(sqlp.sqp_ly_amazon_cart_adds, 0) as sqp_ly_amazon_cart_adds,
    COALESCE(sqlp.sqp_ly_amazon_orders, 0) as sqp_ly_amazon_orders,
    ROUND(COALESCE(sqlp.sqp_ly_amazon_search_volume, 0), 0) as sqp_ly_amazon_search_volume,

    -- Hero ASIN
    th.hero_asin,
    th.hero_product_name,
    th.hero_score,
    th.hero_sqp_cvr_pct,
    th.hero_ads_cvr_pct,
    th.hero_confidence,
    COALESCE(a8.asin = th.hero_asin, FALSE) as is_hero_match,

    -- Segment / classification
    tc.experiment_segment,
    tc.intent_segment,
    tc.occasion,
    tc.amazon_avg_weekly_orders as market_weekly_orders,
    tc.your_orders_share_pct,
    COALESCE(tc.is_best_asin_for_term, FALSE) as is_best_asin_for_term,

    -- Already in EXACT_BOOST?
    ebt.search_term IS NOT NULL as already_in_exact_boost,

    -- Current bid from bulksheet config (SP keyword → SB keyword → product targeting → ad group default)
    ROUND(COALESCE(cc.keyword_bid, ccsb.keyword_bid, ccpt.pt_bid, ccag.ad_group_default_bid), 2) as current_bid,

    -- Current campaign placement adjustments
    COALESCE(cp.tos_pct, 0) as tos_pct,
    COALESCE(cp.product_page_pct, 0) as product_page_pct,
    COALESCE(cp.b2b_pct, 0) as b2b_pct,

    -- Pre-peak snapshot (for Cooldown restore)
    pps.pre_peak_bid,
    pps.pre_peak_tos_pct,
    pps.pre_peak_pp_pct,
    pps.pre_peak_b2b_pct,
    pps.pre_peak_avg_cpc,
    pps.pre_peak_avg_daily_spend,

    -- Latest day CPC
    ldc.last_day_cpc,
    ldc.last_day_date,

    -- Campaign budget (for Cooldown budget recommendations)
    ccb.current_budget,
    cpb.pre_peak_budget,

    -- Campaign state (for action guards — suppress recommendations on paused campaigns)
    ccs.campaign_state,

    -- Campaign creation date (for warmup guard — 14-day new campaign tolerance)
    ccs.campaign_creation_date,

    -- Action frequency control (days since last change from SCD2 history)
    COALESCE(klbc.days_since_last_bid_change, 999) as days_since_last_bid_change,
    COALESCE(clbc.days_since_last_budget_change, 999) as days_since_last_budget_change,
    -- Launch-track batch gate: clicks accrued since the last bid change
    COALESCE(kcsbc.clicks_since_last_bid_change, 0) as clicks_since_last_bid_change,
    -- 3-day no-re-suggest cooldown: days since WE last changed this target / campaign (change log).
    LEAST(COALESCE(slk.days_since, 999), COALESCE(slt.days_since, 999)) as days_since_last_suggestion,
    COALESCE(slc.days_since, 999) as days_since_last_suggestion_camp,
    -- Target-level 4w rollup (summed across all search terms under this targeting). The launch
    -- track judges on these so SP-Auto auto-clauses (loose-match etc.) aren't under-read by the
    -- per-search-term fan-out. target_net_roas_4w mirrors the ads_net_roas_4w formula on tr4 sums.
    COALESCE(cr4.clause_orders_4w, 0) as target_orders_4w,
    COALESCE(cr4.clause_clicks_4w, 0) as target_clicks_4w,
    ROUND(SAFE_DIVIDE(cr4.clause_net_profit_4w, NULLIF(cr4.clause_spend_4w, 0)), 2) as target_net_roas_4w,
    -- Keyword-grain 4w spend + hero match — consumed by the TARGET bid decision so its money-bleeder
    -- and SWITCH_HERO branches judge the whole keyword, not a single search-term slice.
    COALESCE(cr4.clause_spend_4w, 0) as target_spend_4w,
    COALESCE(thm.target_is_hero_match, FALSE) as target_is_hero_match,

    -- ═══ Per-product strategy profile (Task 5: season + profile join) ═══
    -- Season: PEAK when the family has an active BLITZ holiday, OFF otherwise.
    -- Profile: one row per (parent × season × match_type) from DE_PRODUCT_STRATEGY_PROFILE.
    -- Join is many-to-one → never multiplies rows.
    COALESCE(fs.profile_season, 'OFF') as profile_season,
    psp.enabled        as profile_enabled,
    psp.cpc_target     as profile_cpc_target,
    psp.cpc_min        as profile_cpc_min,
    psp.cpc_max        as profile_cpc_max,
    psp.confidence     as profile_confidence,
    psp.source         as profile_source,
    -- profile_steers = true when the evidence is conclusive or the user set it manually
    (psp.source IN ('MANUAL','BORROWED') OR psp.confidence = 'CONCLUSIVE') as profile_steers,
    -- intent_class: BRAND / PRODUCT / GENERIC (from V_KEYWORD_INTENT_CLASS; default GENERIC)
    COALESCE(kic.intent_class, 'GENERIC') as intent_class,
    -- cell coordinates exposed for V_STRATEGY_GAPS (Coacher C) — identical to the psp join below,
    -- so the gaps aggregation can never drift from the profile grain.
    COALESCE(fs.profile_season, 'OFF') as season,
    CASE UPPER(a8.targeting_type)
      WHEN 'BROAD'         THEN 'BROAD'
      WHEN 'EXACT'         THEN 'EXACT'
      WHEN 'PHRASE'        THEN 'PHRASE'
      WHEN 'AUTOMATIC'     THEN 'AUTO'
      WHEN 'ASIN'          THEN 'PRODUCT'
      WHEN 'ASIN EXPANDED' THEN 'PRODUCT'
      WHEN 'CATEGORY'      THEN 'CATEGORY'
      ELSE UPPER(a8.targeting_type)
    END as match_type,
    -- PROBE eligibility (Coacher C): cell does not steer AND no borrow donor reachable
    (NOT COALESCE((psp.source IN ('MANUAL','BORROWED') OR psp.confidence = 'CONCLUSIVE'), FALSE)
       AND dip.parent_name IS NULL
       AND dim.match_type IS NULL)        as is_probe_cell,
    pcpc.probe_launch_cpc                  as probe_launch_cpc,
    pst.probe_status                       as probe_status,

    -- ═══ TOS signals (Task 3): 8-week per-keyword aggregate from V_KEYWORD_DAILY ═══
    -- target_tos_share: impression-weighted avg TOS share (0–100) over 8w lag-trimmed window.
    -- target_impressions_8w_kw: total keyword impressions in that window.
    -- no_traffic_rate: fraction of days the keyword had 0 impressions (buried detection).
    -- tos_target_pct: per-cell TOS target from DE_PRODUCT_STRATEGY_PROFILE (seeded by Task 2).
    t8w.target_tos_share,
    t8w.target_impressions_8w_kw,
    t8w.no_traffic_rate,
    psp.tos_target_pct

  FROM ads_8w a8
  JOIN asin_economics ae ON a8.asin = ae.asin
  LEFT JOIN ads_1w a1 ON a8.campaign_id = a1.campaign_id AND a8.search_term = a1.search_term AND a8.asin = a1.asin AND a8.targeting = a1.targeting
  LEFT JOIN ads_3d a3 ON a8.campaign_id = a3.campaign_id AND a8.search_term = a3.search_term AND a8.asin = a3.asin AND a8.targeting = a3.targeting
  LEFT JOIN ads_14d a14 ON a8.campaign_id = a14.campaign_id AND a8.search_term = a14.search_term AND a8.asin = a14.asin AND a8.targeting = a14.targeting
  LEFT JOIN ads_4w a4 ON a8.campaign_id = a4.campaign_id AND a8.search_term = a4.search_term AND a8.asin = a4.asin AND a8.targeting = a4.targeting
  LEFT JOIN target_rollup tr ON a8.campaign_id = tr.campaign_id AND a8.targeting = tr.targeting AND a8.keyword_id = tr.keyword_id AND a8.asin = tr.asin
  LEFT JOIN target_rollup_1w tr1 ON a8.campaign_id = tr1.campaign_id AND a8.targeting = tr1.targeting AND a8.asin = tr1.asin
  LEFT JOIN target_rollup_4w tr4 ON a8.campaign_id = tr4.campaign_id AND a8.targeting = tr4.targeting AND a8.asin = tr4.asin
  LEFT JOIN clause_rollup_4w cr4 ON a8.campaign_id = cr4.campaign_id AND a8.targeting = cr4.targeting
  LEFT JOIN target_hero_match thm ON a8.campaign_id = thm.campaign_id AND a8.targeting = thm.targeting AND a8.asin = thm.asin
  LEFT JOIN target_rollup_lag trl ON a8.campaign_id = trl.campaign_id AND a8.targeting = trl.targeting AND a8.asin = trl.asin
  LEFT JOIN ads_lag alag ON a8.campaign_id = alag.campaign_id AND a8.search_term = alag.search_term AND a8.asin = alag.asin AND a8.targeting = alag.targeting
  LEFT JOIN ads_offseason aos ON a8.campaign_id = aos.campaign_id AND a8.search_term = aos.search_term AND a8.asin = aos.asin AND a8.targeting = aos.targeting
  LEFT JOIN target_rollup_offseason tros ON a8.campaign_id = tros.campaign_id AND a8.targeting = tros.targeting AND a8.asin = tros.asin
  -- Hot-season components (CROSS-CAMPAIGN: term × asin)
  LEFT JOIN ads_ty_14d t14 ON a8.search_term = t14.search_term AND a8.asin = t14.asin
  LEFT JOIN ads_last_peak alp ON a8.search_term = alp.search_term AND a8.asin = alp.asin
  LEFT JOIN ads_ly_same_holiday lysh ON a8.search_term = lysh.search_term AND a8.asin = lysh.asin
  LEFT JOIN target_rollup_hotseason trh ON a8.search_term = trh.search_term AND a8.asin = trh.asin
  LEFT JOIN target_rollup_last_peak trlp ON a8.search_term = trlp.search_term AND a8.asin = trlp.asin
  -- Q4 seasonal detection
  LEFT JOIN q4_seasonal_detection q4s ON a8.search_term = q4s.search_term AND a8.asin = q4s.asin
  LEFT JOIN cross_campaign_8w xc ON a8.search_term = xc.search_term AND a8.asin = xc.asin
  LEFT JOIN ads_lifetime lt ON a8.search_term = lt.search_term AND a8.asin = lt.asin
  LEFT JOIN ads_ly_peak lyp ON a8.search_term = lyp.search_term AND a8.asin = lyp.asin
  LEFT JOIN sqp_8w sq8 ON a8.search_term = sq8.search_term AND a8.asin = sq8.asin
  LEFT JOIN sqp_ly_peak sqlp ON a8.search_term = sqlp.search_term AND a8.asin = sqlp.asin
  LEFT JOIN term_hero th ON a8.search_term = th.search_term AND ae.parent_name = th.hero_parent_name
  LEFT JOIN term_classification tc ON a8.search_term = tc.search_term AND a8.asin = tc.asin
  LEFT JOIN exact_boost_terms ebt ON a8.search_term = ebt.search_term AND a8.asin = ebt.asin
  LEFT JOIN campaign_config cc ON a8.campaign_id = cc.campaign_id AND a8.keyword_id = cc.keyword_id
  LEFT JOIN campaign_config_sb ccsb ON a8.campaign_id = ccsb.campaign_id AND a8.keyword_id = ccsb.keyword_id
  LEFT JOIN campaign_config_pt ccpt ON a8.campaign_id = ccpt.campaign_id AND a8.keyword_id = ccpt.product_targeting_id
  LEFT JOIN campaign_config_ag ccag ON a8.campaign_id = ccag.campaign_id
  LEFT JOIN campaign_placements cp ON a8.campaign_id = cp.campaign_id
  LEFT JOIN pre_peak_snap pps ON a8.campaign_id = pps.campaign_id AND LOWER(a8.targeting) = LOWER(pps.targeting)
  LEFT JOIN latest_day_cpc ldc ON a8.campaign_id = ldc.campaign_id AND LOWER(a8.targeting) = LOWER(ldc.targeting)
  LEFT JOIN campaign_current_budget ccb ON a8.campaign_id = ccb.campaign_id
  LEFT JOIN campaign_pre_peak_budget cpb ON a8.campaign_id = cpb.campaign_id
  LEFT JOIN campaign_current_state ccs ON a8.campaign_id = ccs.campaign_id
  LEFT JOIN keyword_last_bid_change klbc ON a8.keyword_id = klbc.keyword_id
  LEFT JOIN keyword_clicks_since_bid_change kcsbc ON a8.keyword_id = kcsbc.keyword_id
  LEFT JOIN campaign_last_budget_change clbc ON a8.campaign_id = clbc.campaign_id
  LEFT JOIN suggestion_by_keyword slk ON a8.campaign_id = slk.campaign_id AND a8.keyword_id = slk.keyword_id
  LEFT JOIN suggestion_by_targeting slt ON a8.campaign_id = slt.campaign_id AND LOWER(a8.targeting) = slt.targeting_lc
  LEFT JOIN suggestion_by_campaign slc ON a8.campaign_id = slc.campaign_id
  -- Per-product strategy profile: season then profile row (many-to-one — no fan-out)
  LEFT JOIN family_season fs ON LOWER(ae.parent_name) = LOWER(fs.parent_name)
  -- Intent class: one row per (parent_name, keyword_text) — no fan-out
  LEFT JOIN `onyga-482313.OI.V_KEYWORD_INTENT_CLASS` kic
    ON kic.parent_name = ae.parent_name
   AND kic.keyword_text = LOWER(a8.targeting)
  LEFT JOIN `onyga-482313.OI.DE_PRODUCT_STRATEGY_PROFILE` psp
    ON psp.parent_name = ae.parent_name
   AND psp.season = COALESCE(fs.profile_season, 'OFF')
   AND psp.intent_class = COALESCE(kic.intent_class, 'GENERIC')
   AND psp.match_type = CASE UPPER(a8.targeting_type)
        WHEN 'BROAD'         THEN 'BROAD'
        WHEN 'EXACT'         THEN 'EXACT'
        WHEN 'PHRASE'        THEN 'PHRASE'
        WHEN 'AUTOMATIC'     THEN 'AUTO'
        WHEN 'ASIN'          THEN 'PRODUCT'
        WHEN 'ASIN EXPANDED' THEN 'PRODUCT'
        WHEN 'CATEGORY'      THEN 'CATEGORY'
        ELSE UPPER(a8.targeting_type)
      END
  -- TOS 8w: one row per keyword_id → many-to-one, no fan-out
  LEFT JOIN tos_8w t8w ON t8w.keyword_id = CAST(a8.keyword_id AS STRING)
  -- PROBE inputs (Coacher C): per-match launch CPC + donor reachability + active-probe state
  LEFT JOIN pm_cpc pcpc
    ON pcpc.parent_name = ae.parent_name
   AND pcpc.match_type = CASE UPPER(a8.targeting_type)
        WHEN 'BROAD' THEN 'BROAD' WHEN 'EXACT' THEN 'EXACT' WHEN 'PHRASE' THEN 'PHRASE'
        WHEN 'AUTOMATIC' THEN 'AUTO' WHEN 'ASIN' THEN 'PRODUCT' WHEN 'ASIN EXPANDED' THEN 'PRODUCT'
        WHEN 'CATEGORY' THEN 'CATEGORY' ELSE UPPER(a8.targeting_type) END
  LEFT JOIN donor_ip dip
    ON dip.intent_class = COALESCE(kic.intent_class, 'GENERIC') AND dip.parent_name = ae.parent_name
  LEFT JOIN donor_im dim
    ON dim.intent_class = COALESCE(kic.intent_class, 'GENERIC')
   AND dim.match_type = CASE UPPER(a8.targeting_type)
        WHEN 'BROAD' THEN 'BROAD' WHEN 'EXACT' THEN 'EXACT' WHEN 'PHRASE' THEN 'PHRASE'
        WHEN 'AUTOMATIC' THEN 'AUTO' WHEN 'ASIN' THEN 'PRODUCT' WHEN 'ASIN EXPANDED' THEN 'PRODUCT'
        WHEN 'CATEGORY' THEN 'CATEGORY' ELSE UPPER(a8.targeting_type) END
  LEFT JOIN probe_state pst ON pst.keyword_id = CAST(a8.keyword_id AS STRING)
),

-- =============================================
-- SECTION B: OPPORTUNITY TERMS
-- SQP terms with purchases NOT targeted by any active experiment
-- =============================================
all_experiment_targeted AS (
  SELECT DISTINCT
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN active_experiments ae ON ec.experiment_id = ae.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec.campaign_id = fa.campaign_id
  WHERE fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
),

sqp_with_purchases AS (
  SELECT
    LOWER(fsq.query_text) as search_term,
    fsq.ASIN as asin,
    SUM(fsq.conversions) as sqp_purchases,
    SUM(fsq.clicks) as sqp_clicks,
    SUM(fsq.impressions) as sqp_impressions,
    SUM(fsq.sales_amount) as sqp_sales,
    COUNT(DISTINCT fsq.week_end_date) as sqp_weeks
  FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
  WHERE fsq.data_source = 'SQP'
    AND fsq.week_end_date >= DATE_SUB(CURRENT_DATE('America/Los_Angeles'), INTERVAL 56 DAY)
    AND fsq.conversions > 0
  GROUP BY 1, 2
  HAVING SUM(fsq.conversions) >= 1
),

opportunity_data AS (
  SELECT
    'OPPORTUNITY' as recommendation_type,

    -- Identity (no campaign for opportunity rows)
    CAST(NULL AS STRING) as campaign_id,
    CAST(NULL AS STRING) as ad_group_id,
    CAST(NULL AS STRING) as campaign_name,
    CAST(NULL AS STRING) as campaign_type,
    'Unassigned' as portfolio_name,  -- Opportunities have no campaign → no portfolio
    COALESCE(th.hero_asin, sp.asin) as asin,
    COALESCE(th.hero_product_name, ae.product_short_name) as product_short_name,
    ae.parent_name,
    sp.search_term,
    CAST(NULL AS STRING) as experiment_id,
    CAST(NULL AS STRING) as experiment_name,
    -- Suggest strategy based on segment
    CASE
      WHEN tc.experiment_segment = 'BRAND' THEN 'BRAND_DEFENSE'
      WHEN tc.intent_segment = 'COMPETITOR' THEN 'CATEGORY_CONQUEST'
      WHEN sp.sqp_purchases >= 3 AND sp.sqp_weeks >= 2 THEN 'EXACT_BOOST'
      WHEN sp.sqp_purchases >= 2 THEN 'EXACT_BOOST'
      ELSE 'HUNTER'
    END as strategy_id,
    CAST(NULL AS STRING) as strategy_name,
    -- Target keyword (N/A for opportunities)
    CAST(NULL AS STRING) as targeting,
    CAST(NULL AS STRING) as keyword_id,

    -- Unit economics
    ROUND(COALESCE(hero_ae.margin_per_unit, ae.margin_per_unit), 2) as margin_per_unit,

    -- Per-campaign 8w (all zeros for opportunity)
    0.0 as ads_spend_8w, 0 as ads_orders_8w, 0 as ads_units_8w, 0 as ads_clicks_8w,
    0 as ads_impressions_8w, 0.0 as ads_sales_8w, CAST(NULL AS INT64) as ads_days_8w,
    CAST(NULL AS DATE) as first_seen_8w, CAST(NULL AS DATE) as last_seen_8w,
    CAST(NULL AS FLOAT64) as ads_cpc_8w, CAST(NULL AS FLOAT64) as ads_cvr_pct_8w,
    CAST(NULL AS FLOAT64) as ads_cost_per_order_8w,
    0.0 as ads_net_profit_8w, CAST(NULL AS FLOAT64) as ads_net_roas_8w,
    -- 1w/4w windows (zeros for opportunity)
    0.0 as ads_spend_1w, 0 as ads_orders_1w, 0 as ads_units_1w, 0 as ads_clicks_1w, 0 as ads_impressions_1w, CAST(NULL AS FLOAT64) as ads_net_roas_1w,
    0.0 as ads_spend_4w, 0 as ads_orders_4w, 0 as ads_units_4w, 0 as ads_clicks_4w, CAST(NULL AS FLOAT64) as ads_net_roas_4w,
    CAST(NULL AS FLOAT64) as ads_weighted_net_roas,
    -- New simple window ROAS fields (NULL for opportunities)
    0.0 as ads_spend_3d, 0 as ads_orders_3d, 0 as ads_units_3d, CAST(NULL AS FLOAT64) as ads_net_roas_3d,
    0.0 as ads_spend_14d, 0 as ads_orders_14d, CAST(NULL AS FLOAT64) as ads_net_roas_14d,
    0 as ads_clicks_recent_5d,
    -- Target rollup (zeros for opportunity)
    0.0 as target_spend_8w, 0 as target_orders_8w, 0 as target_clicks_8w,
    0 as target_impressions_8w, 0 as target_search_term_count, 0 as target_clicks_recent_5d,
    CAST(NULL AS STRING) as target_keyword_status,
    CAST(NULL AS FLOAT64) as target_net_roas_8w,
    CAST(NULL AS FLOAT64) as target_net_roas_1w,
    CAST(NULL AS FLOAT64) as target_weighted_net_roas,
    CAST(NULL AS FLOAT64) as target_lag_net_roas,
    CAST(NULL AS FLOAT64) as ads_lag_net_roas,
    -- Off-season ROAS (NULL for opportunities — no ads data)
    CAST(NULL AS FLOAT64) as ads_net_roas_1w_os,
    CAST(NULL AS FLOAT64) as ads_weighted_net_roas_offseason,
    CAST(NULL AS FLOAT64) as target_net_roas_1w_os,
    CAST(NULL AS FLOAT64) as target_weighted_net_roas_offseason,
    -- Hot-season ROAS (NULL for opportunities — no ads data)
    CAST(NULL AS FLOAT64) as ads_weighted_net_roas_hotseason,
    CAST(NULL AS FLOAT64) as target_weighted_net_roas_hotseason,
    -- Q4 seasonal detection (NULL for opportunities)
    0 as q4_peak_orders, 0 as q4_peak_units, 0.0 as q4_peak_spend, CAST(NULL AS FLOAT64) as q4_peak_net_roas,
    0 as q4_os_orders, 0.0 as q4_os_spend, CAST(NULL AS FLOAT64) as q4_os_net_roas,
    FALSE as is_q4_seasonal,
    FALSE as is_holiday_seasonal,

    -- Cross-campaign (zeros)
    0.0 as xc_spend_8w, 0 as xc_orders_8w, 0 as xc_clicks_8w,
    0 as xc_campaign_count, 0 as xc_selling_campaigns,
    CAST(NULL AS FLOAT64) as spend_share_pct, CAST(NULL AS FLOAT64) as orders_share_pct,

    -- Lifetime (zeros)
    0.0 as lt_spend, 0 as lt_orders, 0 as lt_units, 0 as lt_clicks, CAST(NULL AS INT64) as lt_days,
    CAST(NULL AS DATE) as lt_first_seen, CAST(NULL AS DATE) as lt_last_seen,
    CAST(NULL AS FLOAT64) as lt_net_roas,

    -- LY Peak (zeros)
    0.0 as ly_spend, 0 as ly_orders, 0 as ly_units, 0 as ly_clicks, 0 as ly_impressions,
    CAST(NULL AS FLOAT64) as ly_cpc, CAST(NULL AS FLOAT64) as ly_cvr_pct,
    CAST(NULL AS FLOAT64) as ly_net_roas,

    -- SQP 8w (from sqp_with_purchases)
    sp.sqp_impressions as sqp_impressions_8w,
    sp.sqp_clicks as sqp_clicks_8w,
    0 as sqp_cart_adds_8w,
    sp.sqp_purchases as sqp_orders_8w,
    ROUND(sp.sqp_sales, 2) as sqp_sales_8w,
    sp.sqp_purchases as sqp_organic_units_8w,
    0.0 as sqp_show_rate_8w, 0.0 as sqp_impression_share_8w, 0.0 as sqp_organic_rank_8w,
    0 as sqp_amazon_impressions_8w, 0 as sqp_amazon_clicks_8w,
    0 as sqp_amazon_cart_adds_8w, 0 as sqp_amazon_orders_8w, 0.0 as sqp_amazon_search_volume_8w,

    -- SQP LY Peak (zeros for now — could enrich later)
    COALESCE(sqlp.sqp_ly_impressions, 0) as sqp_ly_impressions,
    COALESCE(sqlp.sqp_ly_clicks, 0) as sqp_ly_clicks,
    COALESCE(sqlp.sqp_ly_cart_adds, 0) as sqp_ly_cart_adds,
    COALESCE(sqlp.sqp_ly_orders, 0) as sqp_ly_orders,
    ROUND(COALESCE(sqlp.sqp_ly_sales, 0), 2) as sqp_ly_sales,
    ROUND(COALESCE(sqlp.sqp_ly_show_rate, 0), 2) as sqp_ly_show_rate,
    ROUND(COALESCE(sqlp.sqp_ly_impression_share, 0), 2) as sqp_ly_impression_share,
    ROUND(COALESCE(sqlp.sqp_ly_organic_rank, 0), 1) as sqp_ly_organic_rank,
    COALESCE(sqlp.sqp_ly_amazon_impressions, 0) as sqp_ly_amazon_impressions,
    COALESCE(sqlp.sqp_ly_amazon_clicks, 0) as sqp_ly_amazon_clicks,
    COALESCE(sqlp.sqp_ly_amazon_cart_adds, 0) as sqp_ly_amazon_cart_adds,
    COALESCE(sqlp.sqp_ly_amazon_orders, 0) as sqp_ly_amazon_orders,
    ROUND(COALESCE(sqlp.sqp_ly_amazon_search_volume, 0), 0) as sqp_ly_amazon_search_volume,

    -- Hero ASIN
    th.hero_asin,
    th.hero_product_name,
    th.hero_score,
    th.hero_sqp_cvr_pct,
    th.hero_ads_cvr_pct,
    th.hero_confidence,
    COALESCE(sp.asin = th.hero_asin, FALSE) as is_hero_match,

    -- Segment
    tc.experiment_segment,
    tc.intent_segment,
    tc.occasion,
    tc.amazon_avg_weekly_orders as market_weekly_orders,
    tc.your_orders_share_pct,
    COALESCE(tc.is_best_asin_for_term, FALSE) as is_best_asin_for_term,

    -- Not in any campaign, so no EXACT_BOOST check
    FALSE as already_in_exact_boost,

    -- No bid for opportunity rows
    CAST(NULL AS FLOAT64) as current_bid,

    -- No placement/snapshot data for opportunities
    CAST(0 AS INT64) as tos_pct,
    CAST(0 AS INT64) as product_page_pct,
    CAST(0 AS INT64) as b2b_pct,
    CAST(NULL AS FLOAT64) as pre_peak_bid,
    CAST(NULL AS INT64) as pre_peak_tos_pct,
    CAST(NULL AS INT64) as pre_peak_pp_pct,
    CAST(NULL AS INT64) as pre_peak_b2b_pct,
    CAST(NULL AS FLOAT64) as pre_peak_avg_cpc,
    CAST(NULL AS FLOAT64) as pre_peak_avg_daily_spend,
    CAST(NULL AS FLOAT64) as last_day_cpc,
    CAST(NULL AS DATE) as last_day_date,
    CAST(NULL AS FLOAT64) as current_budget,
    CAST(NULL AS FLOAT64) as pre_peak_budget,
    CAST(NULL AS STRING) as campaign_state,
    CAST(NULL AS TIMESTAMP) as campaign_creation_date,
    CAST(999 AS INT64) as days_since_last_bid_change,
    CAST(999 AS INT64) as days_since_last_budget_change,
    CAST(0 AS INT64) as clicks_since_last_bid_change,
    CAST(999 AS INT64) as days_since_last_suggestion,
    CAST(999 AS INT64) as days_since_last_suggestion_camp,
    CAST(0 AS INT64) as target_orders_4w,
    CAST(0 AS INT64) as target_clicks_4w,
    CAST(NULL AS FLOAT64) as target_net_roas_4w,
    CAST(0 AS FLOAT64) as target_spend_4w,
    CAST(FALSE AS BOOL) as target_is_hero_match,

    -- Per-product strategy profile (NULL for opportunities — no targeting match type)
    CAST(NULL AS STRING)  as profile_season,
    CAST(NULL AS BOOL)    as profile_enabled,
    CAST(NULL AS FLOAT64) as profile_cpc_target,
    CAST(NULL AS FLOAT64) as profile_cpc_min,
    CAST(NULL AS FLOAT64) as profile_cpc_max,
    CAST(NULL AS STRING)  as profile_confidence,
    CAST(NULL AS STRING)  as profile_source,
    CAST(NULL AS BOOL)    as profile_steers,
    CAST(NULL AS STRING)  as intent_class,
    CAST(NULL AS STRING)  as season,
    CAST(NULL AS STRING)  as match_type,
    CAST(NULL AS BOOL)    as is_probe_cell,
    CAST(NULL AS FLOAT64) as probe_launch_cpc,
    CAST(NULL AS STRING)  as probe_status,

    -- TOS signals (NULL for opportunities — no keyword_id / no keyword report data)
    CAST(NULL AS FLOAT64) as target_tos_share,
    CAST(NULL AS INT64)   as target_impressions_8w_kw,
    CAST(NULL AS FLOAT64) as no_traffic_rate,
    CAST(NULL AS FLOAT64) as tos_target_pct

  FROM sqp_with_purchases sp
  JOIN asin_economics ae ON sp.asin = ae.asin
  LEFT JOIN all_experiment_targeted aet
    ON sp.search_term = aet.search_term AND sp.asin = aet.asin
  LEFT JOIN term_classification tc
    ON sp.search_term = tc.search_term AND sp.asin = tc.asin
  LEFT JOIN term_hero th
    ON sp.search_term = th.search_term AND ae.parent_name = th.hero_parent_name  -- ae = asin_economics (FROM/JOIN above), not active_experiments
  LEFT JOIN asin_economics hero_ae ON th.hero_asin = hero_ae.asin
  LEFT JOIN sqp_ly_peak sqlp ON sp.search_term = sqlp.search_term AND sp.asin = sqlp.asin
  WHERE aet.search_term IS NULL  -- Not targeted by any experiment
)

-- =============================================
-- Final: UNION active terms + opportunities
-- =============================================
SELECT * FROM active_term_data
UNION ALL
SELECT * FROM opportunity_data;
