-- =============================================
-- OI Database Project - V_EXPERIMENT_SUGGESTED_CAMPAIGNS View
-- =============================================
--
-- Purpose: Expands each experiment suggestion into specific campaigns to open.
--          Each row = one campaign you should create in Amazon Ads Console.
--
--          Combines:
--          - V_EXPERIMENT_SUGGESTIONS (which ASIN + strategy to pursue)
--          - DIM_STRATEGY_CAMPAIGN_TEMPLATE (which campaigns per strategy)
--          - V_EXPERIMENT_PLACEMENT_LEARNINGS (historical performance per format+placement)
--
-- Grain: One row per suggested_experiment_id + campaign_seq
--
-- Dependencies:
--   V_EXPERIMENT_SUGGESTIONS, DIM_STRATEGY_CAMPAIGN_TEMPLATE,
--   V_EXPERIMENT_PLACEMENT_LEARNINGS, DIM_PRODUCT
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_EXPERIMENT_SUGGESTED_CAMPAIGNS`
AS
WITH
-- =============================================
-- Unit economics per ASIN (for margin + net_roas display)
-- =============================================
asin_unit_economics AS (
  SELECT
    p.asin,
    p.listing_price_amount as selling_price,
    COALESCE(ch.TOTAL_COST_PER_UNIT, 0) as total_cost_per_unit,
    p.listing_price_amount - COALESCE(ch.TOTAL_COST_PER_UNIT, 0) as margin_per_unit
  FROM `onyga-482313.OI.DIM_PRODUCT` p
  LEFT JOIN (
    SELECT asin, TOTAL_COST_PER_UNIT,
      ROW_NUMBER() OVER (PARTITION BY asin ORDER BY end_date DESC) as rn
    FROM `onyga-482313.OI.DIM_COSTS_HISTORY`
  ) ch ON p.asin = ch.asin AND ch.rn = 1
  WHERE p.asin IS NOT NULL
),

suggestions AS (
  SELECT
    sug.suggested_experiment_id,
    sug.asin,
    sug.product_short_name,
    sug.suggested_strategy_id,
    sug.suggested_strategy_name,
    sug.target_experiment_segment,
    sug.priority_score,
    sug.addressable_weekly_orders,
    sug.proven_term_count,
    sug.high_volume_unproven_count,
    sug.avg_your_conversion_rate_pct,
    sug.avg_ads_conversion_rate_pct,
    sug.avg_amazon_conversion_rate_pct,
    sug.is_peak_season,
    sug.current_holiday,
    sug.reason,
    sug.asin_segment_key
  FROM `onyga-482313.OI.V_EXPERIMENT_SUGGESTIONS` sug
  WHERE sug.priority_score > 0
),

-- =============================================
-- DRAFT ASIN conclusions: proven budgets from active/completed experiments
-- =============================================
draft_conclusions AS (
  SELECT
    ac.asin,
    ac.strategy_id,
    ac.experiment_segment,
    ac.season_context,
    ac.proven_daily_budget,
    ac.ads_only_net_roas as conclusion_net_roas,
    ac.experiment_count as conclusion_experiment_count
  FROM `onyga-482313.OI.FACT_ASIN_CONCLUSIONS` ac
  WHERE ac.status = 'DRAFT'
),

-- Historical placement performance per strategy + ad_format (best placement)
placement_history AS (
  SELECT
    pl.strategy_id,
    pl.ad_format,
    SUM(pl.total_impressions) as hist_impressions,
    SUM(pl.total_clicks) as hist_clicks,
    SUM(pl.total_orders) as hist_orders,
    ROUND(SUM(pl.total_cost), 2) as hist_cost,
    ROUND(SUM(pl.total_sales), 2) as hist_sales,
    ROUND(SAFE_DIVIDE(SUM(pl.total_sales), NULLIF(SUM(pl.total_cost), 0)), 2) as hist_roas,
    ROUND(SAFE_DIVIDE(SUM(pl.total_cost), NULLIF(SUM(pl.total_clicks), 0)), 2) as hist_cpc,
    ROUND(SAFE_DIVIDE(SUM(pl.total_orders), NULLIF(SUM(pl.total_clicks), 0)) * 100, 2) as hist_conversion_rate_pct,
    MAX(pl.experiment_count) as hist_experiment_count,
    SUM(pl.days_of_data) as hist_days_of_data
  FROM `onyga-482313.OI.V_EXPERIMENT_PLACEMENT_LEARNINGS` pl
  GROUP BY pl.strategy_id, pl.ad_format
)

SELECT
  -- Keys
  CONCAT(s.suggested_experiment_id, '|', ct.campaign_seq) as row_key,
  s.asin_segment_key,

  -- Suggestion context
  s.suggested_experiment_id,
  s.asin,
  s.product_short_name,
  s.suggested_strategy_id,
  s.suggested_strategy_name,
  s.target_experiment_segment,
  s.priority_score,
  s.addressable_weekly_orders,
  s.reason,

  -- Campaign recipe (uses ENABLED conclusions when available, otherwise template defaults)
  ct.campaign_seq,
  ct.ad_format,
  ct.match_type,
  ct.bidding_strategy,
  -- Bids: use proven bids from conclusions if available, else template defaults
  ct.bid_min as bid_min,
  ct.bid_max as bid_max,
  -- Budget: use proven budget from conclusions if available, else template default
  COALESCE(dc.proven_daily_budget, ct.daily_budget) as daily_budget,
  ct.top_of_search_pct,
  ct.product_page_pct,
  ct.purpose,
  ct.is_required,
  ct.notes as campaign_notes,

  -- Confidence: HIGH if DRAFT conclusion exists with data, LOW otherwise
  CASE WHEN dc.asin IS NOT NULL THEN 'HIGH' ELSE 'LOW' END as budget_confidence,
  dc.conclusion_net_roas,
  dc.conclusion_experiment_count,

  -- Suggested campaign name (replace placeholder with product name)
  REPLACE(ct.naming_hint, '{PRODUCT}',
    UPPER(REPLACE(COALESCE(s.product_short_name, 'PRODUCT'), ' ', '_'))
  ) as suggested_campaign_name,

  -- Total daily budget for this experiment (sum of all campaigns in strategy)
  SUM(COALESCE(dc.proven_daily_budget, ct.daily_budget))
    OVER (PARTITION BY s.suggested_experiment_id) as experiment_total_daily_budget,
  -- Required-only budget
  SUM(CASE WHEN ct.is_required THEN COALESCE(dc.proven_daily_budget, ct.daily_budget) ELSE 0 END)
    OVER (PARTITION BY s.suggested_experiment_id) as experiment_required_daily_budget,
  -- Campaign count per experiment
  COUNT(*) OVER (PARTITION BY s.suggested_experiment_id) as campaigns_in_strategy,
  SUM(CASE WHEN ct.is_required THEN 1 ELSE 0 END)
    OVER (PARTITION BY s.suggested_experiment_id) as required_campaigns_in_strategy,

  -- Unit economics for this ASIN
  ROUND(ue.margin_per_unit, 2) as margin_per_unit,
  ROUND(ue.selling_price, 2) as selling_price,
  ROUND(ue.total_cost_per_unit, 2) as total_cost_per_unit,

  -- Historical placement performance for this ad_format + strategy
  ph.hist_roas,
  ph.hist_cpc,
  ph.hist_conversion_rate_pct,
  ph.hist_orders,
  ph.hist_cost,
  ph.hist_days_of_data,
  CASE
    WHEN ph.hist_orders IS NULL OR ph.hist_orders = 0 THEN 'NO_DATA'
    WHEN ph.hist_roas >= 3.0 THEN 'PROVEN_STRONG'
    WHEN ph.hist_roas >= 1.5 THEN 'PROVEN_MODERATE'
    WHEN ph.hist_roas >= 1.0 THEN 'PROVEN_WEAK'
    ELSE 'PROVEN_NEGATIVE'
  END as hist_verdict,

  -- Season adjustments (from DIM_STRATEGY_TEMPLATE seasonal multipliers)
  CASE
    WHEN s.is_peak_season THEN ROUND(ct.bid_max * COALESCE(st.peak_bid_multiplier, 1.0), 2)
    ELSE ct.bid_max
  END as season_adjusted_bid_max,
  CASE
    WHEN s.is_peak_season THEN ROUND(COALESCE(dc.proven_daily_budget, ct.daily_budget) * COALESCE(st.peak_budget_multiplier, 1.0), 2)
    ELSE COALESCE(dc.proven_daily_budget, ct.daily_budget)
  END as season_adjusted_daily_budget,
  CASE
    WHEN s.is_peak_season THEN ct.top_of_search_pct + COALESCE(st.peak_tos_add_pct, 0)
    ELSE ct.top_of_search_pct
  END as season_adjusted_tos_pct

FROM suggestions s
JOIN `onyga-482313.OI.DIM_STRATEGY_CAMPAIGN_TEMPLATE` ct
  ON s.suggested_strategy_id = ct.strategy_id
LEFT JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st
  ON s.suggested_strategy_id = st.strategy_id
LEFT JOIN placement_history ph
  ON s.suggested_strategy_id = ph.strategy_id
  AND ct.ad_format = ph.ad_format
LEFT JOIN asin_unit_economics ue
  ON s.asin = ue.asin
LEFT JOIN draft_conclusions dc
  ON s.asin = dc.asin
  AND s.suggested_strategy_id = dc.strategy_id
  AND s.target_experiment_segment = dc.experiment_segment
  AND CASE WHEN s.is_peak_season THEN 'PEAK' ELSE 'NORMAL' END = dc.season_context;
