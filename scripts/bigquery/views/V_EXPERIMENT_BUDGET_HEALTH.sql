-- =============================================
-- OI Database Project - V_EXPERIMENT_BUDGET_HEALTH View
-- =============================================
--
-- Purpose: 3-tier experiment monitoring dashboard.
--          Shows net profit AND net ROAS for each tier.
--          No auto budget_action -- user decides manually.
--
-- Grain: One row per experiment_id
--
-- Tiers (each has net_profit and net_roas):
--   Tier 0 (Parent): ALL siblings in product family - total units * margin - ALL family ad spend
--   Tier 1 (ASIN):   total ASIN units * margin - ALL ad spend on ASIN (cross-experiment)
--   Tier 2 (Ads):    this experiment's ad units * margin - this experiment's ad spend
--   Tier 3 (SQP):    SQP purchases on experiment terms * margin - this experiment's ad spend
--
-- Parent-family: advertising one child drives sales across siblings.
-- Tier 0 captures the true family-level impact of ad spend.
--
-- Net ROAS: > 1.0 = profitable, = 1.0 = break-even, < 1.0 = losing money
--
-- Dependencies:
--   DIM_EXPERIMENT, DIM_EXPERIMENT_CAMPAIGN, FACT_EXPERIMENT_DAILY,
--   FACT_AMAZON_ADS, FACT_SEARCH_QUERY, FACT_AMAZON_PERFORMANCE_DAILY,
--   DIM_PRODUCT, DIM_COSTS_HISTORY, DIM_STRATEGY_TEMPLATE,
--   DIM_STRATEGY_CAMPAIGN_TEMPLATE, DIM_US_HOLIDAYS
--
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_EXPERIMENT_BUDGET_HEALTH`
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

-- =============================================
-- Peak season detection
-- =============================================
current_season AS (
  SELECT
    COUNTIF(CURRENT_DATE() BETWEEN pre_season_start AND holiday_date) > 0 as is_peak_season,
    MAX(CASE WHEN CURRENT_DATE() BETWEEN pre_season_start AND holiday_date THEN holiday_name END) as current_holiday
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
),

-- =============================================
-- Active experiments with metadata
-- =============================================
active_experiments AS (
  SELECT
    e.experiment_id,
    e.experiment_name,
    e.strategy_id,
    e.start_date,
    e.season_context,
    DATE_DIFF(CURRENT_DATE(), e.start_date, DAY) as days_running,
    st.strategy_name,
    st.recommended_daily_budget as template_daily_budget
  FROM `onyga-482313.OI.DIM_EXPERIMENT` e
  LEFT JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st ON e.strategy_id = st.strategy_id
  WHERE e.status = 'ACTIVE'
),

-- =============================================
-- Expected daily budget per experiment from DIM_STRATEGY_CAMPAIGN_TEMPLATE
-- =============================================
expected_budgets AS (
  SELECT
    ae.experiment_id,
    SUM(ct.daily_budget) as expected_total_daily_budget,
    SUM(CASE WHEN ct.is_required THEN ct.daily_budget ELSE 0 END) as expected_required_daily_budget,
    COUNT(*) as template_campaign_count
  FROM active_experiments ae
  JOIN `onyga-482313.OI.DIM_STRATEGY_CAMPAIGN_TEMPLATE` ct ON ae.strategy_id = ct.strategy_id
  GROUP BY 1
),

-- =============================================
-- Which ASINs does each experiment target? (from ad data)
-- =============================================
experiment_asins AS (
  SELECT DISTINCT ec.experiment_id, fa.advertised_asins as asin
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN active_experiments ae ON ec.experiment_id = ae.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa ON ec.campaign_id = fa.campaign_id
  WHERE fa.advertised_asins IS NOT NULL
),

-- =============================================
-- TIER 1: ASIN-level total performance (deduped across experiments)
-- Total units come from Business Reports (via FACT_EXPERIMENT_DAILY)
-- Ad spend includes ALL campaigns on the ASIN, not just this experiment
-- =============================================
asin_perf_deduped AS (
  SELECT
    ea.experiment_id,
    SUM(dd.daily_units * ue.margin_per_unit) as asin_gross_margin,
    SUM(dd.daily_units) as asin_total_units
  FROM experiment_asins ea
  JOIN active_experiments ae ON ea.experiment_id = ae.experiment_id
  JOIN (
    SELECT asin, snapshot_date, MAX(performance_total_units) as daily_units
    FROM `onyga-482313.OI.FACT_EXPERIMENT_DAILY`
    GROUP BY 1, 2
  ) dd ON ea.asin = dd.asin AND dd.snapshot_date >= ae.start_date
  JOIN asin_unit_economics ue ON ea.asin = ue.asin
  GROUP BY 1
),

asin_all_ad_spend AS (
  SELECT
    ea.experiment_id,
    SUM(fa.Ads_cost) as asin_total_ad_spend,
    COUNT(DISTINCT fa.campaign_id) as campaigns_on_asin
  FROM experiment_asins ea
  JOIN active_experiments ae ON ea.experiment_id = ae.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON ea.asin = fa.advertised_asins
    AND fa.date >= ae.start_date
  GROUP BY 1
),

-- =============================================
-- TIER 0 (PARENT FAMILY): Cross-sibling impact
-- Ad spend on one child drives sales across ALL siblings in the parent family.
-- =============================================
experiment_parent AS (
  SELECT DISTINCT
    ea.experiment_id,
    ue.parent_name
  FROM experiment_asins ea
  JOIN asin_unit_economics ue ON ea.asin = ue.asin
  WHERE ue.parent_name IS NOT NULL
),

family_members AS (
  SELECT DISTINCT
    ep.experiment_id,
    ep.parent_name,
    ue.asin as family_asin,
    ue.product_short_name as family_product,
    COALESCE(ue.margin_per_unit, 0) as margin_per_unit
  FROM experiment_parent ep
  JOIN asin_unit_economics ue ON ep.parent_name = ue.parent_name
  WHERE ue.asin IS NOT NULL AND ue.asin != 'UNKNOWN'
),

family_units AS (
  SELECT
    fm.experiment_id,
    fm.parent_name,
    SUM(fp.PURCHASED_UNITS) as family_units,
    SUM(fp.PURCHASED_UNITS * fm.margin_per_unit) as family_gross_margin
  FROM family_members fm
  JOIN active_experiments ae ON fm.experiment_id = ae.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY` fp
    ON fm.family_asin = fp.PURCHASED_ASIN
    AND fp.DATE >= ae.start_date
  GROUP BY 1, 2
),

family_ad_spend_deduped AS (
  SELECT DISTINCT
    fm.experiment_id,
    fm.parent_name,
    fa.campaign_id,
    fa.date,
    fa.advertised_asins,
    fa.search_term,
    fa.Ads_cost,
    fa.Ads_orders as ad_orders
  FROM family_members fm
  JOIN active_experiments ae ON fm.experiment_id = ae.experiment_id
  JOIN `onyga-482313.OI.FACT_AMAZON_ADS` fa
    ON REGEXP_CONTAINS(fa.advertised_asins, fm.family_asin)
    AND fa.date >= ae.start_date
  WHERE fa.advertised_asins IS NOT NULL
),

family_ad_spend AS (
  SELECT
    experiment_id,
    parent_name,
    SUM(Ads_cost) as family_ad_cost,
    SUM(ad_orders) as family_ad_orders
  FROM family_ad_spend_deduped
  GROUP BY 1, 2
),

parent_family_perf AS (
  SELECT
    fm_agg.experiment_id,
    fm_agg.parent_name,
    fm_agg.parent_child_count,
    fm_agg.parent_children,
    COALESCE(fu.family_units, 0) as parent_family_units,
    ROUND(COALESCE(fu.family_gross_margin, 0), 2) as parent_family_gross_margin,
    ROUND(COALESCE(fas.family_ad_cost, 0), 2) as parent_family_ad_cost,
    COALESCE(fas.family_ad_orders, 0) as parent_family_ad_orders,
    ROUND(COALESCE(fu.family_gross_margin, 0) - COALESCE(fas.family_ad_cost, 0), 2) as parent_family_net_profit,
    ROUND(SAFE_DIVIDE(fu.family_gross_margin, NULLIF(fas.family_ad_cost, 0)), 2) as parent_family_net_roas
  FROM (
    SELECT experiment_id, parent_name,
      COUNT(DISTINCT family_asin) as parent_child_count,
      STRING_AGG(DISTINCT family_product, ', ' ORDER BY family_product) as parent_children
    FROM family_members
    GROUP BY 1, 2
  ) fm_agg
  LEFT JOIN family_units fu ON fm_agg.experiment_id = fu.experiment_id AND fm_agg.parent_name = fu.parent_name
  LEFT JOIN family_ad_spend fas ON fm_agg.experiment_id = fas.experiment_id AND fm_agg.parent_name = fas.parent_name
),

-- =============================================
-- TIER 2: Cumulative experiment metrics from FACT_EXPERIMENT_DAILY
-- Ad-attributed units only, per experiment
-- =============================================
experiment_cumulative AS (
  SELECT
    fed.experiment_id,
    SUM(fed.ads_exp_cost) as cum_ad_spend,
    SUM(fed.ads_exp_orders) as cum_ads_orders,
    SUM(fed.ads_exp_units) as cum_ads_units,
    SUM(fed.ads_exp_sales) as cum_ads_sales,
    SUM(fed.performance_total_orders) as cum_total_orders,
    SUM(fed.performance_total_units) as cum_total_units,
    SUM(fed.performance_total_sales) as cum_total_sales,
    SUM(fed.performance_organic_units) as cum_organic_units,
    SUM(fed.performance_sessions) as cum_sessions,
    SUM(fed.ads_exp_units * ue.margin_per_unit) as cum_ads_only_net_revenue,
    AVG(ue.margin_per_unit) as avg_margin_per_unit,
    COUNT(DISTINCT fed.snapshot_date) as days_with_data,
    COUNT(DISTINCT fed.asin) as tracked_asins
  FROM `onyga-482313.OI.FACT_EXPERIMENT_DAILY` fed
  JOIN active_experiments ae ON fed.experiment_id = ae.experiment_id
  JOIN asin_unit_economics ue ON fed.asin = ue.asin
  GROUP BY 1
),

-- =============================================
-- TIER 3: SQP metrics per search term (organic + ads, term-level attribution)
-- =============================================
sqp_experiment_metrics AS (
  SELECT
    ec.experiment_id,
    SUM(fsq.conversions) as sqp_total_purchases,
    SUM(fsq.conversions * ue.margin_per_unit) as sqp_net_revenue,
    COUNT(DISTINCT fsq.query_text) as sqp_matched_terms,
    COUNT(DISTINCT fsq.week_end_date) as sqp_weeks
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN active_experiments ae ON ec.experiment_id = ae.experiment_id
  JOIN (
    SELECT DISTINCT campaign_id, search_term, advertised_asins
    FROM `onyga-482313.OI.FACT_AMAZON_ADS`
    WHERE search_term IS NOT NULL AND search_term != ''
  ) fa ON ec.campaign_id = fa.campaign_id
  JOIN `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
    ON LOWER(fa.search_term) = LOWER(fsq.query_text)
    AND fa.advertised_asins = fsq.ASIN
    AND fsq.data_source = 'SQP'
    AND fsq.week_end_date >= ae.start_date
  JOIN asin_unit_economics ue ON fsq.ASIN = ue.asin
  GROUP BY 1
),

-- =============================================
-- Weekly trend: this week vs last week
-- =============================================
weekly_trend AS (
  SELECT
    fed.experiment_id,
    SUM(CASE WHEN fed.snapshot_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) THEN fed.ads_exp_cost ELSE 0 END) as week_ad_spend,
    SUM(CASE WHEN fed.snapshot_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) THEN fed.ads_exp_orders ELSE 0 END) as week_ads_orders,
    SUM(CASE WHEN fed.snapshot_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) THEN fed.performance_total_units ELSE 0 END) as week_total_units,
    SUM(CASE WHEN fed.snapshot_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) THEN fed.ads_exp_units * ue.margin_per_unit ELSE 0 END) as week_ads_net_revenue,
    SUM(CASE WHEN fed.snapshot_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY) AND DATE_SUB(CURRENT_DATE(), INTERVAL 8 DAY) THEN fed.ads_exp_cost ELSE 0 END) as prev_week_ad_spend,
    SUM(CASE WHEN fed.snapshot_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY) AND DATE_SUB(CURRENT_DATE(), INTERVAL 8 DAY) THEN fed.ads_exp_orders ELSE 0 END) as prev_week_ads_orders,
    SUM(CASE WHEN fed.snapshot_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY) AND DATE_SUB(CURRENT_DATE(), INTERVAL 8 DAY) THEN fed.performance_total_units ELSE 0 END) as prev_week_total_units,
    SUM(CASE WHEN fed.snapshot_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY) AND DATE_SUB(CURRENT_DATE(), INTERVAL 8 DAY) THEN fed.ads_exp_units * ue.margin_per_unit ELSE 0 END) as prev_week_ads_net_revenue
  FROM `onyga-482313.OI.FACT_EXPERIMENT_DAILY` fed
  JOIN active_experiments ae ON fed.experiment_id = ae.experiment_id
  JOIN asin_unit_economics ue ON fed.asin = ue.asin
  WHERE fed.snapshot_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
  GROUP BY 1
)

SELECT
  -- =============================================
  -- Experiment identity
  -- =============================================
  ae.experiment_id,
  ae.experiment_name,
  ae.strategy_id,
  ae.strategy_name,
  ae.start_date,
  ae.days_running,
  ae.season_context,
  cs.is_peak_season,
  cs.current_holiday,

  -- ASIN context
  ec.tracked_asins,
  ROUND(ec.avg_margin_per_unit, 2) as avg_margin_per_unit,

  -- =============================================
  -- TIER 0: PARENT FAMILY (cross-sibling impact)
  -- Ad spend on one child drives sales across ALL siblings
  -- =============================================
  pfp.parent_name,
  pfp.parent_child_count,
  pfp.parent_children,
  pfp.parent_family_units,
  pfp.parent_family_gross_margin,
  pfp.parent_family_ad_cost,
  pfp.parent_family_ad_orders,
  pfp.parent_family_net_profit,
  pfp.parent_family_net_roas,

  -- =============================================
  -- Budget pacing
  -- =============================================
  ROUND(SAFE_DIVIDE(ec.cum_ad_spend, NULLIF(ec.days_with_data, 0)), 2) as actual_daily_spend,
  ROUND(eb.expected_total_daily_budget, 2) as expected_daily_budget,
  ROUND(SAFE_DIVIDE(
    SAFE_DIVIDE(ec.cum_ad_spend, NULLIF(ec.days_with_data, 0)),
    NULLIF(eb.expected_total_daily_budget, 0)
  ) * 100, 1) as budget_utilization_pct,
  ROUND(ec.cum_ad_spend, 2) as cumulative_ad_spend,
  ec.days_with_data,

  -- =============================================
  -- TIER 1: ASIN LEVEL (total picture -- all units, all ad spend on ASIN)
  -- Cross-experiment: same ASIN values for all experiments targeting it
  -- =============================================
  apd.asin_total_units,
  ROUND(apd.asin_gross_margin, 2) as asin_gross_margin,
  ROUND(aas.asin_total_ad_spend, 2) as asin_total_ad_spend,
  ROUND(apd.asin_gross_margin - COALESCE(aas.asin_total_ad_spend, 0), 2) as asin_net_profit,
  ROUND(SAFE_DIVIDE(apd.asin_gross_margin, NULLIF(aas.asin_total_ad_spend, 0)), 2) as asin_net_roas,
  aas.campaigns_on_asin,

  -- =============================================
  -- TIER 2: ADS ONLY (this experiment's direct ad performance)
  -- Directly attributable to this experiment's campaigns
  -- =============================================
  ec.cum_ads_units as ads_units,
  ec.cum_ads_orders as ads_orders,
  ROUND(ec.cum_ads_only_net_revenue, 2) as ads_gross_margin,
  ROUND(ec.cum_ads_only_net_revenue - COALESCE(ec.cum_ad_spend, 0), 2) as ads_net_profit,
  ROUND(SAFE_DIVIDE(ec.cum_ads_only_net_revenue, NULLIF(ec.cum_ad_spend, 0)), 2) as ads_net_roas,

  -- Traditional ROAS (revenue / cost, for reference)
  ROUND(SAFE_DIVIDE(ec.cum_ads_sales, NULLIF(ec.cum_ad_spend, 0)), 2) as traditional_roas,

  -- =============================================
  -- TIER 3: SQP (this experiment's search terms, organic + ads)
  -- Best attribution: per search term, captures organic halo, ~2 week lag
  -- =============================================
  sqp.sqp_total_purchases as sqp_purchases,
  sqp.sqp_matched_terms,
  sqp.sqp_weeks,
  ROUND(sqp.sqp_net_revenue, 2) as sqp_gross_margin,
  ROUND(COALESCE(sqp.sqp_net_revenue, 0) - COALESCE(ec.cum_ad_spend, 0), 2) as sqp_net_profit,
  ROUND(SAFE_DIVIDE(sqp.sqp_net_revenue, NULLIF(ec.cum_ad_spend, 0)), 2) as sqp_net_roas,

  -- =============================================
  -- Volume metrics
  -- =============================================
  ec.cum_total_units as total_units_sold,
  ec.cum_ads_units as ads_units_sold,
  ec.cum_total_units - ec.cum_ads_units as organic_units_sold,
  ec.cum_total_orders as total_orders,
  ec.cum_sessions as total_sessions,

  -- =============================================
  -- Weekly trend (Tier 2 basis)
  -- =============================================
  ROUND(wt.week_ad_spend, 2) as this_week_ad_spend,
  wt.week_ads_orders as this_week_ads_orders,
  wt.week_total_units as this_week_total_units,
  ROUND(SAFE_DIVIDE(wt.week_ads_net_revenue, NULLIF(wt.week_ad_spend, 0)), 2) as this_week_ads_net_roas,
  ROUND(wt.prev_week_ad_spend, 2) as prev_week_ad_spend,
  wt.prev_week_ads_orders as prev_week_ads_orders,
  wt.prev_week_total_units as prev_week_total_units,
  ROUND(SAFE_DIVIDE(wt.prev_week_ads_net_revenue, NULLIF(wt.prev_week_ad_spend, 0)), 2) as prev_week_ads_net_roas,

  CASE
    WHEN wt.prev_week_ad_spend = 0 OR wt.prev_week_ad_spend IS NULL THEN 'INSUFFICIENT_DATA'
    WHEN SAFE_DIVIDE(wt.week_ads_net_revenue, NULLIF(wt.week_ad_spend, 0))
       > SAFE_DIVIDE(wt.prev_week_ads_net_revenue, NULLIF(wt.prev_week_ad_spend, 0)) * 1.1 THEN 'IMPROVING'
    WHEN SAFE_DIVIDE(wt.week_ads_net_revenue, NULLIF(wt.week_ad_spend, 0))
       < SAFE_DIVIDE(wt.prev_week_ads_net_revenue, NULLIF(wt.prev_week_ad_spend, 0)) * 0.9 THEN 'DECLINING'
    ELSE 'STABLE'
  END as ads_roas_trend,

  -- =============================================
  -- Data readiness indicator (replaces auto budget_action)
  -- =============================================
  CASE
    WHEN ec.days_with_data IS NULL OR ec.days_with_data = 0 THEN 'NO_DATA'
    WHEN ec.days_with_data < 7 THEN 'COLLECTING'
    WHEN sqp.sqp_weeks >= 2 THEN 'ALL_TIERS_AVAILABLE'
    WHEN ec.days_with_data >= 7 THEN 'ADS_DATA_READY'
    ELSE 'COLLECTING'
  END as data_status

FROM active_experiments ae
CROSS JOIN current_season cs
LEFT JOIN experiment_cumulative ec ON ae.experiment_id = ec.experiment_id
LEFT JOIN expected_budgets eb ON ae.experiment_id = eb.experiment_id
LEFT JOIN asin_perf_deduped apd ON ae.experiment_id = apd.experiment_id
LEFT JOIN asin_all_ad_spend aas ON ae.experiment_id = aas.experiment_id
LEFT JOIN parent_family_perf pfp ON ae.experiment_id = pfp.experiment_id
LEFT JOIN weekly_trend wt ON ae.experiment_id = wt.experiment_id
LEFT JOIN sqp_experiment_metrics sqp ON ae.experiment_id = sqp.experiment_id;
