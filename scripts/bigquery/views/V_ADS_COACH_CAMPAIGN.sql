-- =============================================
-- OI Database Project - V_ADS_COACH_CAMPAIGN View
-- =============================================
--
-- Purpose: Per campaign: aggregated term actions → campaign-level action.
--          Dashboard reads this to show "what to do per campaign."
--
-- Dependencies: FACT_ADS_COACH_ACTIONS
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_COACH_CAMPAIGN`
AS
WITH

term_data AS (
  SELECT * FROM `onyga-482313.OI.FACT_ADS_COACH_ACTIONS`
),

-- Pre-aggregate top negate terms per campaign
negate_ranked AS (
  SELECT campaign_id, search_term, ads_spend_4w, priority_score,
    ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY priority_score DESC) as rn
  FROM term_data WHERE action_type = 'TERM' AND action = 'NEGATE'
),
negate_top AS (
  SELECT campaign_id,
    STRING_AGG(CONCAT(search_term, ' ($', CAST(ROUND(ads_spend_4w, 0) AS STRING), ')'), ', ' ORDER BY rn) as top_negate_terms
  FROM negate_ranked WHERE rn <= 5
  GROUP BY campaign_id
),

-- Pre-aggregate top scale terms per campaign
scale_ranked AS (
  SELECT campaign_id, search_term, net_roas_4w, priority_score,
    ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY priority_score DESC) as rn
  FROM term_data WHERE action_type = 'TARGET' AND action = 'SCALE_UP'
),
scale_top AS (
  SELECT campaign_id,
    STRING_AGG(CONCAT(search_term, ' (ROAS ', CAST(ROUND(COALESCE(net_roas_4w, 0), 1) AS STRING), ')'), ', ' ORDER BY rn) as top_scale_terms
  FROM scale_ranked WHERE rn <= 5
  GROUP BY campaign_id
),

campaign_agg AS (
  SELECT
    td.campaign_id,
    td.campaign_name,
    td.campaign_type,
    td.experiment_id,
    td.experiment_name,
    td.strategy_id,
    td.strategy_name,
    td.experiment_status,
    ANY_VALUE(dc.state) as campaign_state,
    ANY_VALUE(td.asin) as asin,
    ANY_VALUE(td.product_short_name) as product_short_name,

    -- Total metrics
    COUNT(DISTINCT search_term) as total_terms,
    ROUND(SUM(ads_spend_4w), 2) as total_spend_4w,
    SUM(ads_orders_4w) as total_orders_4w,
    SUM(ads_clicks_4w) as total_clicks_4w,
    ROUND(SUM(ads_sales_4w), 2) as total_sales_4w,
    ROUND(SUM(net_profit_4w), 2) as total_net_profit_4w,
    ROUND(SAFE_DIVIDE(SUM(ads_orders_4w * margin_per_unit), NULLIF(SUM(ads_spend_4w), 0)), 2) as campaign_net_roas_4w,
    ROUND(SAFE_DIVIDE(SUM(ads_spend_4w), NULLIF(SUM(ads_clicks_4w), 0)), 2) as campaign_avg_cpc_4w,
    ROUND(SAFE_DIVIDE(SUM(ads_orders_4w), NULLIF(SUM(ads_clicks_4w), 0)) * 100, 2) as campaign_cvr_pct_4w,

    -- SQP metrics
    SUM(sqp_orders_4w) as total_sqp_orders_4w,

    -- Search-term action counts
    COUNTIF(action_type = 'TERM' AND action = 'NEGATE') as terms_negate,
    COUNTIF(action_type = 'TERM' AND action = 'STOP') as terms_stop,
    COUNTIF(action_type = 'TERM' AND action = 'PROMOTE_TO_EXACT') as terms_promote,
    COUNTIF(action_type = 'TERM' AND action = 'KEEP') as terms_keep,
    COUNTIF(action_type = 'TERM' AND action = 'START') as terms_start,
    COUNTIF(action_type = 'TERM' AND action = 'MONITOR') as terms_monitor,

    -- Target-level action counts (distinct per targeting keyword)
    COUNT(DISTINCT CASE WHEN action_type = 'TARGET' AND action = 'REDUCE_BID' THEN targeting END) as targets_reduce,
    COUNT(DISTINCT CASE WHEN action_type = 'TARGET' AND action = 'INCREASE_BID' THEN targeting END) as targets_increase,
    COUNT(DISTINCT CASE WHEN action_type = 'TARGET' AND action = 'SCALE_UP' THEN targeting END) as targets_scale,

    -- Spend by action category (search-term level)
    ROUND(SUM(CASE WHEN action_type = 'TERM' AND action = 'NEGATE' THEN ads_spend_4w ELSE 0 END), 2) as spend_on_negate_terms,
    ROUND(SUM(CASE WHEN action_type = 'TERM' AND action = 'STOP' THEN ads_spend_4w ELSE 0 END), 2) as spend_on_stop_terms,
    ROUND(SUM(CASE WHEN action_type = 'TERM' AND action = 'KEEP' THEN ads_spend_4w ELSE 0 END), 2) as spend_on_keep_terms,

    -- Aggregated target metrics
    ROUND(MAX(target_net_roas_8w), 2) as best_target_roas,
    MAX(target_orders_8w) as best_target_orders,

    -- SQP organic (from FACT_ADS_COACH_ACTIONS)
    SUM(COALESCE(sqp_orders_4w, 0)) as total_sqp_organic_units_4w,

    -- Hero mismatch aggregation
    COUNTIF(action_type = 'HERO' AND action = 'SWITCH_HERO') as terms_hero_mismatch,
    ROUND(SUM(CASE WHEN action_type = 'HERO' AND action = 'SWITCH_HERO' THEN ads_spend_4w ELSE 0 END), 2) as spend_on_wrong_hero,

    -- Urgency
    ROUND(SUM(priority_score), 0) as total_priority_score

  FROM term_data td
  LEFT JOIN `onyga-482313.OI.DIM_CAMPAIGN` dc ON td.campaign_id = dc.campaign_id
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
)

SELECT
  c.*,

  -- Top terms
  COALESCE(nt.top_negate_terms, '') as top_negate_terms,
  COALESCE(st.top_scale_terms, '') as top_scale_terms,

  -- Campaign-level action
  CASE
    -- 🚫 PAUSED: campaign not active — no actions needed
    WHEN UPPER(c.campaign_state) != 'ENABLED' AND c.campaign_state IS NOT NULL
      THEN 'CAMPAIGN_PAUSED'
    WHEN (terms_negate + terms_stop) >= 3 AND spend_on_negate_terms >= 50
      THEN 'CLEAN_UP'
    WHEN campaign_net_roas_4w < 0.5 AND total_spend_4w >= 50
      THEN 'REDUCE_BUDGET'
    WHEN targets_scale >= 1 AND campaign_net_roas_4w >= 2.0
      THEN 'INCREASE_BUDGET'
    WHEN campaign_net_roas_4w >= 1.5 AND total_orders_4w >= 10
      THEN 'SCALE'
    WHEN campaign_net_roas_4w >= 1.0
      THEN 'MAINTAIN'
    WHEN campaign_net_roas_4w < 1.0 AND total_spend_4w >= 30
      THEN 'REDUCE_BUDGET'
    ELSE 'REVIEW'
  END as campaign_action,

  ROUND(spend_on_negate_terms / 4.0, 2) as est_weekly_savings,

  -- Legacy compat aliases
  targets_reduce as terms_reduce,
  targets_scale as terms_scale,
  ROUND(0, 2) as spend_on_reduce_terms,
  ROUND(0, 2) as spend_on_scale_terms,

  CONCAT(
    CASE WHEN terms_negate > 0
      THEN CONCAT('Negate ', CAST(terms_negate AS STRING), ' terms (saving ~$', CAST(ROUND(spend_on_negate_terms / 4.0, 0) AS STRING), '/wk). ')
      ELSE '' END,
    CASE WHEN terms_stop > 0
      THEN CONCAT('Stop ', CAST(terms_stop AS STRING), ' terms. ')
      ELSE '' END,
    CASE WHEN targets_reduce > 0
      THEN CONCAT('Reduce bids on ', CAST(targets_reduce AS STRING), ' targets. ')
      ELSE '' END,
    CASE WHEN targets_scale > 0
      THEN CONCAT('Scale ', CAST(targets_scale AS STRING), ' targets. ')
      ELSE '' END,
    CASE WHEN targets_increase > 0
      THEN CONCAT('Increase bid on ', CAST(targets_increase AS STRING), ' targets. ')
      ELSE '' END,
    CASE WHEN terms_keep > 0
      THEN CONCAT(CAST(terms_keep AS STRING), ' terms profitable. ')
      ELSE '' END,
    CASE WHEN terms_promote > 0
      THEN CONCAT('Promote ', CAST(terms_promote AS STRING), ' terms to exact. ')
      ELSE '' END,
    CAST(terms_monitor AS STRING), ' terms monitoring.'
  ) as action_summary,

  -- Placement action: based on TOS bid adjustment
  CASE
    WHEN c.campaign_net_roas_4w >= 2.0 AND c.total_orders_4w >= 5
      THEN 'BOOST_TOS'
    WHEN c.campaign_net_roas_4w < 0.7 AND c.total_spend_4w >= 30
      THEN 'REDUCE_TOS'
    ELSE 'MAINTAIN'
  END as placement_action

FROM campaign_agg c
LEFT JOIN negate_top nt ON c.campaign_id = nt.campaign_id
LEFT JOIN scale_top st ON c.campaign_id = st.campaign_id;
