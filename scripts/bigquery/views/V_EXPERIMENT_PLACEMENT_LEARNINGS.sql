-- =============================================
-- OI Database Project - V_EXPERIMENT_PLACEMENT_LEARNINGS View
-- =============================================
--
-- Purpose: Learn which ad format (SP / SB Video / SB Store) and placement
--          (Top of Search / Rest of Search / Detail Page) combinations
--          perform best for each strategy template.
--
--          Aggregates placement-level performance across all experiments
--          within a strategy, so you can answer:
--          "Should EXACT_BOOST use SP TOS or SB Video?"
--
-- Grain:   One row per strategy + ad_format + placement
--
-- Source:  V_CAMPAIGN_PLACEMENT_REPORT (granular: TOS, ROS, Detail Page)
--          + DIM_EXPERIMENT_CAMPAIGN (for campaign names / ad_format derivation)
--          + campaign_source in placement report (SP vs SB)
--
-- Dependencies:
--   DIM_EXPERIMENT, DIM_EXPERIMENT_CAMPAIGN, DIM_STRATEGY_TEMPLATE,
--   V_CAMPAIGN_PLACEMENT_REPORT
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_EXPERIMENT_PLACEMENT_LEARNINGS`
AS
WITH experiment_placement_raw AS (
  SELECT
    e.experiment_id,
    e.experiment_name,
    e.strategy_id,
    e.status as experiment_status,
    e.start_date,
    COALESCE(e.end_date, CURRENT_DATE()) as effective_end_date,
    ec.campaign_id,
    ec.campaign_name,
    pr.campaign_source as campaign_type,
    CASE
      WHEN pr.campaign_source = 'SP' THEN 'SP'
      WHEN UPPER(ec.campaign_name) LIKE '%VIDEO%' THEN 'SB_VIDEO'
      WHEN UPPER(ec.campaign_name) LIKE '%STORE%' THEN 'SB_STORE'
      ELSE 'SB_OTHER'
    END as ad_format,
    pr.placement,
    pr.report_date,
    pr.impressions,
    pr.clicks,
    pr.cost,
    pr.orders,
    pr.units,
    pr.sales,
    pr.orders_same_sku,
    pr.sales_same_sku
  FROM `onyga-482313.OI.DIM_EXPERIMENT` e
  JOIN `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
    ON e.experiment_id = ec.experiment_id
  JOIN `onyga-482313.OI.V_CAMPAIGN_PLACEMENT_REPORT` pr
    ON ec.campaign_id = pr.campaign_id
    AND pr.report_date >= e.start_date
    AND pr.report_date <= COALESCE(e.end_date, CURRENT_DATE())
  WHERE e.status IN ('ACTIVE', 'COMPLETED')
),

-- Aggregate by strategy + ad_format + placement
strategy_placement AS (
  SELECT
    r.strategy_id,
    r.ad_format,
    r.placement,
    COUNT(DISTINCT r.experiment_id) as experiment_count,
    COUNT(DISTINCT r.campaign_id) as campaign_count,
    COUNT(DISTINCT r.report_date) as days_of_data,
    SUM(r.impressions) as total_impressions,
    SUM(r.clicks) as total_clicks,
    SUM(r.orders) as total_orders,
    SUM(r.units) as total_units,
    ROUND(SUM(r.cost), 2) as total_cost,
    ROUND(SUM(r.sales), 2) as total_sales,
    SUM(r.orders_same_sku) as total_orders_same_sku,
    ROUND(SUM(r.sales_same_sku), 2) as total_sales_same_sku
  FROM experiment_placement_raw r
  GROUP BY 1, 2, 3
),

-- Total per strategy (for cost share calculations)
strategy_total AS (
  SELECT
    strategy_id,
    SUM(total_cost) as strategy_total_cost,
    SUM(total_sales) as strategy_total_sales,
    SUM(total_orders) as strategy_total_orders
  FROM strategy_placement
  GROUP BY 1
),

-- Total per strategy + ad_format (for within-format share)
strategy_format_total AS (
  SELECT
    strategy_id,
    ad_format,
    SUM(total_cost) as format_total_cost,
    SUM(total_sales) as format_total_sales
  FROM strategy_placement
  GROUP BY 1, 2
)

SELECT
  -- Keys
  CONCAT(COALESCE(sp.strategy_id, 'NONE'), '|', sp.ad_format, '|', sp.placement) as row_key,

  -- Strategy
  sp.strategy_id,
  st.strategy_name,
  st.recommended_campaign_type as strategy_campaign_type,

  -- Placement dimensions
  sp.ad_format,
  sp.placement,

  -- Data coverage
  sp.experiment_count,
  sp.campaign_count,
  sp.days_of_data,

  -- Volume metrics
  sp.total_impressions,
  sp.total_clicks,
  sp.total_orders,
  sp.total_units,
  sp.total_cost,
  sp.total_sales,
  sp.total_orders_same_sku,
  sp.total_sales_same_sku,

  -- Efficiency metrics
  ROUND(SAFE_DIVIDE(sp.total_sales, NULLIF(sp.total_cost, 0)), 2) as roas,
  ROUND(SAFE_DIVIDE(sp.total_sales_same_sku, NULLIF(sp.total_cost, 0)), 2) as roas_same_sku,
  ROUND(SAFE_DIVIDE(sp.total_cost, NULLIF(sp.total_clicks, 0)), 2) as cpc,
  ROUND(SAFE_DIVIDE(sp.total_clicks, NULLIF(sp.total_impressions, 0)) * 100, 2) as ctr_pct,
  ROUND(SAFE_DIVIDE(sp.total_orders, NULLIF(sp.total_clicks, 0)) * 100, 2) as conversion_rate_pct,

  -- Cost share within strategy
  ROUND(SAFE_DIVIDE(sp.total_cost, NULLIF(stot.strategy_total_cost, 0)) * 100, 1) as cost_share_of_strategy_pct,
  ROUND(SAFE_DIVIDE(sp.total_sales, NULLIF(stot.strategy_total_sales, 0)) * 100, 1) as sales_share_of_strategy_pct,
  ROUND(SAFE_DIVIDE(sp.total_orders, NULLIF(stot.strategy_total_orders, 0)) * 100, 1) as orders_share_of_strategy_pct,

  -- Cost share within ad_format
  ROUND(SAFE_DIVIDE(sp.total_cost, NULLIF(sft.format_total_cost, 0)) * 100, 1) as placement_cost_share_within_format_pct,

  -- Rank by ROAS within strategy (1 = best performing combo)
  ROW_NUMBER() OVER (
    PARTITION BY sp.strategy_id
    ORDER BY SAFE_DIVIDE(sp.total_sales, NULLIF(sp.total_cost, 0)) DESC
  ) as roas_rank_in_strategy,

  -- Rank by orders within strategy (1 = highest volume combo)
  ROW_NUMBER() OVER (
    PARTITION BY sp.strategy_id
    ORDER BY sp.total_orders DESC
  ) as orders_rank_in_strategy

FROM strategy_placement sp
LEFT JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st
  ON sp.strategy_id = st.strategy_id
LEFT JOIN strategy_total stot
  ON sp.strategy_id = stot.strategy_id
LEFT JOIN strategy_format_total sft
  ON sp.strategy_id = sft.strategy_id AND sp.ad_format = sft.ad_format;
