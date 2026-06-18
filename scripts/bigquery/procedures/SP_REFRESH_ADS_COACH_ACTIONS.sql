-- =============================================
-- OI Database Project - SP_REFRESH_ADS_COACH_ACTIONS
-- =============================================
--
-- Purpose: Materializes V_ADS_COACH action rows into FACT_ADS_COACH_ACTIONS.
--          Each action type is inserted at its NATURAL GRAIN:
--            TERM   → 1 row per campaign × search_term
--            TARGET → 1 row per campaign × targeting × target_action  (GROUP BY)
--            BUDGET → 1 row per campaign × budget_action              (GROUP BY)
--            HERO   → 1 row per campaign × search_term × hero_action
--
--          base_rows is computed ONCE into a temp table, then each INSERT
--          reads from it independently — no CTE expansion, no complexity limit.
--
-- Dependencies:
--   V_ADS_COACH (master decision engine),
--   V_DIM_CAMPAIGN_CURRENT, FACT_AMAZON_ADS (4w display),
--   DIM_EXPERIMENT, DIM_EXPERIMENT_CAMPAIGN, DIM_STRATEGY_TEMPLATE,
--   DIM_PRODUCT, DIM_COSTS_HISTORY,
--   FACT_SEARCH_QUERY, V_PARENT_HERO_ASIN, DIM_KEYWORD
--
-- Called by: SP_ORCHESTRATE_DAILY_REFRESH
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_REFRESH_ADS_COACH_ACTIONS`()
BEGIN

  -- ═══════════════════════════════════════════
  -- Step 1: Build base_rows temp table (computed once)
  -- ═══════════════════════════════════════════
  CREATE TEMP TABLE _base_rows AS
  WITH
  campaign_experiment AS (
    -- One row per campaign. A campaign can map to several experiments (a current ACTIVE one plus a
    -- stale PAUSED one). Without this dedupe the downstream LEFT JOINs on campaign_id (here in
    -- `assembled` and again as top-level `ce_fb`) fan out, and SUM in Steps 4/5 double-counts
    -- clicks/orders/spend. Every multi-experiment campaign is exactly 1 ACTIVE + PAUSED, so prefer
    -- ACTIVE; latest start_date then experiment_id as a deterministic tiebreak for any future case.
    SELECT * EXCEPT(rn) FROM (
      SELECT
        ec.campaign_id,
        e.experiment_id,
        e.experiment_name,
        e.strategy_id,
        e.status as experiment_status,
        st.strategy_name,
        st.recommended_bid_min,
        st.recommended_bid_max,
        ROW_NUMBER() OVER (
          PARTITION BY ec.campaign_id
          ORDER BY IF(e.status = 'ACTIVE', 0, 1), e.start_date DESC NULLS LAST, e.experiment_id
        ) AS rn
      FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
      JOIN `onyga-482313.OI.DIM_EXPERIMENT` e ON ec.experiment_id = e.experiment_id
      LEFT JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st ON e.strategy_id = st.strategy_id
      WHERE e.status IN ('ACTIVE', 'PAUSED')
    )
    WHERE rn = 1
  ),
  asin_economics AS (
    SELECT p.asin, p.product_short_name, p.parent_name,
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
  ads_4w AS (
    SELECT
      fa.campaign_id, ANY_VALUE(fa.campaign_name HAVING MAX fa.date) as campaign_name, fa.campaign_type,
      LOWER(fa.search_term) as search_term,
      COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
      ANY_VALUE(fa.ad_group_id HAVING MAX fa.date) as ad_group_id,
      SUM(fa.Ads_cost) as ads_spend_4w,
      SUM(fa.Ads_orders) as ads_orders_4w,
      SUM(fa.Ads_units) as ads_units_4w,
      SUM(fa.Ads_clicks) as ads_clicks_4w,
      SUM(fa.Ads_impressions) as ads_impressions_4w,
      SUM(fa.Ads_sales) as ads_sales_4w,
      COUNT(DISTINCT fa.date) as ads_days_4w -- kept in CTE, dropped from output
    FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
    WHERE fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
      AND fa.search_term IS NOT NULL AND fa.search_term != ''
      AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
    GROUP BY 1, 3, 4, 5
  ),
  term_totals AS (
    SELECT
      search_term,
      SUM(ads_spend_4w) as term_spend_4w,
      SUM(ads_orders_4w) as term_orders_4w,
      SUM(ads_clicks_4w) as term_clicks_4w,
      COUNT(DISTINCT campaign_id) as term_campaign_count,
      COUNT(DISTINCT CASE WHEN ads_orders_4w > 0 THEN campaign_id END) as term_selling_campaigns,
      MAX(CASE WHEN ads_orders_4w > 0 THEN ads_orders_4w END) as best_campaign_orders
    FROM ads_4w
    GROUP BY 1
  ),
  sqp_4w AS (
    SELECT
      LOWER(fsq.query_text) as search_term,
      SUM(fsq.conversions) as sqp_orders_4w,
      SUM(fsq.TOTAL_IMPRESSIONS) as sqp_total_impressions_4w,
      AVG(fsq.show_rate_pct) as sqp_show_rate_4w
    FROM `onyga-482313.OI.FACT_SEARCH_QUERY` fsq
    WHERE fsq.data_source = 'SQP' AND fsq.week_end_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
    GROUP BY 1
  ),
  hero_lookup AS (
    SELECT
      LOWER(search_term) as search_term,
      asin as hero_asin,
      product_short_name as hero_product_name,
      ads_net_roas as hero_net_roas,
      total_orders as hero_total_orders,
      ads_ctr_pct as hero_ads_ctr_pct
    FROM `onyga-482313.OI.V_PARENT_HERO_ASIN`
    WHERE global_hero_rank = 1 AND qualifies_as_hero = TRUE
  ),
  assembled AS (
    SELECT
      a4.campaign_id,
      COALESCE(dc.campaign_name, a4.campaign_name) as campaign_name,
      a4.campaign_type, a4.search_term, a4.asin,
      CAST(a4.ad_group_id AS STRING) as ad_group_id,
      ae.product_short_name, ae.parent_name,
      ce.experiment_id, ce.experiment_name, ce.strategy_id,
      ce.strategy_name, ce.experiment_status, ce.recommended_bid_max,
      ROUND(a4.ads_spend_4w, 2) as ads_spend_4w,
      a4.ads_orders_4w, a4.ads_units_4w, a4.ads_clicks_4w, a4.ads_impressions_4w,
      ROUND(a4.ads_sales_4w, 2) as ads_sales_4w,

      ROUND(SAFE_DIVIDE(a4.ads_spend_4w, NULLIF(a4.ads_clicks_4w, 0)), 2) as ads_cpc_4w,
      ROUND(SAFE_DIVIDE(a4.ads_orders_4w, NULLIF(a4.ads_clicks_4w, 0)) * 100, 2) as ads_cvr_pct_4w,
      ROUND(
        COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a4.ads_sales_4w, NULLIF(a4.ads_orders_4w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
        * a4.ads_units_4w - a4.ads_spend_4w, 2) as net_profit_4w,
      ROUND(SAFE_DIVIDE(
        COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a4.ads_sales_4w, NULLIF(a4.ads_orders_4w, 0)) - COALESCE(ae.total_cost_per_unit, 0))
        * a4.ads_units_4w, NULLIF(a4.ads_spend_4w, 0)), 2) as net_roas_4w,
      ROUND(COALESCE(ae.margin_per_unit, SAFE_DIVIDE(a4.ads_sales_4w, NULLIF(a4.ads_orders_4w, 0)) - COALESCE(ae.total_cost_per_unit, 0)), 2) as margin_per_unit,
      tt.term_spend_4w, tt.term_orders_4w, tt.term_campaign_count, tt.term_selling_campaigns,
      ROUND(SAFE_DIVIDE(a4.ads_spend_4w, NULLIF(tt.term_spend_4w, 0)) * 100, 1) as spend_share_pct,
      ROUND(SAFE_DIVIDE(a4.ads_orders_4w, NULLIF(tt.term_orders_4w, 0)) * 100, 1) as orders_share_pct,
      COALESCE(sq4.sqp_orders_4w, 0) as sqp_orders_4w,
      ROUND(COALESCE(sq4.sqp_show_rate_4w, 0), 2) as sqp_show_rate_4w
    FROM ads_4w a4
    LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` dc ON a4.campaign_id = dc.campaign_id
    LEFT JOIN campaign_experiment ce ON a4.campaign_id = ce.campaign_id
    LEFT JOIN asin_economics ae ON a4.asin = ae.asin
    LEFT JOIN term_totals tt ON a4.search_term = tt.search_term
    LEFT JOIN sqp_4w sq4 ON a4.search_term = sq4.search_term
  )
  SELECT
    ca.campaign_id,
    COALESCE(dc_cur.campaign_name, a.campaign_name, ca.campaign_name) as campaign_name,
    COALESCE(a.campaign_type, ca.campaign_type) as campaign_type,
    dc_cur.campaign_state,
    ca.search_term,
    ca.asin,
    COALESCE(a.product_short_name, ca.product_short_name) as product_short_name,
    COALESCE(a.parent_name, ca.parent_name) as parent_name,
    COALESCE(a.experiment_id, ca.experiment_id) as experiment_id,
    COALESCE(a.experiment_name, ca.experiment_name) as experiment_name,
    COALESCE(a.strategy_id, ca.strategy_id) as strategy_id,
    COALESCE(a.strategy_name, ce_fb.strategy_name) as strategy_name,
    COALESCE(a.experiment_status, ce_fb.experiment_status) as experiment_status,
    COALESCE(a.recommended_bid_max, ce_fb.recommended_bid_max) as recommended_bid_max,
    -- 4w volume from `ca` (per-targeting). `assembled` (a) is grouped (campaign, search_term, asin)
    -- WITHOUT targeting, so a.*_4w is cross-targeting and over-counts when TARGET/BUDGET rows SUM by
    -- campaign×targeting (Step 4/5). 1w already comes from ca; this aligns 4w. impressions/sales_4w
    -- stay on `a` (not exposed on ca, not card-critical — same asin-grain bucket as net_profit_4w).
    ROUND(COALESCE(ca.ads_spend_4w, 0), 2) as ads_spend_4w,
    COALESCE(ca.ads_orders_4w, 0) as ads_orders_4w,
    COALESCE(ca.ads_units_4w, 0) as ads_units_4w,
    COALESCE(ca.ads_clicks_4w, 0) as ads_clicks_4w,
    COALESCE(a.ads_impressions_4w, 0) as ads_impressions_4w,
    ROUND(COALESCE(a.ads_sales_4w, 0), 2) as ads_sales_4w,
    a.ads_cpc_4w,
    a.ads_cvr_pct_4w,
    a.net_profit_4w,
    a.net_roas_4w,
    COALESCE(a.margin_per_unit, ca.margin_per_unit) as margin_per_unit,
    a.term_spend_4w,
    a.term_orders_4w,
    a.term_campaign_count,
    a.term_selling_campaigns,
    a.spend_share_pct,
    a.orders_share_pct,
    COALESCE(a.sqp_orders_4w, 0) as sqp_orders_4w,
    COALESCE(a.sqp_show_rate_4w, 0) as sqp_show_rate_4w,
    COALESCE(ca.hero_asin, hl.hero_asin) as hero_asin,
    COALESCE(ca.hero_product_name, hl.hero_product_name) as hero_product_name,
    hl.hero_net_roas,
    hl.hero_total_orders,
    hl.hero_ads_ctr_pct,
    COALESCE(ca.is_hero_match, FALSE) as is_hero_match,
    ca.targeting,
    ca.keyword_id,
    a.ad_group_id,
    ca.ads_signal,
    ca.target_roas,
    ca.th_scale_up_roas,
    ca.th_profitable_roas,
    ca.th_halo_roas,
    ca.th_reduce_bid_roas,
    ca.th_min_clicks,

    ca.target_net_roas_8w,
    ca.target_clicks_8w,
    ca.target_orders_8w,
    ROUND(COALESCE(ca.target_spend_8w, 0), 2) as target_spend_8w,
    ca.recommendation_object,
    ROUND(ca.current_bid, 2) as current_bid,
    ca.recommended_bid,
    ca.bid_change_pct,
    COALESCE(ca.coach_mode, 'GUARDIAN') as coach_mode,
    COALESCE(ca.active_occasion, 'NONE') as active_occasion,
    COALESCE(ca.current_phase, 'OFF_SEASON') as current_phase,
    ca.pp_days,
    ca.pp_target_net_roas,
    ca.pp_target_spend,
    ca.pp_target_orders,
    ca.tos_pct,
    ca.product_page_pct,
    ca.b2b_pct,
    ca.pre_peak_bid,
    ca.pre_peak_tos_pct,
    ca.pre_peak_pp_pct,
    ca.pre_peak_b2b_pct,
    ca.pre_peak_avg_cpc,
    ca.last_day_cpc,
    ca.current_budget,
    ca.pre_peak_budget,
    ca.recommended_budget,
    ca.pp_campaign_net_roas,
    ca.pp_campaign_spend,
    ca.pp_campaign_orders,
    ca.pp_campaign_sales,
    ca.pp_campaign_days,
    COALESCE(ca.strategic_task, 'Evaluate Search Terms') as strategic_task,
    COALESCE(dk.match_type,
      CASE 
        WHEN REGEXP_CONTAINS(COALESCE(ca.targeting, ''), r'^asin=') THEN 'PRODUCT_TARGETING'
        WHEN LOWER(COALESCE(ca.targeting, '')) IN ('close-match', 'loose-match', 'substitutes', 'complements') THEN 'PRODUCT_TARGETING'
        ELSE 'SEARCH_TERM' 
      END
    ) as match_type,
    ca.action,
    ca.priority_score,
    ca.confidence,
    ca.reason,
    ca.target_action,
    ca.target_decision_trace,
    ca.term_decision_trace,
    ca.budget_action,
    ca.camp_effective_roas,
    ca.camp_avg_daily_spend,
    ca.camp_budget_util_pct,
    -- Aggregated ROAS windows + SQP context
    ROUND(COALESCE(ca.ads_spend_3d, 0), 2) as ads_spend_3d,
    CAST(ca.ads_orders_3d AS INT64) as ads_orders_3d,
    CAST(ca.ads_units_3d AS INT64) as ads_units_3d,
    ca.ads_net_roas_3d,
    ROUND(COALESCE(ca.ads_spend_1w, 0), 2) as ads_spend_1w,
    CAST(ca.ads_orders_1w AS INT64) as ads_orders_1w,
    CAST(ca.ads_units_1w AS INT64) as ads_units_1w,
    ca.ads_clicks_1w,
    ca.ads_impressions_1w,
    ca.ads_net_roas_1w,
    ROUND(COALESCE(ca.lt_net_roas, 0), 2) as lt_net_roas,
    CAST(ca.lt_orders AS INT64) as lt_orders,
    CAST(ca.lt_units AS INT64) as lt_units,
    ROUND(COALESCE(ca.ly_net_roas, 0), 2) as ly_net_roas,
    CAST(ca.ly_orders AS INT64) as ly_orders,
    CAST(ca.ly_units AS INT64) as ly_units,
    ROUND(COALESCE(ca.ly_spend, 0), 2) as ly_spend,
    CAST(ca.ly_clicks AS INT64) as ly_clicks,
    ca.ly_cpc as ly_cpc,
    ROUND(COALESCE(ca.q4_peak_net_roas, 0), 2) as q4_peak_net_roas,
    CAST(ca.q4_peak_orders AS INT64) as q4_peak_orders,
    CAST(ca.q4_peak_units AS INT64) as q4_peak_units,
    ROUND(COALESCE(ca.q4_peak_spend, 0), 2) as q4_peak_spend,
    CAST(ca.sqp_amazon_search_volume_8w AS INT64) as sqp_amazon_search_volume_8w,
    CAST(ca.sqp_clicks_8w AS INT64) as sqp_clicks_8w,
    ROUND(ca.sqp_sales_8w, 2) as sqp_sales_8w,
    CAST(ca.sqp_orders_8w AS INT64) as sqp_orders_8w,
    ROUND(COALESCE(ca.lt_spend, 0), 2) as lt_spend,
    ca.lt_first_seen,
    ca.lt_last_seen,
    -- Hero action — only fire when hero is QUALIFIED (from hero_lookup) with proven orders
    CASE
      WHEN hl.hero_asin IS NOT NULL
        AND NOT COALESCE(ca.is_hero_match, FALSE)
        AND COALESCE(a.ads_orders_4w, 0) > 0
        AND COALESCE(hl.hero_total_orders, 0) > 0 THEN 'SWITCH_HERO'
      ELSE NULL
    END as hero_action,
    CASE
      WHEN hl.hero_asin IS NOT NULL
        AND NOT COALESCE(ca.is_hero_match, FALSE)
        AND COALESCE(a.ads_orders_4w, 0) > 0
        AND COALESCE(hl.hero_total_orders, 0) > 0
        THEN CONCAT(
          'SWITCH_HERO: You are advertising ', COALESCE(a.product_short_name, ca.product_short_name),
          ' but ', hl.hero_product_name, ' is the hero for "', ca.search_term, '".',
          ' Hero Net ROAS: ', CAST(ROUND(COALESCE(hl.hero_net_roas, 0), 1) AS STRING),
          ', Hero Orders: ', CAST(COALESCE(hl.hero_total_orders, 0) AS STRING), '.'
        )
      ELSE NULL
    END as hero_action_explanation
  FROM `onyga-482313.OI.V_ADS_COACH` ca
  LEFT JOIN `onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT` dc_cur ON ca.campaign_id = dc_cur.campaign_id
  LEFT JOIN assembled a ON ca.campaign_id = a.campaign_id AND ca.search_term = a.search_term
    -- include asin: `assembled` is (campaign, search_term, asin); without this key the join is
    -- many-to-many and SUM in Steps 4/5 double-counts clicks/orders/spend across asins.
    AND ca.asin IS NOT DISTINCT FROM a.asin
  LEFT JOIN campaign_experiment ce_fb ON ca.campaign_id = ce_fb.campaign_id
  LEFT JOIN hero_lookup hl ON ca.search_term = hl.search_term
  LEFT JOIN `onyga-482313.OI.DIM_KEYWORD` dk
    ON ca.keyword_id = dk.keyword_id AND dk.is_current = TRUE AND UPPER(dk.state) = 'ENABLED';


  -- ═══════════════════════════════════════════
  -- Step 2: Truncate target table
  -- ═══════════════════════════════════════════
  TRUNCATE TABLE `onyga-482313.OI.FACT_ADS_COACH_ACTIONS`;


  -- ═══════════════════════════════════════════
  -- Step 3: INSERT TERM actions
  -- 1 row per campaign × search_term × action
  -- ═══════════════════════════════════════════
  INSERT INTO `onyga-482313.OI.FACT_ADS_COACH_ACTIONS`
  SELECT
    campaign_id,
    ANY_VALUE(campaign_name) as campaign_name,
    ANY_VALUE(campaign_type) as campaign_type,
    ANY_VALUE(campaign_state) as campaign_state,
    search_term,
    ANY_VALUE(asin) as asin,
    ANY_VALUE(product_short_name) as product_short_name,
    ANY_VALUE(parent_name) as parent_name,
    ANY_VALUE(experiment_id) as experiment_id,
    ANY_VALUE(experiment_name) as experiment_name,
    ANY_VALUE(strategy_id) as strategy_id,
    ANY_VALUE(strategy_name) as strategy_name,
    ANY_VALUE(experiment_status) as experiment_status,
    ANY_VALUE(recommended_bid_max) as recommended_bid_max,
    ANY_VALUE(ads_spend_4w) as ads_spend_4w,
    ANY_VALUE(ads_orders_4w) as ads_orders_4w,
    ANY_VALUE(ads_units_4w) as ads_units_4w,
    ANY_VALUE(ads_clicks_4w) as ads_clicks_4w,
    ANY_VALUE(ads_impressions_4w) as ads_impressions_4w,
    ANY_VALUE(ads_clicks_1w) as ads_clicks_1w,
    ANY_VALUE(ads_impressions_1w) as ads_impressions_1w,
    ANY_VALUE(ads_sales_4w) as ads_sales_4w,
    ANY_VALUE(ads_cpc_4w) as ads_cpc_4w,
    ANY_VALUE(ads_cvr_pct_4w) as ads_cvr_pct_4w,
    ANY_VALUE(net_profit_4w) as net_profit_4w,
    ANY_VALUE(net_roas_4w) as net_roas_4w,
    ANY_VALUE(margin_per_unit) as margin_per_unit,
    ANY_VALUE(term_spend_4w) as term_spend_4w,
    ANY_VALUE(term_orders_4w) as term_orders_4w,
    ANY_VALUE(term_campaign_count) as term_campaign_count,
    ANY_VALUE(term_selling_campaigns) as term_selling_campaigns,
    ANY_VALUE(spend_share_pct) as spend_share_pct,
    ANY_VALUE(orders_share_pct) as orders_share_pct,
    ANY_VALUE(sqp_orders_4w) as sqp_orders_4w,
    ANY_VALUE(sqp_show_rate_4w) as sqp_show_rate_4w,
    ANY_VALUE(hero_asin) as hero_asin,
    ANY_VALUE(hero_product_name) as hero_product_name,
    ANY_VALUE(hero_net_roas) as hero_net_roas,
    ANY_VALUE(hero_total_orders) as hero_total_orders,
    ANY_VALUE(hero_ads_ctr_pct) as hero_ads_ctr_pct,
    ANY_VALUE(is_hero_match) as is_hero_match,
    CAST(NULL AS STRING) as targeting,
    CAST(NULL AS STRING) as keyword_id,

    ANY_VALUE(target_net_roas_8w) as target_net_roas_8w,
    ANY_VALUE(target_clicks_8w) as target_clicks_8w,
    ANY_VALUE(target_orders_8w) as target_orders_8w,
    ANY_VALUE(target_spend_8w) as target_spend_8w,
    ANY_VALUE(recommendation_object HAVING MAX priority_score) as recommendation_object,
    ANY_VALUE(current_bid) as current_bid,
    ANY_VALUE(recommended_bid) as recommended_bid,
    ANY_VALUE(bid_change_pct) as bid_change_pct,
    ANY_VALUE(coach_mode) as coach_mode,
    ANY_VALUE(active_occasion) as active_occasion,
    ANY_VALUE(current_phase) as current_phase,
    ANY_VALUE(pp_days) as pp_days,
    ANY_VALUE(pp_target_net_roas) as pp_target_net_roas,
    ANY_VALUE(pp_target_spend) as pp_target_spend,
    ANY_VALUE(pp_target_orders) as pp_target_orders,
    ANY_VALUE(tos_pct) as tos_pct,
    ANY_VALUE(product_page_pct) as product_page_pct,
    ANY_VALUE(b2b_pct) as b2b_pct,
    ANY_VALUE(pre_peak_bid) as pre_peak_bid,
    ANY_VALUE(pre_peak_tos_pct) as pre_peak_tos_pct,
    ANY_VALUE(pre_peak_pp_pct) as pre_peak_pp_pct,
    ANY_VALUE(pre_peak_b2b_pct) as pre_peak_b2b_pct,
    ANY_VALUE(pre_peak_avg_cpc) as pre_peak_avg_cpc,
    ANY_VALUE(last_day_cpc) as last_day_cpc,
    ANY_VALUE(current_budget) as current_budget,
    ANY_VALUE(pre_peak_budget) as pre_peak_budget,
    ANY_VALUE(recommended_budget) as recommended_budget,
    ANY_VALUE(pp_campaign_net_roas) as pp_campaign_net_roas,
    ANY_VALUE(pp_campaign_spend) as pp_campaign_spend,
    ANY_VALUE(pp_campaign_orders) as pp_campaign_orders,
    ANY_VALUE(pp_campaign_sales) as pp_campaign_sales,
    ANY_VALUE(pp_campaign_days) as pp_campaign_days,
    ANY_VALUE(strategic_task) as strategic_task,
    ANY_VALUE(match_type) as match_type,
    MAX(priority_score) as priority_score,
    ANY_VALUE(confidence HAVING MAX priority_score) as confidence,
    'TERM' as action_type,
    action,
    ANY_VALUE(reason) as action_explanation,
    -- TERM trace: passthrough from V_ADS_COACH (co-located with action logic)
    ANY_VALUE(term_decision_trace) as decision_trace,
    -- Branch ID derived from the trace's pass/fail pattern
    CONCAT('B-', SUBSTR(FORMAT('%x', ABS(FARM_FINGERPRINT(
      ANY_VALUE(term_decision_trace)
    ))), 1, 6)) as decision_branch_id,
    CONCAT('TRM-', SUBSTR(FORMAT('%x', ABS(FARM_FINGERPRINT(
      CONCAT(COALESCE(campaign_id, ''), '|', COALESCE(search_term, ''), '|', action)
    ))), 1, 12)) as action_id,
    ANY_VALUE(ads_signal) as ads_signal,
    -- ROAS windows + SQP context
    ANY_VALUE(ads_net_roas_3d) as ads_net_roas_3d,
    ANY_VALUE(ads_orders_3d) as ads_orders_3d,
    ANY_VALUE(ads_units_3d) as ads_units_3d,
    ANY_VALUE(ads_net_roas_1w) as ads_net_roas_1w,
    ANY_VALUE(ads_orders_1w) as ads_orders_1w,
    ANY_VALUE(ads_units_1w) as ads_units_1w,
    ANY_VALUE(ly_net_roas) as ly_net_roas,
    ANY_VALUE(ly_orders) as ly_orders,
    ANY_VALUE(ly_units) as ly_units,
    ANY_VALUE(q4_peak_net_roas) as q4_peak_net_roas,
    ANY_VALUE(q4_peak_orders) as q4_peak_orders,
    ANY_VALUE(q4_peak_units) as q4_peak_units,
    ANY_VALUE(sqp_amazon_search_volume_8w) as sqp_amazon_search_volume_8w,
    ANY_VALUE(sqp_clicks_8w) as sqp_clicks_8w,
    ANY_VALUE(sqp_sales_8w) as sqp_sales_8w,
    ANY_VALUE(sqp_orders_8w) as sqp_orders_8w,
    ANY_VALUE(lt_net_roas) as lt_net_roas,
    ANY_VALUE(lt_orders) as lt_orders,
    ANY_VALUE(lt_units) as lt_units,
    ANY_VALUE(lt_first_seen) as lt_first_seen,
    ANY_VALUE(lt_last_seen) as lt_last_seen,
    ROUND(ANY_VALUE(ads_spend_1w), 2) as ads_spend_1w,
    ROUND(SAFE_DIVIDE(ANY_VALUE(ads_spend_1w), NULLIF(ANY_VALUE(ads_clicks_1w), 0)), 2) as ads_cpc_1w,
    -- Peak-window evidence (per-term rows share the same ly_/q4_ values → ANY_VALUE)
    ROUND(COALESCE(ANY_VALUE(ly_spend), 0), 2) as ly_spend,
    CAST(ANY_VALUE(ly_clicks) AS INT64) as ly_clicks,
    ANY_VALUE(ly_cpc) as ly_cpc,
    ROUND(COALESCE(ANY_VALUE(q4_peak_spend), 0), 2) as q4_peak_spend,
    ANY_VALUE(ad_group_id) as ad_group_id
  FROM _base_rows
  WHERE action IS NOT NULL
  GROUP BY campaign_id, search_term, action;



  -- ═══════════════════════════════════════════
  -- Step 4: INSERT TARGET actions
  -- 1 row per campaign × targeting × target_action (GROUP BY)
  -- ═══════════════════════════════════════════
  INSERT INTO `onyga-482313.OI.FACT_ADS_COACH_ACTIONS`
  SELECT
    campaign_id,
    ANY_VALUE(campaign_name) as campaign_name,
    ANY_VALUE(campaign_type) as campaign_type,
    ANY_VALUE(campaign_state) as campaign_state,
    -- TARGET rows represent keyword-level decisions, not search-term decisions
    CAST(NULL AS STRING) as search_term,
    ANY_VALUE(asin) as asin,
    ANY_VALUE(product_short_name) as product_short_name,
    ANY_VALUE(parent_name) as parent_name,
    ANY_VALUE(experiment_id) as experiment_id,
    ANY_VALUE(experiment_name) as experiment_name,
    ANY_VALUE(strategy_id) as strategy_id,
    ANY_VALUE(strategy_name) as strategy_name,
    ANY_VALUE(experiment_status) as experiment_status,
    ANY_VALUE(recommended_bid_max) as recommended_bid_max,
    ROUND(SUM(ads_spend_4w), 2) as ads_spend_4w,
    SUM(ads_orders_4w) as ads_orders_4w,
    SUM(ads_units_4w) as ads_units_4w,
    SUM(ads_clicks_4w) as ads_clicks_4w,
    SUM(ads_impressions_4w) as ads_impressions_4w,
    SUM(ads_clicks_1w) as ads_clicks_1w,
    SUM(ads_impressions_1w) as ads_impressions_1w,
    ROUND(SUM(ads_sales_4w), 2) as ads_sales_4w,
    ROUND(SAFE_DIVIDE(SUM(ads_spend_4w), NULLIF(SUM(ads_clicks_4w), 0)), 2) as ads_cpc_4w,
    ROUND(SAFE_DIVIDE(SUM(ads_orders_4w), NULLIF(SUM(ads_clicks_4w), 0)) * 100, 2) as ads_cvr_pct_4w,
    -- Net profit from the corrected per-targeting volume (consistent with net_roas_4w and the
    -- displayed orders/spend). SUM(net_profit_4w) would carry `assembled`'s cross-targeting value
    -- and overstate the "$/wk" opportunity shown on cards.
    ROUND(SUM(COALESCE(margin_per_unit, 0) * ads_units_4w) - SUM(ads_spend_4w), 2) as net_profit_4w,
    ROUND(SAFE_DIVIDE(SUM(COALESCE(margin_per_unit, 0) * ads_units_4w), NULLIF(SUM(ads_spend_4w), 0)), 2) as net_roas_4w,
    ANY_VALUE(margin_per_unit) as margin_per_unit,
    ANY_VALUE(term_spend_4w HAVING MAX ads_spend_4w) as term_spend_4w,
    ANY_VALUE(term_orders_4w HAVING MAX ads_spend_4w) as term_orders_4w,
    ANY_VALUE(term_campaign_count HAVING MAX ads_spend_4w) as term_campaign_count,
    ANY_VALUE(term_selling_campaigns HAVING MAX ads_spend_4w) as term_selling_campaigns,
    ANY_VALUE(spend_share_pct HAVING MAX ads_spend_4w) as spend_share_pct,
    ANY_VALUE(orders_share_pct HAVING MAX ads_spend_4w) as orders_share_pct,
    ANY_VALUE(sqp_orders_4w HAVING MAX ads_spend_4w) as sqp_orders_4w,
    ANY_VALUE(sqp_show_rate_4w HAVING MAX ads_spend_4w) as sqp_show_rate_4w,
    ANY_VALUE(hero_asin) as hero_asin,
    ANY_VALUE(hero_product_name) as hero_product_name,
    ANY_VALUE(hero_net_roas) as hero_net_roas,
    ANY_VALUE(hero_total_orders) as hero_total_orders,
    ANY_VALUE(hero_ads_ctr_pct) as hero_ads_ctr_pct,
    ANY_VALUE(is_hero_match) as is_hero_match,
    targeting,
    ANY_VALUE(keyword_id) as keyword_id,

    ANY_VALUE(target_net_roas_8w) as target_net_roas_8w,
    ANY_VALUE(target_clicks_8w) as target_clicks_8w,
    ANY_VALUE(target_orders_8w) as target_orders_8w,
    ANY_VALUE(target_spend_8w) as target_spend_8w,
    ANY_VALUE(recommendation_object HAVING MAX priority_score) as recommendation_object,
    ANY_VALUE(current_bid) as current_bid,
    ANY_VALUE(recommended_bid) as recommended_bid,
    ANY_VALUE(bid_change_pct) as bid_change_pct,
    ANY_VALUE(coach_mode) as coach_mode,
    ANY_VALUE(active_occasion) as active_occasion,
    ANY_VALUE(current_phase) as current_phase,
    ANY_VALUE(pp_days) as pp_days,
    ANY_VALUE(pp_target_net_roas) as pp_target_net_roas,
    ANY_VALUE(pp_target_spend) as pp_target_spend,
    ANY_VALUE(pp_target_orders) as pp_target_orders,
    ANY_VALUE(tos_pct) as tos_pct,
    ANY_VALUE(product_page_pct) as product_page_pct,
    ANY_VALUE(b2b_pct) as b2b_pct,
    ANY_VALUE(pre_peak_bid) as pre_peak_bid,
    ANY_VALUE(pre_peak_tos_pct) as pre_peak_tos_pct,
    ANY_VALUE(pre_peak_pp_pct) as pre_peak_pp_pct,
    ANY_VALUE(pre_peak_b2b_pct) as pre_peak_b2b_pct,
    ANY_VALUE(pre_peak_avg_cpc) as pre_peak_avg_cpc,
    ANY_VALUE(last_day_cpc) as last_day_cpc,
    ANY_VALUE(current_budget) as current_budget,
    ANY_VALUE(pre_peak_budget) as pre_peak_budget,
    ANY_VALUE(recommended_budget) as recommended_budget,
    ANY_VALUE(pp_campaign_net_roas) as pp_campaign_net_roas,
    ANY_VALUE(pp_campaign_spend) as pp_campaign_spend,
    ANY_VALUE(pp_campaign_orders) as pp_campaign_orders,
    ANY_VALUE(pp_campaign_sales) as pp_campaign_sales,
    ANY_VALUE(pp_campaign_days) as pp_campaign_days,
    -- Derive strategic_task from the actual target_action (not inherited from term rows)
    CASE
      WHEN target_action = 'SWITCH_HERO' THEN 'CORRECT_HEROES'
      WHEN target_action = 'STOP_TARGET' THEN 'ELIMINATE_WASTE'
      WHEN target_action IN ('INCREASE_BID', 'SCALE_UP') THEN 'SCALE_WINNERS'
      WHEN target_action = 'REDUCE_BID' THEN 'OPTIMIZE_BIDS'
      WHEN target_action = 'ENABLE_CAMPAIGN' THEN 'PROTECT_TERMS'
      WHEN target_action = 'COOLDOWN_MONITOR' THEN 'MONITOR_PERFORMANCE'
      WHEN target_action IN ('REDUCE_TO_BASELINE', 'RESTORE_PRE_PEAK') THEN 'NORMALIZE_BIDS'
      WHEN target_action = 'WARMUP_MONITOR' THEN 'MAINTAIN'
      ELSE 'MAINTAIN'
    END as strategic_task,
    ANY_VALUE(match_type) as match_type,
    MAX(priority_score) as priority_score,
    ANY_VALUE(confidence HAVING MAX priority_score) as confidence,
    'TARGET' as action_type,
    target_action as action,
    ANY_VALUE(
      CASE
        WHEN target_action IN ('INCREASE_BID', 'REDUCE_BID', 'SCALE_UP') 
          THEN CONCAT(
            IF(target_action='REDUCE_BID', 'Decrease', 'Increase'), ' bid', 
            IF(bid_change_pct IS NOT NULL, CONCAT(' by ', CAST(ROUND(ABS(bid_change_pct), 0) AS STRING), '%'), ''),
            IF(current_bid IS NOT NULL AND recommended_bid IS NOT NULL, 
               CONCAT(' from $', CAST(ROUND(current_bid, 2) AS STRING), ' to $', CAST(ROUND(recommended_bid, 2) AS STRING), '.'), '.')
          )
        WHEN target_action = 'CAMPAIGN_PAUSED' THEN 'Campaign is paused — no bid changes will take effect.'
        WHEN target_action = 'TARGET_PAUSED' THEN 'Target keyword is paused/archived — no bid changes will take effect.'
        WHEN target_action = 'STOP_TARGET' THEN 'Target is losing heavily or wasting spend. Stop/pause targeting.'
        WHEN target_action = 'COOLDOWN_MONITOR'
          THEN CONCAT('Post-peak performing well (Ads ROAS ≥ 0.8). No bid change needed.',
            IF(pp_target_net_roas IS NOT NULL, CONCAT(' PP ROAS: ', CAST(ROUND(pp_target_net_roas, 2) AS STRING)), ''))
        WHEN target_action = 'REDUCE_TO_BASELINE'
          THEN CONCAT('Post-peak marginal (Ads ROAS 0.6–0.8). Gradual bid reduction.',
            IF(current_bid IS NOT NULL AND recommended_bid IS NOT NULL, 
               CONCAT(' $', CAST(ROUND(current_bid, 2) AS STRING), ' → $', CAST(ROUND(recommended_bid, 2) AS STRING)), ''))
        WHEN target_action = 'RESTORE_PRE_PEAK'
          THEN CONCAT('Post-peak losing (Ads ROAS < 0.6). Restore pre-peak bid.',
            IF(current_bid IS NOT NULL AND recommended_bid IS NOT NULL, 
               CONCAT(' $', CAST(ROUND(current_bid, 2) AS STRING), ' → $', CAST(ROUND(recommended_bid, 2) AS STRING)), ''),
            IF(pre_peak_bid IS NOT NULL, CONCAT(' (pre-peak: $', CAST(ROUND(pre_peak_bid, 2) AS STRING), ')'), ''))
        WHEN target_action = 'KEEP_TARGET' THEN 'Target is profitable. Keep current bid.'
        WHEN target_action = 'WARMUP_MONITOR'
          THEN COALESCE(
            REGEXP_EXTRACT(target_decision_trace, r'"id":"summary"[^}]*"value":"([^"]*)"'),
            'New campaign warming up. Algorithm needs 14 days to find optimal placements.'
          )
        WHEN target_action = 'MONITOR_TARGET'
          -- Extract the narrative summary pill from the decision trace (generated by V_ADS_COACH)
          THEN COALESCE(
            REGEXP_EXTRACT(target_decision_trace, r'"id":"summary"[^}]*"value":"([^"]*)"'),
            'Monitoring target performance.'
          )
      END
    ) as action_explanation,
    -- TARGET trace: passthrough from V_ADS_COACH (co-located with target_action logic)
    -- Uses target_roas (mode-aware), not raw target_net_roas_8w
    ANY_VALUE(target_decision_trace) as decision_trace,
    -- Branch ID derived from the trace's logic (stripping dynamic values and string formatting)
    CONCAT('B-', SUBSTR(FORMAT('%x', ABS(FARM_FINGERPRINT(
      REGEXP_REPLACE(
        REGEXP_REPLACE(ANY_VALUE(target_decision_trace), r',"value":"?[^"}]+"?', ''),
        r',\{"id":"summary"[^}]+\}', ''
      )
    ))), 1, 6)) as decision_branch_id,
    CONCAT('TGT-', SUBSTR(FORMAT('%x', ABS(FARM_FINGERPRINT(
      CONCAT(COALESCE(campaign_id, ''), '|', COALESCE(targeting, ''), '|', target_action)
    ))), 1, 12)) as action_id,
    -- Target-level signal derived from target metrics (not inherited from random term rows)
    CASE
      WHEN ANY_VALUE(target_clicks_8w) < ANY_VALUE(th_min_clicks) THEN 'INSUFFICIENT_DATA'
      WHEN ANY_VALUE(target_orders_8w) = 0 THEN 'WASTED_SPEND'
      WHEN ANY_VALUE(target_roas) >= ANY_VALUE(th_scale_up_roas) THEN 'STRONG'
      WHEN ANY_VALUE(target_roas) >= ANY_VALUE(th_profitable_roas) THEN 'PROFITABLE'
      WHEN ANY_VALUE(target_roas) >= ANY_VALUE(th_halo_roas) THEN 'MARGINAL'
      WHEN ANY_VALUE(target_orders_8w) > 0 THEN 'UNPROFITABLE'
      ELSE 'INSUFFICIENT_DATA'
    END as ads_signal,
    -- ROAS windows: TARGET uses SUM (not ANY_VALUE) to aggregate across all search terms under this target
    ROUND(SAFE_DIVIDE(
      COALESCE(ANY_VALUE(margin_per_unit), 0) * SUM(ads_units_3d),
      NULLIF(SUM(ads_spend_3d), 0)
    ), 2) as ads_net_roas_3d,
    SUM(ads_orders_3d) as ads_orders_3d,
    SUM(ads_units_3d) as ads_units_3d,
    ROUND(SAFE_DIVIDE(
      COALESCE(ANY_VALUE(margin_per_unit), 0) * SUM(ads_units_1w),
      NULLIF(SUM(ads_spend_1w), 0)
    ), 2) as ads_net_roas_1w,
    SUM(ads_orders_1w) as ads_orders_1w,
    SUM(ads_units_1w) as ads_units_1w,
    ROUND(SAFE_DIVIDE(
      COALESCE(ANY_VALUE(margin_per_unit), 0) * SUM(ly_units),
      NULLIF(SUM(ly_spend), 0)
    ), 2) as ly_net_roas,
    SUM(ly_orders) as ly_orders,
    SUM(ly_units) as ly_units,
    ROUND(SAFE_DIVIDE(
      COALESCE(ANY_VALUE(margin_per_unit), 0) * SUM(q4_peak_units),
      NULLIF(SUM(q4_peak_spend), 0)
    ), 2) as q4_peak_net_roas,
    SUM(q4_peak_orders) as q4_peak_orders,
    SUM(q4_peak_units) as q4_peak_units,
    SUM(sqp_amazon_search_volume_8w) as sqp_amazon_search_volume_8w,
    SUM(sqp_clicks_8w) as sqp_clicks_8w,
    SUM(sqp_sales_8w) as sqp_sales_8w,
    SUM(sqp_orders_8w) as sqp_orders_8w,
    ROUND(SAFE_DIVIDE(
      COALESCE(ANY_VALUE(margin_per_unit), 0) * SUM(lt_units),
      NULLIF(SUM(lt_spend), 0)
    ), 2) as lt_net_roas,
    SUM(lt_orders) as lt_orders,
    SUM(lt_units) as lt_units,
    MIN(lt_first_seen) as lt_first_seen,
    MAX(lt_last_seen) as lt_last_seen,
    ROUND(SUM(ads_spend_1w), 2) as ads_spend_1w,
    ROUND(SAFE_DIVIDE(SUM(ads_spend_1w), NULLIF(SUM(ads_clicks_1w), 0)), 2) as ads_cpc_1w,
    -- Peak-window evidence (aggregated across search terms under this target → SUM/SAFE_DIVIDE)
    ROUND(COALESCE(SUM(ly_spend), 0), 2) as ly_spend,
    SUM(ly_clicks) as ly_clicks,
    ROUND(SAFE_DIVIDE(SUM(ly_spend), NULLIF(SUM(ly_clicks), 0)), 2) as ly_cpc,
    ROUND(COALESCE(SUM(q4_peak_spend), 0), 2) as q4_peak_spend,
    -- ad_group_id is constant per campaign×targeting (one ad group per keyword); ANY_VALUE is correct
    ANY_VALUE(ad_group_id) as ad_group_id
  FROM _base_rows
  WHERE target_action IS NOT NULL
  GROUP BY campaign_id, targeting, target_action;


  -- ═══════════════════════════════════════════
  -- Step 5: INSERT BUDGET actions
  -- 1 row per campaign × budget_action (GROUP BY)
  -- ═══════════════════════════════════════════
  INSERT INTO `onyga-482313.OI.FACT_ADS_COACH_ACTIONS`
  SELECT
    campaign_id,
    ANY_VALUE(campaign_name) as campaign_name,
    ANY_VALUE(campaign_type) as campaign_type,
    ANY_VALUE(campaign_state) as campaign_state,
    CAST(NULL AS STRING) as search_term,
    ANY_VALUE(asin) as asin,
    ANY_VALUE(product_short_name) as product_short_name,
    ANY_VALUE(parent_name) as parent_name,
    ANY_VALUE(experiment_id) as experiment_id,
    ANY_VALUE(experiment_name) as experiment_name,
    ANY_VALUE(strategy_id) as strategy_id,
    ANY_VALUE(strategy_name) as strategy_name,
    ANY_VALUE(experiment_status) as experiment_status,
    ANY_VALUE(recommended_bid_max) as recommended_bid_max,
    -- Campaign-level 4w aggregates
    ROUND(SUM(ads_spend_4w), 2) as ads_spend_4w,
    SUM(ads_orders_4w) as ads_orders_4w,
    SUM(ads_units_4w) as ads_units_4w,
    SUM(ads_clicks_4w) as ads_clicks_4w,
    SUM(ads_impressions_4w) as ads_impressions_4w,
    SUM(ads_clicks_1w) as ads_clicks_1w,
    SUM(ads_impressions_1w) as ads_impressions_1w,
    ROUND(SUM(ads_sales_4w), 2) as ads_sales_4w,
    ROUND(SAFE_DIVIDE(SUM(ads_spend_4w), NULLIF(SUM(ads_clicks_4w), 0)), 2) as ads_cpc_4w,
    ROUND(SAFE_DIVIDE(SUM(ads_orders_4w), NULLIF(SUM(ads_clicks_4w), 0)) * 100, 2) as ads_cvr_pct_4w,
    -- Net profit from the corrected per-targeting volume (consistent with net_roas_4w and the
    -- displayed orders/spend). SUM(net_profit_4w) would carry `assembled`'s cross-targeting value
    -- and overstate the "$/wk" opportunity shown on cards.
    ROUND(SUM(COALESCE(margin_per_unit, 0) * ads_units_4w) - SUM(ads_spend_4w), 2) as net_profit_4w,
    ROUND(SAFE_DIVIDE(SUM(COALESCE(margin_per_unit, 0) * ads_units_4w), NULLIF(SUM(ads_spend_4w), 0)), 2) as net_roas_4w,
    ANY_VALUE(margin_per_unit) as margin_per_unit,
    CAST(NULL AS FLOAT64) as term_spend_4w,
    CAST(NULL AS INT64) as term_orders_4w,
    CAST(NULL AS INT64) as term_campaign_count,
    CAST(NULL AS INT64) as term_selling_campaigns,
    CAST(NULL AS FLOAT64) as spend_share_pct,
    CAST(NULL AS FLOAT64) as orders_share_pct,
    CAST(NULL AS INT64) as sqp_orders_4w,
    CAST(NULL AS FLOAT64) as sqp_show_rate_4w,
    CAST(NULL AS STRING) as hero_asin,
    CAST(NULL AS STRING) as hero_product_name,
    CAST(NULL AS FLOAT64) as hero_net_roas,
    CAST(NULL AS INT64) as hero_total_orders,
    CAST(NULL AS FLOAT64) as hero_ads_ctr_pct,
    FALSE as is_hero_match,
    CAST(NULL AS STRING) as targeting,
    CAST(NULL AS STRING) as keyword_id,

    CAST(NULL AS FLOAT64) as target_net_roas_8w,
    CAST(NULL AS INT64) as target_clicks_8w,
    CAST(NULL AS INT64) as target_orders_8w,
    CAST(NULL AS FLOAT64) as target_spend_8w,
    CAST(NULL AS STRING) as recommendation_object,
    CAST(NULL AS FLOAT64) as current_bid,
    CAST(NULL AS FLOAT64) as recommended_bid,
    CAST(NULL AS FLOAT64) as bid_change_pct,
    ANY_VALUE(coach_mode) as coach_mode,
    ANY_VALUE(active_occasion) as active_occasion,
    ANY_VALUE(current_phase) as current_phase,
    ANY_VALUE(pp_days) as pp_days,
    CAST(NULL AS FLOAT64) as pp_target_net_roas,
    CAST(NULL AS FLOAT64) as pp_target_spend,
    CAST(NULL AS INT64) as pp_target_orders,
    CAST(NULL AS INT64) as tos_pct,
    CAST(NULL AS INT64) as product_page_pct,
    CAST(NULL AS INT64) as b2b_pct,
    CAST(NULL AS FLOAT64) as pre_peak_bid,
    CAST(NULL AS INT64) as pre_peak_tos_pct,
    CAST(NULL AS INT64) as pre_peak_pp_pct,
    CAST(NULL AS INT64) as pre_peak_b2b_pct,
    CAST(NULL AS FLOAT64) as pre_peak_avg_cpc,
    CAST(NULL AS FLOAT64) as last_day_cpc,
    ANY_VALUE(current_budget) as current_budget,
    ANY_VALUE(pre_peak_budget) as pre_peak_budget,
    ANY_VALUE(recommended_budget) as recommended_budget,
    ANY_VALUE(pp_campaign_net_roas) as pp_campaign_net_roas,
    ANY_VALUE(pp_campaign_spend) as pp_campaign_spend,
    ANY_VALUE(pp_campaign_orders) as pp_campaign_orders,
    ANY_VALUE(pp_campaign_sales) as pp_campaign_sales,
    ANY_VALUE(pp_campaign_days) as pp_campaign_days,
    -- Derive strategic_task from the actual budget_action (not inherited from term rows)
    CASE
      WHEN budget_action IN ('GUARDIAN_BUDGET_INCREASE', 'BLITZ_BUDGET_INCREASE') THEN 'SCALE_WINNERS'
      WHEN budget_action = 'GUARDIAN_BUDGET_DECREASE' THEN 'OPTIMIZE_BIDS'
      WHEN budget_action = 'BLITZ_BUDGET_DECREASE' THEN 'COST_CONTROL'
      WHEN budget_action = 'STOP_SEASONAL' THEN 'ELIMINATE_WASTE'
      WHEN budget_action = 'COOLDOWN_BUDGET_MONITOR' THEN 'MONITOR_PERFORMANCE'
      WHEN budget_action IN ('COOLDOWN_BUDGET_REDUCE', 'RESTORE_BUDGET_PRE_PEAK') THEN 'NORMALIZE_BIDS'
      ELSE 'MAINTAIN'
    END as strategic_task,
    CAST(NULL AS STRING) as match_type,
    MAX(priority_score) as priority_score,
    ANY_VALUE(confidence) as confidence,
    'BUDGET' as action_type,
    budget_action as action,
    ANY_VALUE(
      CASE
        WHEN budget_action = 'GUARDIAN_BUDGET_INCREASE'
          THEN CONCAT('Campaign hitting budget cap (', CAST(COALESCE(camp_budget_util_pct, 0) AS STRING), '% utilization) with strong Net ROAS ',
            CAST(COALESCE(camp_effective_roas, 0) AS STRING), '. Increase budget 10% from $',
            CAST(ROUND(current_budget, 0) AS STRING), ' to $', CAST(ROUND(COALESCE(recommended_budget, current_budget), 0) AS STRING), '.')
        WHEN budget_action = 'GUARDIAN_BUDGET_DECREASE'
          THEN CONCAT('Campaign underperforming (Net ROAS ', CAST(COALESCE(camp_effective_roas, 0) AS STRING),
            ', ', CAST(COALESCE(camp_budget_util_pct, 0) AS STRING), '% budget utilization). Reduce budget 15% from $',
            CAST(ROUND(current_budget, 0) AS STRING), ' to $', CAST(ROUND(COALESCE(recommended_budget, current_budget), 0) AS STRING), '.')
        WHEN budget_action = 'BLITZ_BUDGET_INCREASE'
          THEN CONCAT('Peak season: campaign maxing budget (', CAST(COALESCE(camp_budget_util_pct, 0) AS STRING),
            '% util) with ROAS ', CAST(COALESCE(camp_effective_roas, 0) AS STRING),
            '. Increase 20% from $', CAST(ROUND(current_budget, 0) AS STRING),
            ' to $', CAST(ROUND(COALESCE(recommended_budget, current_budget), 0) AS STRING), '.')
        WHEN budget_action = 'BLITZ_BUDGET_DECREASE'
          THEN CONCAT('Even in peak, campaign losing money (ROAS ', CAST(COALESCE(camp_effective_roas, 0) AS STRING),
            ', only ', CAST(COALESCE(camp_budget_util_pct, 0) AS STRING), '% budget used). Reduce 10% from $',
            CAST(ROUND(current_budget, 0) AS STRING), ' to $', CAST(ROUND(COALESCE(recommended_budget, current_budget), 0) AS STRING), '.')
        WHEN budget_action = 'BUDGET_OK' THEN 'Budget is appropriate for current performance. No change needed.'
        WHEN budget_action = 'COOLDOWN_BUDGET_MONITOR' THEN 'Post-peak budget performing well (Ads ROAS ≥ 0.8). Keep current budget.'
        WHEN budget_action = 'COOLDOWN_BUDGET_REDUCE'
          THEN CONCAT('Post-peak budget marginal (Ads ROAS 0.6–0.8). Reduce budget 10%.',
            IF(recommended_budget IS NOT NULL, CONCAT(' Recommended: $', CAST(ROUND(recommended_budget, 0) AS STRING)), ''))
        WHEN budget_action = 'RESTORE_BUDGET_PRE_PEAK'
          THEN CONCAT('Post-peak losing (Ads ROAS < 0.6). Restore pre-peak budget.',
            IF(pre_peak_budget IS NOT NULL, CONCAT(' Pre-peak: $', CAST(ROUND(pre_peak_budget, 0) AS STRING)), ''))
        WHEN budget_action = 'STOP_SEASONAL'
          THEN CONCAT('Seasonal campaign past its season. Pause campaign to prevent off-season spend. Current budget: $',
            CAST(ROUND(COALESCE(current_budget, 0), 0) AS STRING), '.')
        ELSE 'Budget limits evaluated based on performance criteria.'
      END
    ) as action_explanation,
    CONCAT('[',
      '{"id":"camp_roas","label":"Campaign ROAS","sql":"camp_effective_roas","rule":"≥ 0.9","pass":',
        IF(COALESCE(ANY_VALUE(camp_effective_roas), ANY_VALUE(pp_campaign_net_roas), 0) >= 0.9, 'true', 'false'),
        ',"value":"', CAST(ROUND(COALESCE(ANY_VALUE(camp_effective_roas), ANY_VALUE(pp_campaign_net_roas), 0), 2) AS STRING), '"},',
      '{"id":"budget","label":"Budget","sql":"current_budget","pass":true,"value":"$',
        CAST(ROUND(COALESCE(ANY_VALUE(current_budget), 0), 0) AS STRING), '"},',
      '{"id":"util","label":"Utilization","sql":"camp_budget_util_pct","rule":"≥ 90%","pass":',
        IF(COALESCE(ANY_VALUE(camp_budget_util_pct), 0) >= 90, 'true', 'false'),
        ',"value":"', CAST(COALESCE(ANY_VALUE(camp_budget_util_pct), 0) AS STRING), '%"},',
      '{"id":"rec","label":"Recommended","sql":"recommended_budget","pass":',
        IF(budget_action NOT IN ('GUARDIAN_BUDGET_DECREASE', 'BLITZ_BUDGET_DECREASE', 'COOLDOWN_BUDGET_REDUCE', 'RESTORE_BUDGET_PRE_PEAK', 'STOP_SEASONAL'), 'true', 'false'),
        ',"value":"$', CAST(ROUND(COALESCE(ANY_VALUE(recommended_budget), ANY_VALUE(current_budget), 0), 0) AS STRING), '"}',
    ']') as decision_trace,
    CONCAT('B-', SUBSTR(FORMAT('%x', ABS(FARM_FINGERPRINT(CONCAT(
      IF(COALESCE(ANY_VALUE(camp_effective_roas), ANY_VALUE(pp_campaign_net_roas), 0) >= 0.9, 'T', 'F'),
      IF(COALESCE(ANY_VALUE(camp_budget_util_pct), 0) >= 90, 'T', 'F'),
      IF(budget_action NOT IN ('GUARDIAN_BUDGET_DECREASE', 'BLITZ_BUDGET_DECREASE', 'COOLDOWN_BUDGET_REDUCE', 'RESTORE_BUDGET_PRE_PEAK', 'STOP_SEASONAL'), 'T', 'F')
    )))), 1, 6)) as decision_branch_id,
    CONCAT('BGT-', SUBSTR(FORMAT('%x', ABS(FARM_FINGERPRINT(
      CONCAT(COALESCE(campaign_id, ''), '|', budget_action)
    ))), 1, 12)) as action_id,
    -- Campaign-level signal derived from aggregated campaign metrics
    CASE
      WHEN SUM(ads_clicks_4w) < ANY_VALUE(th_min_clicks) THEN 'INSUFFICIENT_DATA'
      WHEN SUM(ads_orders_4w) = 0 THEN 'WASTED_SPEND'
      WHEN ANY_VALUE(camp_effective_roas) >= ANY_VALUE(th_scale_up_roas) THEN 'STRONG'
      WHEN ANY_VALUE(camp_effective_roas) >= ANY_VALUE(th_profitable_roas) THEN 'PROFITABLE'
      WHEN ANY_VALUE(camp_effective_roas) >= ANY_VALUE(th_halo_roas) THEN 'MARGINAL'
      WHEN SUM(ads_orders_4w) > 0 THEN 'UNPROFITABLE'
      ELSE 'INSUFFICIENT_DATA'
    END as ads_signal,
    -- ROAS windows: BUDGET uses SUM (not ANY_VALUE) to aggregate across all search terms in campaign
    ROUND(SAFE_DIVIDE(
      COALESCE(ANY_VALUE(margin_per_unit), 0) * SUM(ads_units_3d),
      NULLIF(SUM(ads_spend_3d), 0)
    ), 2) as ads_net_roas_3d,
    SUM(ads_orders_3d) as ads_orders_3d,
    SUM(ads_units_3d) as ads_units_3d,
    ROUND(SAFE_DIVIDE(
      COALESCE(ANY_VALUE(margin_per_unit), 0) * SUM(ads_units_1w),
      NULLIF(SUM(ads_spend_1w), 0)
    ), 2) as ads_net_roas_1w,
    SUM(ads_orders_1w) as ads_orders_1w,
    SUM(ads_units_1w) as ads_units_1w,
    -- LY: proper campaign-level aggregation
    ROUND(SAFE_DIVIDE(
      COALESCE(ANY_VALUE(margin_per_unit), 0) * SUM(ly_units),
      NULLIF(SUM(ly_spend), 0)
    ), 2) as ly_net_roas,
    SUM(ly_orders) as ly_orders,
    SUM(ly_units) as ly_units,
    -- Dec/Q4: proper campaign-level aggregation
    ROUND(SAFE_DIVIDE(
      COALESCE(ANY_VALUE(margin_per_unit), 0) * SUM(q4_peak_units),
      NULLIF(SUM(q4_peak_spend), 0)
    ), 2) as q4_peak_net_roas,
    SUM(q4_peak_orders) as q4_peak_orders,
    SUM(q4_peak_units) as q4_peak_units,
    -- SQP: NULL for BUDGET rows (SQP is per-search-term, meaningless at campaign level)
    CAST(NULL AS INT64) as sqp_amazon_search_volume_8w,
    CAST(NULL AS INT64) as sqp_clicks_8w,
    CAST(NULL AS FLOAT64) as sqp_sales_8w,
    CAST(NULL AS INT64) as sqp_orders_8w,
    -- 12m lifetime: proper campaign-level aggregation
    ROUND(SAFE_DIVIDE(
      COALESCE(ANY_VALUE(margin_per_unit), 0) * SUM(lt_units),
      NULLIF(SUM(lt_spend), 0)
    ), 2) as lt_net_roas,
    SUM(lt_orders) as lt_orders,
    SUM(lt_units) as lt_units,
    MIN(lt_first_seen) as lt_first_seen,
    MAX(lt_last_seen) as lt_last_seen,
    ROUND(SUM(ads_spend_1w), 2) as ads_spend_1w,
    ROUND(SAFE_DIVIDE(SUM(ads_spend_1w), NULLIF(SUM(ads_clicks_1w), 0)), 2) as ads_cpc_1w,
    -- Peak-window evidence (aggregated across all search terms in campaign → SUM/SAFE_DIVIDE)
    ROUND(COALESCE(SUM(ly_spend), 0), 2) as ly_spend,
    SUM(ly_clicks) as ly_clicks,
    ROUND(SAFE_DIVIDE(SUM(ly_spend), NULLIF(SUM(ly_clicks), 0)), 2) as ly_cpc,
    ROUND(COALESCE(SUM(q4_peak_spend), 0), 2) as q4_peak_spend,
    -- BUDGET is campaign-grain; a campaign may span multiple ad groups → ANY_VALUE (best effort)
    ANY_VALUE(ad_group_id) as ad_group_id
  FROM _base_rows
  WHERE budget_action IS NOT NULL
  GROUP BY campaign_id, budget_action;


  -- ═══════════════════════════════════════════
  -- Step 6: INSERT HERO actions
  -- 1 row per campaign × search_term × hero_action
  -- ═══════════════════════════════════════════
  INSERT INTO `onyga-482313.OI.FACT_ADS_COACH_ACTIONS`
  SELECT
    campaign_id,
    ANY_VALUE(campaign_name) as campaign_name,
    ANY_VALUE(campaign_type) as campaign_type,
    ANY_VALUE(campaign_state) as campaign_state,
    search_term,
    ANY_VALUE(asin) as asin,
    ANY_VALUE(product_short_name) as product_short_name,
    ANY_VALUE(parent_name) as parent_name,
    ANY_VALUE(experiment_id) as experiment_id,
    ANY_VALUE(experiment_name) as experiment_name,
    ANY_VALUE(strategy_id) as strategy_id,
    ANY_VALUE(strategy_name) as strategy_name,
    ANY_VALUE(experiment_status) as experiment_status,
    ANY_VALUE(recommended_bid_max) as recommended_bid_max,
    ANY_VALUE(ads_spend_4w) as ads_spend_4w,
    ANY_VALUE(ads_orders_4w) as ads_orders_4w,
    ANY_VALUE(ads_units_4w) as ads_units_4w,
    ANY_VALUE(ads_clicks_4w) as ads_clicks_4w,
    ANY_VALUE(ads_impressions_4w) as ads_impressions_4w,
    ANY_VALUE(ads_clicks_1w) as ads_clicks_1w,
    ANY_VALUE(ads_impressions_1w) as ads_impressions_1w,
    ANY_VALUE(ads_sales_4w) as ads_sales_4w,
    ANY_VALUE(ads_cpc_4w) as ads_cpc_4w,
    ANY_VALUE(ads_cvr_pct_4w) as ads_cvr_pct_4w,
    ANY_VALUE(net_profit_4w) as net_profit_4w,
    ANY_VALUE(net_roas_4w) as net_roas_4w,
    ANY_VALUE(margin_per_unit) as margin_per_unit,
    ANY_VALUE(term_spend_4w) as term_spend_4w,
    ANY_VALUE(term_orders_4w) as term_orders_4w,
    ANY_VALUE(term_campaign_count) as term_campaign_count,
    ANY_VALUE(term_selling_campaigns) as term_selling_campaigns,
    ANY_VALUE(spend_share_pct) as spend_share_pct,
    ANY_VALUE(orders_share_pct) as orders_share_pct,
    ANY_VALUE(sqp_orders_4w) as sqp_orders_4w,
    ANY_VALUE(sqp_show_rate_4w) as sqp_show_rate_4w,
    ANY_VALUE(hero_asin) as hero_asin,
    ANY_VALUE(hero_product_name) as hero_product_name,
    ANY_VALUE(hero_net_roas) as hero_net_roas,
    ANY_VALUE(hero_total_orders) as hero_total_orders,
    ANY_VALUE(hero_ads_ctr_pct) as hero_ads_ctr_pct,
    ANY_VALUE(is_hero_match) as is_hero_match,
    CAST(NULL AS STRING) as targeting,
    CAST(NULL AS STRING) as keyword_id,

    ANY_VALUE(target_net_roas_8w) as target_net_roas_8w,
    ANY_VALUE(target_clicks_8w) as target_clicks_8w,
    ANY_VALUE(target_orders_8w) as target_orders_8w,
    ANY_VALUE(target_spend_8w) as target_spend_8w,
    ANY_VALUE(recommendation_object) as recommendation_object,
    ANY_VALUE(current_bid) as current_bid,
    ANY_VALUE(recommended_bid) as recommended_bid,
    ANY_VALUE(bid_change_pct) as bid_change_pct,
    ANY_VALUE(coach_mode) as coach_mode,
    ANY_VALUE(active_occasion) as active_occasion,
    ANY_VALUE(current_phase) as current_phase,
    ANY_VALUE(pp_days) as pp_days,
    ANY_VALUE(pp_target_net_roas) as pp_target_net_roas,
    ANY_VALUE(pp_target_spend) as pp_target_spend,
    ANY_VALUE(pp_target_orders) as pp_target_orders,
    ANY_VALUE(tos_pct) as tos_pct,
    ANY_VALUE(product_page_pct) as product_page_pct,
    ANY_VALUE(b2b_pct) as b2b_pct,
    ANY_VALUE(pre_peak_bid) as pre_peak_bid,
    ANY_VALUE(pre_peak_tos_pct) as pre_peak_tos_pct,
    ANY_VALUE(pre_peak_pp_pct) as pre_peak_pp_pct,
    ANY_VALUE(pre_peak_b2b_pct) as pre_peak_b2b_pct,
    ANY_VALUE(pre_peak_avg_cpc) as pre_peak_avg_cpc,
    ANY_VALUE(last_day_cpc) as last_day_cpc,
    ANY_VALUE(current_budget) as current_budget,
    ANY_VALUE(pre_peak_budget) as pre_peak_budget,
    ANY_VALUE(recommended_budget) as recommended_budget,
    ANY_VALUE(pp_campaign_net_roas) as pp_campaign_net_roas,
    ANY_VALUE(pp_campaign_spend) as pp_campaign_spend,
    ANY_VALUE(pp_campaign_orders) as pp_campaign_orders,
    ANY_VALUE(pp_campaign_sales) as pp_campaign_sales,
    ANY_VALUE(pp_campaign_days) as pp_campaign_days,
    -- HERO actions always map to CORRECT_HEROES (qualified heroes only)
    'CORRECT_HEROES' as strategic_task,
    ANY_VALUE(match_type) as match_type,
    MAX(priority_score) as priority_score,
    ANY_VALUE(confidence) as confidence,
    'HERO' as action_type,
    hero_action as action,
    ANY_VALUE(hero_action_explanation) as action_explanation,
    ANY_VALUE(
      CONCAT('[',
        '{"id":"hero","label":"Hero ASIN","sql":"hero_asin","pass":false,"value":"', COALESCE(hero_asin, 'N/A'), '"},',
        '{"id":"match","label":"Hero Match","sql":"is_hero_match","pass":false,"value":"', IF(COALESCE(is_hero_match, FALSE), 'YES', 'NO'), '"},',
        '{"id":"hero_roas","label":"Hero ROAS","sql":"hero_net_roas","rule":"\u003e 0","pass":true,"value":"', CAST(ROUND(COALESCE(hero_net_roas, 0), 1) AS STRING), '"},',
        '{"id":"hero_orders","label":"Hero Orders","sql":"hero_total_orders","rule":"\u003e 0","pass":true,"value":"', CAST(COALESCE(hero_total_orders, 0) AS STRING), '"}',
      ']')
    ) as decision_trace,
    CONCAT('B-', SUBSTR(FORMAT('%x', ABS(FARM_FINGERPRINT(CONCAT(
      IF(COALESCE(ANY_VALUE(is_hero_match), FALSE), 'T', 'F'),
      IF(COALESCE(ANY_VALUE(hero_net_roas), 0) > 0, 'T', 'F'),
      IF(COALESCE(ANY_VALUE(hero_total_orders), 0) > 0, 'T', 'F')
    )))), 1, 6)) as decision_branch_id,
    CONCAT('HRO-', SUBSTR(FORMAT('%x', ABS(FARM_FINGERPRINT(
      CONCAT(COALESCE(campaign_id, ''), '|', COALESCE(search_term, ''), '|', hero_action)
    ))), 1, 6)) as action_id,
    ANY_VALUE(ads_signal) as ads_signal,
    -- ROAS windows + SQP context
    ANY_VALUE(ads_net_roas_3d) as ads_net_roas_3d,
    ANY_VALUE(ads_orders_3d) as ads_orders_3d,
    ANY_VALUE(ads_units_3d) as ads_units_3d,
    ANY_VALUE(ads_net_roas_1w) as ads_net_roas_1w,
    ANY_VALUE(ads_orders_1w) as ads_orders_1w,
    ANY_VALUE(ads_units_1w) as ads_units_1w,
    ANY_VALUE(ly_net_roas) as ly_net_roas,
    ANY_VALUE(ly_orders) as ly_orders,
    ANY_VALUE(ly_units) as ly_units,
    ANY_VALUE(q4_peak_net_roas) as q4_peak_net_roas,
    ANY_VALUE(q4_peak_orders) as q4_peak_orders,
    ANY_VALUE(q4_peak_units) as q4_peak_units,
    ANY_VALUE(sqp_amazon_search_volume_8w) as sqp_amazon_search_volume_8w,
    ANY_VALUE(sqp_clicks_8w) as sqp_clicks_8w,
    ANY_VALUE(sqp_sales_8w) as sqp_sales_8w,
    ANY_VALUE(sqp_orders_8w) as sqp_orders_8w,
    ANY_VALUE(lt_net_roas) as lt_net_roas,
    ANY_VALUE(lt_orders) as lt_orders,
    ANY_VALUE(lt_units) as lt_units,
    ANY_VALUE(lt_first_seen) as lt_first_seen,
    ANY_VALUE(lt_last_seen) as lt_last_seen,
    ROUND(ANY_VALUE(ads_spend_1w), 2) as ads_spend_1w,
    ROUND(SAFE_DIVIDE(ANY_VALUE(ads_spend_1w), NULLIF(ANY_VALUE(ads_clicks_1w), 0)), 2) as ads_cpc_1w,
    -- Peak-window evidence (per-term rows share the same ly_/q4_ values → ANY_VALUE)
    ROUND(COALESCE(ANY_VALUE(ly_spend), 0), 2) as ly_spend,
    CAST(ANY_VALUE(ly_clicks) AS INT64) as ly_clicks,
    ANY_VALUE(ly_cpc) as ly_cpc,
    ROUND(COALESCE(ANY_VALUE(q4_peak_spend), 0), 2) as q4_peak_spend,
    ANY_VALUE(ad_group_id) as ad_group_id
  FROM _base_rows
  WHERE hero_action IS NOT NULL
  GROUP BY campaign_id, search_term, hero_action;



  -- Cleanup
  DROP TABLE IF EXISTS _base_rows;

END;
