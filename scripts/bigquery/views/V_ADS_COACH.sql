-- =============================================
-- OI Database Project - V_ADS_COACH View
-- =============================================
--
-- Purpose: THIN LOGIC LAYER — single source of truth for all action decisions.
--          References V_ADS_COACH_DATA for metrics.
--          Joins strategy-specific thresholds from DE_COACH_THRESHOLDS
--          (falls back to GLOBAL when strategy-specific not set).
--
-- This is THE ONLY place action logic lives. All dashboard pages read from here.
--
-- Grain: campaign_id × asin × search_term  (same as V_ADS_COACH_DATA)
--
-- Strategy-aware logic:
--   • EXACT_BOOST: boosted keyword underperforming? REDUCE_BID or STOP. Never PROMOTE (already exact).
--   • HUNTER / LOW_COST_DISCOVERY: promote converting keywords to EXACT_BOOST (only if SQP volume exists)
--   • BRAND_DEFENSE: never negate brand terms — keep defending (NEGATE_ROAS = -999)
--   • PRODUCT_DEFENSE: similar to brand — never negate (NEGATE_ROAS = -999)
--   • CATEGORY_CONQUEST / COMPETITOR_CONQUEST: aggressive — lower ROAS thresholds, wider spend tolerance
--   • All others: use GLOBAL fallback thresholds
--
-- Decision logic guards:
--   • Insufficient data → based on CLICKS (not spend)
--   • NEGATE → requires min clicks threshold (don't negate a keyword you just started testing)
--   • SCALE_UP → only from EXACT campaign type with strong ROAS
--   • PROMOTE_TO_EXACT → requires SQP search volume (keyword worth targeting)
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_COACH`
AS
WITH

-- ─── Strategy-specific thresholds with GLOBAL fallback ───
-- Pivot DE_COACH_THRESHOLDS per strategy, then COALESCE with GLOBAL
global_thresholds AS (
  SELECT
    COALESCE(MAX(IF(threshold_key='INSUFFICIENT_DATA_CLICKS', threshold_value, NULL)), 15) as min_clicks,
    COALESCE(MAX(IF(threshold_key='WASTED_SPEND_THRESHOLD', threshold_value, NULL)), 15) as wasted_spend_min,
    COALESCE(MAX(IF(threshold_key='NEGATE_ROAS_THRESHOLD', threshold_value, NULL)), 0.5) as negate_roas,
    COALESCE(MAX(IF(threshold_key='NEGATE_SPEND_THRESHOLD', threshold_value, NULL)), 20) as negate_spend,
    COALESCE(MAX(IF(threshold_key='REDUCE_BID_ROAS', threshold_value, NULL)), 0.7) as reduce_bid_roas,
    COALESCE(MAX(IF(threshold_key='SCALE_UP_ROAS', threshold_value, NULL)), 2.0) as scale_up_roas,
    COALESCE(MAX(IF(threshold_key='SCALE_UP_SPEND_CAP', threshold_value, NULL)), 50) as scale_up_spend_cap,
    COALESCE(MAX(IF(threshold_key='PROFITABLE_ROAS', threshold_value, NULL)), 1.0) as profitable_roas,
    COALESCE(MAX(IF(threshold_key='HALO_ROAS', threshold_value, NULL)), 0.5) as halo_roas,
    COALESCE(MAX(IF(threshold_key='PROMOTE_MIN_ORDERS', threshold_value, NULL)), 4) as promote_min_orders,
    COALESCE(MAX(IF(threshold_key='PROMOTE_MIN_ROAS', threshold_value, NULL)), 0.7) as promote_min_roas,
    COALESCE(MAX(IF(threshold_key='PROMOTE_MIN_SQP_VOLUME', threshold_value, NULL)), 500) as promote_min_sqp_vol,
    COALESCE(MAX(IF(threshold_key='CONFIDENCE_DAYS_HIGH', threshold_value, NULL)), 14) as conf_days_high,
    COALESCE(MAX(IF(threshold_key='CONFIDENCE_CLICKS_HIGH', threshold_value, NULL)), 50) as conf_clicks_high,
    COALESCE(MAX(IF(threshold_key='CONFIDENCE_DAYS_MEDIUM', threshold_value, NULL)), 7) as conf_days_medium,
    COALESCE(MAX(IF(threshold_key='CONFIDENCE_CLICKS_MEDIUM', threshold_value, NULL)), 20) as conf_clicks_medium
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id = 'GLOBAL' AND product_family IS NULL
),

strategy_thresholds AS (
  SELECT
    strategy_id,
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
    MAX(IF(threshold_key='CONFIDENCE_DAYS_HIGH', threshold_value, NULL)) as conf_days_high,
    MAX(IF(threshold_key='CONFIDENCE_CLICKS_HIGH', threshold_value, NULL)) as conf_clicks_high,
    MAX(IF(threshold_key='CONFIDENCE_DAYS_MEDIUM', threshold_value, NULL)) as conf_days_medium,
    MAX(IF(threshold_key='CONFIDENCE_CLICKS_MEDIUM', threshold_value, NULL)) as conf_clicks_medium
  FROM `onyga-482313.OI.DE_COACH_THRESHOLDS`
  WHERE strategy_id != 'GLOBAL' AND product_family IS NULL
  GROUP BY strategy_id
),

-- ─── Data with resolved thresholds ───
coach_data AS (
  SELECT
    d.*,
    -- Resolved thresholds: strategy-specific COALESCE GLOBAL
    COALESCE(st.min_clicks, gt.min_clicks) as th_min_clicks,
    COALESCE(st.wasted_spend_min, gt.wasted_spend_min) as th_wasted_spend_min,
    COALESCE(st.negate_roas, gt.negate_roas) as th_negate_roas,
    COALESCE(st.negate_spend, gt.negate_spend) as th_negate_spend,
    COALESCE(st.reduce_bid_roas, gt.reduce_bid_roas) as th_reduce_bid_roas,
    COALESCE(st.scale_up_roas, gt.scale_up_roas) as th_scale_up_roas,
    COALESCE(st.scale_up_spend_cap, gt.scale_up_spend_cap) as th_scale_up_spend_cap,
    COALESCE(st.profitable_roas, gt.profitable_roas) as th_profitable_roas,
    COALESCE(st.halo_roas, gt.halo_roas) as th_halo_roas,
    COALESCE(st.promote_min_orders, gt.promote_min_orders) as th_promote_min_orders,
    COALESCE(st.promote_min_roas, gt.promote_min_roas) as th_promote_min_roas,
    COALESCE(st.promote_min_sqp_vol, gt.promote_min_sqp_vol) as th_promote_min_sqp_vol,
    COALESCE(st.conf_days_high, gt.conf_days_high) as th_conf_days_high,
    COALESCE(st.conf_clicks_high, gt.conf_clicks_high) as th_conf_clicks_high,
    COALESCE(st.conf_days_medium, gt.conf_days_medium) as th_conf_days_medium,
    COALESCE(st.conf_clicks_medium, gt.conf_clicks_medium) as th_conf_clicks_medium
  FROM `onyga-482313.OI.V_ADS_COACH_DATA` d
  CROSS JOIN global_thresholds gt
  LEFT JOIN strategy_thresholds st ON d.strategy_id = st.strategy_id
)

SELECT
  d.*,
  -- Pre-resolve: use weighted ROAS when available, fall back to 8w ROAS
  COALESCE(d.ads_weighted_net_roas, d.ads_net_roas_8w) as effective_roas,

  -- ─── Signal ───
  CASE
    WHEN d.recommendation_type = 'OPPORTUNITY' THEN 'NOT_TARGETED'
    WHEN d.ads_clicks_8w < d.th_min_clicks THEN 'INSUFFICIENT_DATA'
    WHEN d.ads_orders_8w = 0 AND d.sqp_organic_units_8w = 0
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0 THEN 'WASTED_SPEND'
    WHEN d.ads_orders_8w = 0 AND d.sqp_organic_units_8w > 0 THEN 'ORGANIC_ONLY'
    WHEN COALESCE(d.ads_weighted_net_roas, d.ads_net_roas_8w) >= d.th_scale_up_roas THEN 'STRONG'
    WHEN COALESCE(d.ads_weighted_net_roas, d.ads_net_roas_8w) >= d.th_profitable_roas THEN 'PROFITABLE'
    WHEN COALESCE(d.ads_weighted_net_roas, d.ads_net_roas_8w) >= d.th_halo_roas THEN 'MARGINAL'
    WHEN d.ads_orders_8w > 0 THEN 'UNPROFITABLE'
    ELSE 'INSUFFICIENT_DATA'
  END as ads_signal,

  -- ─── Action (strategy-aware) ───
  CASE
    -- ═══ OPPORTUNITY: Very successful term + high SQP volume ═══
    WHEN d.recommendation_type = 'OPPORTUNITY' THEN 'START_TERM'

    -- ═══ Insufficient data at SEARCH TERM level → MONITOR ═══
    -- Bid decisions (INCREASE/REDUCE) live in target_action column, not here.
    WHEN d.ads_clicks_8w < d.th_min_clicks THEN 'MONITOR'

    -- ═══ EXACT_BOOST strategy: already boosted, evaluate performance ═══
    -- If a keyword is boosted but not working → reduce or stop
    -- Never PROMOTE from EXACT_BOOST (it IS the exact campaign)
    WHEN d.strategy_id = 'EXACT_BOOST' AND d.ads_orders_8w = 0
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0 THEN 'STOP_TERM'
    WHEN d.strategy_id = 'EXACT_BOOST' AND d.ads_net_roas_8w < d.th_negate_roas
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0 THEN 'STOP_TERM'
    WHEN d.strategy_id = 'EXACT_BOOST' AND d.ads_net_roas_8w < d.th_reduce_bid_roas
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0 THEN 'STOP_TERM'
    -- (bid actions live in target_action column)
    WHEN d.strategy_id = 'EXACT_BOOST' AND COALESCE(d.ads_weighted_net_roas, d.ads_net_roas_8w) >= d.th_profitable_roas THEN 'KEEP'

    -- ═══ BRAND_DEFENSE / PRODUCT_DEFENSE: never negate (NEGATE_ROAS = -999) ═══
    -- These strategies defend position — even unprofitable is acceptable
    WHEN d.strategy_id IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE')
      AND d.ads_orders_8w = 0 AND d.ads_clicks_8w >= d.th_min_clicks
      AND d.ads_clicks_recent_5d > 0
      AND d.th_negate_roas <= -999 THEN 'KEEP'  -- Don't negate brand terms, keep defending
    WHEN d.strategy_id IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE')
      AND COALESCE(d.ads_weighted_net_roas, d.ads_net_roas_8w) >= d.th_profitable_roas THEN 'KEEP'

    -- ═══ CATEGORY_CONQUEST / COMPETITOR_CONQUEST: aggressive thresholds ═══
    WHEN d.strategy_id IN ('CATEGORY_CONQUEST', 'COMPETITOR_CONQUEST')
      AND d.ads_orders_8w = 0 AND d.ads_clicks_8w >= d.th_min_clicks
      AND d.ads_clicks_recent_5d > 0 THEN 'STOP_TERM'
    WHEN d.strategy_id IN ('CATEGORY_CONQUEST', 'COMPETITOR_CONQUEST')
      AND COALESCE(d.ads_weighted_net_roas, d.ads_net_roas_8w) >= d.th_profitable_roas THEN 'KEEP'
    WHEN d.strategy_id IN ('CATEGORY_CONQUEST', 'COMPETITOR_CONQUEST')
      AND d.ads_net_roas_8w < d.th_negate_roas
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0 THEN 'STOP_TERM'

    -- ═══ GENERAL LOGIC (HUNTER, LOW_COST_DISCOVERY, others) ═══
    -- Ignore BRAND_DEFENSE and PRODUCT_DEFENSE for existing actions
    WHEN d.strategy_id IN ('PRODUCT_DEFENSE', 'BRAND_DEFENSE') THEN 'MONITOR'

    -- Wasted: 0 orders + 0 SQP organic + enough clicks + still active
    WHEN d.ads_orders_8w = 0 AND d.sqp_organic_units_8w = 0
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0 THEN 'STOP_TERM'

    -- This campaign has 0 orders but OTHER campaigns sell → consolidate
    -- Guard: require min_clicks so we don't negate a keyword we just started testing
    WHEN d.ads_orders_8w = 0 AND d.xc_selling_campaigns > 0
      AND d.ads_clicks_8w >= d.th_min_clicks THEN 'NEGATE_TERM'

    -- Nobody sells this term and significant spend → negate everywhere
    WHEN d.ads_orders_8w = 0 AND d.xc_selling_campaigns = 0
      AND d.xc_spend_8w >= d.th_negate_spend AND d.ads_clicks_recent_5d > 0 THEN 'NEGATE_TERM'

    -- Promote to exact (hunter/discovery with consistent conversions)
    -- Guard: MUST have SQP search volume (if no SQP volume, keyword may not be worth exact targeting)
    WHEN d.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
      AND d.ads_orders_8w >= CAST(d.th_promote_min_orders AS INT64)
      AND d.ads_net_roas_8w >= d.th_promote_min_roas
      AND NOT d.already_in_exact_boost
      AND d.sqp_amazon_search_volume_8w >= d.th_promote_min_sqp_vol THEN 'PROMOTE_TO_EXACT'

    -- Profitable
    WHEN COALESCE(d.ads_weighted_net_roas, d.ads_net_roas_8w) >= d.th_profitable_roas THEN 'KEEP'

    -- Marginally unprofitable but organic halo justifies
    WHEN COALESCE(d.ads_weighted_net_roas, d.ads_net_roas_8w) < d.th_profitable_roas AND d.sqp_organic_units_8w >= 2
      AND SAFE_DIVIDE(d.sqp_orders_8w * d.margin_per_unit, NULLIF(d.ads_spend_8w, 0)) >= 0.8 THEN 'KEEP'

    -- Heavy loss + still active → stop
    WHEN d.ads_net_roas_8w < d.th_negate_roas
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0 THEN 'STOP_TERM'

    ELSE 'MONITOR'
  END as action,

  -- ─── Target Action (bid decisions at TARGET KEYWORD level) ───
  -- This is what you actually change in Amazon: increase/decrease bid on the target.
  -- One decision per campaign × targeting — dashboard should GROUP BY targeting.
  -- Uses target_weighted_net_roas (recent-biased, target-level aggregated) when available.
  CASE
    WHEN d.recommendation_type = 'OPPORTUNITY' THEN NULL
    
    -- Ignore BRAND_DEFENSE and PRODUCT_DEFENSE for existing target actions
    WHEN d.strategy_id IN ('PRODUCT_DEFENSE', 'BRAND_DEFENSE') THEN 'MONITOR_TARGET'

    WHEN d.target_clicks_8w < d.th_min_clicks THEN 'MONITOR_TARGET'
    -- STOP_TARGET: all terms under target have 0 orders + enough clicks → entire target is bad
    WHEN d.target_orders_8w = 0 AND d.target_clicks_8w >= d.th_min_clicks
      AND d.target_clicks_recent_5d > 0 THEN 'STOP_TARGET'
    WHEN COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w) >= d.th_scale_up_roas AND d.target_orders_8w >= 2 THEN 'INCREASE_BID'
    WHEN COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w) >= d.th_profitable_roas AND d.target_orders_8w >= 2 THEN 'INCREASE_BID'
    WHEN COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w) < d.th_reduce_bid_roas AND d.target_orders_8w > 0 THEN 'REDUCE_BID'
    WHEN d.target_orders_8w > 0 THEN 'KEEP_TARGET'
    ELSE 'MONITOR_TARGET'
  END as target_action,

  -- ─── Target Decision Trace (mirrors target_action logic step-by-step) ───
  CASE
    WHEN d.recommendation_type = 'OPPORTUNITY' THEN NULL
    ELSE CONCAT('[',
      '{"id":"tgt_clicks","label":"Target Clicks 8w","rule":"≥ ',
        CAST(CAST(d.th_min_clicks AS INT64) AS STRING),
        '","pass":', IF(COALESCE(d.target_clicks_8w, 0) >= d.th_min_clicks, 'true', 'false'),
        ',"value":"', CAST(COALESCE(d.target_clicks_8w, 0) AS STRING), '"},',
      '{"id":"tgt_orders","label":"Target Orders 8w","rule":"≥ 2","pass":',
        IF(COALESCE(d.target_orders_8w, 0) >= 2, 'true', 'false'),
        ',"value":"', CAST(COALESCE(d.target_orders_8w, 0) AS STRING), '"},',
      '{"id":"tgt_roas","label":"Target ROAS (weighted)","rule":"≥ ',
        CAST(ROUND(d.th_profitable_roas, 2) AS STRING),
        '","pass":', IF(COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w, 0) >= d.th_profitable_roas, 'true', 'false'),
        ',"value":"', CAST(ROUND(COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w, 0), 2) AS STRING), '"},',
      '{"id":"tgt_spend","label":"Target Spend 8w","rule":"context","pass":true,"value":"$',
        CAST(ROUND(COALESCE(d.target_spend_8w, 0), 2) AS STRING), '"}',
    ']')
  END as target_decision_trace,

  -- ─── Recommendation Object (what the primary action applies to) ───
  CASE
    WHEN d.recommendation_type = 'OPPORTUNITY' THEN 'TERM'
    -- Bid-level actions apply to the target keyword
    WHEN d.target_clicks_8w < d.th_min_clicks THEN 'TERM'
    WHEN d.target_orders_8w = 0 AND d.target_clicks_8w >= d.th_min_clicks
      AND d.target_clicks_recent_5d > 0 THEN 'TARGET'
    WHEN d.target_net_roas_8w >= d.th_scale_up_roas AND d.target_orders_8w >= 2 THEN 'TARGET'
    WHEN d.target_net_roas_8w >= d.th_profitable_roas AND d.target_orders_8w >= 2 THEN 'TARGET'
    WHEN d.target_net_roas_8w < d.th_reduce_bid_roas AND d.target_orders_8w > 0 THEN 'TARGET'
    ELSE 'TERM'
  END as recommendation_object,

  -- ─── Recommended Bid (graduated based on target_net_roas_8w) ───
  -- Uses current_bid from bulksheet as base, applies ROAS-graduated multiplier,
  -- caps increases at margin × 0.5, floors decreases at $0.10
  ROUND(CASE
    WHEN d.recommendation_type = 'OPPORTUNITY' THEN NULL
    WHEN d.current_bid IS NULL THEN NULL
    -- Target has 0 orders + enough clicks + still active → reduce 30%
    WHEN d.target_orders_8w = 0 AND d.target_clicks_8w >= d.th_min_clicks
      AND d.target_clicks_recent_5d > 0
      THEN GREATEST(d.current_bid * 0.70, 0.10)
    -- SCALE_UP tier: ROAS ≥ 5x → +40%
    WHEN COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w) >= 5.0 AND d.target_orders_8w >= 2
      THEN LEAST(d.current_bid * 1.40, GREATEST(d.margin_per_unit * 0.5, 0.30))
    -- SCALE_UP tier: ROAS ≥ 3x → +30%
    WHEN COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w) >= 3.0 AND d.target_orders_8w >= 2
      THEN LEAST(d.current_bid * 1.30, GREATEST(d.margin_per_unit * 0.5, 0.30))
    -- INCREASE tier: ROAS ≥ 2x → +20%
    WHEN COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w) >= 2.0 AND d.target_orders_8w >= 2
      THEN LEAST(d.current_bid * 1.20, GREATEST(d.margin_per_unit * 0.5, 0.30))
    -- INCREASE tier: ROAS ≥ 1.5x → +10%
    WHEN COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w) >= 1.5 AND d.target_orders_8w >= 2
      THEN LEAST(d.current_bid * 1.10, GREATEST(d.margin_per_unit * 0.5, 0.30))
    -- REDUCE tier: ROAS < 0.3 → -35%
    WHEN COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w) < 0.3 AND d.target_orders_8w > 0
      THEN GREATEST(d.current_bid * 0.65, 0.10)
    -- REDUCE tier: ROAS < 0.5 → -25%
    WHEN COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w) < 0.5 AND d.target_orders_8w > 0
      THEN GREATEST(d.current_bid * 0.75, 0.10)
    -- REDUCE tier: ROAS < 0.7 → -15%
    WHEN COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w) < 0.7 AND d.target_orders_8w > 0
      THEN GREATEST(d.current_bid * 0.85, 0.10)
    -- Sufficient data but no bid action needed
    ELSE NULL
  END, 2) as recommended_bid,

  -- ─── Bid Change % ───
  ROUND(CASE
    WHEN d.recommendation_type = 'OPPORTUNITY' THEN NULL
    WHEN d.current_bid IS NULL OR d.current_bid = 0 THEN NULL
    WHEN d.target_orders_8w = 0 AND d.target_clicks_8w >= d.th_min_clicks
      AND d.target_clicks_recent_5d > 0 THEN -30
    WHEN COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w) >= 5.0 AND d.target_orders_8w >= 2 THEN 40
    WHEN COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w) >= 3.0 AND d.target_orders_8w >= 2 THEN 30
    WHEN COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w) >= 2.0 AND d.target_orders_8w >= 2 THEN 20
    WHEN COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w) >= 1.5 AND d.target_orders_8w >= 2 THEN 10
    WHEN COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w) < 0.3 AND d.target_orders_8w > 0 THEN -35
    WHEN COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w) < 0.5 AND d.target_orders_8w > 0 THEN -25
    WHEN COALESCE(d.target_weighted_net_roas, d.target_net_roas_8w) < 0.7 AND d.target_orders_8w > 0 THEN -15
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

    -- Negate: this campaign doesn't sell but others do
    WHEN d.ads_orders_8w = 0 AND d.xc_selling_campaigns > 0
      AND d.ads_clicks_8w >= d.th_min_clicks
      THEN GREATEST(d.ads_spend_8w * 3.0, 1.0)

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

    -- Heavy loss
    WHEN COALESCE(d.ads_weighted_net_roas, d.ads_net_roas_8w) < d.th_negate_roas AND d.ads_clicks_8w >= d.th_min_clicks
      THEN d.ads_spend_8w * 5.0

    -- Reduce bid: loss amount
    WHEN COALESCE(d.ads_weighted_net_roas, d.ads_net_roas_8w) < d.th_reduce_bid_roas AND d.ads_orders_8w > 0
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
            WHEN d.ads_orders_8w = 0 AND d.xc_selling_campaigns > 0 AND d.ads_clicks_8w >= d.th_min_clicks
              THEN CONCAT(' xc_selling=', CAST(d.xc_selling_campaigns AS STRING), ' [OTHER_SELLS => NEGATE]')
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
            WHEN COALESCE(d.ads_weighted_net_roas, d.ads_net_roas_8w) >= d.th_profitable_roas
              THEN ' [KEEP]'
            WHEN d.ads_net_roas_8w < d.th_negate_roas AND d.ads_clicks_recent_5d > 0
              THEN ' [HEAVY_LOSS => STOP]'
            WHEN d.ads_net_roas_8w < d.th_reduce_bid_roas
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
                   ' on $', CAST(ROUND(d.ads_spend_8w, 0) AS STRING), ' spend. Stop exact.')
    WHEN d.strategy_id = 'EXACT_BOOST' AND d.ads_net_roas_8w < d.th_reduce_bid_roas AND d.ads_clicks_recent_5d > 0
      THEN CONCAT('Boosted keyword marginal: Net ROAS ', CAST(d.ads_net_roas_8w AS STRING), '. Reduce bid ~30%.')

    -- BRAND_DEFENSE / PRODUCT_DEFENSE special handling
    WHEN d.strategy_id IN ('BRAND_DEFENSE', 'PRODUCT_DEFENSE') AND d.ads_orders_8w = 0 AND d.th_negate_roas <= -999
      THEN CONCAT('Defending "', d.search_term, '" — ', CAST(d.ads_clicks_8w AS STRING),
                   ' clicks, 0 orders. Reduce bid but keep defending (', d.strategy_id, ').')

    -- STOP: wasted spend
    WHEN d.ads_orders_8w = 0 AND d.sqp_organic_units_8w = 0
      AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0
      THEN CONCAT(CAST(d.ads_clicks_8w AS STRING), ' clicks(8w) on "', d.search_term,
                   '" with zero orders. Still receiving clicks (', CAST(d.ads_clicks_recent_5d AS STRING), ' in 5d).',
                   CASE WHEN d.hero_asin IS NOT NULL AND NOT d.is_hero_match
                        THEN CONCAT(' [WRONG ASIN: switch to ', COALESCE(d.hero_product_name, ''), ']') ELSE '' END)

    -- NEGATE: this campaign doesn't sell but others do
    WHEN d.ads_orders_8w = 0 AND d.xc_selling_campaigns > 0 AND d.ads_clicks_8w >= d.th_min_clicks
      THEN CONCAT('$', CAST(ROUND(d.ads_spend_8w, 0) AS STRING), ' spent in ',
                   COALESCE(d.campaign_type, 'this'), ' campaign, 0 orders. ',
                   'Term sells in ', CAST(d.xc_selling_campaigns AS STRING), ' other campaign(s) (',
                   CAST(d.xc_orders_8w AS STRING), ' total orders). Remove from this campaign.')

    -- NEGATE: nobody sells
    WHEN d.ads_orders_8w = 0 AND d.xc_selling_campaigns = 0 AND d.xc_spend_8w >= d.th_negate_spend
      THEN CONCAT('$', CAST(ROUND(d.xc_spend_8w, 0) AS STRING), ' total spend across ',
                   CAST(d.xc_campaign_count AS STRING), ' campaigns, 0 orders anywhere. Negate everywhere.')

    -- PROMOTE (with SQP volume check)
    WHEN d.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
      AND d.ads_orders_8w >= CAST(d.th_promote_min_orders AS INT64)
      AND d.ads_net_roas_8w >= d.th_promote_min_roas AND NOT d.already_in_exact_boost
      AND d.sqp_amazon_search_volume_8w >= d.th_promote_min_sqp_vol
      THEN CONCAT('"', d.search_term, '" converts in ', COALESCE(d.campaign_type, 'broad/auto'), ' (',
                   CAST(d.ads_orders_8w AS STRING), ' Orders(8w), Net ROAS ', CAST(d.ads_net_roas_8w AS STRING),
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
      THEN CONCAT('Strong ROAS ', CAST(d.ads_net_roas_8w AS STRING), ', ',
                   CAST(d.ads_orders_8w AS STRING), ' orders in EXACT_BOOST. Profit $',
                   CAST(ROUND(COALESCE(d.ads_net_profit_8w, 0), 0) AS STRING), '. Increase budget/bid.')

    -- INCREASE_BID (HUNTER/LOW_COST strong targets)
    WHEN d.strategy_id IN ('HUNTER', 'LOW_COST_DISCOVERY')
      AND d.ads_orders_8w >= 2 AND d.ads_net_roas_8w >= d.th_scale_up_roas
      THEN CONCAT('Target performing well: ', CAST(d.ads_orders_8w AS STRING),
                   ' orders, ROAS ', CAST(d.ads_net_roas_8w AS STRING),
                   '. Increase bid to capture more volume.')

    -- KEEP: profitable
    WHEN COALESCE(d.ads_weighted_net_roas, d.ads_net_roas_8w) >= d.th_profitable_roas
      THEN CONCAT('Profitable: $', CAST(ROUND(COALESCE(d.ads_net_profit_8w, 0), 0) AS STRING),
                   ' net profit(8w) on $', CAST(ROUND(d.ads_spend_8w, 0) AS STRING),
                   ' (Net ROAS ', CAST(d.ads_net_roas_8w AS STRING), '). Keep.')

    -- KEEP: halo
    WHEN COALESCE(d.ads_weighted_net_roas, d.ads_net_roas_8w) < d.th_profitable_roas AND d.sqp_organic_units_8w >= 2
      THEN CONCAT('Ads marginal (ROAS ', CAST(d.ads_net_roas_8w AS STRING),
                   ') but ', CAST(d.sqp_organic_units_8w AS STRING),
                   ' organic orders — halo effect justifies ad spend.')

    -- STOP: heavy loss
    WHEN COALESCE(d.ads_weighted_net_roas, d.ads_net_roas_8w) < d.th_negate_roas AND d.ads_clicks_8w >= d.th_min_clicks AND d.ads_clicks_recent_5d > 0
      THEN CONCAT('Losing $', CAST(ROUND(ABS(COALESCE(d.ads_net_profit_8w, 0)), 0) AS STRING),
                   ' on ', CAST(d.ads_clicks_8w AS STRING), ' clicks (Net ROAS ',
                   CAST(d.ads_net_roas_8w AS STRING), '). Still active.')

    -- REDUCE_BID
    WHEN d.ads_net_roas_8w < d.th_reduce_bid_roas AND d.ads_clicks_8w >= 15
      THEN CONCAT('Net ROAS ', CAST(d.ads_net_roas_8w AS STRING),
                   ' — slightly unprofitable. Reduce bid ~30%.')

    -- MONITOR fallback
    ELSE CONCAT(CAST(d.ads_clicks_8w AS STRING), ' clicks, ', CAST(d.ads_orders_8w AS STRING),
                ' orders (ROAS ', CAST(COALESCE(d.ads_net_roas_8w, 0) AS STRING), '). Monitoring.')
  END as reason

FROM coach_data d;
