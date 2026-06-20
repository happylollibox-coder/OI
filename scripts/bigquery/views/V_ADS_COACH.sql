CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_COACH` AS
WITH

-- ═══════════════════════════════════════════════════════
-- COACH MODE RESOLUTION: Blitz 🔥 / Cooldown ❄️ / Guardian 🛡
-- One mode per product family per day.
-- COOLDOWN = default for ALL families when any holiday is in cooldown window
-- BLITZ = only for families with proven peak lift (V_PEAK_RELEVANCE)
-- GUARDIAN = everything else (off-season)
-- ═══════════════════════════════════════════════════════

-- All gift-season holidays near today (±90 days) with their date ranges
-- Uses US Eastern time as the business timezone
active_holidays AS (
  SELECT
    holiday_name,
    holiday_date,
    pre_season_start,
    boost_start,
    peak_start,
    cooldown_start,
    cooldown_end,
    CASE
      WHEN CURRENT_DATE('America/New_York') BETWEEN cooldown_start AND cooldown_end THEN 'COOLDOWN'
      WHEN CURRENT_DATE('America/New_York') BETWEEN peak_start AND holiday_date THEN 'PEAK'
      WHEN CURRENT_DATE('America/New_York') BETWEEN boost_start AND DATE_SUB(peak_start, INTERVAL 1 DAY) THEN 'BOOST'
      WHEN CURRENT_DATE('America/New_York') BETWEEN pre_season_start AND DATE_SUB(boost_start, INTERVAL 1 DAY) THEN 'PRE_PEAK'
      ELSE 'OFF_SEASON'
    END as today_phase
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
  WHERE category = 'gift_season'
    AND holiday_date BETWEEN DATE_SUB(CURRENT_DATE('America/New_York'), INTERVAL 10 DAY)
                        AND DATE_ADD(CURRENT_DATE('America/New_York'), INTERVAL 90 DAY)
),

-- Global cooldown check: is ANY holiday in Cooldown right now?
-- If yes, ALL families get Cooldown (everyone winds down after peak)
global_cooldown AS (
  SELECT
    MAX(CASE WHEN today_phase = 'COOLDOWN' THEN 1 ELSE 0 END) = 1 AS is_cooldown,
    MAX(CASE WHEN today_phase = 'COOLDOWN' THEN holiday_name END) AS cooldown_holiday
  FROM active_holidays
),

-- Which families are relevant for each holiday (from V_PEAK_RELEVANCE)
-- Used ONLY for Blitz mode (pre-peak/boost/peak) — not for Cooldown
family_holiday_relevance AS (
  SELECT DISTINCT
    family AS parent_name,
    holiday_name
  FROM `onyga-482313.OI.V_PEAK_RELEVANCE`
  WHERE is_relevant_peak = TRUE
),

-- Resolve Blitz per family (only for families with peak relevance)
family_blitz_modes AS (
  SELECT
    fhr.parent_name,
    ah.holiday_name,
    ah.today_phase
  FROM active_holidays ah
  JOIN family_holiday_relevance fhr ON ah.holiday_name = fhr.holiday_name
  WHERE ah.today_phase IN ('PRE_PEAK', 'BOOST', 'PEAK')
),

-- Final coach mode per family:
-- 1. If global Cooldown is active → ALL families get COOLDOWN
-- 2. Else if family has active Blitz holiday → BLITZ
-- 3. Else → GUARDIAN
family_coach_mode AS (
  SELECT
    families.parent_name,
    CASE
      WHEN gc.is_cooldown THEN gc.cooldown_holiday
      ELSE ARRAY_AGG(fb.holiday_name IGNORE NULLS ORDER BY fb.today_phase LIMIT 1)[SAFE_OFFSET(0)]
    END as active_occasion,
    CASE
      WHEN gc.is_cooldown THEN 'COOLDOWN'
      WHEN COUNT(fb.parent_name) > 0 THEN 'BLITZ'
      ELSE 'GUARDIAN'
    END as coach_mode,
    CASE
      WHEN gc.is_cooldown THEN 'COOLDOWN'
      ELSE COALESCE(
        ARRAY_AGG(fb.today_phase IGNORE NULLS ORDER BY fb.today_phase LIMIT 1)[SAFE_OFFSET(0)],
        'OFF_SEASON'
      )
    END as current_phase
  FROM (
    -- All active product families
    SELECT DISTINCT parent_name
    FROM `onyga-482313.OI.V_ADS_COACH_DATA`
    WHERE parent_name IS NOT NULL AND parent_name != ''
  ) families
  CROSS JOIN global_cooldown gc
  LEFT JOIN family_blitz_modes fb ON LOWER(families.parent_name) = LOWER(fb.parent_name)
  GROUP BY parent_name, gc.is_cooldown, gc.cooldown_holiday
),

-- ═══════════════════════════════════════════════════════
-- THRESHOLD RESOLUTION: mode-aware with 4-level fallback
-- Priority: strategy×mode → GLOBAL×mode → strategy×GUARDIAN → GLOBAL×GUARDIAN
-- ═══════════════════════════════════════════════════════

-- Pivot thresholds by (strategy_id, coach_mode)
threshold_pivot AS (
  SELECT
    strategy_id,
    COALESCE(coach_mode, 'GUARDIAN') as coach_mode,
    MAX(IF(threshold_key='INSUFFICIENT_DATA_CLICKS', threshold_value, NULL)) as min_clicks,
    MAX(IF(threshold_key='WASTED_SPEND_THRESHOLD', threshold_value, NULL)) as wasted_spend_min,
    MAX(IF(threshold_key='NEGATE_ROAS_THRESHOLD', threshold_value, NULL)) as negate_roas,
    MAX(IF(threshold_key='NEGATE_SPEND_THRESHOLD', threshold_value, NULL)) as negate_spend,
    MAX(IF(threshold_key='REDUCE_BID_ROAS', threshold_value, NULL)) as reduce_bid_roas,
    MAX(IF(threshold_key='SCALE_UP_ROAS', threshold_value, NULL)) as scale_up_roas,
    MAX(IF(threshold_key='SCALE_UP_SPEND_CAP', threshold_value, NULL)) as scale_up_spend_cap,
    MAX(IF(threshold_key='PROFITABLE_ROAS', threshold_value, NULL)) as profitable_roas,
    MAX(IF(threshold_key='HALO_ROAS', threshold_value, NULL)) as halo_roas,
    MAX(IF(threshold_key='PROMOTE_MIN_ORDERS', threshold_value, NULL)) as promote_min_orders,
    MAX(IF(threshold_key='PROMOTE_MIN_ROAS', threshold_value, NULL)) as promote_min_roas,
    MAX(IF(threshold_key='PROMOTE_MIN_SQP_VOLUME', threshold_value, NULL)) as promote_min_sqp_vol,
    MAX(IF(threshold_key='PROMOTE_MIN_RANK', threshold_value, NULL)) as promote_min_rank,
    MAX(IF(threshold_key='CONFIDENCE_DAYS_HIGH', threshold_value, NULL)) as conf_days_high,
    MAX(IF(threshold_key='CONFIDENCE_CLICKS_HIGH', threshold_value, NULL)) as conf_clicks_high,
    MAX(IF(threshold_key='CONFIDENCE_DAYS_MEDIUM', threshold_value, NULL)) as conf_days_medium,
    MAX(IF(threshold_key='CONFIDENCE_CLICKS_MEDIUM', threshold_value, NULL)) as conf_clicks_medium,
    MAX(IF(threshold_key='BID_CAP_SUGGESTION', threshold_value, NULL)) as bid_cap,
    MAX(IF(threshold_key='DEFENSE_DOMINATE_IS_PCT', threshold_value, NULL)) as defense_dominate_is,
    -- Launch track (new-campaign aggressive→reduce→decide lifecycle)
    MAX(IF(threshold_key='LAUNCH_WINDOW_DAYS', threshold_value, NULL)) as launch_window_days,
    MAX(IF(threshold_key='LAUNCH_BID_MULT', threshold_value, NULL)) as launch_bid_mult,
    MAX(IF(threshold_key='LAUNCH_BID_CEILING', threshold_value, NULL)) as launch_bid_ceiling,
    MAX(IF(threshold_key='LAUNCH_COLD_BID', threshold_value, NULL)) as launch_cold_bid,
    MAX(IF(threshold_key='LAUNCH_STEP_DOWN_PCT', threshold_value, NULL)) as launch_step_down_pct,
    MAX(IF(threshold_key='LAUNCH_CHECKPOINT_CLICKS', threshold_value, NULL)) as launch_checkpoint_clicks,
    MAX(IF(threshold_key='LAUNCH_NEGATE_CLICKS', threshold_value, NULL)) as launch_negate_clicks,
    MAX(IF(threshold_key='LAUNCH_WINNER_ORDERS', threshold_value, NULL)) as launch_winner_orders,
    MAX(IF(threshold_key='LAUNCH_WINNER_DAYS', threshold_value, NULL)) as launch_winner_days,
    -- Money-bleeder fit-gated rule
    MAX(IF(threshold_key='BLEEDER_FIT_RANK', threshold_value, NULL)) as bleeder_fit_rank,
    MAX(IF(threshold_key='BLEEDER_REDUCE_PCT', threshold_value, NULL)) as bleeder_reduce_pct,
    MAX(IF(threshold_key='BLEEDER_MIN_CLICKS', threshold_value, NULL)) as bleeder_min_clicks
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE product_family IS NULL
  GROUP BY strategy_id, coach_mode
),

-- ─── Data with resolved thresholds (mode-aware) ───
coach_data AS (
  SELECT
    d.*,
    -- Strategy min bid floor from DIM_STRATEGY_TEMPLATE
    COALESCE(stmpl.recommended_bid_min, 0.10) as strategy_bid_min,
    -- Coach mode: resolved per family → fallback to global cooldown check → GUARDIAN
    COALESCE(fcm.coach_mode,
      CASE WHEN (SELECT is_cooldown FROM global_cooldown) THEN 'COOLDOWN' ELSE 'GUARDIAN' END
    ) as coach_mode,
    COALESCE(fcm.active_occasion, 'NONE') as active_occasion,
    COALESCE(fcm.current_phase, 'OFF_SEASON') as current_phase,
    -- Resolved thresholds: strategy×mode → GLOBAL×mode → strategy×GUARDIAN → GLOBAL×GUARDIAN
    COALESCE(tp_sm.min_clicks, tp_gm.min_clicks, tp_sg.min_clicks, tp_gg.min_clicks, 15) as th_min_clicks,
    COALESCE(tp_sm.wasted_spend_min, tp_gm.wasted_spend_min, tp_sg.wasted_spend_min, tp_gg.wasted_spend_min, 15) as th_wasted_spend_min,
    COALESCE(tp_sm.negate_roas, tp_gm.negate_roas, tp_sg.negate_roas, tp_gg.negate_roas, 0.5) as th_negate_roas,
    COALESCE(tp_sm.negate_spend, tp_gm.negate_spend, tp_sg.negate_spend, tp_gg.negate_spend, 20) as th_negate_spend,
    COALESCE(tp_sm.reduce_bid_roas, tp_gm.reduce_bid_roas, tp_sg.reduce_bid_roas, tp_gg.reduce_bid_roas, 0.9) as th_reduce_bid_roas,
    COALESCE(tp_sm.scale_up_roas, tp_gm.scale_up_roas, tp_sg.scale_up_roas, tp_gg.scale_up_roas, 2.0) as th_scale_up_roas,
    COALESCE(tp_sm.scale_up_spend_cap, tp_gm.scale_up_spend_cap, tp_sg.scale_up_spend_cap, tp_gg.scale_up_spend_cap, 50) as th_scale_up_spend_cap,
    COALESCE(tp_sm.profitable_roas, tp_gm.profitable_roas, tp_sg.profitable_roas, tp_gg.profitable_roas, 1.1) as th_profitable_roas,
    COALESCE(tp_sm.halo_roas, tp_gm.halo_roas, tp_sg.halo_roas, tp_gg.halo_roas, 0.5) as th_halo_roas,
    COALESCE(tp_sm.promote_min_orders, tp_gm.promote_min_orders, tp_sg.promote_min_orders, tp_gg.promote_min_orders, 4) as th_promote_min_orders,
    COALESCE(tp_sm.promote_min_roas, tp_gm.promote_min_roas, tp_sg.promote_min_roas, tp_gg.promote_min_roas, 1.5) as th_promote_min_roas,
    COALESCE(tp_sm.promote_min_sqp_vol, tp_gm.promote_min_sqp_vol, tp_sg.promote_min_sqp_vol, tp_gg.promote_min_sqp_vol, 500) as th_promote_min_sqp_vol,
    COALESCE(tp_sm.promote_min_rank, tp_gm.promote_min_rank, tp_sg.promote_min_rank, tp_gg.promote_min_rank, 75) as th_promote_min_rank,
    -- Research Rank (Fit + Purchase, 0-100) for this term × family — gates PROMOTE_TO_EXACT.
    rr.rank AS research_rank,
    -- SQP impression share (our impr ÷ total for the query, latest week) — gates BRAND_DEFENSE bid-up.
    sqis.impr_share_pct AS impression_share_pct,
    COALESCE(tp_sm.conf_days_high, tp_gm.conf_days_high, tp_sg.conf_days_high, tp_gg.conf_days_high, 14) as th_conf_days_high,
    COALESCE(tp_sm.conf_clicks_high, tp_gm.conf_clicks_high, tp_sg.conf_clicks_high, tp_gg.conf_clicks_high, 50) as th_conf_clicks_high,
    COALESCE(tp_sm.conf_days_medium, tp_gm.conf_days_medium, tp_sg.conf_days_medium, tp_gg.conf_days_medium, 7) as th_conf_days_medium,
    COALESCE(tp_sm.conf_clicks_medium, tp_gm.conf_clicks_medium, tp_sg.conf_clicks_medium, tp_gg.conf_clicks_medium, 20) as th_conf_clicks_medium,
    -- Hard bid ceiling ($) and BRAND_DEFENSE "already dominating" impression-share cutoff (%)
    COALESCE(tp_sm.bid_cap, tp_gm.bid_cap, tp_sg.bid_cap, tp_gg.bid_cap, 2.0) as th_bid_cap,
    COALESCE(tp_sm.defense_dominate_is, tp_gm.defense_dominate_is, tp_sg.defense_dominate_is, tp_gg.defense_dominate_is, 50.0) as th_defense_dominate_is,
    -- Launch-track thresholds (resolved strategy×mode → GLOBAL×mode → strategy×GUARDIAN → GLOBAL×GUARDIAN)
    COALESCE(tp_sm.launch_window_days, tp_gm.launch_window_days, tp_sg.launch_window_days, tp_gg.launch_window_days, 30) as th_launch_window_days,
    COALESCE(tp_sm.launch_bid_mult, tp_gm.launch_bid_mult, tp_sg.launch_bid_mult, tp_gg.launch_bid_mult, 1.7) as th_launch_bid_mult,
    COALESCE(tp_sm.launch_bid_ceiling, tp_gm.launch_bid_ceiling, tp_sg.launch_bid_ceiling, tp_gg.launch_bid_ceiling, 1.4) as th_launch_bid_ceiling,
    COALESCE(tp_sm.launch_cold_bid, tp_gm.launch_cold_bid, tp_sg.launch_cold_bid, tp_gg.launch_cold_bid, 1.2) as th_launch_cold_bid,
    COALESCE(tp_sm.launch_step_down_pct, tp_gm.launch_step_down_pct, tp_sg.launch_step_down_pct, tp_gg.launch_step_down_pct, 0.2) as th_launch_step_down_pct,
    COALESCE(tp_sm.launch_checkpoint_clicks, tp_gm.launch_checkpoint_clicks, tp_sg.launch_checkpoint_clicks, tp_gg.launch_checkpoint_clicks, 15) as th_launch_checkpoint_clicks,
    COALESCE(tp_sm.launch_negate_clicks, tp_gm.launch_negate_clicks, tp_sg.launch_negate_clicks, tp_gg.launch_negate_clicks, 45) as th_launch_negate_clicks,
    COALESCE(tp_sm.launch_winner_orders, tp_gm.launch_winner_orders, tp_sg.launch_winner_orders, tp_gg.launch_winner_orders, 2) as th_launch_winner_orders,
    COALESCE(tp_sm.launch_winner_days, tp_gm.launch_winner_days, tp_sg.launch_winner_days, tp_gg.launch_winner_days, 3) as th_launch_winner_days,
    -- Money-bleeder thresholds
    COALESCE(tp_sm.bleeder_fit_rank, tp_gm.bleeder_fit_rank, tp_sg.bleeder_fit_rank, tp_gg.bleeder_fit_rank, 50) as th_bleeder_fit_rank,
    COALESCE(tp_sm.bleeder_reduce_pct, tp_gm.bleeder_reduce_pct, tp_sg.bleeder_reduce_pct, tp_gg.bleeder_reduce_pct, 0.4) as th_bleeder_reduce_pct,
    COALESCE(tp_sm.bleeder_min_clicks, tp_gm.bleeder_min_clicks, tp_sg.bleeder_min_clicks, tp_gg.bleeder_min_clicks, 20) as th_bleeder_min_clicks,
    -- Strategy template max bid (cold-start bid anchor when no CPC exists) + research-page CPC anchors
    stmpl.recommended_bid_max as strategy_bid_max,
    rr.cpc_30d AS research_cpc_30d,
    rr.cpc_12m AS research_cpc_12m,
    -- Mode-aware target ROAS:
    --   GUARDIAN/COOLDOWN  → 7d off-season (live)
    --   BLITZ PEAK         → 3d raw (live, react fast at peak)
    --   BLITZ BOOST/PRE_PEAK → ANTICIPATORY blend (target_weighted_net_roas_hotseason
    --       = equal-weight TY-14d + LY-same-holiday + last-peak, missing components
    --       dropped). For a dormant seasonal target it degrades to pure history
    --       (LY-same-holiday, else last-peak), so bids climb BEFORE this year's demand.
    CASE
      WHEN COALESCE(fcm.coach_mode,
        CASE WHEN (SELECT is_cooldown FROM global_cooldown) THEN 'COOLDOWN' ELSE 'GUARDIAN' END
      ) IN ('GUARDIAN', 'COOLDOWN')
        THEN d.target_net_roas_1w_os
      WHEN COALESCE(fcm.coach_mode,
        CASE WHEN (SELECT is_cooldown FROM global_cooldown) THEN 'COOLDOWN' ELSE 'GUARDIAN' END
      ) = 'BLITZ' AND COALESCE(fcm.current_phase, 'OFF_SEASON') = 'PEAK'
        THEN d.ads_net_roas_3d
      WHEN COALESCE(fcm.coach_mode,
        CASE WHEN (SELECT is_cooldown FROM global_cooldown) THEN 'COOLDOWN' ELSE 'GUARDIAN' END
      ) = 'BLITZ'
        THEN d.target_weighted_net_roas_hotseason
      ELSE d.target_net_roas_1w
    END as target_roas,
    -- Anticipatory bid gate for BLITZ BOOST/PRE_PEAK: a proven seasonal target
    -- (strong LY-same-holiday or last-peak orders) is bid-eligible even with 0 recent
    -- orders, so the raise tiers fire and pre-position bids before demand arrives.
    -- Outside BOOST/PRE_PEAK this is just the recent 8-week orders (no behavior change).
    CASE
      WHEN COALESCE(fcm.coach_mode,
        CASE WHEN (SELECT is_cooldown FROM global_cooldown) THEN 'COOLDOWN' ELSE 'GUARDIAN' END
      ) = 'BLITZ' AND COALESCE(fcm.current_phase, 'OFF_SEASON') IN ('BOOST', 'PRE_PEAK')
        THEN GREATEST(COALESCE(d.target_orders_8w, 0), COALESCE(d.ly_orders, 0), COALESCE(d.q4_peak_orders, 0))
      ELSE COALESCE(d.target_orders_8w, 0)
    END as eff_orders_for_bid
  FROM `onyga-482313.OI.V_ADS_COACH_DATA` d
  -- Resolve coach mode from family
  LEFT JOIN family_coach_mode fcm ON LOWER(d.parent_name) = LOWER(fcm.parent_name)
  -- 4-level threshold resolution:
  -- tp_sm = strategy × mode (most specific)
  LEFT JOIN threshold_pivot tp_sm ON d.strategy_id = tp_sm.strategy_id AND COALESCE(fcm.coach_mode, 'GUARDIAN') = tp_sm.coach_mode
  -- tp_gm = GLOBAL × mode
  LEFT JOIN threshold_pivot tp_gm ON tp_gm.strategy_id = 'GLOBAL' AND COALESCE(fcm.coach_mode, 'GUARDIAN') = tp_gm.coach_mode
  -- tp_sg = strategy × GUARDIAN (fallback to default strategy thresholds)
  LEFT JOIN threshold_pivot tp_sg ON d.strategy_id = tp_sg.strategy_id AND tp_sg.coach_mode = 'GUARDIAN'
  -- tp_gg = GLOBAL × GUARDIAN (ultimate fallback)
  LEFT JOIN threshold_pivot tp_gg ON tp_gg.strategy_id = 'GLOBAL' AND tp_gg.coach_mode = 'GUARDIAN'
  -- Strategy template for min bid floor
  LEFT JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` stmpl ON d.strategy_id = stmpl.strategy_id
  -- Research Rank per term × family (deduped to one row per term+family to avoid fan-out).
  LEFT JOIN (
    SELECT LOWER(query_text) AS qt, parent_name, MAX(rank) AS rank,
      MAX(cpc_30d) AS cpc_30d, MAX(cpc_12m) AS cpc_12m
    FROM `onyga-482313.OI.V_RESEARCH_RANKED`
    GROUP BY 1, 2
  ) rr ON LOWER(d.search_term) = rr.qt AND d.parent_name = rr.parent_name
  -- SQP impression share per term × ASIN (latest week) — feeds the BRAND_DEFENSE bid-up gate.
  LEFT JOIN (
    SELECT qt, asin, impr_share_pct FROM (
      SELECT LOWER(query_text) AS qt, ASIN AS asin, impression_share_pct AS impr_share_pct,
        ROW_NUMBER() OVER (PARTITION BY LOWER(query_text), ASIN ORDER BY week_start_date DESC) AS rn
      FROM `onyga-482313.OI.FACT_SEARCH_QUERY`
    ) WHERE rn = 1
  ) sqis ON LOWER(d.search_term) = sqis.qt AND d.asin = sqis.asin
),

-- ═══════════════════════════════════════════════════════
-- POST-PEAK TARGET METRICS: aggregate ONLY days after the holiday
-- Used exclusively for Cooldown bid/budget decisions.
-- Uses cooldown_start (not holiday_date) as the post-peak start date.
-- ═══════════════════════════════════════════════════════
pp_cooldown_holiday AS (
  SELECT MIN(cooldown_start) as hol_date
  FROM active_holidays
  WHERE today_phase = 'COOLDOWN'
),

pp_target_metrics AS (
  SELECT
    fa.campaign_id,
    COALESCE(fa.targeting, LOWER(kw.keyword_text)) as targeting,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    SUM(fa.Ads_cost) as pp_spend,
    SUM(fa.Ads_clicks) as pp_clicks,
    SUM(fa.Ads_orders) as pp_orders,
    SUM(fa.Ads_sales) as pp_sales,
    COUNT(DISTINCT fa.date) as pp_days
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  CROSS JOIN pp_cooldown_holiday pch
  LEFT JOIN (
    SELECT keyword_id, keyword_text FROM (
      SELECT keyword_id, keyword_text,
        ROW_NUMBER() OVER (PARTITION BY keyword_id ORDER BY keyword_text) as rn
      FROM `onyga-482313.OI.DIM_KEYWORD`
      WHERE is_current = TRUE AND keyword_text IS NOT NULL
    ) WHERE rn = 1
  ) kw ON fa.keyword_id = kw.keyword_id
  WHERE pch.hol_date IS NOT NULL
    AND fa.date >= pch.hol_date
    AND fa.date < CURRENT_DATE()
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2, 3
),

-- ─── Campaign-level post-peak Ads ROAS (for budget decisions) ───
-- Uses Ads ROAS (sales/spend) since only ads data is available during post-peak
pp_campaign_metrics AS (
  SELECT
    campaign_id,
    SUM(pp_spend) as pp_campaign_spend,
    SUM(pp_orders) as pp_campaign_orders,
    SUM(pp_sales) as pp_campaign_sales,
    MAX(pp_days) as pp_campaign_days,
    ROUND(SAFE_DIVIDE(SUM(pp_sales), NULLIF(SUM(pp_spend), 0)), 2) as pp_campaign_net_roas
  FROM pp_target_metrics
  GROUP BY campaign_id
),

-- ─── Campaign-level budget health metrics (for GUARDIAN/BLITZ budget decisions) ───
-- Aggregates spend, orders, ROAS at campaign level + out-of-budget detection
campaign_budget_metrics AS (
  SELECT
    d.campaign_id,
    SUM(d.ads_spend_1w) as camp_spend_1w,
    SUM(d.ads_spend_4w) as camp_spend_4w,
    SUM(d.ads_spend_8w) as camp_spend_8w,
    SUM(d.ads_orders_8w) as camp_orders_8w,
    SUM(d.ads_sales_8w) as camp_sales_8w,
    SUM(d.ads_net_profit_8w) as camp_net_profit_8w,
    -- Campaign Net ROAS 8w = (profit / spend) + 1 (legacy, kept for backward compat)
    ROUND(SAFE_DIVIDE(SUM(d.ads_net_profit_8w), NULLIF(SUM(d.ads_spend_8w), 0)) + 1, 2) as camp_net_roas_8w,
    -- Mode-aware campaign ROAS: weighted average of target_roas across targets
    -- Weighted by target spend (targets with more spend contribute more to campaign ROAS)
    ROUND(SAFE_DIVIDE(
      SUM(d.target_roas * COALESCE(d.target_spend_8w, 0)),
      NULLIF(SUM(COALESCE(d.target_spend_8w, 0)), 0)
    ), 2) as camp_effective_roas,
    -- Last-day spend proxy (1w avg — TODO: enrich source with per-day campaign spend)
    ROUND(SUM(d.ads_spend_1w) / 7.0, 2) as camp_avg_daily_spend,
    -- Budget utilization: daily_spend / budget (>90% = out of budget)
    ROUND(SAFE_DIVIDE(SUM(d.ads_spend_1w) / 7.0, NULLIF(ANY_VALUE(d.current_budget), 0)) * 100, 0) as camp_budget_util_pct
  FROM coach_data d
  WHERE d.recommendation_type = 'ACTIVE_TERM'
    AND UPPER(d.campaign_state) = 'ENABLED'
  GROUP BY d.campaign_id
),

-- ═══════════════════════════════════════════════════════
-- SEASONAL CAMPAIGN DETECTION: match campaign name to holiday
-- Campaigns tagged with a peak name (e.g., "Easter 2026", "Easter")
-- are seasonal campaigns that should be paused during cooldown
-- and enabled during blitz (if profitable last year).
-- ═══════════════════════════════════════════════════════
seasonal_campaign_holiday AS (
  SELECT
    d.campaign_id,
    d.campaign_name,
    h.holiday_name as seasonal_peak_name,
    h.today_phase as seasonal_peak_phase
  FROM (SELECT DISTINCT campaign_id, campaign_name FROM `onyga-482313.OI.V_ADS_COACH_DATA`) d
  INNER JOIN active_holidays h
    ON STRPOS(UPPER(d.campaign_name), UPPER(h.holiday_name)) > 0
    OR STRPOS(UPPER(d.campaign_name), UPPER(REGEXP_REPLACE(h.holiday_name, r"'?s?\s+Day$", ''))) > 0
),

-- Last year's peak net ROAS per holiday (all campaigns matching holiday keyword)
-- Used by blitz to decide if seasonal campaigns should be enabled
ly_peak_campaign_roas AS (
  SELECT
    h_now.holiday_name,
    ROUND(SAFE_DIVIDE(SUM(fa.Ads_sales), NULLIF(SUM(fa.Ads_cost), 0)), 2) as ly_peak_net_roas
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h_now
  INNER JOIN `onyga-482313.OI.DIM_US_HOLIDAYS` h_ly
    ON h_ly.holiday_name = h_now.holiday_name
    AND EXTRACT(YEAR FROM h_ly.holiday_date) = EXTRACT(YEAR FROM h_now.holiday_date) - 1
  INNER JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON fa.date BETWEEN h_ly.peak_start AND h_ly.holiday_date
    AND (STRPOS(UPPER(fa.campaign_name), UPPER(h_now.holiday_name)) > 0
      OR STRPOS(UPPER(fa.campaign_name), UPPER(REGEXP_REPLACE(h_now.holiday_name, r"'?s?\s+Day$", ''))) > 0)
  WHERE h_now.category = 'gift_season'
    AND h_ly.category = 'gift_season'
    AND h_now.holiday_date BETWEEN DATE_SUB(CURRENT_DATE('America/New_York'), INTERVAL 10 DAY)
                                AND DATE_ADD(CURRENT_DATE('America/New_York'), INTERVAL 90 DAY)
  GROUP BY h_now.holiday_name
),

scored_raw AS (
SELECT
  d.*,
  -- Pre-resolve: each coach mode uses the most relevant ROAS signal (no fallback)
  --   GUARDIAN/COOLDOWN → 7d off-season
  --   BLITZ BOOST → 14d raw
  --   BLITZ PEAK → 7d raw
  CASE
    WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN') THEN d.ads_net_roas_1w_os
    WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN d.ads_net_roas_1w
    WHEN d.coach_mode = 'BLITZ' THEN d.ads_net_roas_14d
    ELSE d.ads_net_roas_1w
  END as effective_roas,
  -- target_roas already computed in CTE with same mode-aware rules

  -- ─── Campaign Age (for 14-day warmup guard) ───
  DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(d.campaign_creation_date), DAY) as campaign_age_days,

  -- ═══════════════════════════════════════════════════════════════════════════
  -- LAUNCH TRACK (new-campaign aggressive→reduce→decide lifecycle)
  -- Young campaigns bid aggressively to buy clicks fast, then re-decide every
  -- LAUNCH_CHECKPOINT_CLICKS clicks; surfaced in the dashboard "New campaigns" section.
  -- ═══════════════════════════════════════════════════════════════════════════
  (DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(d.campaign_creation_date), DAY) < d.th_launch_window_days) as is_new_campaign,
  -- launch_clicks ≈ lifetime clicks (the 4w window ≈ a <30d campaign's whole life)
  COALESCE(d.ads_clicks_4w, 0) as launch_clicks,
  -- Aggressive launch bid: anchor (research CPC) × mult, cold-start chain, capped at ceiling.
  -- Cold-start (a) "SQP market CPC" is infeasible (SQP has no cost) → proxy with the term's own
  -- observed 8w CPC, then strategy template max, then the flat cold bid.
  ROUND(LEAST(
    CASE
      WHEN COALESCE(NULLIF(d.research_cpc_30d, 0), NULLIF(d.research_cpc_12m, 0)) IS NOT NULL
        THEN COALESCE(NULLIF(d.research_cpc_30d, 0), NULLIF(d.research_cpc_12m, 0)) * d.th_launch_bid_mult
      WHEN NULLIF(d.ads_cpc_8w, 0) IS NOT NULL THEN d.ads_cpc_8w * d.th_launch_bid_mult
      WHEN NULLIF(d.strategy_bid_max, 0) IS NOT NULL THEN d.strategy_bid_max * d.th_launch_bid_mult
      ELSE d.th_launch_cold_bid
    END,
    d.th_launch_bid_ceiling
  ), 2) as launch_bid,
  CASE
    WHEN COALESCE(NULLIF(d.research_cpc_30d, 0), NULLIF(d.research_cpc_12m, 0)) IS NOT NULL THEN 'cpc'
    WHEN NULLIF(d.ads_cpc_8w, 0) IS NOT NULL THEN 'market'
    WHEN NULLIF(d.strategy_bid_max, 0) IS NOT NULL THEN 'template'
    ELSE 'cold'
  END as launch_bid_source,
  -- Lifecycle phase (label only; null off-track)
  CASE
    WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(d.campaign_creation_date), DAY) >= d.th_launch_window_days THEN NULL
    WHEN COALESCE(d.ads_orders_3d, 0) >= d.th_launch_winner_orders AND COALESCE(d.ads_net_roas_3d, 0) >= d.th_profitable_roas THEN 'WINNER'
    WHEN COALESCE(d.ads_orders_4w, 0) = 0 AND COALESCE(d.ads_clicks_4w, 0) >= d.th_launch_negate_clicks THEN 'CUT'
    WHEN COALESCE(d.ads_orders_4w, 0) >= 1 THEN 'EVALUATE'
    ELSE 'GATHER'
  END as launch_phase,
  -- The 15-click decision matrix (NULL = not on the launch track)
  CASE
    WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(d.campaign_creation_date), DAY) >= d.th_launch_window_days THEN NULL
    -- Winner: trailing-window orders at/above the profitable bar → graduate to the normal coacher
    WHEN COALESCE(d.ads_orders_3d, 0) >= d.th_launch_winner_orders AND COALESCE(d.ads_net_roas_3d, 0) >= d.th_profitable_roas THEN 'LAUNCH_GRADUATE'
    -- Has orders: profitable → hold; expensive → reduce (gated to once per click batch)
    WHEN COALESCE(d.ads_orders_4w, 0) >= 1 THEN
      CASE
        WHEN COALESCE(d.ads_net_roas_4w, 0) >= d.th_profitable_roas THEN 'LAUNCH_HOLD'
        WHEN COALESCE(d.clicks_since_last_bid_change, 0) >= d.th_launch_checkpoint_clicks THEN 'LAUNCH_REDUCE_BID'
        ELSE 'LAUNCH_HOLD'
      END
    -- Zero orders: 15 hold / 30 reduce / 45 negate
    WHEN COALESCE(d.ads_clicks_4w, 0) >= d.th_launch_negate_clicks THEN 'LAUNCH_NEGATE'
    WHEN COALESCE(d.ads_clicks_4w, 0) >= 2 * d.th_launch_checkpoint_clicks
         AND COALESCE(d.clicks_since_last_bid_change, 0) >= d.th_launch_checkpoint_clicks THEN 'LAUNCH_REDUCE_BID'
    ELSE 'LAUNCH_HOLD'
  END as launch_decision,

  -- ─── Signal ───
  CASE
    WHEN d.recommendation_type = 'OPPORTUNITY' THEN 'NOT_TARGETED'
    -- DEFENSE strategies hold position regardless of ROAS — show DEFENDED, not WASTED_SPEND
    WHEN d.strategy_id IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE') THEN 'DEFENDED'
    WHEN d.ads_clicks_8w < d.th_min_clicks THEN 'INSUFFICIENT_DATA'
    WHEN d.ads_orders_8w = 0 AND d.sqp_organic_units_8w = 0
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0 THEN 'WASTED_SPEND'
    WHEN d.ads_orders_8w = 0 AND d.sqp_organic_units_8w > 0 THEN 'ORGANIC_ONLY'
    WHEN CASE
           WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN') THEN d.ads_net_roas_1w_os
           WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN d.ads_net_roas_1w
           WHEN d.coach_mode = 'BLITZ' THEN d.ads_net_roas_14d
           ELSE d.ads_net_roas_1w
         END >= d.th_scale_up_roas THEN 'STRONG'
    WHEN CASE
           WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN') THEN d.ads_net_roas_1w_os
           WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN d.ads_net_roas_1w
           WHEN d.coach_mode = 'BLITZ' THEN d.ads_net_roas_14d
           ELSE d.ads_net_roas_1w
         END >= d.th_profitable_roas THEN 'PROFITABLE'
    WHEN CASE
           WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN') THEN d.ads_net_roas_1w_os
           WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN d.ads_net_roas_1w
           WHEN d.coach_mode = 'BLITZ' THEN d.ads_net_roas_14d
           ELSE d.ads_net_roas_1w
         END >= d.th_halo_roas THEN 'MARGINAL'
    WHEN d.ads_orders_8w > 0 THEN 'UNPROFITABLE'
    ELSE 'INSUFFICIENT_DATA'
  END as ads_signal,

  -- ─── Action (strategy-aware) ───
  CASE
    -- ═══ OPPORTUNITY: SQP orders + high volume + high CVR + not a brand term ═══
    -- Bug #2/#3 fix: require SQP CVR > 15% and SQP volume > 1500, exclude brand terms
    WHEN d.recommendation_type = 'OPPORTUNITY'
      AND COALESCE(SAFE_DIVIDE(d.sqp_orders_8w, NULLIF(d.sqp_clicks_8w, 0)) * 100, 0) > 15
      AND COALESCE(d.sqp_impressions_8w, 0) > 1500
      AND d.strategy_id NOT IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE')
      THEN 'START_TERM'
    -- Opportunity that doesn't meet thresholds → MONITOR
    WHEN d.recommendation_type = 'OPPORTUNITY' THEN 'MONITOR'

    -- ═══ STOP_SEASONAL: seasonal campaign past its season ═══
    -- Fires in GUARDIAN and COOLDOWN — SEASONAL_PUSH strategy only
    WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN')
      AND d.strategy_id = 'SEASONAL_PUSH'
      AND EXISTS (
        SELECT 1 FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
        WHERE h.category = 'gift_season'
          AND h.cooldown_end < CURRENT_DATE('America/New_York')
          AND (
            STRPOS(UPPER(d.campaign_name), UPPER(h.holiday_name)) > 0
            OR STRPOS(UPPER(d.campaign_name), UPPER(REGEXP_REPLACE(h.holiday_name, r"'?s?\s+Day$", ''))) > 0
          )
      )
      AND d.ads_clicks_recent_5d > 0  -- still active
      THEN 'STOP_SEASONAL'

    -- ═══ BLITZ SEASONAL LIFECYCLE ═══
    -- START_SEASONAL: reactivate paused seasonal campaigns when BLITZ starts
    WHEN d.coach_mode = 'BLITZ'
      AND UPPER(d.campaign_state) != 'ENABLED' AND d.campaign_state IS NOT NULL
      AND (d.strategy_id = 'SEASONAL_PUSH'
           OR STRPOS(UPPER(d.campaign_name), 'Q4 SEASONAL') > 0
           OR STRPOS(UPPER(d.campaign_name), 'SEASONAL') > 0)
      THEN 'START_SEASONAL'

    -- NEW_SEASONAL: Q4 term detected but not yet in a seasonal campaign → create one
    WHEN d.coach_mode = 'BLITZ' AND d.is_q4_seasonal = TRUE
      AND d.strategy_id != 'SEASONAL_PUSH'
      AND NOT REGEXP_CONTAINS(UPPER(d.campaign_name), r'Q4 SEASONAL|SEASONAL.PUSH')
      THEN 'NEW_SEASONAL'

    -- ═══ COOLDOWN: suppress negations — only bid/budget reductions, no term changes ═══
    -- STOP_SEASONAL already handled above
    WHEN d.coach_mode = 'COOLDOWN' AND d.ads_orders_8w > 0 THEN 'KEEP'
    WHEN d.coach_mode = 'COOLDOWN' THEN 'MONITOR'

    -- ═══ Insufficient data at SEARCH TERM level → MONITOR ═══
    -- Bid decisions (INCREASE/REDUCE) live in target_action column, not here.
    WHEN d.ads_clicks_8w < d.th_min_clicks THEN 'MONITOR'

    -- ═══ FIT PROTECTION (money-bleeder rule) — runs BEFORE every negate branch ═══
    -- A research-fit term (rank ≥ BLEEDER_FIT_RANK) with 0 orders (4w) is NEVER negated:
    -- keep it (MONITOR here) so target_action can REDUCE_BID aggressively instead. Broad on
    -- purpose (no spend/clicks gate) so a fit term can't slip into a downstream negate; the
    -- actual bid cut is still gated to real bleeders in target_action/recommended_bid.
    WHEN d.strategy_id NOT IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE')
      AND COALESCE(d.ads_orders_4w, 0) = 0
      AND COALESCE(d.research_rank, 0) >= d.th_bleeder_fit_rank
      THEN 'MONITOR'

    -- ═══ EXACT_BOOST strategy: already boosted, evaluate performance ═══
    -- When target = term: can't negate yourself → STOP_TARGET or MOVE_TO_SEASONAL_PUSH
    -- When target ≠ term: negate the specific search term from the target keyword

    -- (MOVE_TO_SEASONAL_PUSH removed — seasonal logic simplified)

    -- Sub-case B: target = term AND NOT seasonal → bad target, let target_action handle STOP_TARGET
    WHEN d.strategy_id = 'EXACT_BOOST' AND d.targeting = d.search_term
      AND d.ads_clicks_8w >= d.th_min_clicks
      AND (d.ads_orders_8w = 0 OR d.ads_net_roas_8w < d.th_reduce_bid_roas)
      THEN 'MONITOR'  -- STOP_TARGET fires in target_action column

    -- Sub-case C: target ≠ term → negate the search term from this target
    WHEN d.strategy_id = 'EXACT_BOOST' AND d.ads_orders_8w = 0
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0 THEN 'NEGATE_BOOST_SIMILAR_EXACT'
    -- Lag safety: if lag ROAS > 1.3, defer EXACT_BOOST negate to MONITOR
    -- NEGATE_BOOST_SIMILAR_EXACT uses 7d raw ROAS
    WHEN d.strategy_id = 'EXACT_BOOST'
      AND d.ads_net_roas_1w IS NOT NULL AND d.ads_net_roas_1w < d.th_negate_roas
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0
      AND COALESCE(d.ads_lag_net_roas, 0) > 1.3 THEN 'MONITOR'
    WHEN d.strategy_id = 'EXACT_BOOST'
      AND d.ads_net_roas_1w IS NOT NULL AND d.ads_net_roas_1w < d.th_negate_roas
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0 THEN 'NEGATE_BOOST_SIMILAR_EXACT'
    WHEN d.strategy_id = 'EXACT_BOOST'
      AND d.ads_net_roas_1w IS NOT NULL AND d.ads_net_roas_1w < d.th_reduce_bid_roas
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0
      AND COALESCE(d.ads_lag_net_roas, 0) > 1.3 THEN 'MONITOR'
    WHEN d.strategy_id = 'EXACT_BOOST'
      AND d.ads_net_roas_1w IS NOT NULL AND d.ads_net_roas_1w < d.th_reduce_bid_roas
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0 THEN 'NEGATE_BOOST_SIMILAR_EXACT'

    -- ═══ BRAND_DEFENSE / PRODUCT_DEFENSE: never negate (NEGATE_ROAS = -999) ═══
    -- These strategies defend position — MONITOR only, no action
    WHEN d.strategy_id IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE') THEN 'MONITOR'

    -- ═══ CATEGORY_CONQUEST / COMPETITOR_CONQUEST: aggressive thresholds ═══
    WHEN d.strategy_id IN ('CATEGORY_CONQUEST', 'COMPETITOR_CONQUEST')
      AND d.ads_orders_8w = 0 AND d.ads_clicks_8w >= d.th_min_clicks
      AND d.ads_clicks_recent_5d > 0 THEN 'NEGATE_TERM'
    -- Lag safety: if lag ROAS > 1.3, defer CONQUEST negate to MONITOR
    -- NEGATE uses 12-month lifetime ROAS — if no LT data, don't negate
    WHEN d.strategy_id IN ('CATEGORY_CONQUEST', 'COMPETITOR_CONQUEST')
      AND d.lt_net_roas IS NOT NULL AND d.lt_net_roas < d.th_negate_roas
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0
      AND COALESCE(d.ads_lag_net_roas, 0) > 1.3 THEN 'MONITOR'
    WHEN d.strategy_id IN ('CATEGORY_CONQUEST', 'COMPETITOR_CONQUEST')
      AND d.lt_net_roas IS NOT NULL AND d.lt_net_roas < d.th_negate_roas
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0 THEN 'NEGATE_TERM'

    -- ═══ GENERAL LOGIC (HUNTER, LOW_COST_DISCOVERY, others) ═══

    -- ═══ SWITCH_HERO: REMOVED from term-level (Bug #5 fix) ═══
    -- SWITCH_HERO logic moved to target_action (TARGET level) below.
    -- See target_action CASE for SWITCH_HERO at targeting level.

    -- Wasted: 0 orders + 0 SQP organic + enough clicks + still active
    -- Wasted: negate only if lifetime confirms loss
    WHEN d.ads_orders_8w = 0 AND d.sqp_organic_units_8w = 0
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0
      AND d.lt_net_roas IS NOT NULL THEN 'NEGATE_TERM'

    -- ═══ SEASONAL TERM GUARD: seasonal terms can only be promoted by BLITZ ═══
    -- Terms containing holiday names (easter, valentine, christmas, etc.)
    -- should not be promoted during off-season — wait for the right BLITZ phase
    WHEN d.coach_mode != 'BLITZ'
      AND d.is_holiday_seasonal = TRUE
      AND d.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
      AND d.ads_orders_8w >= CAST(d.th_promote_min_orders AS INT64)
      AND d.ads_weighted_net_roas_offseason IS NOT NULL AND d.ads_weighted_net_roas_offseason >= d.th_promote_min_roas
      AND NOT d.already_in_exact_boost
      THEN 'MONITOR'

    -- Promote to exact (hunter/discovery with consistent conversions)
    -- Uses mode-aware ROAS (off-season for GUARDIAN)
    WHEN d.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
      AND d.ads_orders_8w >= CAST(d.th_promote_min_orders AS INT64)
      AND d.ads_weighted_net_roas_offseason IS NOT NULL AND d.ads_weighted_net_roas_offseason >= d.th_promote_min_roas
      AND NOT d.already_in_exact_boost
      AND d.sqp_amazon_search_volume_8w >= d.th_promote_min_sqp_vol
      -- Research-rank gate: only promote terms that are a strong fit for the family (rank > threshold).
      -- NULL rank (term not in research) is treated as below threshold → not promoted.
      AND COALESCE(d.research_rank, 0) >= d.th_promote_min_rank THEN 'PROMOTE_TO_EXACT'

    -- Heavy loss + still active → negate (uses 12-month lifetime ROAS)
    -- If no LT data, don't negate → MONITOR
    -- Lag safety: if lag ROAS > 1.3, defer to MONITOR
    WHEN d.lt_net_roas IS NOT NULL AND d.lt_net_roas < d.th_negate_roas
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0
      AND COALESCE(d.ads_lag_net_roas, 0) > 1.3 THEN 'MONITOR'
    WHEN d.lt_net_roas IS NOT NULL AND d.lt_net_roas < d.th_negate_roas
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0 THEN 'NEGATE_TERM'

    -- ═══ MONEY BLEEDER (not-fit) catch — stop the bleed ═══
    -- A 0-order (4w) term with real spend ($5+ panel floor) + enough clicks that is NOT a research
    -- fit (rank < BLEEDER_FIT_RANK, or not in research) → NEGATE_TERM. Catches bleeders the
    -- strategy-specific branches let fall through to MONITOR (e.g. no recent-5d clicks / no LT data).
    WHEN d.strategy_id NOT IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE')
      AND COALESCE(d.ads_orders_4w, 0) = 0
      AND COALESCE(d.ads_spend_4w, 0) >= 5
      AND COALESCE(d.ads_clicks_4w, 0) >= d.th_bleeder_min_clicks
      AND COALESCE(d.research_rank, 0) < d.th_bleeder_fit_rank
      THEN 'NEGATE_TERM'

    ELSE 'MONITOR'
  END as action,

  -- ─── Target Action (bid decisions at TARGET KEYWORD level) ───
  -- This is what you actually change in Amazon: increase/decrease bid on the target.
  -- One decision per campaign × targeting — dashboard should GROUP BY targeting.
  -- Uses target_weighted_net_roas (recent-biased, target-level aggregated) when available.
  CASE
    WHEN d.recommendation_type = 'OPPORTUNITY' THEN NULL
    -- NEEDS_STRATEGY: campaign has no mapped strategy → no bid action; flag for the user to assign one.
    WHEN d.strategy_id IS NULL THEN 'NEEDS_STRATEGY'

    -- 🔥 BLITZ: paused seasonal campaign → let START_SEASONAL handle (term-level action)
    WHEN d.coach_mode = 'BLITZ'
      AND UPPER(d.campaign_state) != 'ENABLED' AND d.campaign_state IS NOT NULL
      AND (d.strategy_id = 'SEASONAL_PUSH'
           OR STRPOS(UPPER(d.campaign_name), 'Q4 SEASONAL') > 0
           OR STRPOS(UPPER(d.campaign_name), 'SEASONAL') > 0)
      THEN 'ENABLE_CAMPAIGN'

    -- 🚫 PAUSED: campaign is paused — bid changes won't take effect
    WHEN UPPER(d.campaign_state) != 'ENABLED' AND d.campaign_state IS NOT NULL THEN 'CAMPAIGN_PAUSED'

    -- ❄️ COOLDOWN v2: 3-tier post-peak bid logic
    -- Tier 1: COOLDOWN_MONITOR — pp Ads ROAS ≥ 0.8, performing → leave alone
    -- Tier 2: REDUCE_TO_BASELINE — pp Ads ROAS ≥ 0.6, marginal → gradual reduce
    -- Tier 3: RESTORE_PRE_PEAK — pp Ads ROAS < 0.6, losing money → restore
    WHEN d.coach_mode = 'COOLDOWN' AND d.current_bid IS NOT NULL
      AND COALESCE(pp.pp_spend, 0) > 0
      AND SAFE_DIVIDE(pp.pp_sales, NULLIF(pp.pp_spend, 0)) >= 0.8
      THEN 'COOLDOWN_MONITOR'
    WHEN d.coach_mode = 'COOLDOWN' AND d.current_bid IS NOT NULL
      AND COALESCE(pp.pp_spend, 0) > 0
      AND SAFE_DIVIDE(pp.pp_sales, NULLIF(pp.pp_spend, 0)) >= 0.6
      THEN 'REDUCE_TO_BASELINE'
    WHEN d.coach_mode = 'COOLDOWN' AND d.current_bid IS NOT NULL
      THEN 'RESTORE_PRE_PEAK'

    -- ═══ DEFENSE BID-RAISE: control the auction, make terms expensive for competitors ═══
    -- BRAND_DEFENSE (brand search terms): bid up toward the ceiling while we're NOT already
    --   dominating (SQP impression share < cutoff). Once dominating, a higher bid won't move it.
    -- PRODUCT_DEFENSE (ASIN targeting on own detail pages): no SQP signal exists for detail-page
    --   slots → bid up toward the ceiling unconditionally to occupy our own listings.
    WHEN d.strategy_id = 'BRAND_DEFENSE'
      AND COALESCE(d.current_bid, 0) < d.th_bid_cap
      AND COALESCE(d.impression_share_pct, 0) < d.th_defense_dominate_is
      THEN 'INCREASE_BID'
    WHEN d.strategy_id = 'PRODUCT_DEFENSE'
      AND COALESCE(d.current_bid, 0) < d.th_bid_cap
      THEN 'INCREASE_BID'
    WHEN d.strategy_id IN ('PRODUCT_DEFENSE', 'BRAND_DEFENSE') THEN 'MONITOR_TARGET'

    WHEN d.target_clicks_8w < d.th_min_clicks THEN 'MONITOR_TARGET'

    -- SWITCH_HERO: wrong ASIN at TARGET level (Bug #5 fix: moved from term-level)
    -- Case 1: zero orders with current ASIN + hero exists + enough clicks at target level
    WHEN d.hero_asin IS NOT NULL AND NOT d.is_hero_match
      AND d.target_orders_8w = 0 AND d.target_clicks_8w >= 20 THEN 'SWITCH_HERO'
    -- Case 2: hero outperforms by 50%+ at target level
    WHEN d.hero_asin IS NOT NULL AND NOT d.is_hero_match
      AND d.target_orders_8w > 0 AND d.target_clicks_8w >= 20
      AND d.hero_ads_cvr_pct > 0
      AND SAFE_DIVIDE(d.hero_ads_cvr_pct, NULLIF(SAFE_DIVIDE(d.target_orders_8w, NULLIF(d.target_clicks_8w, 0)) * 100, 0)) >= 1.5
      AND COALESCE(d.hero_score, 0) >= 3
      THEN 'SWITCH_HERO'

    -- STOP_TARGET: all terms under target have 0 orders + enough clicks → entire target is bad
    WHEN d.target_orders_8w = 0 AND d.target_clicks_8w >= d.th_min_clicks
      AND d.target_clicks_recent_5d > 0 THEN 'STOP_TARGET'

    -- ═══ SEASONAL GUARD: GUARDIAN should NOT increase bids on seasonal targets ═══
    -- Targets containing holiday names (easter, valentine, mothers day, etc.)
    -- are capped at KEEP_TARGET during off-season to prevent wasteful scaling
    WHEN d.coach_mode = 'GUARDIAN'
      AND d.target_roas >= d.th_profitable_roas AND d.eff_orders_for_bid >= 2
      AND d.is_holiday_seasonal = TRUE
      THEN 'KEEP_TARGET'

    -- ═══ PAUSED/ARCHIVED GUARD: Bid changes only apply to ENABLED targets ═══
    -- If the target keyword is paused/archived, no point recommending bid changes.
    -- Uses target_keyword_status from V_ADS_COACH_DATA (latest from FACT_AMAZON_ADS).
    WHEN COALESCE(d.target_keyword_status, 'ENABLED') != 'ENABLED' THEN 'TARGET_PAUSED'

    -- ═══ WARMUP GUARD: new campaigns need 14 days for algorithm to learn ═══
    -- Blocks INCREASE_BID for campaigns created less than 14 days ago.
    -- Amazon's algorithm needs time to find optimal placements.
    WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(d.campaign_creation_date), DAY) < 14
      AND d.target_roas >= d.th_profitable_roas AND d.eff_orders_for_bid >= 2
      THEN 'WARMUP_MONITOR'

    -- ═══ MONEY BLEEDER (fit): 0 orders (4w) + real spend + enough clicks + research-fit → REDUCE_BID ═══
    -- The standard reduce tier needs target_orders_8w > 0; a fit bleeder has 0 orders, so it would
    -- otherwise fall through to MONITOR_TARGET. Cut the bid hard (recommended_bid handles -BLEEDER_REDUCE_PCT).
    WHEN d.strategy_id NOT IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE')
      AND COALESCE(d.ads_orders_4w, 0) = 0
      AND COALESCE(d.ads_spend_4w, 0) >= 5
      AND COALESCE(d.ads_clicks_4w, 0) >= d.th_bleeder_min_clicks
      AND COALESCE(d.research_rank, 0) >= d.th_bleeder_fit_rank
      AND NOT (
        (d.coach_mode = 'GUARDIAN' AND d.days_since_last_bid_change < 7)
        OR (d.coach_mode = 'COOLDOWN' AND d.days_since_last_bid_change < 1)
        OR (d.coach_mode = 'BLITZ' AND d.current_phase IN ('BOOST', 'PEAK') AND d.days_since_last_bid_change < 3)
      )
      THEN 'REDUCE_BID'

    -- ═══ FREQUENCY GATE: prevent too-frequent bid changes ═══
    -- GUARDIAN: weekly (7d), COOLDOWN: daily (1d), BLITZ BOOST: every 3d, BLITZ PEAK: every 3d
    -- BOOST ramps fast (3d) so bids are already high when PEAK starts.
    WHEN d.target_roas >= d.th_scale_up_roas AND d.eff_orders_for_bid >= 2
      AND NOT (
        (d.coach_mode = 'GUARDIAN' AND d.days_since_last_bid_change < 7 AND NOT (d.days_since_last_bid_change >= 3 AND COALESCE(d.ads_net_roas_3d, 0) >= 2.0))
        OR (d.coach_mode = 'COOLDOWN' AND d.days_since_last_bid_change < 1)
        OR (d.coach_mode = 'BLITZ' AND d.current_phase = 'BOOST' AND d.days_since_last_bid_change < 3)
        OR (d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' AND d.days_since_last_bid_change < 3)
      )
      THEN 'INCREASE_BID'
    WHEN d.target_roas >= d.th_scale_up_roas AND d.eff_orders_for_bid >= 2 THEN 'MONITOR_TARGET'
    -- Profitable tier: ROAS ≥ profitable_threshold → increase bid
    WHEN d.target_roas >= d.th_profitable_roas AND d.eff_orders_for_bid >= 2
      AND NOT (
        (d.coach_mode = 'GUARDIAN' AND d.days_since_last_bid_change < 7 AND NOT (d.days_since_last_bid_change >= 3 AND COALESCE(d.ads_net_roas_3d, 0) >= 2.0))
        OR (d.coach_mode = 'COOLDOWN' AND d.days_since_last_bid_change < 1)
        OR (d.coach_mode = 'BLITZ' AND d.current_phase = 'BOOST' AND d.days_since_last_bid_change < 3)
        OR (d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' AND d.days_since_last_bid_change < 3)
      )
      THEN 'INCREASE_BID'
    WHEN d.target_roas >= d.th_profitable_roas AND d.eff_orders_for_bid >= 2 THEN 'MONITOR_TARGET'
    -- Reduce tier: ROAS < reduce_threshold → reduce (with lag safety check)
    -- Safety: if the lag window (last 3 days, excluded by 4-day lag) shows strong ROAS, defer to MONITOR
    WHEN d.target_roas < d.th_reduce_bid_roas AND d.target_orders_8w > 0
      AND COALESCE(d.target_lag_net_roas, 0) > 1.3 THEN 'MONITOR_TARGET'
    WHEN d.target_roas < d.th_reduce_bid_roas AND d.target_orders_8w > 0
      AND NOT (
        (d.coach_mode = 'GUARDIAN' AND d.days_since_last_bid_change < 7)
        OR (d.coach_mode = 'COOLDOWN' AND d.days_since_last_bid_change < 1)
        OR (d.coach_mode = 'BLITZ' AND d.current_phase = 'BOOST' AND d.days_since_last_bid_change < 3)
        OR (d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' AND d.days_since_last_bid_change < 3)
      )
      THEN 'REDUCE_BID'
    WHEN d.target_roas < d.th_reduce_bid_roas AND d.target_orders_8w > 0 THEN 'MONITOR_TARGET'
    -- Dead zone: between reduce and profitable thresholds → KEEP_TARGET (no action)
    WHEN d.target_orders_8w > 0 THEN 'KEEP_TARGET'
    ELSE 'MONITOR_TARGET'
  END as target_action,

  -- ─── Target Decision Trace (mirrors target_action logic step-by-step) ───
  CASE
    WHEN d.recommendation_type = 'OPPORTUNITY' THEN NULL

    -- ❄️ Cooldown-specific trace: pp Net ROAS tiers + pre-peak comparison
    WHEN d.coach_mode = 'COOLDOWN' THEN CONCAT('[',
      '{"id":"cd_mode","label":"Cooldown","rule":"active","pass":true,"value":"❄️ ',
        COALESCE(d.active_occasion, '?'), '"},',
      '{"id":"cd_pp_roas","label":"PP Ads ROAS","rule":"≥ 0.8 monitor","pass":',
        IF(COALESCE(SAFE_DIVIDE(pp.pp_sales, NULLIF(pp.pp_spend, 0)), 0) >= 0.8, 'true', 'false'),
        ',"value":"', CAST(ROUND(COALESCE(SAFE_DIVIDE(pp.pp_sales, NULLIF(pp.pp_spend, 0)), 0), 2) AS STRING),
        ' (', CAST(COALESCE(pp.pp_days, 0) AS STRING), 'd)"},',
      '{"id":"cd_pp_roas2","label":"PP Marginal?","rule":"≥ 0.6 reduce","pass":',
        IF(COALESCE(SAFE_DIVIDE(pp.pp_sales, NULLIF(pp.pp_spend, 0)), 0) >= 0.6, 'true', 'false'),
        ',"value":"', CAST(ROUND(COALESCE(SAFE_DIVIDE(pp.pp_sales, NULLIF(pp.pp_spend, 0)), 0), 2) AS STRING), '"},',
      '{"id":"cd_bid","label":"Bid","rule":"pre=$', CAST(ROUND(COALESCE(d.pre_peak_bid, 0), 2) AS STRING),
        '","pass":', IF(d.current_bid <= COALESCE(d.pre_peak_bid, d.current_bid), 'true', 'false'),
        ',"value":"$', CAST(ROUND(COALESCE(d.current_bid, 0), 2) AS STRING), '"},',
      '{"id":"cd_budget","label":"Budget","rule":"pre=$', CAST(ROUND(COALESCE(d.pre_peak_budget, 0), 0) AS STRING),
        '","pass":', IF(COALESCE(d.current_budget, 0) <= COALESCE(d.pre_peak_budget, d.current_budget), 'true', 'false'),
        ',"value":"$', CAST(ROUND(COALESCE(d.current_budget, 0), 0) AS STRING), '"}',
    ']')

    -- ⏸️ Paused target trace
    WHEN COALESCE(d.target_keyword_status, 'ENABLED') != 'ENABLED' THEN CONCAT(
      '[{"id":"tgt_status","label":"Target Status","rule":"ENABLED","pass":false,"value":"',
        COALESCE(d.target_keyword_status, 'UNKNOWN'), '"}]')

    -- Standard Guardian/Blitz trace — shows actual source field, not computed target_roas
    -- Every pill has rule = "condition → pass_consequence | fail_consequence"
    ELSE CONCAT('[',
      -- 1. Clicks gate
      '{"id":"tgt_clicks","label":"Target Clicks 8w","sql":"target_clicks_8w","rule":"≥ ',
        CAST(CAST(d.th_min_clicks AS INT64) AS STRING),
        ' → evaluate | < ', CAST(CAST(d.th_min_clicks AS INT64) AS STRING), ' → MONITOR',
        '","pass":', IF(COALESCE(d.target_clicks_8w, 0) >= d.th_min_clicks, 'true', 'false'),
        ',"value":"', CAST(COALESCE(d.target_clicks_8w, 0) AS STRING), '"},',
      -- 2. Orders gate
      '{"id":"tgt_orders","label":"Target Orders 8w","sql":"target_orders_8w","rule":"≥ 2 → bid eligible | = 0 → STOP_TARGET","pass":',
        IF(COALESCE(d.target_orders_8w, 0) >= 2, 'true', 'false'),
        ',"value":"', CAST(COALESCE(d.target_orders_8w, 0) AS STRING), '"},',
      -- 3. ROAS evaluation (mode-aware, simple windows, no fallback)
      '{"id":"tgt_roas","label":"',
        CASE
          WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN') THEN 'Target ROAS 7d OS'
          WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN 'Ads ROAS 3d'
          WHEN d.coach_mode = 'BLITZ' THEN 'Target ROAS 7d'
          ELSE 'Target ROAS 7d'
        END,
        '","sql":"',
        CASE
          WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN') THEN 'target_net_roas_1w_os'
          WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN 'ads_net_roas_3d'
          WHEN d.coach_mode = 'BLITZ' THEN 'target_net_roas_1w'
          ELSE 'target_net_roas_1w'
        END,
        '","rule":"≥ ', CAST(ROUND(d.th_scale_up_roas, 2) AS STRING), ' → increase bid',
        ' | ≥ ', CAST(ROUND(d.th_profitable_roas, 2) AS STRING), ' → increase bid',
        ' | < ', CAST(ROUND(d.th_reduce_bid_roas, 2) AS STRING), ' → reduce bid',
        '","pass":', IF(COALESCE(d.target_roas, 0) >= d.th_profitable_roas, 'true', 'false'),
        ',"value":"', CAST(ROUND(COALESCE(d.target_roas, 0), 2) AS STRING), '"},',
      -- 4. Spend context
      '{"id":"tgt_spend","label":"Target Spend 8w","sql":"target_spend_8w","rule":"context (informational)","pass":true,"value":"$',
        CAST(ROUND(COALESCE(d.target_spend_8w, 0), 2) AS STRING), '"}',
      -- 5. Lag ROAS safety (only when ROAS below reduce threshold)
      CASE WHEN d.target_roas < d.th_reduce_bid_roas AND d.target_orders_8w > 0
        THEN CONCAT(
          ',{"id":"tgt_lag","label":"Lag ROAS (3d)","sql":"target_lag_net_roas","rule":"≤ 1.3 → REDUCE_BID | > 1.3 → defer reduction","pass":',
          IF(COALESCE(d.target_lag_net_roas, 0) > 1.3, 'false', 'true'),
          ',"value":"', CAST(ROUND(COALESCE(d.target_lag_net_roas, 0), 2) AS STRING), '"}')
        ELSE ''
      END,
      -- 6. Frequency gate
      CONCAT(
        ',{"id":"tgt_freq","label":"Bid Freq","sql":"days_since_last_bid_change","rule":"≥ ',
        CASE
          WHEN d.coach_mode = 'GUARDIAN' THEN '7'
          WHEN d.coach_mode = 'COOLDOWN' THEN '1'
          WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'BOOST' THEN '7'
          WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN '3'
          ELSE '1'
        END,
        'd → allow change | < ',
        CASE
          WHEN d.coach_mode = 'GUARDIAN' THEN '7'
          WHEN d.coach_mode = 'COOLDOWN' THEN '1'
          WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'BOOST' THEN '7'
          WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN '3'
          ELSE '1'
        END,
        'd → defer',
        '","pass":',
        CASE
          WHEN d.coach_mode = 'GUARDIAN' AND d.days_since_last_bid_change < 7 THEN 'false'
          WHEN d.coach_mode = 'COOLDOWN' AND d.days_since_last_bid_change < 1 THEN 'false'
          WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'BOOST' AND d.days_since_last_bid_change < 3 THEN 'false'
          WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' AND d.days_since_last_bid_change < 3 THEN 'false'
          ELSE 'true'
        END,
        ',"value":"', CAST(d.days_since_last_bid_change AS STRING), 'd"}'),
      -- 7. Warmup guard pill (campaign age < 14 days)
      CASE WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(d.campaign_creation_date), DAY) < 14
        THEN CONCAT(
          ',{"id":"tgt_warmup","label":"Campaign Age","sql":"campaign_creation_date","rule":"≥ 14d → allow bid increase | < 14d → WARMUP_MONITOR","pass":false',
          ',"value":"', CAST(DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(d.campaign_creation_date), DAY) AS STRING),
          'd (', CAST(14 - DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(d.campaign_creation_date), DAY) AS STRING), 'd left)"}')
        ELSE CONCAT(
          ',{"id":"tgt_warmup","label":"Campaign Age","sql":"campaign_creation_date","rule":"≥ 14d → allow bid increase","pass":true',
          ',"value":"', CAST(COALESCE(DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(d.campaign_creation_date), DAY), 999) AS STRING), 'd"}')
      END,
      -- 7. Summary narrative (generated in SQL, frontend only renders)
      ',{"id":"summary","label":"Summary","pass":true,"value":"',
      CASE
        -- Defense: mirror the DEFENSE BID-RAISE branches in target_action (~line 592) so the
        -- summary matches the action — raise to dominate when not yet dominant / below the ceiling, else monitor.
        WHEN d.strategy_id = 'BRAND_DEFENSE'
          AND COALESCE(d.current_bid, 0) < d.th_bid_cap
          AND COALESCE(d.impression_share_pct, 0) < d.th_defense_dominate_is
          THEN CONCAT('🛡 Defense — impression share ',
               CAST(ROUND(COALESCE(d.impression_share_pct, 0), 0) AS STRING), '% < ',
               CAST(CAST(d.th_defense_dominate_is AS INT64) AS STRING),
               '% → bid up to dominate the auction.')
        WHEN d.strategy_id = 'PRODUCT_DEFENSE'
          AND COALESCE(d.current_bid, 0) < d.th_bid_cap
          THEN '🛡 Defense — bid up toward the ceiling to occupy our own detail pages.'
        WHEN d.strategy_id IN ('PRODUCT_DEFENSE', 'BRAND_DEFENSE')
          THEN '🔒 Defense — already dominating (or at bid ceiling), monitoring only.'
        -- Insufficient clicks
        WHEN COALESCE(d.target_clicks_8w, 0) < d.th_min_clicks
          THEN CONCAT('📊 Only ', CAST(COALESCE(d.target_clicks_8w, 0) AS STRING),
               ' clicks — need ', CAST(CAST(d.th_min_clicks AS INT64) AS STRING), ' to evaluate.')
        -- Zero orders with enough clicks → STOP
        WHEN d.target_orders_8w = 0 AND COALESCE(d.target_clicks_8w, 0) >= d.th_min_clicks
          THEN CONCAT('🛑 ', CAST(COALESCE(d.target_clicks_8w, 0) AS STRING), ' clicks, 0 orders → stop target.')
        -- ROAS below reduce threshold + lag safety saved it
        WHEN d.target_roas < d.th_reduce_bid_roas AND d.target_orders_8w > 0
          AND COALESCE(d.target_lag_net_roas, 0) > 1.3
          THEN CONCAT('⚠️ ROAS ', CAST(ROUND(COALESCE(d.target_roas, 0), 2) AS STRING),
               ' below ', CAST(ROUND(d.th_reduce_bid_roas, 2) AS STRING),
               ' threshold → would reduce bid, but recent 3d ROAS (',
               CAST(ROUND(COALESCE(d.target_lag_net_roas, 0), 2) AS STRING),
               ') shows improvement. Deferring.')
        -- ROAS below reduce threshold + frequency gate blocked
        WHEN d.target_roas < d.th_reduce_bid_roas AND d.target_orders_8w > 0
          AND ((d.coach_mode = 'GUARDIAN' AND d.days_since_last_bid_change < 7)
            OR (d.coach_mode = 'COOLDOWN' AND d.days_since_last_bid_change < 1)
            OR (d.coach_mode = 'BLITZ' AND d.current_phase = 'BOOST' AND d.days_since_last_bid_change < 3)
            OR (d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' AND d.days_since_last_bid_change < 3))
          THEN CONCAT('⏳ ROAS ', CAST(ROUND(COALESCE(d.target_roas, 0), 2) AS STRING),
               ' qualifies for bid decrease, but last change was ',
               CAST(d.days_since_last_bid_change AS STRING), 'd ago. Waiting for frequency window.')
        -- ROAS below reduce threshold → REDUCE_BID
        WHEN d.target_roas < d.th_reduce_bid_roas AND d.target_orders_8w > 0
          THEN CONCAT('📉 ROAS ', CAST(ROUND(COALESCE(d.target_roas, 0), 2) AS STRING),
               ' below ', CAST(ROUND(d.th_reduce_bid_roas, 2) AS STRING),
               ' → reduce bid.')
        -- Warmup guard: new campaign in learning period
        WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(d.campaign_creation_date), DAY) < 14
          AND d.target_roas >= d.th_profitable_roas AND d.eff_orders_for_bid >= 2
          THEN CONCAT('🌱 New campaign (',
               CAST(DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(d.campaign_creation_date), DAY) AS STRING),
               'd old). Algorithm needs 14 days to find optimal placements. ROAS ',
               CAST(ROUND(COALESCE(d.target_roas, 0), 2) AS STRING),
               ' looks promising — hold bids for ',
               CAST(14 - DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(d.campaign_creation_date), DAY) AS STRING),
               ' more days.')
        -- Scale-up tier, frequency gate blocked
        WHEN d.target_roas >= d.th_scale_up_roas AND d.eff_orders_for_bid >= 2
          AND ((d.coach_mode = 'GUARDIAN' AND d.days_since_last_bid_change < 7)
            OR (d.coach_mode = 'COOLDOWN' AND d.days_since_last_bid_change < 1)
            OR (d.coach_mode = 'BLITZ' AND d.current_phase = 'BOOST' AND d.days_since_last_bid_change < 3)
            OR (d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' AND d.days_since_last_bid_change < 3))
          THEN CONCAT('⏳ Strong ROAS ', CAST(ROUND(COALESCE(d.target_roas, 0), 2) AS STRING),
               ' qualifies for bid increase, but last change was ',
               CAST(d.days_since_last_bid_change AS STRING), 'd ago. Waiting.')
        -- Scale-up tier → INCREASE_BID
        WHEN d.target_roas >= d.th_scale_up_roas AND d.eff_orders_for_bid >= 2
          THEN CONCAT('🚀 Strong ROAS ', CAST(ROUND(COALESCE(d.target_roas, 0), 2) AS STRING),
               ' with ', CAST(d.target_orders_8w AS STRING), ' orders → increase bid.')
        -- Profitable tier, frequency gate blocked
        WHEN d.target_roas >= d.th_profitable_roas AND d.eff_orders_for_bid >= 2
          AND ((d.coach_mode = 'GUARDIAN' AND d.days_since_last_bid_change < 7)
            OR (d.coach_mode = 'COOLDOWN' AND d.days_since_last_bid_change < 1)
            OR (d.coach_mode = 'BLITZ' AND d.current_phase = 'BOOST' AND d.days_since_last_bid_change < 3)
            OR (d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' AND d.days_since_last_bid_change < 3))
          THEN CONCAT('⏳ Profitable ROAS ', CAST(ROUND(COALESCE(d.target_roas, 0), 2) AS STRING),
               ' qualifies for bid increase, but last change was ',
               CAST(d.days_since_last_bid_change AS STRING), 'd ago. Waiting.')
        -- Profitable tier → INCREASE_BID
        WHEN d.target_roas >= d.th_profitable_roas AND d.eff_orders_for_bid >= 2
          THEN CONCAT('📈 Profitable ROAS ', CAST(ROUND(COALESCE(d.target_roas, 0), 2) AS STRING),
               ' with ', CAST(d.target_orders_8w AS STRING), ' orders → increase bid.')
        -- Dead zone (between reduce and profitable)
        WHEN d.target_orders_8w > 0
          THEN CONCAT('✅ ROAS ', CAST(ROUND(COALESCE(d.target_roas, 0), 2) AS STRING),
               ' is in neutral zone. Keep current bid.')
        ELSE '👀 Monitoring target performance.'
      END,
      '"}',
    ']')
  END as target_decision_trace,

  -- ─── Recommendation Object (what the primary action applies to) ───
  -- Rule: if the target_action involves a bid or target-level change, it's TARGET.
  -- You can never change a search term's bid — only a target/keyword's bid.
  CASE
    WHEN d.recommendation_type = 'OPPORTUNITY' THEN 'TERM'
    -- ❄️ Cooldown bid actions are ALWAYS target-level
    WHEN d.coach_mode = 'COOLDOWN' AND d.current_bid IS NOT NULL THEN 'TARGET'
    -- STOP/INCREASE/REDUCE/KEEP on targets are target-level
    WHEN d.target_orders_8w = 0 AND d.target_clicks_8w >= d.th_min_clicks
      AND d.target_clicks_recent_5d > 0 THEN 'TARGET'
    WHEN d.eff_orders_for_bid >= 2 THEN 'TARGET'
    WHEN d.target_orders_8w > 0 THEN 'TARGET'
    ELSE 'TERM'
  END as recommendation_object,

  -- ─── Recommended Bid (graduated based on target_net_roas_8w) ───
  -- Uses current_bid from bulksheet as base, applies ROAS-graduated multiplier,
  -- caps increases at margin × 0.5, floors decreases at $0.10
  ROUND(LEAST(CASE
    WHEN d.recommendation_type = 'OPPORTUNITY' THEN NULL
    WHEN d.current_bid IS NULL THEN NULL
    -- 🚫 PAUSED: suppress bid recommendations for non-enabled campaigns
    WHEN UPPER(d.campaign_state) != 'ENABLED' AND d.campaign_state IS NOT NULL THEN NULL

    -- 🛡 DEFENSE bid: step toward the ceiling (mirrors the defense raise in target_action)
    WHEN d.strategy_id = 'BRAND_DEFENSE'
      AND COALESCE(d.current_bid, 0) < d.th_bid_cap
      AND COALESCE(d.impression_share_pct, 0) < d.th_defense_dominate_is
      THEN LEAST(GREATEST(d.current_bid * 1.5, d.current_bid + 0.20), d.th_bid_cap)
    WHEN d.strategy_id = 'PRODUCT_DEFENSE'
      AND COALESCE(d.current_bid, 0) < d.th_bid_cap
      THEN LEAST(GREATEST(d.current_bid * 1.5, d.current_bid + 0.20), d.th_bid_cap)
    WHEN d.strategy_id IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE') THEN NULL

    -- ❄️ COOLDOWN v2: 3-tier bid recommendations (pp Net ROAS thresholds)
    -- COOLDOWN_MONITOR: pp Ads ROAS ≥ 0.8 → no bid change
    WHEN d.coach_mode = 'COOLDOWN'
      AND COALESCE(pp.pp_spend, 0) > 0
      AND SAFE_DIVIDE(pp.pp_sales, NULLIF(pp.pp_spend, 0)) >= 0.8
      THEN NULL

    -- REDUCE_TO_BASELINE: pp Ads ROAS ≥ 0.6 → gradual -10% per cycle
    WHEN d.coach_mode = 'COOLDOWN'
      AND COALESCE(pp.pp_spend, 0) > 0
      AND SAFE_DIVIDE(pp.pp_sales, NULLIF(pp.pp_spend, 0)) >= 0.6
      THEN GREATEST(d.current_bid * 0.90, COALESCE(d.pre_peak_bid, 0.10), 0.10)

    -- RESTORE_PRE_PEAK: pp Ads ROAS < 0.6 → snap to pre-peak bid (or -30% if no snapshot)
    WHEN d.coach_mode = 'COOLDOWN'
      AND d.pre_peak_bid IS NOT NULL
      THEN GREATEST(d.pre_peak_bid, 0.10)
    WHEN d.coach_mode = 'COOLDOWN'
      THEN GREATEST(d.current_bid * 0.70, 0.10)
    -- Money bleeder (fit): aggressive -BLEEDER_REDUCE_PCT cut. The CPC floor only applies when the
    -- term's CPC is BELOW the current bid (its purpose: keep the bid competitive enough to win some
    -- clicks). When the bid is already at/below CPC (stale/SB data), the floor is moot → apply the
    -- full cut down to the $0.10 minimum. Always non-increasing.
    WHEN d.strategy_id NOT IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE')
      AND COALESCE(d.ads_orders_4w, 0) = 0
      AND COALESCE(d.ads_spend_4w, 0) >= 5
      AND COALESCE(d.ads_clicks_4w, 0) >= d.th_bleeder_min_clicks
      AND COALESCE(d.research_rank, 0) >= d.th_bleeder_fit_rank
      THEN GREATEST(
        d.current_bid * (1 - d.th_bleeder_reduce_pct),
        IF(d.ads_cpc_8w IS NOT NULL AND d.ads_cpc_8w > 0 AND d.ads_cpc_8w < d.current_bid, d.ads_cpc_8w, 0.10)
      )
    -- Target has 0 orders + enough clicks + still active → reduce 30%
    WHEN d.target_orders_8w = 0 AND d.target_clicks_8w >= d.th_min_clicks
      AND d.target_clicks_recent_5d > 0
      THEN GREATEST(d.current_bid * 0.70, 0.10)
    -- SEASONAL GUARD: no bid increase for seasonal targets in GUARDIAN mode
    WHEN d.coach_mode = 'GUARDIAN'
      AND d.target_roas >= d.th_profitable_roas AND d.eff_orders_for_bid >= 2
      AND d.is_holiday_seasonal = TRUE
      THEN NULL
    -- WARMUP GUARD: no bid increase for new campaigns (< 14 days)
    WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(d.campaign_creation_date), DAY) < 14
      AND d.target_roas >= d.th_profitable_roas AND d.eff_orders_for_bid >= 2
      THEN NULL
    -- ═══ MODE-AWARE INCREASE: BLITZ aggressive ↑ · GUARDIAN gentle ↑ · COOLDOWN minimal ↑ ═══
    WHEN d.target_roas >= 5.0 AND d.eff_orders_for_bid >= 2
      THEN LEAST(d.current_bid * CASE d.coach_mode WHEN 'BLITZ' THEN 1.50 WHEN 'GUARDIAN' THEN 1.10 WHEN 'COOLDOWN' THEN 1.05 ELSE 1.40 END, GREATEST(d.margin_per_unit * 0.5, 0.30))
    WHEN d.target_roas >= 3.0 AND d.eff_orders_for_bid >= 2
      THEN LEAST(d.current_bid * CASE d.coach_mode WHEN 'BLITZ' THEN 1.40 WHEN 'GUARDIAN' THEN 1.08 WHEN 'COOLDOWN' THEN 1.05 ELSE 1.30 END, GREATEST(d.margin_per_unit * 0.5, 0.30))
    WHEN d.target_roas >= 2.0 AND d.eff_orders_for_bid >= 2
      THEN LEAST(d.current_bid * CASE d.coach_mode WHEN 'BLITZ' THEN 1.30 WHEN 'GUARDIAN' THEN 1.05 WHEN 'COOLDOWN' THEN 1.03 ELSE 1.20 END, GREATEST(d.margin_per_unit * 0.5, 0.30))
    WHEN d.target_roas >= 1.5 AND d.eff_orders_for_bid >= 2
      THEN LEAST(d.current_bid * CASE d.coach_mode WHEN 'BLITZ' THEN 1.20 WHEN 'GUARDIAN' THEN 1.05 WHEN 'COOLDOWN' THEN 1.03 ELSE 1.10 END, GREATEST(d.margin_per_unit * 0.5, 0.30))
    WHEN d.target_roas >= d.th_profitable_roas AND d.eff_orders_for_bid >= 2
      THEN LEAST(d.current_bid * CASE d.coach_mode WHEN 'BLITZ' THEN 1.10 WHEN 'GUARDIAN' THEN 1.03 WHEN 'COOLDOWN' THEN 1.03 ELSE 1.05 END, GREATEST(d.margin_per_unit * 0.5, 0.30))
    -- ═══ MODE-AWARE REDUCE: COOLDOWN aggressive ↓ · GUARDIAN gentle ↓ · BLITZ easy ↓ (protect peak) ═══
    WHEN d.target_roas < 0.3 AND d.target_orders_8w > 0
      THEN GREATEST(d.current_bid * CASE d.coach_mode WHEN 'COOLDOWN' THEN 0.50 WHEN 'GUARDIAN' THEN 0.85 WHEN 'BLITZ' THEN 0.80 ELSE 0.65 END, 0.10)
    WHEN d.target_roas < 0.5 AND d.target_orders_8w > 0
      THEN GREATEST(d.current_bid * CASE d.coach_mode WHEN 'COOLDOWN' THEN 0.60 WHEN 'GUARDIAN' THEN 0.90 WHEN 'BLITZ' THEN 0.85 ELSE 0.75 END, 0.10)
    WHEN d.target_roas < d.th_reduce_bid_roas AND d.target_orders_8w > 0
      THEN GREATEST(d.current_bid * CASE d.coach_mode WHEN 'COOLDOWN' THEN 0.75 WHEN 'GUARDIAN' THEN 0.93 WHEN 'BLITZ' THEN 0.90 ELSE 0.85 END, 0.10)
    -- Sufficient data but no bid action needed
    ELSE NULL
  END, d.th_bid_cap), 2) as recommended_bid,

  -- ─── Bid Change % ───
  ROUND(CASE
    WHEN d.recommendation_type = 'OPPORTUNITY' THEN NULL
    WHEN d.current_bid IS NULL OR d.current_bid = 0 THEN NULL
    -- 🚫 PAUSED: no bid change for non-enabled campaigns
    WHEN UPPER(d.campaign_state) != 'ENABLED' AND d.campaign_state IS NOT NULL THEN NULL
    -- 🛡 DEFENSE: % toward the ceiling (mirrors the defense raise in recommended_bid)
    WHEN d.strategy_id = 'BRAND_DEFENSE'
      AND COALESCE(d.current_bid, 0) < d.th_bid_cap
      AND COALESCE(d.impression_share_pct, 0) < d.th_defense_dominate_is
      THEN (LEAST(GREATEST(d.current_bid * 1.5, d.current_bid + 0.20), d.th_bid_cap) / NULLIF(d.current_bid, 0) - 1) * 100
    WHEN d.strategy_id = 'PRODUCT_DEFENSE'
      AND COALESCE(d.current_bid, 0) < d.th_bid_cap
      THEN (LEAST(GREATEST(d.current_bid * 1.5, d.current_bid + 0.20), d.th_bid_cap) / NULLIF(d.current_bid, 0) - 1) * 100
    WHEN d.strategy_id IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE') THEN NULL
    -- ❄️ COOLDOWN: bid change % by pp Ads ROAS tier
    WHEN d.coach_mode = 'COOLDOWN'
      AND COALESCE(pp.pp_spend, 0) > 0
      AND SAFE_DIVIDE(pp.pp_sales, NULLIF(pp.pp_spend, 0)) >= 0.8 THEN 0
    WHEN d.coach_mode = 'COOLDOWN'
      AND COALESCE(pp.pp_spend, 0) > 0
      AND SAFE_DIVIDE(pp.pp_sales, NULLIF(pp.pp_spend, 0)) >= 0.6 THEN -10
    WHEN d.coach_mode = 'COOLDOWN' THEN -30
    WHEN d.target_orders_8w = 0 AND d.target_clicks_8w >= d.th_min_clicks
      AND d.target_clicks_recent_5d > 0 THEN -30
    -- SEASONAL GUARD: 0% change for seasonal targets in GUARDIAN
    WHEN d.coach_mode = 'GUARDIAN'
      AND d.target_roas >= d.th_profitable_roas AND d.eff_orders_for_bid >= 2
      AND d.is_holiday_seasonal = TRUE
      THEN 0
    -- WARMUP GUARD: 0% change for new campaigns (< 14 days)
    WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(d.campaign_creation_date), DAY) < 14
      AND d.target_roas >= d.th_profitable_roas AND d.eff_orders_for_bid >= 2
      THEN 0
    -- Mode-aware % (mirrors recommended_bid; COOLDOWN reduce handled by the block above)
    WHEN d.target_roas >= 5.0 AND d.eff_orders_for_bid >= 2 THEN CASE d.coach_mode WHEN 'BLITZ' THEN 50 WHEN 'GUARDIAN' THEN 10 WHEN 'COOLDOWN' THEN 5 ELSE 40 END
    WHEN d.target_roas >= 3.0 AND d.eff_orders_for_bid >= 2 THEN CASE d.coach_mode WHEN 'BLITZ' THEN 40 WHEN 'GUARDIAN' THEN 8 WHEN 'COOLDOWN' THEN 5 ELSE 30 END
    WHEN d.target_roas >= 2.0 AND d.eff_orders_for_bid >= 2 THEN CASE d.coach_mode WHEN 'BLITZ' THEN 30 WHEN 'GUARDIAN' THEN 5 WHEN 'COOLDOWN' THEN 3 ELSE 20 END
    WHEN d.target_roas >= 1.5 AND d.eff_orders_for_bid >= 2 THEN CASE d.coach_mode WHEN 'BLITZ' THEN 20 WHEN 'GUARDIAN' THEN 5 WHEN 'COOLDOWN' THEN 3 ELSE 10 END
    WHEN d.target_roas >= d.th_profitable_roas AND d.eff_orders_for_bid >= 2 THEN CASE d.coach_mode WHEN 'BLITZ' THEN 10 WHEN 'GUARDIAN' THEN 3 WHEN 'COOLDOWN' THEN 3 ELSE 5 END
    WHEN d.target_roas < 0.3 AND d.target_orders_8w > 0 THEN CASE d.coach_mode WHEN 'COOLDOWN' THEN -50 WHEN 'GUARDIAN' THEN -15 WHEN 'BLITZ' THEN -20 ELSE -35 END
    WHEN d.target_roas < 0.5 AND d.target_orders_8w > 0 THEN CASE d.coach_mode WHEN 'COOLDOWN' THEN -40 WHEN 'GUARDIAN' THEN -10 WHEN 'BLITZ' THEN -15 ELSE -25 END
    WHEN d.target_roas < d.th_reduce_bid_roas AND d.target_orders_8w > 0 THEN CASE d.coach_mode WHEN 'COOLDOWN' THEN -25 WHEN 'GUARDIAN' THEN -7 WHEN 'BLITZ' THEN -10 ELSE -15 END
    ELSE NULL
  END, 0) as bid_change_pct,

  -- ─── Priority Score ───
  ROUND(CASE
    WHEN d.recommendation_type = 'OPPORTUNITY'
      THEN COALESCE(d.sqp_orders_8w, 0) * COALESCE(d.margin_per_unit, 0)
           + COALESCE(d.market_weekly_orders, 0) * 0.5
           + COALESCE(d.sqp_orders_8w, 0) * 10.0

    -- Wasted spend: higher spend = higher priority to stop
    WHEN d.ads_orders_8w = 0 AND d.sqp_organic_units_8w = 0
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0
      THEN d.ads_spend_8w * 10.0

    -- (NEGATE_TERM removed — no cross-campaign consolidation)

    -- Promote to exact
    WHEN d.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
      AND d.ads_orders_8w >= CAST(d.th_promote_min_orders AS INT64)
      AND NOT d.already_in_exact_boost AND d.sqp_amazon_search_volume_8w >= d.th_promote_min_sqp_vol
      THEN d.ads_orders_8w * 50.0

    -- Scale up (EXACT_BOOST only)
    WHEN d.strategy_id = 'EXACT_BOOST' AND d.ads_net_roas_8w >= d.th_scale_up_roas
      AND d.ads_orders_8w >= 2
      THEN d.ads_orders_8w * 30.0

    -- Increase bid (HUNTER/LOW_COST strong targets)
    WHEN d.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
      AND d.ads_orders_8w >= 2 AND d.ads_net_roas_8w >= d.th_scale_up_roas
      THEN d.ads_orders_8w * 20.0

    -- Heavy loss (mode-aware ROAS)
    WHEN CASE
           WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN') THEN d.ads_net_roas_1w_os
           WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN d.ads_net_roas_1w
           WHEN d.coach_mode = 'BLITZ' THEN d.ads_net_roas_14d
           ELSE d.ads_net_roas_1w
         END < d.th_negate_roas AND d.ads_clicks_8w >= d.th_min_clicks
      THEN d.ads_spend_8w * 5.0

    -- Reduce bid: loss amount (mode-aware ROAS)
    WHEN CASE
           WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN') THEN d.ads_net_roas_1w_os
           WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN d.ads_net_roas_1w
           WHEN d.coach_mode = 'BLITZ' THEN d.ads_net_roas_14d
           ELSE d.ads_net_roas_1w
         END < d.th_reduce_bid_roas AND d.ads_orders_8w > 0
      THEN d.ads_spend_8w * 1.0

    ELSE 0
  END, 0) as priority_score,

  -- ─── Confidence ───
  CASE
    WHEN d.recommendation_type = 'OPPORTUNITY' THEN
      CASE
        WHEN d.sqp_orders_8w >= 5 THEN 'HIGH'
        WHEN d.sqp_orders_8w >= 2 THEN 'MEDIUM'
        ELSE 'LOW'
      END
    WHEN d.ads_days_8w >= CAST(d.th_conf_days_high AS INT64) AND d.ads_clicks_8w >= CAST(d.th_conf_clicks_high AS INT64) THEN 'HIGH'
    WHEN d.ads_days_8w >= CAST(d.th_conf_days_medium AS INT64) AND d.ads_clicks_8w >= CAST(d.th_conf_clicks_medium AS INT64) THEN 'MEDIUM'
    ELSE 'LOW'
  END as confidence,

  -- ─── Decision Trace ───
  CASE
    WHEN d.recommendation_type = 'OPPORTUNITY'
      THEN CONCAT('type=OPPORTUNITY | sqp_orders=', CAST(d.sqp_orders_8w AS STRING), ' => START')
    ELSE CONCAT(
      'strategy=', COALESCE(d.strategy_id, '?'),
      ' | clicks_8w=', CAST(d.ads_clicks_8w AS STRING),
        CASE WHEN d.ads_clicks_8w < d.th_min_clicks
             THEN CONCAT(' [<', CAST(CAST(d.th_min_clicks AS INT64) AS STRING), ' => MONITOR]')
             ELSE CONCAT(' [>=', CAST(CAST(d.th_min_clicks AS INT64) AS STRING), ' PASS]') END,
      CASE WHEN d.ads_clicks_8w >= d.th_min_clicks THEN
        CONCAT(' | orders_8w=', CAST(d.ads_orders_8w AS STRING),
          CASE
            WHEN d.ads_orders_8w = 0 AND d.sqp_organic_units_8w = 0 AND d.ads_clicks_recent_5d > 0
              THEN ' sqp_organic=0 bleeding=YES [WASTED]'
            WHEN d.ads_orders_8w > 0 THEN ''
            ELSE ' [NO_ORDERS_NO_ACTION]'
          END)
      ELSE '' END,
      CASE WHEN d.ads_orders_8w > 0 THEN
        CONCAT(' | roas=', CAST(COALESCE(d.ads_net_roas_8w, 0) AS STRING),
          ' campaign_type=', COALESCE(d.campaign_type, '?'),
          CASE
            WHEN d.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
              AND d.ads_orders_8w >= CAST(d.th_promote_min_orders AS INT64) AND NOT d.already_in_exact_boost
              AND d.sqp_amazon_search_volume_8w >= d.th_promote_min_sqp_vol
              THEN CONCAT(' sqp_vol=', CAST(ROUND(d.sqp_amazon_search_volume_8w, 0) AS STRING), '>=', CAST(CAST(d.th_promote_min_sqp_vol AS INT64) AS STRING), ' [PROMOTE]')
            WHEN d.strategy_id = 'EXACT_BOOST' AND d.ads_net_roas_8w >= d.th_scale_up_roas
              THEN ' [SCALE_UP]'
            WHEN d.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
              AND d.ads_orders_8w >= 2 AND d.ads_net_roas_8w >= d.th_scale_up_roas
              THEN ' [INCREASE_BID]'
            WHEN CASE
           WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN') THEN d.ads_net_roas_1w_os
           WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN d.ads_net_roas_1w
           WHEN d.coach_mode = 'BLITZ' THEN d.ads_net_roas_14d
           ELSE d.ads_net_roas_1w
         END >= d.th_profitable_roas
              THEN ' [MONITOR]'
            WHEN CASE
           WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN') THEN d.ads_net_roas_1w_os
           WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN d.ads_net_roas_1w
           WHEN d.coach_mode = 'BLITZ' THEN d.ads_net_roas_14d
           ELSE d.ads_net_roas_1w
         END < d.th_negate_roas AND d.ads_clicks_recent_5d > 0
              THEN ' [HEAVY_LOSS => STOP]'
            WHEN CASE
           WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN') THEN d.ads_net_roas_1w_os
           WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN d.ads_net_roas_1w
           WHEN d.coach_mode = 'BLITZ' THEN d.ads_net_roas_14d
           ELSE d.ads_net_roas_1w
         END < d.th_reduce_bid_roas
              THEN ' [MARGINAL => REDUCE_BID]'
            ELSE ' [MONITOR]'
          END)
      ELSE '' END
    )
  END as decision_trace,

  -- ─── Reason ───
  CASE
    -- OPPORTUNITY
    WHEN d.recommendation_type = 'OPPORTUNITY'
      THEN CONCAT(
        CAST(d.sqp_orders_8w AS STRING), ' SQP Orders(8w) for "', d.search_term, '". No ads target this term.',
        CASE
          WHEN d.hero_asin IS NOT NULL AND d.hero_asin != d.asin
            THEN CONCAT(' Advertise ', COALESCE(d.hero_product_name, ''), ' (hero',
              CASE WHEN COALESCE(d.hero_ads_cvr_pct, 0) > 0 THEN CONCAT(', Ads CVR ', CAST(ROUND(d.hero_ads_cvr_pct, 1) AS STRING), '%') ELSE '' END,
              CASE WHEN COALESCE(d.hero_sqp_cvr_pct, 0) > 0 THEN CONCAT(', SQP CVR ', CAST(ROUND(d.hero_sqp_cvr_pct, 1) AS STRING), '%') ELSE '' END,
              ').')
          WHEN d.hero_asin IS NOT NULL
            THEN CONCAT(' Advertise ', COALESCE(d.hero_product_name, ''), ' (hero).')
          ELSE CONCAT(' Advertise ', d.product_short_name, '.')
        END)

    -- STOP_SEASONAL: holiday campaign post-season (GUARDIAN + COOLDOWN)
    WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN')
      AND EXISTS (
        SELECT 1 FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
        WHERE h.category = 'gift_season'
          AND h.cooldown_end < CURRENT_DATE('America/New_York')
          AND (STRPOS(UPPER(d.campaign_name), UPPER(h.holiday_name)) > 0
            OR STRPOS(UPPER(d.campaign_name), UPPER(REGEXP_REPLACE(h.holiday_name, r"'?s?\s+Day$", ''))) > 0)
      )
      AND d.ads_clicks_recent_5d > 0
      THEN CONCAT('Seasonal campaign still active after season ended. ',
                   'Campaign "', d.campaign_name, '" should be paused.')

    -- START_SEASONAL: reactivate paused seasonal campaign in BLITZ
    WHEN d.coach_mode = 'BLITZ'
      AND UPPER(d.campaign_state) != 'ENABLED' AND d.campaign_state IS NOT NULL
      AND (d.strategy_id = 'SEASONAL_PUSH'
           OR STRPOS(UPPER(d.campaign_name), 'Q4 SEASONAL') > 0
           OR STRPOS(UPPER(d.campaign_name), 'SEASONAL') > 0)
      THEN CONCAT('Season is starting! Reactivate paused campaign "',
                   d.campaign_name, '". Q4 Net ROAS ',
                   CAST(ROUND(d.q4_peak_net_roas, 2) AS STRING),
                   ' (', CAST(d.q4_peak_orders AS STRING), ' peak orders).')

    -- NEW_SEASONAL: Q4 term needs a seasonal campaign in BLITZ
    WHEN d.coach_mode = 'BLITZ' AND d.is_q4_seasonal = TRUE
      AND d.strategy_id != 'SEASONAL_PUSH'
      AND NOT REGEXP_CONTAINS(UPPER(d.campaign_name), r'Q4 SEASONAL|SEASONAL.PUSH')
      THEN CONCAT('"', d.search_term, '" is a Q4 seasonal winner (ROAS ',
                   CAST(ROUND(d.q4_peak_net_roas, 2) AS STRING),
                   ' / ', CAST(d.q4_peak_orders AS STRING),
                   ' orders). Create a SEASONAL_PUSH exact campaign. ',
                   'See V_ADS_COACH_SEASONAL_CAMPAIGNS for grouping. ',
                   'ALSO: negate "', d.search_term, '" in source campaign "', d.campaign_name, '" to prevent overlap.')

    -- MOVE_TO_SEASONAL_PUSH: (removed — seasonal logic simplified)

    -- SEASONAL TERM GUARD (non-BLITZ): profitable seasonal term held for next BLITZ
    WHEN d.coach_mode != 'BLITZ'
      AND d.is_holiday_seasonal = TRUE
      AND d.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
      AND d.ads_orders_8w >= CAST(d.th_promote_min_orders AS INT64)
      THEN CONCAT('🛡 Seasonal term "', d.search_term, '" is profitable (',
                   CAST(d.ads_orders_8w AS STRING), ' orders, ROAS ',
                   CAST(ROUND(CASE
           WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN') THEN d.ads_net_roas_1w_os
           WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN d.ads_net_roas_1w
           WHEN d.coach_mode = 'BLITZ' THEN d.ads_net_roas_14d
           ELSE d.ads_net_roas_1w
         END, 2) AS STRING),
                   ') but promotion blocked — seasonal terms can only be promoted during BLITZ. ',
                   'Will auto-promote next season.')

    -- Insufficient data (clicks-based)
    WHEN d.ads_clicks_8w < d.th_min_clicks
      THEN CONCAT(CAST(d.ads_clicks_8w AS STRING), ' clicks(8w) — need at least ',
                   CAST(CAST(d.th_min_clicks AS INT64) AS STRING), ' clicks for ', COALESCE(d.strategy_id, 'this strategy'), '.')

    -- EXACT_BOOST specific reasons
    WHEN d.strategy_id = 'EXACT_BOOST' AND d.ads_orders_8w = 0 AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0
      THEN CONCAT('Boosted keyword "', d.search_term, '" has ', CAST(d.ads_clicks_8w AS STRING),
                   ' clicks but 0 orders. Stop exact targeting.')
    WHEN d.strategy_id = 'EXACT_BOOST' AND d.ads_net_roas_8w < d.th_negate_roas AND d.ads_clicks_recent_5d > 0
      THEN CONCAT('Boosted keyword underperforming: Net ROAS ', CAST(d.ads_net_roas_8w AS STRING),
                   ' on $', CAST(ROUND(d.ads_spend_8w, 0) AS STRING), ' spend. Negate exact match.')
    WHEN d.strategy_id = 'EXACT_BOOST' AND d.ads_net_roas_8w < d.th_reduce_bid_roas AND d.ads_clicks_recent_5d > 0
      THEN CONCAT('Boosted keyword marginal: Net ROAS ', CAST(d.ads_net_roas_8w AS STRING),
                   ' on ', CAST(d.ads_clicks_8w AS STRING), ' clicks. Negate exact match for "', d.search_term, '".')

    -- BRAND_DEFENSE / PRODUCT_DEFENSE — MONITOR only
    WHEN d.strategy_id IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE')
      THEN CONCAT('Defending "', d.search_term, '" (', d.strategy_id, '). Monitoring.')

    -- STOP: wasted spend
    WHEN d.ads_orders_8w = 0 AND d.sqp_organic_units_8w = 0
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0
      THEN CONCAT(CAST(d.ads_clicks_8w AS STRING), ' clicks(8w) on "', d.search_term,
                   '" with zero orders. Still receiving clicks (', CAST(d.ads_clicks_recent_5d AS STRING), ' in 5d).',
                   CASE WHEN d.hero_asin IS NOT NULL AND NOT d.is_hero_match
                        THEN CONCAT(' [WRONG ASIN: switch to ', COALESCE(d.hero_product_name, ''), ']') ELSE '' END)

    -- PROMOTE (with SQP volume check) — uses mode-aware ROAS
    WHEN d.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
      AND d.ads_orders_8w >= CAST(d.th_promote_min_orders AS INT64)
      AND CASE
           WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN') THEN d.ads_net_roas_1w_os
           WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN d.ads_net_roas_1w
           WHEN d.coach_mode = 'BLITZ' THEN d.ads_net_roas_14d
           ELSE d.ads_net_roas_1w
         END >= d.th_promote_min_roas
      AND NOT d.already_in_exact_boost
      AND d.sqp_amazon_search_volume_8w >= d.th_promote_min_sqp_vol
      THEN CONCAT('"', d.search_term, '" converts in ', COALESCE(d.campaign_type, 'broad/auto'), ' (',
                   CAST(d.ads_orders_8w AS STRING), ' Orders(8w), Effective ROAS ',
                   CAST(CASE
           WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN') THEN d.ads_net_roas_1w_os
           WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN d.ads_net_roas_1w
           WHEN d.coach_mode = 'BLITZ' THEN d.ads_net_roas_14d
           ELSE d.ads_net_roas_1w
         END AS STRING),
                   ', SQP vol ', CAST(ROUND(d.sqp_amazon_search_volume_8w, 0) AS STRING),
                   '/', CAST(CAST(d.th_promote_min_sqp_vol AS INT64) AS STRING), ').',
                   ' Promote to EXACT_BOOST.',
                   CASE
                     WHEN d.hero_asin IS NOT NULL AND d.is_hero_match
                       THEN CONCAT(' [HERO MATCH: ', d.product_short_name, ' IS the best child',
                         CASE WHEN COALESCE(d.hero_ads_cvr_pct, 0) > 0 THEN CONCAT(' (Ads CVR ', CAST(ROUND(d.hero_ads_cvr_pct, 1) AS STRING), '%)') ELSE '' END, ']')
                     WHEN d.hero_asin IS NOT NULL AND NOT d.is_hero_match
                       THEN CONCAT(' [WRONG ASIN: ', COALESCE(d.hero_product_name, ''), ' is the hero',
                         CASE WHEN COALESCE(d.hero_ads_cvr_pct, 0) > 0 THEN CONCAT(' (Ads CVR ', CAST(ROUND(d.hero_ads_cvr_pct, 1) AS STRING), '%)') ELSE '' END, ']')
                     ELSE '' END)

    -- SCALE_UP (EXACT_BOOST campaigns)
    WHEN d.strategy_id = 'EXACT_BOOST' AND d.ads_net_roas_8w >= d.th_scale_up_roas
      AND d.ads_orders_8w >= 2
      THEN CONCAT('Strong ROAS ', CAST(d.ads_net_roas_8w AS STRING), ' (8w), ',
                   CAST(d.ads_orders_8w AS STRING), ' orders (8w) in EXACT_BOOST. Profit $',
                   CAST(ROUND(COALESCE(d.ads_net_profit_8w, 0), 0) AS STRING), '. Keep targeting — check TARGET for bid recommendation.')

    -- INCREASE_BID (HUNTER/LOW_COST strong targets)
    WHEN d.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
      AND d.ads_orders_8w >= 2 AND d.ads_net_roas_8w >= d.th_scale_up_roas
      THEN CONCAT('Target performing well: ', CAST(d.ads_orders_8w AS STRING),
                   ' orders (8w), ROAS ', CAST(d.ads_net_roas_8w AS STRING), ' (8w)',
                   '. Increase bid to capture more volume.')

    -- STOP: heavy loss (mode-aware ROAS)
    WHEN CASE
           WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN') THEN d.ads_net_roas_1w_os
           WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN d.ads_net_roas_1w
           WHEN d.coach_mode = 'BLITZ' THEN d.ads_net_roas_14d
           ELSE d.ads_net_roas_1w
         END < d.th_negate_roas
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0
      THEN CONCAT('Losing $', CAST(ROUND(ABS(COALESCE(d.ads_net_profit_8w, 0)), 0) AS STRING),
                   ' on ', CAST(d.ads_clicks_8w AS STRING), ' clicks (Effective ROAS ',
                   CAST(CASE
           WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN') THEN d.ads_net_roas_1w_os
           WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN d.ads_net_roas_1w
           WHEN d.coach_mode = 'BLITZ' THEN d.ads_net_roas_14d
           ELSE d.ads_net_roas_1w
         END AS STRING), '). Still active.')

    -- MONITOR fallback
    ELSE CONCAT(CAST(d.ads_clicks_8w AS STRING), ' clicks, ', CAST(d.ads_orders_8w AS STRING),
                ' orders (ROAS ', CAST(COALESCE(d.ads_net_roas_8w, 0) AS STRING), '). Monitoring.')
  END as reason,

  -- ─── Term Decision Trace (JSON chips — co-located with action logic) ───
  -- Uses the EXACT same metrics as the action CASE above:
  --   Clicks 8w vs th_min_clicks, Orders 8w, mode-aware ROAS (OS_WtROAS for GUARDIAN)
  CONCAT('[',
    '{"id":"clicks","label":"Clicks 8w","sql":"ads_clicks_8w","rule":"≥ ',
      CAST(CAST(d.th_min_clicks AS INT64) AS STRING),
      '","pass":', IF(COALESCE(d.ads_clicks_8w, 0) >= d.th_min_clicks, 'true', 'false'),
      ',"value":"', CAST(COALESCE(d.ads_clicks_8w, 0) AS STRING), '"},',
    '{"id":"orders","label":"Orders 8w","sql":"ads_orders_8w","rule":"> 0","pass":', IF(COALESCE(d.ads_orders_8w, 0) > 0, 'true', 'false'),
      ',"value":"', CAST(COALESCE(d.ads_orders_8w, 0) AS STRING), '"},',
    '{"id":"roas","label":"LT ROAS (12m)","sql":"lt_net_roas","rule":"≥ ',
      CAST(ROUND(d.th_negate_roas, 2) AS STRING),
      '","pass":',
      -- pass = true when lifetime ROAS is above negate threshold (or NULL = no LT data)
      IF(d.lt_net_roas IS NULL OR d.lt_net_roas >= d.th_negate_roas, 'true', 'false'),
      ',"value":"', CASE WHEN d.lt_net_roas IS NULL THEN 'N/A' ELSE CAST(ROUND(d.lt_net_roas, 2) AS STRING) END, '"}',
    -- Lag window safety check for term negate
    CASE WHEN CASE
           WHEN d.coach_mode IN ('GUARDIAN', 'COOLDOWN') THEN d.ads_net_roas_1w_os
           WHEN d.coach_mode = 'BLITZ' AND d.current_phase = 'PEAK' THEN d.ads_net_roas_1w
           WHEN d.coach_mode = 'BLITZ' THEN d.ads_net_roas_14d
           ELSE d.ads_net_roas_1w
         END < d.th_negate_roas
           AND d.ads_orders_8w > 0
      THEN CONCAT(
        ',{"id":"term_lag","label":"Lag ROAS (3d)","sql":"ads_lag_net_roas","rule":"≤ 1.3 → negate","pass":',
        IF(COALESCE(d.ads_lag_net_roas, 0) > 1.3, 'false', 'true'),
        ',"value":"', CAST(ROUND(COALESCE(d.ads_lag_net_roas, 0), 2) AS STRING), '"}')
      ELSE ''
    END,
  ']') as term_decision_trace,

  -- ─── Post-peak metrics (exposed for dashboard) ───
  pp.pp_spend as pp_target_spend,
  pp.pp_clicks as pp_target_clicks,
  pp.pp_orders as pp_target_orders,
  pp.pp_sales as pp_target_sales,
  pp.pp_days as pp_days,
  ROUND(SAFE_DIVIDE(pp.pp_sales, NULLIF(pp.pp_spend, 0)), 2) as pp_target_net_roas,

  -- ─── Budget action (campaign-level decision — all modes) ───
  -- GUARDIAN: increase/decrease based on budget utilization + campaign ROAS
  -- BLITZ: aggressive increase for profitable out-of-budget campaigns
  -- COOLDOWN: 3-tier post-peak restore logic
  CASE
    -- ═══ STOP_SEASONAL: campaign-level — seasonal campaign past its season ═══
    WHEN d.strategy_id = 'SEASONAL_PUSH'
      AND EXISTS (
        SELECT 1 FROM `onyga-482313.OI.DIM_US_HOLIDAYS` h
        WHERE h.category = 'gift_season'
          AND h.cooldown_end < CURRENT_DATE('America/New_York')
          AND (
            STRPOS(UPPER(d.campaign_name), UPPER(h.holiday_name)) > 0
            OR STRPOS(UPPER(d.campaign_name), UPPER(REGEXP_REPLACE(h.holiday_name, r"'?s?\s+Day$", ''))) > 0
          )
      )
      THEN 'STOP_SEASONAL'

    WHEN d.current_budget IS NULL THEN NULL

    -- ═══ GUARDIAN MODE ═══
    -- OUT OF BUDGET + PROFITABLE → increase (with frequency gate: every 3d)
    WHEN d.coach_mode = 'GUARDIAN'
      AND COALESCE(cbm.camp_budget_util_pct, 0) >= 90
      AND COALESCE(cbm.camp_effective_roas, 0) >= 1.1
      AND d.days_since_last_budget_change >= 3
      THEN 'GUARDIAN_BUDGET_INCREASE'
    -- LOSING → decrease (with frequency gate: every 3d)
    WHEN d.coach_mode = 'GUARDIAN'
      AND COALESCE(cbm.camp_effective_roas, 0) < 0.9
      AND COALESCE(cbm.camp_spend_8w, 0) > 25
      AND d.days_since_last_budget_change >= 3
      THEN 'GUARDIAN_BUDGET_DECREASE'
    -- GUARDIAN: no action needed (or frequency gate not met)
    WHEN d.coach_mode = 'GUARDIAN' THEN 'BUDGET_OK'

    -- ═══ BLITZ MODE ═══
    -- Frequency gate: BOOST=3d, PEAK=1d
    -- OUT OF BUDGET + PROFITABLE → aggressive increase
    WHEN d.coach_mode = 'BLITZ'
      AND COALESCE(cbm.camp_budget_util_pct, 0) >= 90
      AND COALESCE(cbm.camp_effective_roas, 0) >= 1.1
      AND (
        (d.current_phase = 'BOOST' AND d.days_since_last_budget_change >= 3)
        OR (d.current_phase = 'PEAK' AND d.days_since_last_budget_change >= 1)
        OR d.current_phase NOT IN ('BOOST', 'PEAK')  -- PRE_PEAK: no extra gate
      )
      THEN 'BLITZ_BUDGET_INCREASE'
    -- LOSING → reduce even in BLITZ
    WHEN d.coach_mode = 'BLITZ'
      AND COALESCE(cbm.camp_effective_roas, 0) < 0.9
      AND COALESCE(cbm.camp_spend_8w, 0) > 25
      AND (
        (d.current_phase = 'BOOST' AND d.days_since_last_budget_change >= 3)
        OR (d.current_phase = 'PEAK' AND d.days_since_last_budget_change >= 1)
        OR d.current_phase NOT IN ('BOOST', 'PEAK')
      )
      THEN 'BLITZ_BUDGET_DECREASE'
    -- BLITZ: no action needed (or frequency gate not met)
    WHEN d.coach_mode = 'BLITZ' THEN 'BUDGET_OK'

    -- ═══ COOLDOWN MODE ═══
    WHEN d.coach_mode = 'COOLDOWN' AND d.pre_peak_budget IS NULL THEN NULL
    WHEN d.coach_mode = 'COOLDOWN' AND d.current_budget <= d.pre_peak_budget THEN 'BUDGET_OK'
    WHEN d.coach_mode = 'COOLDOWN' AND COALESCE(ppc.pp_campaign_net_roas, 0) >= 0.8 THEN 'COOLDOWN_BUDGET_MONITOR'
    WHEN d.coach_mode = 'COOLDOWN' AND COALESCE(ppc.pp_campaign_net_roas, 0) >= 0.6 THEN 'COOLDOWN_BUDGET_REDUCE'
    WHEN d.coach_mode = 'COOLDOWN' THEN 'RESTORE_BUDGET_PRE_PEAK'

    ELSE NULL
  END as budget_action,

  -- Campaign-level post-peak metrics (for cooldown budget trace)
  ppc.pp_campaign_spend,
  ppc.pp_campaign_orders,
  ppc.pp_campaign_sales,
  ppc.pp_campaign_days,
  ppc.pp_campaign_net_roas,

  -- Campaign-level budget health metrics (for guardian/blitz budget trace)
  cbm.camp_effective_roas,
  cbm.camp_avg_daily_spend,
  cbm.camp_budget_util_pct,
  cbm.camp_spend_8w as camp_total_spend_8w,
  cbm.camp_orders_8w as camp_total_orders_8w,

  -- ─── Budget recommendation (all modes) ───
  CASE
    WHEN d.current_budget IS NULL THEN NULL

    -- GUARDIAN: +10% for profitable out-of-budget, -15% for losing
    WHEN d.coach_mode = 'GUARDIAN'
      AND COALESCE(cbm.camp_budget_util_pct, 0) >= 90
      AND COALESCE(cbm.camp_effective_roas, 0) >= 1.1
      THEN ROUND(d.current_budget * 1.10, 0)
    WHEN d.coach_mode = 'GUARDIAN'
      AND COALESCE(cbm.camp_effective_roas, 0) < 0.9
      AND COALESCE(cbm.camp_spend_8w, 0) > 25
      THEN ROUND(d.current_budget * 0.85, 0)

    -- BLITZ: +20% for aggressive scaling, -10% for bad performers
    WHEN d.coach_mode = 'BLITZ'
      AND COALESCE(cbm.camp_budget_util_pct, 0) >= 90
      AND COALESCE(cbm.camp_effective_roas, 0) >= 1.1
      THEN ROUND(d.current_budget * 1.20, 0)
    WHEN d.coach_mode = 'BLITZ'
      AND COALESCE(cbm.camp_effective_roas, 0) < 0.9
      AND COALESCE(cbm.camp_spend_8w, 0) > 25
      THEN ROUND(d.current_budget * 0.90, 0)

    -- COOLDOWN: 3-tier restore logic
    WHEN d.coach_mode = 'COOLDOWN' AND d.pre_peak_budget IS NULL THEN NULL
    WHEN d.coach_mode = 'COOLDOWN' AND d.current_budget <= d.pre_peak_budget THEN NULL
    WHEN d.coach_mode = 'COOLDOWN' AND COALESCE(ppc.pp_campaign_net_roas, 0) >= 0.8 THEN NULL
    WHEN d.coach_mode = 'COOLDOWN' AND COALESCE(ppc.pp_campaign_net_roas, 0) >= 0.6 THEN ROUND(d.current_budget * 0.90, 0)
    WHEN d.coach_mode = 'COOLDOWN' THEN d.pre_peak_budget

    ELSE NULL
  END as recommended_budget,

  -- ─── Strategic Task (maps each action to the coach's strategic plan) ───
  -- Mirrors the action/target_action logic above to classify into strategic tasks
  CASE
    -- COOLDOWN tasks — mirrors target_action 3-tier logic (1.3 / 1.1)
    WHEN d.coach_mode = 'COOLDOWN' THEN
      CASE
        -- Insufficient term data → no bid-level strategic classification
        WHEN d.ads_clicks_8w < d.th_min_clicks AND d.recommendation_type != 'OPPORTUNITY' THEN 'MAINTAIN'
        -- Tier 1: COOLDOWN_MONITOR → monitor performance (pp Ads ROAS ≥ 0.8)
        WHEN d.current_bid IS NOT NULL
             AND COALESCE(pp.pp_spend, 0) > 0
             AND SAFE_DIVIDE(pp.pp_sales, NULLIF(pp.pp_spend, 0)) >= 0.8
             THEN 'MONITOR_PERFORMANCE'
        -- Tier 2: REDUCE_TO_BASELINE → normalize bids (pp Ads ROAS ≥ 0.6)
        WHEN d.current_bid IS NOT NULL
             AND COALESCE(pp.pp_spend, 0) > 0
             AND SAFE_DIVIDE(pp.pp_sales, NULLIF(pp.pp_spend, 0)) >= 0.6
             THEN 'NORMALIZE_BIDS'
        -- Tier 3: RESTORE_PRE_PEAK → normalize bids (losing money)
        WHEN d.current_bid IS NOT NULL
             THEN 'NORMALIZE_BIDS'
        -- No bid data → protect terms
        ELSE 'PROTECT_TERMS'
      END
    -- BLITZ tasks
    WHEN d.coach_mode = 'BLITZ' THEN
      CASE
        -- Insufficient term data → no bid-level strategic classification
        WHEN d.ads_clicks_8w < d.th_min_clicks AND d.recommendation_type != 'OPPORTUNITY' THEN 'MAINTAIN'
        -- Bid increase on profitable targets
        WHEN d.target_roas >= d.th_scale_up_roas
             AND d.eff_orders_for_bid >= 2 THEN 'SCALE_WINNERS'
        -- Promote to exact
        WHEN d.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
             AND d.ads_orders_8w >= CAST(d.th_promote_min_orders AS INT64)
             AND NOT d.already_in_exact_boost THEN 'PROMOTE_TERMS'
        -- Heavy loss even in blitz → cost control
        WHEN d.target_orders_8w = 0 AND d.target_clicks_8w >= d.th_min_clicks
             AND d.target_clicks_recent_5d > 0 THEN 'COST_CONTROL'
        WHEN d.target_roas < d.th_negate_roas
             AND d.target_orders_8w > 0 THEN 'COST_CONTROL'
        -- Keeping terms active during peak
        ELSE 'PROTECT_TERMS'
      END
    -- GUARDIAN tasks (default)
    ELSE
      CASE
        -- Insufficient term data → no target-level strategic classification
        WHEN d.ads_clicks_8w < d.th_min_clicks AND d.recommendation_type != 'OPPORTUNITY' THEN 'MAINTAIN'
        -- Wasted spend → eliminate waste
        WHEN d.ads_orders_8w = 0 AND d.sqp_organic_units_8w = 0
             AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0 THEN 'ELIMINATE_WASTE'
        WHEN d.ads_orders_8w = 0 AND d.xc_selling_campaigns > 0
             AND d.ads_clicks_8w >= d.th_min_clicks THEN 'ELIMINATE_WASTE'
        WHEN d.target_orders_8w = 0 AND d.target_clicks_8w >= d.th_min_clicks
             AND d.target_clicks_recent_5d > 0 THEN 'ELIMINATE_WASTE'
        -- Bid reduction on underperformers
        WHEN d.target_roas < d.th_reduce_bid_roas
             AND d.target_orders_8w > 0 THEN 'OPTIMIZE_BIDS'
        -- Warmup: new campaigns (< 14 days) → MAINTAIN until algorithm matures
        WHEN DATE_DIFF(CURRENT_DATE('America/New_York'), DATE(d.campaign_creation_date), DAY) < 14
             AND d.target_roas >= d.th_profitable_roas AND d.eff_orders_for_bid >= 2 THEN 'MAINTAIN'
        -- Bid increase on winners
        WHEN d.target_roas >= d.th_scale_up_roas
             AND d.eff_orders_for_bid >= 2 THEN 'SCALE_WINNERS'
        -- Promote to exact (blocked for seasonal terms — only BLITZ promotes seasonal)
        WHEN d.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
             AND d.ads_orders_8w >= CAST(d.th_promote_min_orders AS INT64)
             AND NOT d.already_in_exact_boost
             AND d.sqp_amazon_search_volume_8w >= d.th_promote_min_sqp_vol
             AND d.is_holiday_seasonal = FALSE THEN 'PROMOTE_TERMS'
        -- Hero correction
        WHEN d.is_hero_match = FALSE AND d.hero_asin IS NOT NULL THEN 'CORRECT_HEROES'
        -- Start targeting (opportunity)
        WHEN d.recommendation_type = 'OPPORTUNITY' THEN 'PROMOTE_TERMS'
        -- Everything else: maintain
        ELSE 'MAINTAIN'
      END
  END as strategic_task,

  -- ─── Seasonal Campaign Action (campaign-level pause/enable) ───
  -- COOLDOWN: pause campaigns tagged for the cooldown peak
  -- BLITZ: enable campaigns tagged for the blitz peak IF profitable last year (net ROAS > 1.2)
  sch.seasonal_peak_name,
  CASE
    WHEN sch.seasonal_peak_name IS NULL THEN NULL
    WHEN sch.seasonal_peak_phase = 'COOLDOWN' THEN 'PAUSE_CAMPAIGN'
    WHEN sch.seasonal_peak_phase IN ('PRE_PEAK', 'BOOST', 'PEAK')
      AND COALESCE(lypr.ly_peak_net_roas, 0) > 1.2 THEN 'ENABLE_CAMPAIGN'
    WHEN sch.seasonal_peak_phase IN ('PRE_PEAK', 'BOOST', 'PEAK')
      THEN NULL  -- seasonal campaign but not profitable last year — don't auto-enable
    ELSE NULL
  END as seasonal_campaign_action,
  lypr.ly_peak_net_roas as ly_peak_net_roas,

  -- ─── Strategy reasoning (plain-language "why" per strategy — the bar varies, so explain it) ───
  CASE
    WHEN d.strategy_id IS NULL THEN 'No strategy assigned to this campaign — assign one so the coach can manage it.'
    WHEN d.strategy_id = 'BRAND_DEFENSE' THEN CONCAT(
      'Brand defense — bid high to own the placement and make competitors overpay; not optimized for our ROAS. Impression share ',
      CAST(ROUND(COALESCE(d.impression_share_pct, 0), 0) AS STRING), '% vs ',
      CAST(CAST(d.th_defense_dominate_is AS INT64) AS STRING), '% dominate cutoff.')
    WHEN d.strategy_id = 'PRODUCT_DEFENSE' THEN 'Product defense — keep our own ASINs on our own detail pages so shoppers see only our options; bid up toward the ceiling.'
    WHEN d.strategy_id = 'HUNTER' THEN CONCAT('Discovery — only scale once it is ad-profitable (net ROAS >= ', CAST(ROUND(d.th_profitable_roas, 2) AS STRING), 'x); net ROAS is ads-only, breakeven 1.0.')
    WHEN d.strategy_id = 'SEASONAL_PUSH' THEN CONCAT('Seasonal — keep warm at >= ', CAST(ROUND(d.th_profitable_roas, 2) AS STRING), 'x so peak-proven terms stay live for the next peak.')
    WHEN d.strategy_id = 'NEW_LAUNCH' THEN CONCAT('New launch — push for clicks early (bar ', CAST(ROUND(d.th_profitable_roas, 2) AS STRING), 'x) to learn before optimizing.')
    ELSE CONCAT('Scales when net ROAS >= ', CAST(ROUND(d.th_profitable_roas, 2) AS STRING), 'x (ads-only; breakeven 1.0).')
  END as strategy_reason,

  -- ─── Bid-ceiling note (flags when a raise is capped by the $ ceiling) ───
  CASE
    WHEN COALESCE(d.current_bid, 0) >= d.th_bid_cap
      THEN CONCAT('at/above BID Ceiling ($', CAST(ROUND(d.th_bid_cap, 2) AS STRING), ') — bid capped')
    WHEN d.strategy_id IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE') AND COALESCE(d.current_bid, 0) * 1.5 >= d.th_bid_cap
      THEN CONCAT('defense raise capped by BID Ceiling ($', CAST(ROUND(d.th_bid_cap, 2) AS STRING), ')')
    ELSE NULL
  END as bid_ceiling_note

FROM coach_data d
LEFT JOIN pp_target_metrics pp
  ON d.campaign_id = pp.campaign_id
  AND LOWER(COALESCE(d.targeting, d.search_term)) = LOWER(pp.targeting)
  AND d.asin = pp.asin
LEFT JOIN (
  SELECT p.asin as ae_asin, COALESCE(ch.TOTAL_COST_PER_UNIT, 0) as total_cost_per_unit
  FROM `onyga-482313.OI.DIM_PRODUCT` p
  LEFT JOIN (
    SELECT asin, TOTAL_COST_PER_UNIT,
      ROW_NUMBER() OVER (PARTITION BY asin ORDER BY end_date DESC NULLS FIRST) as rn
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  ) ch ON p.asin = ch.asin AND ch.rn = 1
  WHERE p.asin IS NOT NULL
) ae ON d.asin = ae.ae_asin
LEFT JOIN pp_campaign_metrics ppc ON d.campaign_id = ppc.campaign_id
LEFT JOIN campaign_budget_metrics cbm ON d.campaign_id = cbm.campaign_id
LEFT JOIN seasonal_campaign_holiday sch ON d.campaign_id = sch.campaign_id
LEFT JOIN ly_peak_campaign_roas lypr ON sch.seasonal_peak_name = lypr.holiday_name
),

-- ─── 3-day "no re-suggest" cooldown ───────────────────────────────────────────
-- Hide a target's bid/budget re-tweaks for 3 days after WE last changed it
-- (days_since_last_suggestion[_camp] sourced from FACT_PPC_CHANGE_LOG in
-- V_ADS_COACH_DATA — the authoritative upload time, unlike the lagging SCD2 history).
-- Safety valve: STOP_TARGET / NEGATE_TERM / STOP_TERM on a clear loser still pass.
scored AS (
  SELECT * REPLACE(
    CASE WHEN days_since_last_suggestion < 3 AND action NOT IN ('NEGATE_TERM', 'STOP_TERM')
         THEN 'KEEP' ELSE action END AS action,
    CASE WHEN days_since_last_suggestion < 3 AND target_action != 'STOP_TARGET'
         THEN 'KEEP_TARGET' ELSE target_action END AS target_action,
    CASE WHEN days_since_last_suggestion_camp < 3
         THEN 'BUDGET_OK' ELSE budget_action END AS budget_action
  ) FROM scored_raw
)

SELECT
  scored.* EXCEPT(bid_ceiling_note, days_since_last_suggestion, days_since_last_suggestion_camp),
  -- Exact bid-ceiling note: fires when the (capped) recommended bid sits at the ceiling on an increase.
  CASE
    WHEN scored.target_action = 'INCREASE_BID'
      AND scored.recommended_bid IS NOT NULL
      AND scored.recommended_bid >= scored.th_bid_cap
      THEN CONCAT('bid set by BID Ceiling ($', CAST(ROUND(scored.th_bid_cap, 2) AS STRING), ')')
    ELSE NULL
  END AS bid_ceiling_note,
  -- Launch-track bid the coacher would set for this decision (capped at the launch ceiling):
  --   HOLD   → the aggressive launch bid (establishes/keeps the gather-phase bid)
  --   REDUCE → current bid −LAUNCH_STEP_DOWN_PCT, floored at the term's own CPC
  --   NEGATE/GRADUATE/off-track → no bid
  CASE scored.launch_decision
    WHEN 'LAUNCH_HOLD' THEN scored.launch_bid
    WHEN 'LAUNCH_REDUCE_BID' THEN ROUND(GREATEST(
      COALESCE(scored.current_bid, scored.launch_bid) * (1 - scored.th_launch_step_down_pct),
      COALESCE(NULLIF(scored.ads_cpc_8w, 0), 0.05)
    ), 2)
    ELSE NULL
  END AS launch_recommended_bid,
  -- Compact decision-trace for the launch card (NULL when off the track)
  CASE WHEN scored.launch_decision IS NOT NULL THEN CONCAT(
    '[',
    '{"id":"launch","label":"Launch","pass":true,"value":"', scored.launch_phase, ' · ', scored.launch_decision, '"},',
    '{"id":"clicks","label":"Clicks (launch)","pass":true,"value":"', CAST(scored.launch_clicks AS STRING), '"},',
    '{"id":"csbc","label":"Clicks since bid","pass":true,"value":"', CAST(COALESCE(scored.clicks_since_last_bid_change, 0) AS STRING), '"},',
    '{"id":"orders","label":"Orders 4w","pass":true,"value":"', CAST(COALESCE(scored.ads_orders_4w, 0) AS STRING), '"},',
    '{"id":"net_roas","label":"Net ROAS 4w","pass":true,"value":"', CAST(ROUND(COALESCE(scored.ads_net_roas_4w, 0), 2) AS STRING), '"},',
    '{"id":"bid","label":"Launch bid","pass":true,"value":"$', CAST(scored.launch_bid AS STRING), ' (', scored.launch_bid_source, ')"}',
    ']'
  ) ELSE NULL END AS launch_decision_trace
FROM scored
