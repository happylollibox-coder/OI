-- =============================================
-- OI Database Project - SP_EXPERIMENT_WEEKLY_REVIEW Stored Procedure
-- =============================================
--
-- Purpose: Weekly recommendation engine - generates actionable recommendations
--          based on experiment results, search term opportunities, seasonal events,
--          and strategy template learnings
-- Method: INSERT into FACT_EXPERIMENT_RECOMMENDATIONS
-- Source: V_EXPERIMENT_SUMMARY, V_SEARCH_TERM_OPPORTUNITIES, V_EXPERIMENT_LEARNINGS,
--         DIM_US_HOLIDAYS, V_EXPERIMENT_CAMPAIGN_SETTINGS, DIM_STRATEGY_TEMPLATE
-- Schedule: Weekly (runs Monday via orchestrator check or manual trigger)
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_EXPERIMENT_WEEKLY_REVIEW`()
OPTIONS (
  description = "Weekly recommendation engine: scores experiments, suggests actions, and recommends new experiments",
  strict_mode = false
)
BEGIN
  DECLARE current_week_start DATE;
  DECLARE rec_count INT64 DEFAULT 0;

  -- Set week start to Monday of current week
  SET current_week_start = DATE_TRUNC(CURRENT_DATE(), WEEK(MONDAY));

  -- Delete any existing recommendations for this week (idempotent)
  DELETE FROM `onyga-482313.OI.FACT_EXPERIMENT_RECOMMENDATIONS`
  WHERE week_start_date = current_week_start;

  -- =============================================
  -- 1. EXPERIMENT_CONTINUE / EXPERIMENT_STOP / EXPERIMENT_REVIEW
  -- Score active experiments and recommend action
  -- =============================================
  INSERT INTO `onyga-482313.OI.FACT_EXPERIMENT_RECOMMENDATIONS`
    (recommendation_id, week_start_date, generated_at, category, priority, title, detail, experiment_id, asin, metric_value, metric_label)
  SELECT
    CONCAT('EXP-', experiment_id, '-', FORMAT_DATE('%Y%m%d', current_week_start)) as recommendation_id,
    current_week_start,
    CURRENT_TIMESTAMP(),
    -- Use SEASONAL-ADJUSTED lift for decisions (falls back to raw if seasonal N/A)
    CASE
      WHEN COALESCE(performance_seasonal_organic_units_lift_pct, performance_organic_units_lift_pct) > 10 AND days_running >= 14 THEN 'EXPERIMENT_CONTINUE'
      WHEN COALESCE(performance_seasonal_organic_units_lift_pct, performance_organic_units_lift_pct) > 0 AND days_running >= 14 THEN 'EXPERIMENT_CONTINUE'
      WHEN days_running >= 28 AND (COALESCE(performance_seasonal_organic_units_lift_pct, performance_organic_units_lift_pct) <= 0 OR COALESCE(performance_seasonal_organic_units_lift_pct, performance_organic_units_lift_pct) IS NULL) THEN 'EXPERIMENT_STOP'
      WHEN days_running >= 14 AND (COALESCE(performance_seasonal_organic_units_lift_pct, performance_organic_units_lift_pct) <= 0 OR COALESCE(performance_seasonal_organic_units_lift_pct, performance_organic_units_lift_pct) IS NULL) THEN 'EXPERIMENT_REVIEW'
      ELSE 'EXPERIMENT_REVIEW'
    END as category,
    CASE
      WHEN COALESCE(performance_seasonal_organic_units_lift_pct, performance_organic_units_lift_pct) > 10 THEN 'HIGH'
      WHEN days_running >= 28 AND (COALESCE(performance_seasonal_organic_units_lift_pct, performance_organic_units_lift_pct) <= 0 OR COALESCE(performance_seasonal_organic_units_lift_pct, performance_organic_units_lift_pct) IS NULL) THEN 'HIGH'
      ELSE 'MEDIUM'
    END as priority,
    CASE
      WHEN COALESCE(performance_seasonal_organic_units_lift_pct, performance_organic_units_lift_pct) > 10 THEN CONCAT(experiment_name, ': Strong seasonal-adj organic lift +', CAST(ROUND(COALESCE(performance_seasonal_organic_units_lift_pct, performance_organic_units_lift_pct), 0) AS STRING), '% - KEEP RUNNING')
      WHEN COALESCE(performance_seasonal_organic_units_lift_pct, performance_organic_units_lift_pct) > 0 THEN CONCAT(experiment_name, ': Slight seasonal-adj organic lift +', CAST(ROUND(COALESCE(performance_seasonal_organic_units_lift_pct, performance_organic_units_lift_pct), 0) AS STRING), '% - continue monitoring')
      WHEN days_running >= 28 AND (COALESCE(performance_seasonal_organic_units_lift_pct, performance_organic_units_lift_pct) <= 0 OR COALESCE(performance_seasonal_organic_units_lift_pct, performance_organic_units_lift_pct) IS NULL) THEN CONCAT(experiment_name, ': No organic lift after ', CAST(days_running AS STRING), ' days (seasonal-adj) - CONSIDER STOPPING')
      WHEN days_running < 14 THEN CONCAT(experiment_name, ': Only ', CAST(days_running AS STRING), ' days in - too early to judge')
      ELSE CONCAT(experiment_name, ': Mixed results after ', CAST(days_running AS STRING), ' days - review details')
    END as title,
    CONCAT(
      'Days running: ', CAST(days_running AS STRING),
      ' | Ad spend: $', CAST(ROUND(ads_total_spend, 0) AS STRING),
      ' | ROAS: ', COALESCE(CAST(ads_avg_roas AS STRING), 'N/A'),
      ' | Seasonal adj ratio: ', COALESCE(CAST(ROUND(seasonal_adjustment_ratio, 2) AS STRING), 'N/A'),
      ' | Raw organic lift: ', COALESCE(CAST(ROUND(performance_organic_units_lift_pct, 1) AS STRING), 'N/A'), '%',
      ' | Seasonal organic lift: ', COALESCE(CAST(ROUND(performance_seasonal_organic_units_lift_pct, 1) AS STRING), 'N/A'), '%',
      ' | Search terms: ', CAST(tracked_search_terms AS STRING),
      ' (', CAST(terms_normalized_positive_total_lift AS STRING), ' norm+, ',
      CAST(terms_normalized_negative_total_lift AS STRING), ' norm-)'
    ) as detail,
    experiment_id,
    NULL as asin,
    COALESCE(performance_seasonal_organic_units_lift_pct, performance_organic_units_lift_pct) as metric_value,
    'performance_seasonal_organic_lift_pct' as metric_label
  FROM `onyga-482313.OI.V_EXPERIMENT_SUMMARY`
  WHERE status = 'ACTIVE';

  -- =============================================
  -- 2. SEASONAL_ACTION
  -- Check upcoming holidays within next 21 days
  -- =============================================
  INSERT INTO `onyga-482313.OI.FACT_EXPERIMENT_RECOMMENDATIONS`
    (recommendation_id, week_start_date, generated_at, category, priority, title, detail, metric_value, metric_label)
  SELECT
    CONCAT('SEASON-', FORMAT_DATE('%Y%m%d', holiday_date), '-', FORMAT_DATE('%Y%m%d', current_week_start)) as recommendation_id,
    current_week_start,
    CURRENT_TIMESTAMP(),
    'SEASONAL_ACTION' as category,
    CASE
      WHEN DATE_DIFF(pre_season_start, CURRENT_DATE(), DAY) <= 0
        AND DATE_DIFF(holiday_date, CURRENT_DATE(), DAY) > 0 THEN 'HIGH'
      WHEN DATE_DIFF(pre_season_start, CURRENT_DATE(), DAY) <= 7 THEN 'HIGH'
      ELSE 'MEDIUM'
    END as priority,
    CASE
      WHEN DATE_DIFF(pre_season_start, CURRENT_DATE(), DAY) <= 0
        AND DATE_DIFF(holiday_date, CURRENT_DATE(), DAY) > 0
        THEN CONCAT(holiday_name, ' in ', CAST(DATE_DIFF(holiday_date, CURRENT_DATE(), DAY) AS STRING), ' days - ADS SHOULD BE RUNNING')
      WHEN DATE_DIFF(pre_season_start, CURRENT_DATE(), DAY) <= 0
        THEN CONCAT(holiday_name, ' has passed - review performance')
      ELSE CONCAT(holiday_name, ' ramp-up starts in ', CAST(DATE_DIFF(pre_season_start, CURRENT_DATE(), DAY) AS STRING), ' days - prepare campaigns')
    END as title,
    CONCAT(
      'Holiday: ', holiday_name, ' (', FORMAT_DATE('%b %d', holiday_date), ')',
      ' | Category: ', category,
      ' | Ramp-up: ', CAST(ramp_up_days AS STRING), ' days before',
      ' | Ramp start: ', FORMAT_DATE('%b %d', pre_season_start)
    ) as detail,
    CAST(DATE_DIFF(holiday_date, CURRENT_DATE(), DAY) AS FLOAT64) as metric_value,
    'days_until_holiday' as metric_label
  FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
  WHERE DATE_DIFF(holiday_date, CURRENT_DATE(), DAY) BETWEEN -7 AND 42
    AND DATE_DIFF(pre_season_start, CURRENT_DATE(), DAY) <= 21;

  -- =============================================
  -- 3. NEW_EXPERIMENT
  -- Suggest new experiments from top opportunities
  -- =============================================
  INSERT INTO `onyga-482313.OI.FACT_EXPERIMENT_RECOMMENDATIONS`
    (recommendation_id, week_start_date, generated_at, category, priority, title, detail, asin, search_term, metric_value, metric_label)
  SELECT
    CONCAT('NEW-', ASIN, '-', SUBSTR(TO_HEX(MD5(Search_Query)), 1, 8), '-', FORMAT_DATE('%Y%m%d', current_week_start)) as recommendation_id,
    current_week_start,
    CURRENT_TIMESTAMP(),
    'NEW_EXPERIMENT' as category,
    CASE
      WHEN opportunity_type IN ('HIGH_IMP_HIGH_CONVERSION', 'PROVEN_ORGANIC_NO_ADS') THEN 'HIGH'
      WHEN opportunity_type = 'ORGANIC_ONLY_HIGH_VOLUME' THEN 'MEDIUM'
      ELSE 'LOW'
    END as priority,
    CONCAT(
      'Test ads on "', Search_Query, '" for ', ASIN,
      ' (', keyword_category, ', ', opportunity_type, ')'
    ) as title,
    CONCAT(
      'Last 8 weeks: ', CAST(search_total_impressions AS STRING), ' impressions, ',
      CAST(search_total_orders AS STRING), ' orders',
      ' | CTR: ', CAST(search_ctr_pct AS STRING), '%',
      ' | Conv: ', COALESCE(CAST(search_conversion_pct AS STRING), '0'), '%',
      ' | Ads coverage: ', coverage_status
    ) as detail,
    ASIN,
    Search_Query,
    priority_score as metric_value,
    'priority_score' as metric_label
  FROM `onyga-482313.OI.V_SEARCH_TERM_OPPORTUNITIES`
  WHERE coverage_status IN ('NO_ADS_COVERAGE', 'PREVIOUSLY_ADVERTISED')
    AND opportunity_type != 'LOW_PRIORITY'
  ORDER BY priority_score DESC
  LIMIT 10;

  -- =============================================
  -- 4. COVERAGE_GAP
  -- High impression terms with zero conversion (listing issues)
  -- =============================================
  INSERT INTO `onyga-482313.OI.FACT_EXPERIMENT_RECOMMENDATIONS`
    (recommendation_id, week_start_date, generated_at, category, priority, title, detail, asin, search_term, metric_value, metric_label)
  SELECT
    CONCAT('GAP-', ASIN, '-', SUBSTR(TO_HEX(MD5(Search_Query)), 1, 8), '-', FORMAT_DATE('%Y%m%d', current_week_start)) as recommendation_id,
    current_week_start,
    CURRENT_TIMESTAMP(),
    'COVERAGE_GAP' as category,
    CASE WHEN search_total_impressions > 50000 THEN 'HIGH' ELSE 'MEDIUM' END as priority,
    CONCAT(
      CAST(search_total_impressions AS STRING), ' impressions on "', Search_Query,
      '" with ', CAST(search_total_orders AS STRING), ' orders - possible listing issue'
    ) as title,
    CONCAT(
      'ASIN: ', ASIN,
      ' | CTR: ', CAST(search_ctr_pct AS STRING), '%',
      ' | Conv: ', COALESCE(CAST(search_conversion_pct AS STRING), '0'), '%',
      ' | Consider: main image optimization, title keywords, or negative keyword'
    ) as detail,
    ASIN,
    Search_Query,
    CAST(search_total_impressions AS FLOAT64) as metric_value,
    'search_total_impressions_8wk' as metric_label
  FROM `onyga-482313.OI.V_SEARCH_TERM_OPPORTUNITIES`
  WHERE opportunity_type = 'HIGH_IMP_ZERO_CONVERSION'
  ORDER BY search_total_impressions DESC
  LIMIT 5;

  -- =============================================
  -- 5. OPTIMIZATION
  -- Check active experiment campaigns for bid/placement optimization
  -- =============================================
  INSERT INTO `onyga-482313.OI.FACT_EXPERIMENT_RECOMMENDATIONS`
    (recommendation_id, week_start_date, generated_at, category, priority, title, detail, experiment_id, search_term, campaign_name, metric_value, metric_label)
  WITH top_performers AS (
    SELECT
      vst.experiment_id,
      vst.search_term,
      vst.asin,
      vst.experiment_campaigns,
      vst.ads_exp_orders,
      vst.ads_exp_cost,
      ROUND(SAFE_DIVIDE(vst.ads_exp_sales, NULLIF(vst.ads_exp_cost, 0)), 2) as term_roas,
      ROW_NUMBER() OVER (PARTITION BY vst.experiment_id ORDER BY vst.ads_exp_orders DESC) as rn
    FROM `onyga-482313.OI.V_EXPERIMENT_SEARCH_TERMS` vst
    WHERE vst.ads_exp_orders > 0
  )
  SELECT
    CONCAT('OPT-', experiment_id, '-', SUBSTR(TO_HEX(MD5(search_term)), 1, 8), '-', FORMAT_DATE('%Y%m%d', current_week_start)),
    current_week_start,
    CURRENT_TIMESTAMP(),
    'OPTIMIZATION',
    CASE WHEN term_roas > 3 THEN 'HIGH' ELSE 'MEDIUM' END,
    CONCAT('Top keyword "', search_term, '" has ROAS ', CAST(term_roas AS STRING), ' - consider increasing bid'),
    CONCAT(
      'Experiment: ', experiment_id,
      ' | Orders: ', CAST(ads_exp_orders AS STRING),
      ' | Cost: $', CAST(ROUND(ads_exp_cost, 0) AS STRING),
      ' | Campaign: ', experiment_campaigns
    ),
    experiment_id,
    search_term,
    experiment_campaigns,
    term_roas,
    'keyword_roas'
  FROM top_performers
  WHERE rn <= 3
    AND term_roas > 2
    AND experiment_id IN (SELECT experiment_id FROM `onyga-482313.OI.DIM_EXPERIMENT` WHERE status = 'ACTIVE');

  -- =============================================
  -- 6. STRATEGY_SUGGESTION
  -- Compare active experiment settings against best-performing settings
  -- from learnings to recommend specific optimizations
  -- =============================================
  INSERT INTO `onyga-482313.OI.FACT_EXPERIMENT_RECOMMENDATIONS`
    (recommendation_id, week_start_date, generated_at, category, priority, title, detail, experiment_id, campaign_name, metric_value, metric_label)
  WITH active_settings AS (
    -- Get settings for each active experiment campaign
    SELECT
      vcs.experiment_id,
      vcs.experiment_name,
      vcs.campaign_id,
      vcs.campaign_name,
      vcs.strategy_id,
      vcs.strategy_name,
      vcs.campaign_type,
      vcs.bidding_strategy,
      vcs.avg_keyword_bid,
      vcs.avg_default_bid,
      vcs.primary_match_type,
      vcs.top_of_search_pct,
      vcs.bid_range_bucket,
      vcs.has_top_of_search_boost
    FROM `onyga-482313.OI.V_EXPERIMENT_CAMPAIGN_SETTINGS` vcs
    WHERE vcs.experiment_status = 'ACTIVE'
  ),
  best_bidding AS (
    -- Find which bidding strategy has highest avg organic lift
    SELECT dimension_value as best_bidding_strategy, avg_organic_lift_pct
    FROM `onyga-482313.OI.V_EXPERIMENT_LEARNINGS`
    WHERE learning_dimension = 'bidding_strategy'
      AND experiment_count >= 1
    ORDER BY avg_organic_lift_pct DESC
    LIMIT 1
  ),
  best_bid_range AS (
    -- Find which bid range bucket works best
    SELECT dimension_value as best_bid_range, avg_organic_lift_pct
    FROM `onyga-482313.OI.V_EXPERIMENT_LEARNINGS`
    WHERE learning_dimension = 'bid_range'
      AND experiment_count >= 1
    ORDER BY avg_organic_lift_pct DESC
    LIMIT 1
  ),
  best_tos AS (
    -- Find if TOS boost experiments outperform non-TOS
    SELECT dimension_value as best_tos_setting, avg_organic_lift_pct
    FROM `onyga-482313.OI.V_EXPERIMENT_LEARNINGS`
    WHERE learning_dimension = 'top_of_search'
      AND experiment_count >= 1
    ORDER BY avg_organic_lift_pct DESC
    LIMIT 1
  ),
  suggestions AS (
    -- Generate suggestions where current settings differ from best-performing
    SELECT
      a.experiment_id,
      a.experiment_name,
      a.campaign_id,
      a.campaign_name,
      a.strategy_name,
      a.bidding_strategy as current_bidding,
      bb.best_bidding_strategy,
      bb.avg_organic_lift_pct as best_bidding_lift,
      a.bid_range_bucket as current_bid_range,
      br.best_bid_range,
      br.avg_organic_lift_pct as best_bid_lift,
      a.has_top_of_search_boost as current_has_tos,
      bt.best_tos_setting,
      bt.avg_organic_lift_pct as best_tos_lift,
      -- Flag: bidding strategy mismatch
      CASE WHEN a.bidding_strategy IS NOT NULL
        AND bb.best_bidding_strategy IS NOT NULL
        AND a.bidding_strategy != bb.best_bidding_strategy THEN TRUE ELSE FALSE END as suggest_bidding_change,
      -- Flag: bid range mismatch
      CASE WHEN a.bid_range_bucket IS NOT NULL
        AND br.best_bid_range IS NOT NULL
        AND a.bid_range_bucket != br.best_bid_range THEN TRUE ELSE FALSE END as suggest_bid_change,
      -- Flag: TOS boost missing but proven better
      CASE WHEN NOT a.has_top_of_search_boost
        AND bt.best_tos_setting LIKE 'TOS_BOOST%' THEN TRUE ELSE FALSE END as suggest_tos
    FROM active_settings a
    CROSS JOIN best_bidding bb
    CROSS JOIN best_bid_range br
    CROSS JOIN best_tos bt
  )
  SELECT
    CONCAT('STRAT-', experiment_id, '-', campaign_id, '-', FORMAT_DATE('%Y%m%d', current_week_start)) as recommendation_id,
    current_week_start,
    CURRENT_TIMESTAMP(),
    'STRATEGY_SUGGESTION' as category,
    'MEDIUM' as priority,
    CASE
      WHEN suggest_bidding_change THEN CONCAT(
        'Campaign "', campaign_name, '": Consider switching from ', current_bidding, ' to ', best_bidding_strategy,
        ' (avg organic lift: ', CAST(ROUND(best_bidding_lift, 1) AS STRING), '%)')
      WHEN suggest_tos THEN CONCAT(
        'Campaign "', campaign_name, '": Add top-of-search boost - experiments with TOS show ',
        CAST(ROUND(best_tos_lift, 1) AS STRING), '% avg organic lift')
      WHEN suggest_bid_change THEN CONCAT(
        'Campaign "', campaign_name, '": Current bid range is ', current_bid_range,
        ' but ', best_bid_range, ' range shows better results (',
        CAST(ROUND(best_bid_lift, 1) AS STRING), '% avg organic lift)')
      ELSE CONCAT(
        'Campaign "', campaign_name, '" settings align with best-performing patterns',
        COALESCE(CONCAT(' (strategy: ', strategy_name, ')'), ''))
    END as title,
    CONCAT(
      'Experiment: ', experiment_name,
      COALESCE(CONCAT(' | Strategy: ', strategy_name), ''),
      ' | Current bidding: ', COALESCE(current_bidding, 'N/A'),
      ' | Current bid range: ', COALESCE(current_bid_range, 'N/A'),
      ' | TOS boost: ', CASE WHEN current_has_tos THEN 'YES' ELSE 'NO' END,
      ' | Best bidding: ', COALESCE(best_bidding_strategy, 'N/A'),
      ' | Best bid range: ', COALESCE(best_bid_range, 'N/A'),
      ' | Best TOS: ', COALESCE(best_tos_setting, 'N/A')
    ) as detail,
    experiment_id,
    campaign_name,
    best_bidding_lift as metric_value,
    'best_organic_lift_pct' as metric_label
  FROM suggestions
  WHERE suggest_bidding_change OR suggest_bid_change OR suggest_tos;

  -- =============================================
  -- 7. STRATEGY_NEW_EXPERIMENT
  -- Recommend specific strategy templates for new experiments
  -- based on learnings + upcoming holidays + opportunities
  -- =============================================
  INSERT INTO `onyga-482313.OI.FACT_EXPERIMENT_RECOMMENDATIONS`
    (recommendation_id, week_start_date, generated_at, category, priority, title, detail, asin, search_term, metric_value, metric_label)
  WITH upcoming_holidays AS (
    SELECT holiday_name, holiday_date, category, pre_season_start, ramp_up_days
    FROM `onyga-482313.OI.DIM_US_HOLIDAYS`
    WHERE DATE_DIFF(pre_season_start, CURRENT_DATE(), DAY) BETWEEN -7 AND 14
    ORDER BY holiday_date
    LIMIT 1
  ),
  strategy_learnings AS (
    SELECT
      dimension_value as strategy_name,
      avg_organic_lift_pct,
      avg_roas,
      experiment_count,
      successful_count
    FROM `onyga-482313.OI.V_EXPERIMENT_LEARNINGS`
    WHERE learning_dimension = 'strategy'
      AND experiment_count >= 1
  ),
  top_opportunities AS (
    SELECT
      ASIN,
      Search_Query,
      keyword_category,
      opportunity_type,
      search_total_impressions,
      search_total_orders,
      priority_score
    FROM `onyga-482313.OI.V_SEARCH_TERM_OPPORTUNITIES`
    WHERE coverage_status IN ('NO_ADS_COVERAGE', 'PREVIOUSLY_ADVERTISED')
      AND opportunity_type != 'LOW_PRIORITY'
    ORDER BY priority_score DESC
    LIMIT 5
  ),
  strategy_recs AS (
    -- Recommend strategy based on opportunity + season
    SELECT
      opp.ASIN,
      opp.Search_Query,
      opp.keyword_category,
      opp.opportunity_type,
      opp.search_total_impressions,
      opp.search_total_orders,
      opp.priority_score,
      -- Pick strategy based on opportunity type and context
      CASE
        -- Seasonal context: if holiday approaching, use SEASONAL_PUSH
        WHEN h.holiday_name IS NOT NULL THEN 'SEASONAL_PUSH'
        -- Brand keyword: use BRAND_DEFENSE
        WHEN opp.keyword_category = 'brand' THEN 'BRAND_DEFENSE'
        -- High impression + high conversion: use EXACT_BOOST
        WHEN opp.opportunity_type = 'HIGH_IMP_HIGH_CONVERSION' THEN 'EXACT_BOOST'
        -- Proven organic but no ads: use EXACT_BOOST
        WHEN opp.opportunity_type = 'PROVEN_ORGANIC_NO_ADS' THEN 'EXACT_BOOST'
        -- High volume organic only: use CATEGORY_CONQUEST
        WHEN opp.opportunity_type = 'ORGANIC_ONLY_HIGH_VOLUME' THEN 'CATEGORY_CONQUEST'
        -- Default: LOW_COST_DISCOVERY
        ELSE 'LOW_COST_DISCOVERY'
      END as suggested_strategy_id,
      h.holiday_name as upcoming_holiday,
      h.holiday_date as holiday_date
    FROM top_opportunities opp
    CROSS JOIN (SELECT * FROM upcoming_holidays UNION ALL SELECT NULL, NULL, NULL, NULL, NULL) h
    WHERE h.holiday_name IS NOT NULL OR h.holiday_date IS NULL  -- keep all rows
    QUALIFY ROW_NUMBER() OVER (PARTITION BY opp.ASIN, opp.Search_Query ORDER BY CASE WHEN h.holiday_name IS NOT NULL THEN 0 ELSE 1 END) = 1
  )
  SELECT
    CONCAT('SNEW-', sr.ASIN, '-', SUBSTR(TO_HEX(MD5(sr.Search_Query)), 1, 8), '-', FORMAT_DATE('%Y%m%d', current_week_start)) as recommendation_id,
    current_week_start,
    CURRENT_TIMESTAMP(),
    'STRATEGY_NEW_EXPERIMENT' as category,
    CASE
      WHEN sr.upcoming_holiday IS NOT NULL THEN 'HIGH'
      WHEN sr.opportunity_type IN ('HIGH_IMP_HIGH_CONVERSION', 'PROVEN_ORGANIC_NO_ADS') THEN 'HIGH'
      ELSE 'MEDIUM'
    END as priority,
    CONCAT(
      'Try ', st.strategy_name, ' on "', sr.Search_Query, '" for ', sr.ASIN,
      CASE WHEN sr.upcoming_holiday IS NOT NULL
        THEN CONCAT(' (', sr.upcoming_holiday, ' approaching)')
        ELSE '' END
    ) as title,
    CONCAT(
      'Suggested strategy: ', st.strategy_name,
      ' | ', COALESCE(st.description, ''),
      ' | Recommended: ', COALESCE(st.recommended_campaign_type, 'SP'),
      ' ', COALESCE(st.recommended_match_type, ''),
      ' with ', COALESCE(st.recommended_bidding_strategy, ''),
      ' bidding',
      ' | Bid range: $', COALESCE(CAST(st.recommended_bid_min AS STRING), '?'),
      '-$', COALESCE(CAST(st.recommended_bid_max AS STRING), '?'),
      CASE WHEN COALESCE(st.recommended_top_of_search_pct, 0) > 0
        THEN CONCAT(' | TOS boost: ', CAST(st.recommended_top_of_search_pct AS STRING), '%')
        ELSE '' END,
      ' | Budget: $', COALESCE(CAST(st.recommended_daily_budget AS STRING), '?'), '/day',
      CASE WHEN sl.avg_organic_lift_pct IS NOT NULL
        THEN CONCAT(' | Past results: avg ', CAST(ROUND(sl.avg_organic_lift_pct, 1) AS STRING), '% organic lift from ', CAST(sl.experiment_count AS STRING), ' experiments')
        ELSE ' | No past results yet for this strategy' END
    ) as detail,
    sr.ASIN,
    sr.Search_Query,
    sr.priority_score as metric_value,
    'priority_score' as metric_label
  FROM strategy_recs sr
  JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st ON sr.suggested_strategy_id = st.strategy_id
  LEFT JOIN strategy_learnings sl ON st.strategy_name = sl.strategy_name
  -- Don't duplicate with existing NEW_EXPERIMENT recommendations
  WHERE NOT EXISTS (
    SELECT 1 FROM `onyga-482313.OI.FACT_EXPERIMENT_RECOMMENDATIONS` er
    WHERE er.week_start_date = current_week_start
      AND er.category = 'NEW_EXPERIMENT'
      AND er.asin = sr.ASIN
      AND er.search_term = sr.Search_Query
  );

  -- =============================================
  -- 8. EXPERIMENT_GRADUATION / EXPERIMENT_FAIL
  -- Evaluate experiments against graduation criteria from DIM_STRATEGY_TEMPLATE
  -- Graduation = experiment becomes a proven RULE
  -- =============================================
  INSERT INTO `onyga-482313.OI.FACT_EXPERIMENT_RECOMMENDATIONS`
    (recommendation_id, week_start_date, generated_at, category, priority, title, detail, experiment_id, metric_value, metric_label)
  WITH graduation_candidates AS (
    SELECT
      e.experiment_id,
      e.experiment_name,
      e.strategy_id,
      e.status,
      e.lifecycle_stage,
      DATE_DIFF(COALESCE(e.end_date, CURRENT_DATE()), e.start_date, DAY) as days_running,
      s.performance_seasonal_total_orders_lift_pct as seasonal_total_lift,
      s.performance_seasonal_organic_units_lift_pct as seasonal_organic_lift,
      s.ads_avg_roas,
      s.ads_total_spend,
      s.seasonal_adjustment_ratio,
      -- Graduation criteria from strategy template
      COALESCE(st.min_experiments_to_graduate, 2) as min_experiments,
      COALESCE(st.min_days_to_graduate, 28) as min_days,
      COALESCE(st.min_seasonal_lift_to_graduate, 0.0) as min_lift,
      st.strategy_name,
      -- Count how many experiments have already graduated for this strategy
      (SELECT COUNT(*) FROM `onyga-482313.OI.DIM_EXPERIMENT` e2
       WHERE e2.strategy_id = e.strategy_id AND e2.lifecycle_stage = 'GRADUATED') as prior_graduated,
      -- Season context
      CASE
        WHEN s.seasonal_adjustment_ratio >= 1.5 THEN 'PEAK'
        WHEN s.seasonal_adjustment_ratio < 0.5 THEN 'OFF_SEASON'
        ELSE 'NORMAL'
      END as experiment_season
    FROM `onyga-482313.OI.DIM_EXPERIMENT` e
    JOIN `onyga-482313.OI.V_EXPERIMENT_SUMMARY` s ON e.experiment_id = s.experiment_id
    LEFT JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st ON e.strategy_id = st.strategy_id
    WHERE e.status = 'ACTIVE'
      AND e.lifecycle_stage NOT IN ('GRADUATED', 'FAILED')
  ),
  evaluated AS (
    SELECT
      *,
      -- Check each graduation criterion
      days_running >= min_days as meets_duration,
      COALESCE(seasonal_total_lift, 0) >= min_lift as meets_lift,
      COALESCE(ads_avg_roas, 0) >= 2.0 as meets_roas,
      -- Overall graduation readiness
      CASE
        -- All criteria met → GRADUATE
        WHEN days_running >= min_days
          AND COALESCE(seasonal_total_lift, 0) >= min_lift
          AND COALESCE(ads_avg_roas, 0) >= 2.0
        THEN 'READY_TO_GRADUATE'
        -- Long-running with negative results → FAIL
        WHEN days_running >= min_days * 2
          AND (COALESCE(seasonal_total_lift, 0) < -10 OR COALESCE(ads_avg_roas, 0) < 1.0)
        THEN 'RECOMMEND_FAIL'
        -- Running long enough but mixed results → REVIEW
        WHEN days_running >= min_days
        THEN 'NEEDS_REVIEW'
        -- Not enough time yet
        ELSE 'TOO_EARLY'
      END as graduation_verdict,
      -- Confidence level
      CASE
        WHEN days_running >= min_days * 2 AND COALESCE(seasonal_total_lift, 0) > min_lift THEN 'HIGH'
        WHEN days_running >= min_days * 1.5 THEN 'MEDIUM'
        ELSE 'LOW'
      END as confidence
    FROM graduation_candidates
  )
  SELECT
    CONCAT('GRAD-', experiment_id, '-', FORMAT_DATE('%Y%m%d', current_week_start)),
    current_week_start,
    CURRENT_TIMESTAMP(),
    CASE graduation_verdict
      WHEN 'READY_TO_GRADUATE' THEN 'EXPERIMENT_GRADUATION'
      WHEN 'RECOMMEND_FAIL' THEN 'EXPERIMENT_FAIL'
      WHEN 'NEEDS_REVIEW' THEN 'EXPERIMENT_REVIEW'
      ELSE 'EXPERIMENT_REVIEW'
    END as category,
    CASE graduation_verdict
      WHEN 'READY_TO_GRADUATE' THEN 'HIGH'
      WHEN 'RECOMMEND_FAIL' THEN 'HIGH'
      ELSE 'MEDIUM'
    END as priority,
    CASE graduation_verdict
      WHEN 'READY_TO_GRADUATE' THEN CONCAT(
        experiment_name, ': READY TO GRADUATE - ',
        CAST(days_running AS STRING), ' days, ',
        'seasonal lift ', COALESCE(CAST(ROUND(seasonal_total_lift, 1) AS STRING), 'N/A'), '%, ',
        'ROAS ', COALESCE(CAST(ads_avg_roas AS STRING), 'N/A'),
        ' (', confidence, ' confidence)')
      WHEN 'RECOMMEND_FAIL' THEN CONCAT(
        experiment_name, ': RECOMMEND ENDING - ',
        CAST(days_running AS STRING), ' days with negative results')
      WHEN 'NEEDS_REVIEW' THEN CONCAT(
        experiment_name, ': Needs review at ', CAST(days_running AS STRING), ' days - criteria partially met')
      ELSE CONCAT(experiment_name, ': ', CAST(days_running AS STRING), '/', CAST(min_days AS STRING), ' days - collecting data')
    END as title,
    CONCAT(
      'Strategy: ', COALESCE(strategy_name, 'None'),
      ' | Days: ', CAST(days_running AS STRING), '/', CAST(min_days AS STRING),
      ' | Seasonal total lift: ', COALESCE(CAST(ROUND(seasonal_total_lift, 1) AS STRING), 'N/A'), '% (need >', CAST(ROUND(min_lift, 0) AS STRING), '%)',
      ' | ROAS: ', COALESCE(CAST(ads_avg_roas AS STRING), 'N/A'), ' (need >2.0)',
      ' | Spend: $', CAST(ROUND(COALESCE(ads_total_spend, 0), 0) AS STRING),
      ' | Season: ', experiment_season,
      ' | Confidence: ', confidence,
      ' | Prior graduated for this strategy: ', CAST(prior_graduated AS STRING),
      CASE graduation_verdict
        WHEN 'READY_TO_GRADUATE' THEN ' | ACTION: Run graduation to create a permanent rule'
        WHEN 'RECOMMEND_FAIL' THEN ' | ACTION: Set lifecycle_stage=FAILED, stop campaign, archive learnings'
        ELSE ''
      END
    ) as detail,
    experiment_id,
    COALESCE(seasonal_total_lift, 0) as metric_value,
    'graduation_readiness' as metric_label
  FROM evaluated
  WHERE graduation_verdict != 'TOO_EARLY';

  -- =============================================
  -- 9. SEASONAL_STRATEGY_ALERT
  -- Alert when current season doesn't match active strategy's applicability
  -- =============================================
  INSERT INTO `onyga-482313.OI.FACT_EXPERIMENT_RECOMMENDATIONS`
    (recommendation_id, week_start_date, generated_at, category, priority, title, detail, experiment_id, metric_value, metric_label)
  SELECT
    CONCAT('SALERT-', e.experiment_id, '-', FORMAT_DATE('%Y%m%d', current_week_start)),
    current_week_start,
    CURRENT_TIMESTAMP(),
    'SEASONAL_STRATEGY_ALERT' as category,
    'HIGH' as priority,
    CASE
      WHEN st.season_applicability = 'PEAK_ONLY' AND scr.current_season_mode = 'OFF_SEASON'
        THEN CONCAT(e.experiment_name, ': SEASONAL_PUSH strategy should NOT run in off-season - PAUSE campaign')
      WHEN st.season_applicability = 'PEAK_PREFERRED' AND scr.current_season_mode = 'OFF_SEASON'
        THEN CONCAT(e.experiment_name, ': ', st.strategy_name, ' is inefficient in off-season - reduce budget to ',
             CAST(ROUND(st.recommended_daily_budget * COALESCE(st.offseason_budget_multiplier, 0.5), 0) AS STRING), '$/day')
      WHEN scr.current_season_mode = 'PEAK' AND scr.is_applicable_now
        THEN CONCAT(e.experiment_name, ': Peak season! Scale ', st.strategy_name, ' budget to $',
             CAST(ROUND(scr.adjusted_daily_budget, 0) AS STRING), '/day (', CAST(ROUND(COALESCE(st.peak_budget_multiplier, 1.0), 1) AS STRING), 'x)')
      ELSE NULL
    END as title,
    CONCAT(
      'Strategy: ', st.strategy_name,
      ' | Applicability: ', COALESCE(st.season_applicability, 'ALL_SEASONS'),
      ' | Current season: ', scr.current_season_mode,
      ' | Seasonal index: ', CAST(ROUND(scr.current_seasonal_index, 2) AS STRING),
      ' | Base budget: $', CAST(st.recommended_daily_budget AS STRING),
      ' | Adjusted budget: $', CAST(ROUND(scr.adjusted_daily_budget, 0) AS STRING),
      ' | Base bid: $', CAST(st.recommended_bid_min AS STRING), '-$', CAST(st.recommended_bid_max AS STRING),
      ' | Adjusted bid: $', CAST(scr.adjusted_bid_min AS STRING), '-$', CAST(scr.adjusted_bid_max AS STRING)
    ) as detail,
    e.experiment_id,
    scr.current_seasonal_index as metric_value,
    'seasonal_index' as metric_label
  FROM `onyga-482313.OI.DIM_EXPERIMENT` e
  JOIN `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st ON e.strategy_id = st.strategy_id
  CROSS JOIN (
    SELECT * FROM `onyga-482313.OI.V_STRATEGY_CURRENT_RECOMMENDATIONS`
    LIMIT 1
  ) scr
  WHERE e.status = 'ACTIVE'
    AND (
      -- Alert: peak strategy in off-season
      (st.season_applicability IN ('PEAK_ONLY', 'PEAK_PREFERRED') AND scr.current_season_mode = 'OFF_SEASON')
      -- Alert: peak season - scale up
      OR (scr.current_season_mode = 'PEAK' AND COALESCE(st.peak_budget_multiplier, 1.0) > 1.0)
    );

  -- =============================================
  -- 10. BUDGET ACTIONS
  -- Read from V_EXPERIMENT_BUDGET_HEALTH and write budget/bid action recommendations.
  -- Timing: Day 1-7 = observation only, Day 7-14 = early signals,
  --         Day 14+ = decisive actions. Peak season: from day 5.
  -- =============================================
  INSERT INTO `onyga-482313.OI.FACT_EXPERIMENT_RECOMMENDATIONS`
    (recommendation_id, week_start_date, generated_at, category, priority, title, detail, experiment_id, metric_value, metric_label)
  SELECT
    CONCAT('BUDGET-', bh.experiment_id, '-', FORMAT_DATE('%Y%m%d', current_week_start)) as recommendation_id,
    current_week_start,
    CURRENT_TIMESTAMP(),
    CASE bh.budget_action
      WHEN 'SCALE_UP' THEN 'BUDGET_SCALE_UP'
      WHEN 'SCALE_UP_PEAK' THEN 'BUDGET_SCALE_UP'
      WHEN 'REDUCE' THEN 'BUDGET_REDUCE'
      WHEN 'PAUSE' THEN 'BUDGET_PAUSE'
      ELSE 'BUDGET_MAINTAIN'
    END as category,
    CASE bh.budget_action
      WHEN 'SCALE_UP' THEN 'HIGH'
      WHEN 'SCALE_UP_PEAK' THEN 'HIGH'
      WHEN 'PAUSE' THEN 'HIGH'
      WHEN 'REDUCE' THEN 'MEDIUM'
      ELSE 'LOW'
    END as priority,
    CASE bh.budget_action
      WHEN 'SCALE_UP' THEN CONCAT(
        bh.experiment_name, ': SCALE UP budget from $',
        CAST(ROUND(bh.expected_daily_budget, 0) AS STRING), ' to $',
        CAST(ROUND(bh.suggested_daily_budget, 0) AS STRING),
        '/day -- net ROAS ', CAST(bh.net_roas AS STRING),
        ' (profitable, $', CAST(ROUND(bh.net_roas - 1, 2) AS STRING), ' net profit per $1 ad spend)')
      WHEN 'SCALE_UP_PEAK' THEN CONCAT(
        bh.experiment_name, ': PEAK SEASON SCALE UP to $',
        CAST(ROUND(bh.suggested_daily_budget, 0) AS STRING),
        '/day -- net ROAS ', CAST(bh.net_roas AS STRING),
        ' (', COALESCE(bh.current_holiday, 'peak season'), ')')
      WHEN 'REDUCE' THEN CONCAT(
        bh.experiment_name, ': REDUCE budget from $',
        CAST(ROUND(bh.expected_daily_budget, 0) AS STRING), ' to $',
        CAST(ROUND(bh.suggested_daily_budget, 0) AS STRING),
        '/day -- net ROAS ', CAST(bh.net_roas AS STRING),
        ' < 1.0 (losing $', CAST(ROUND(1 - COALESCE(bh.net_roas, 0), 2) AS STRING), ' per $1 ad spend)')
      WHEN 'PAUSE' THEN CONCAT(
        bh.experiment_name, ': PAUSE campaigns -- ',
        CASE
          WHEN bh.total_orders = 0 THEN CONCAT('zero orders after ', CAST(bh.days_running AS STRING), ' days')
          ELSE CONCAT('net ROAS ', CAST(COALESCE(bh.net_roas, 0) AS STRING), ' after ', CAST(bh.days_running AS STRING), ' days')
        END)
      ELSE CONCAT(bh.experiment_name, ': Maintain current budget -- ', bh.action_explanation)
    END as title,
    CONCAT(
      'Days running: ', CAST(bh.days_running AS STRING),
      ' | Net ROAS: ', COALESCE(CAST(bh.net_roas AS STRING), 'N/A'),
      ' (>1.0 = profit)',
      ' | Ads-only net ROAS: ', COALESCE(CAST(bh.ads_only_net_roas AS STRING), 'N/A'),
      ' | Ad spend: $', CAST(ROUND(COALESCE(bh.cumulative_ad_spend, 0), 0) AS STRING),
      ' | Net profit: $', CAST(ROUND(COALESCE(bh.cumulative_net_profit, 0), 0) AS STRING),
      ' | Budget util: ', COALESCE(CAST(ROUND(bh.budget_utilization_pct, 0) AS STRING), 'N/A'), '%',
      ' | Total units: ', CAST(COALESCE(bh.total_units_sold, 0) AS STRING),
      ' (', CAST(COALESCE(bh.ads_units_sold, 0) AS STRING), ' ads + ',
      CAST(COALESCE(bh.organic_units_sold, 0) AS STRING), ' organic)',
      ' | Trend: ', bh.net_roas_trend,
      ' | This week net ROAS: ', COALESCE(CAST(bh.this_week_net_roas AS STRING), 'N/A'),
      ' | Margin/unit: $', COALESCE(CAST(bh.avg_margin_per_unit AS STRING), 'N/A'),
      CASE WHEN bh.is_peak_season THEN CONCAT(' | PEAK SEASON: ', COALESCE(bh.current_holiday, 'active')) ELSE '' END
    ) as detail,
    bh.experiment_id,
    bh.net_roas as metric_value,
    'net_roas' as metric_label
  FROM `onyga-482313.OI.V_EXPERIMENT_BUDGET_HEALTH` bh
  WHERE bh.budget_action != 'OBSERVE';

  -- =============================================
  -- 11. EXPERIMENT_CONCLUDE
  -- Recommend concluding experiments that have run long enough
  -- and have clear net ROAS signal (positive or negative)
  -- =============================================
  INSERT INTO `onyga-482313.OI.FACT_EXPERIMENT_RECOMMENDATIONS`
    (recommendation_id, week_start_date, generated_at, category, priority, title, detail, experiment_id, metric_value, metric_label)
  SELECT
    CONCAT('CONCLUDE-', bh.experiment_id, '-', FORMAT_DATE('%Y%m%d', current_week_start)) as recommendation_id,
    current_week_start,
    CURRENT_TIMESTAMP(),
    'EXPERIMENT_CONCLUDE' as category,
    CASE
      WHEN bh.net_roas >= 1.5 AND bh.days_running >= 21 THEN 'HIGH'
      WHEN bh.net_roas < 0.5 AND bh.days_running >= 14 THEN 'HIGH'
      ELSE 'MEDIUM'
    END as priority,
    CASE
      WHEN bh.net_roas >= 1.0 THEN CONCAT(
        'Conclude ', bh.experiment_name, ' after ', CAST(bh.days_running AS STRING),
        ' days -- net ROAS ', CAST(bh.net_roas AS STRING), ', verdict: PROFITABLE')
      ELSE CONCAT(
        'Conclude ', bh.experiment_name, ' after ', CAST(bh.days_running AS STRING),
        ' days -- net ROAS ', CAST(COALESCE(bh.net_roas, 0) AS STRING), ', verdict: UNPROFITABLE')
    END as title,
    CONCAT(
      'Net ROAS: ', COALESCE(CAST(bh.net_roas AS STRING), 'N/A'),
      ' | Net profit: $', CAST(ROUND(COALESCE(bh.cumulative_net_profit, 0), 0) AS STRING),
      ' | Total units: ', CAST(COALESCE(bh.total_units_sold, 0) AS STRING),
      ' | Strategy: ', COALESCE(bh.strategy_name, 'N/A'),
      ' | ACTION: Set status=COMPLETED, end_date=CURRENT_DATE() in DIM_EXPERIMENT',
      CASE WHEN bh.net_roas >= 1.0
        THEN '. Then run SP_UPDATE_ASIN_CONCLUSIONS to create DRAFT conclusion.'
        ELSE '. Consider FAILED lifecycle_stage.'
      END
    ) as detail,
    bh.experiment_id,
    bh.net_roas as metric_value,
    'net_roas' as metric_label
  FROM `onyga-482313.OI.V_EXPERIMENT_BUDGET_HEALTH` bh
  WHERE bh.days_running >= 21
    AND (bh.net_roas >= 1.5 OR bh.net_roas < 0.5 OR bh.days_running >= 28)
    -- Don't duplicate existing graduation recommendations
    AND NOT EXISTS (
      SELECT 1 FROM `onyga-482313.OI.FACT_EXPERIMENT_RECOMMENDATIONS` er
      WHERE er.week_start_date = current_week_start
        AND er.category IN ('EXPERIMENT_GRADUATION', 'EXPERIMENT_FAIL')
        AND er.experiment_id = bh.experiment_id
    );

  -- Count total recommendations generated
  SET rec_count = (
    SELECT COUNT(*)
    FROM `onyga-482313.OI.FACT_EXPERIMENT_RECOMMENDATIONS`
    WHERE week_start_date = current_week_start
  );

  SELECT FORMAT(
    'SP_EXPERIMENT_WEEKLY_REVIEW: Generated %d recommendations for week of %s',
    rec_count,
    FORMAT_DATE('%Y-%m-%d', current_week_start)
  ) as log_message;
END;
