-- =============================================
-- OI Database Project - V_ADS_COACH_SEARCH_TERM View
-- =============================================
--
-- Purpose: ONE ROW PER SEARCH TERM × CAMPAIGN.
--          Campaign-specific action: should this term stay in THIS campaign?
--
--          Example: "birthday gift for 12 year old girl" in 8 campaigns.
--          Only 1 video campaign sells → KEEP there, NEGATE from other 7.
--
-- Grain: search_term × campaign_id × asin
--
-- Dependencies:
--   FACT_AMAZON_ADS, DIM_EXPERIMENT, DIM_EXPERIMENT_CAMPAIGN,
--   DIM_STRATEGY_TEMPLATE, DIM_PRODUCT, DIM_COSTS_HISTORY,
--   DIM_US_HOLIDAYS, FACT_SEARCH_QUERY
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_ADS_COACH_SEARCH_TERM`
AS
WITH

-- Campaign → experiment → strategy
campaign_experiment AS (
  SELECT
    ec.campaign_id,
    e.experiment_id,
    e.experiment_name,
    e.strategy_id,
    e.status as experiment_status,
    st.strategy_name,
    st.recommended_bid_min,
    st.recommended_bid_max
  FROM `onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN` ec
  JOIN `onyga-482313.OI.DIM_EXPERIMENT` e ON ec.experiment_id = e.experiment_id
  LEFT JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st ON e.strategy_id = st.strategy_id
  WHERE e.status IN ('ACTIVE', 'PAUSED')
),

-- Unit economics
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

-- Ads 4w per campaign × term × ASIN
ads_4w AS (
  SELECT
    fa.campaign_id, fa.campaign_name, fa.campaign_type,
    LOWER(fa.search_term) as search_term,
    COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) as asin,
    -- Pick latest ad_group_id for this campaign×term (SP campaigns typically have 1 ad group)
    ANY_VALUE(fa.ad_group_id HAVING MAX fa.date) as ad_group_id,
    SUM(fa.Ads_cost) as ads_spend_4w,
    SUM(fa.Ads_orders) as ads_orders_4w,
    SUM(fa.Ads_units) as ads_units_4w,
    SUM(fa.Ads_clicks) as ads_clicks_4w,
    SUM(fa.Ads_impressions) as ads_impressions_4w,
    SUM(fa.Ads_sales) as ads_sales_4w,
    COUNT(DISTINCT fa.date) as ads_days_4w
  FROM `onyga-482313.OI.FACT_AMAZON_ADS` fa
  WHERE fa.date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
    AND fa.search_term IS NOT NULL AND fa.search_term != ''
    AND COALESCE(fa.most_advertised_asin_impressions, fa.ASIN_BY_CAMPAIGN_NAME) IS NOT NULL
  GROUP BY 1, 2, 3, 4, 5
),

-- Per-term aggregates (to compare campaigns within same term)
term_totals AS (
  SELECT
    search_term,
    SUM(ads_spend_4w) as term_spend_4w,
    SUM(ads_orders_4w) as term_orders_4w,
    SUM(ads_clicks_4w) as term_clicks_4w,
    COUNT(DISTINCT campaign_id) as term_campaign_count,
    COUNT(DISTINCT CASE WHEN ads_orders_4w > 0 THEN campaign_id END) as term_selling_campaigns,
    -- Best ROAS campaign
    MAX(CASE WHEN ads_orders_4w > 0 THEN ads_orders_4w END) as best_campaign_orders
  FROM ads_4w
  GROUP BY 1
),

-- SQP 4w (per term across ASINs)
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

-- Hero ASIN per search term (global rank 1 + qualified)
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

-- Assemble: per campaign × term
assembled AS (
  SELECT
    a4.campaign_id,
    a4.campaign_name,
    a4.campaign_type,
    a4.search_term,
    a4.asin,
    ae.product_short_name,
    ae.parent_name,
    ce.experiment_id,
    ce.experiment_name,
    ce.strategy_id,
    ce.strategy_name,
    ce.experiment_status,
    ce.recommended_bid_max,

    -- This campaign's metrics
    ROUND(a4.ads_spend_4w, 2) as ads_spend_4w,
    a4.ads_orders_4w,
    a4.ads_clicks_4w,
    a4.ads_impressions_4w,
    ROUND(a4.ads_sales_4w, 2) as ads_sales_4w,
    a4.ads_days_4w,
    ROUND(SAFE_DIVIDE(a4.ads_spend_4w, NULLIF(a4.ads_clicks_4w, 0)), 2) as ads_cpc_4w,
    ROUND(SAFE_DIVIDE(a4.ads_orders_4w, NULLIF(a4.ads_clicks_4w, 0)) * 100, 2) as ads_cvr_pct_4w,
    -- Net profit: margin × orders - spend (use ads selling price when listing price missing)
    ROUND(
      COALESCE(
        ae.margin_per_unit,
        SAFE_DIVIDE(a4.ads_sales_4w, NULLIF(a4.ads_orders_4w, 0)) - COALESCE(ae.total_cost_per_unit, 0)
      ) * a4.ads_orders_4w - a4.ads_spend_4w,
    2) as ads_net_profit_4w,
    -- Net ROAS: margin × orders / spend
    ROUND(SAFE_DIVIDE(
      COALESCE(
        ae.margin_per_unit,
        SAFE_DIVIDE(a4.ads_sales_4w, NULLIF(a4.ads_orders_4w, 0)) - COALESCE(ae.total_cost_per_unit, 0)
      ) * a4.ads_orders_4w,
      NULLIF(a4.ads_spend_4w, 0)
    ), 2) as ads_net_roas_4w,
    ROUND(COALESCE(
      ae.margin_per_unit,
      SAFE_DIVIDE(a4.ads_sales_4w, NULLIF(a4.ads_orders_4w, 0)) - COALESCE(ae.total_cost_per_unit, 0)
    ), 2) as margin_per_unit,

    -- Cross-campaign context
    tt.term_spend_4w,
    tt.term_orders_4w,
    tt.term_campaign_count,
    tt.term_selling_campaigns,

    -- This campaign's share of the term
    ROUND(SAFE_DIVIDE(a4.ads_spend_4w, NULLIF(tt.term_spend_4w, 0)) * 100, 1) as spend_share_pct,
    ROUND(SAFE_DIVIDE(a4.ads_orders_4w, NULLIF(tt.term_orders_4w, 0)) * 100, 1) as orders_share_pct,

    -- SQP
    COALESCE(sq4.sqp_orders_4w, 0) as sqp_orders_4w,
    ROUND(COALESCE(sq4.sqp_show_rate_4w, 0), 2) as sqp_show_rate_4w,

    -- Hero ASIN
    hl.hero_asin,
    hl.hero_product_name,
    hl.hero_net_roas,
    hl.hero_total_orders,
    hl.hero_ads_ctr_pct,
    CASE WHEN a4.asin = hl.hero_asin THEN TRUE ELSE FALSE END as is_hero_match

  FROM ads_4w a4
  LEFT JOIN campaign_experiment ce ON a4.campaign_id = ce.campaign_id
  LEFT JOIN asin_economics ae ON a4.asin = ae.asin
  LEFT JOIN term_totals tt ON a4.search_term = tt.search_term
  LEFT JOIN sqp_4w sq4 ON a4.search_term = sq4.search_term
  LEFT JOIN hero_lookup hl ON a4.search_term = hl.search_term
),

-- Pull targeting & target_action from the main coach view
coach_actions AS (
  SELECT
    campaign_id, LOWER(search_term) as search_term,
    targeting, keyword_id, target_action, effective_roas,
    ads_weighted_net_roas, ads_net_roas_1w, ads_net_roas_4w,
    target_net_roas_8w, target_clicks_8w, target_orders_8w, target_spend_8w,
    target_decision_trace, recommendation_object,
    current_bid, recommended_bid, bid_change_pct
  FROM `onyga-482313.OI.V_ADS_COACH`
  WHERE recommendation_type = 'ACTIVE_TERM'
)

-- =============================================
-- Campaign-specific action for each term
-- =============================================
SELECT
  a.*,
  ca.targeting,
  ca.keyword_id,
  ca.target_action,
  ca.effective_roas,
  ca.ads_weighted_net_roas,
  ca.ads_net_roas_1w as ads_net_roas_1w_coach,
  ca.ads_net_roas_4w as ads_net_roas_4w_coach,
  ca.target_net_roas_8w,
  ca.target_clicks_8w,
  ca.target_orders_8w,
  ROUND(ca.target_spend_8w, 2) as target_spend_8w,
  ca.target_decision_trace,
  ca.recommendation_object,
  ROUND(ca.current_bid, 2) as current_bid,
  ca.recommended_bid,
  ca.bid_change_pct,
  -- match_type: from DIM_AD_keyword for keywords, derived for product targeting
  COALESCE(dk.match_type,
    CASE 
      WHEN REGEXP_CONTAINS(COALESCE(ca.targeting, ''), r'^asin=') THEN 'PRODUCT_TARGETING'
      WHEN LOWER(COALESCE(ca.targeting, '')) IN ('close-match', 'loose-match', 'substitutes', 'complements') THEN 'PRODUCT_TARGETING'
      ELSE NULL 
    END
  ) as match_type,

  -- Action: what to do with THIS term in THIS campaign
  CASE
    -- Ignore BRAND_DEFENSE and PRODUCT_DEFENSE
    WHEN a.strategy_id IN ('PRODUCT_DEFENSE', 'BRAND_DEFENSE') THEN 'MONITOR'

    -- This campaign sells: KEEP (bid action is on the target, not the term)
    WHEN a.ads_orders_4w > 0 AND a.ads_net_roas_4w >= 0.7 THEN 'KEEP'
    WHEN a.ads_orders_4w > 0 AND a.ads_net_roas_4w < 0.7 THEN 'KEEP'

    -- This campaign doesn't sell BUT other campaigns for this term DO sell
    -- Low threshold: we KNOW the term converts, so remove from non-selling campaigns
    WHEN a.ads_orders_4w = 0 AND a.term_selling_campaigns > 0
      THEN 'NEGATE_TERM'

    -- This campaign doesn't sell AND no campaign sells this term
    WHEN a.ads_orders_4w = 0 AND a.term_selling_campaigns = 0 AND a.term_spend_4w >= 15
      THEN 'NEGATE_TERM'

    -- CPC too high for strategy
    WHEN a.ads_cpc_4w > COALESCE(a.recommended_bid_max, 2.0) AND a.ads_spend_4w >= 5
      THEN 'KEEP'

    -- Not enough data
    WHEN a.ads_spend_4w < 3 THEN 'MONITOR'

    ELSE 'MONITOR'
  END as action,

  -- Priority: higher = act sooner
  ROUND(CASE
    -- Negate priority: non-selling campaign while others sell
    WHEN a.ads_orders_4w = 0 AND a.term_selling_campaigns > 0
      THEN GREATEST(a.ads_spend_4w * 3.0, 1.0)  -- Even low-spend gets priority
    WHEN a.ads_orders_4w = 0 AND a.term_selling_campaigns = 0 AND a.term_spend_4w >= 15
      THEN a.ads_spend_4w * 2.0
    WHEN a.ads_orders_4w > 0 AND a.ads_net_roas_4w >= 2.0
      THEN a.ads_orders_4w * 30.0  -- Scale opportunity
    WHEN a.ads_orders_4w > 0 AND a.ads_net_roas_4w < 0.7
      THEN a.ads_spend_4w * 1.0
    ELSE 0
  END, 0) as priority_score,

  -- Confidence
  CASE
    WHEN a.ads_days_4w >= 14 AND a.ads_clicks_4w >= 30 THEN 'HIGH'
    WHEN a.ads_days_4w >= 7 AND a.ads_clicks_4w >= 10 THEN 'MEDIUM'
    ELSE 'LOW'
  END as confidence,

  -- Reason: why THIS action in THIS campaign
  CASE
    WHEN a.ads_orders_4w > 0 AND a.ads_net_roas_4w >= 2.0
      THEN CONCAT('This ', a.campaign_type, ' campaign sells: ', CAST(a.ads_orders_4w AS STRING),
                   ' orders, ROAS ', CAST(ROUND(a.ads_net_roas_4w, 1) AS STRING),
                   '. Scale up.')
    WHEN a.ads_orders_4w > 0 AND a.ads_net_roas_4w >= 0.7
      THEN CONCAT('Selling: ', CAST(a.ads_orders_4w AS STRING), ' orders in this ',
                   a.campaign_type, ' campaign (ROAS ', CAST(ROUND(a.ads_net_roas_4w, 1) AS STRING),
                   '). Keep.')
    WHEN a.ads_orders_4w > 0 AND a.ads_net_roas_4w < 0.7
      THEN CONCAT('Selling but unprofitable: ', CAST(a.ads_orders_4w AS STRING),
                   ' orders, ROAS ', CAST(ROUND(a.ads_net_roas_4w, 1) AS STRING),
                   ', losing $', CAST(ROUND(ABS(a.ads_net_profit_4w), 0) AS STRING), '. Reduce bid.')
    WHEN a.ads_orders_4w = 0 AND a.term_selling_campaigns > 0
      THEN CONCAT('$', CAST(ROUND(a.ads_spend_4w, 0) AS STRING), ' spent, 0 orders. ',
                   'But this term sells in ', CAST(a.term_selling_campaigns AS STRING),
                   ' other campaign(s) (',  CAST(a.term_orders_4w AS STRING), ' total orders). ',
                   'Remove from this ', a.campaign_type, ' campaign — consolidate spend.')
    WHEN a.ads_orders_4w = 0 AND a.term_selling_campaigns = 0 AND a.term_spend_4w >= 15
      THEN CONCAT('$', CAST(ROUND(a.ads_spend_4w, 0) AS STRING), ' spent, 0 orders. ',
                   'No campaign sells this term ($', CAST(ROUND(a.term_spend_4w, 0) AS STRING),
                   ' total across ', CAST(a.term_campaign_count AS STRING), ' campaigns). Negate everywhere.')
    WHEN a.ads_spend_4w < 3
      THEN CONCAT('Only $', CAST(ROUND(a.ads_spend_4w, 2) AS STRING), ' spent. Monitoring.')
    ELSE CONCAT('$', CAST(ROUND(a.ads_spend_4w, 0) AS STRING), ' spent, ',
                CAST(a.ads_orders_4w AS STRING), ' orders. Monitoring.')
  END as reason,

  -- Hero action: SWITCH_HERO when advertising wrong ASIN
  -- Only for terms with orders (KEEP/REDUCE_BID/SCALE_UP) — not for STOP/NEGATE terms
  CASE
    WHEN a.hero_asin IS NOT NULL AND NOT a.is_hero_match
      AND a.ads_orders_4w > 0 THEN 'SWITCH_HERO'
    ELSE NULL
  END as hero_action,

  CASE
    WHEN a.hero_asin IS NOT NULL AND NOT a.is_hero_match
      AND a.ads_orders_4w > 0
      THEN CONCAT(
        'SWITCH_HERO: You are advertising ', a.product_short_name,
        ' but ', a.hero_product_name, ' is the hero for "', a.search_term, '".',
        ' Hero Net ROAS: ', CAST(ROUND(COALESCE(a.hero_net_roas, 0), 1) AS STRING),
        ', Hero Orders: ', CAST(COALESCE(a.hero_total_orders, 0) AS STRING), '.'
      )
    ELSE NULL
  END as hero_action_explanation

FROM assembled a
LEFT JOIN coach_actions ca
  ON a.campaign_id = ca.campaign_id
  AND a.search_term = ca.search_term
LEFT JOIN `onyga-482313.OI.DIM_AD_keyword` dk
  ON ca.keyword_id = dk.keyword_id;
