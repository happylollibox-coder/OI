-- =============================================
-- OI Database Project - SP_SUGGEST_THRESHOLD_UPDATES Stored Procedure
-- =============================================
--
-- Purpose: Analyze experiment outcomes and promotion ramp-up data
--          to automatically suggest threshold adjustments.
--          Writes suggestions to DE_COACH_THRESHOLDS.suggested_value.
--
-- Run: CALL `onyga-482313.OI.SP_SUGGEST_THRESHOLD_UPDATES`();
--
-- Dependencies:
--   V_EXPERIMENT_EVALUATION, V_PROMOTION_RAMP_ANALYSIS,
--   DE_COACH_THRESHOLDS, DIM_STRATEGY_TEMPLATE, FACT_CAMPAIGN_CONFIG
--
-- Project: onyga-482313
-- Dataset: OI
-- =============================================

CREATE OR REPLACE PROCEDURE `onyga-482313.OI.SP_SUGGEST_THRESHOLD_UPDATES`()
BEGIN

  DECLARE now DATETIME DEFAULT CURRENT_DATETIME();

  -- =============================================
  -- SUGGESTION 1: EXACT_BOOST starting bid range
  -- If keywords with higher starting bids ramp faster (first order sooner),
  -- suggest adjusting recommended_bid_min/max
  -- =============================================
  -- Check avg starting bid for FAST_START vs SLOW_START/STALLED keywords
  MERGE INTO `onyga-482313.OI.DE_COACH_THRESHOLDS` t
  USING (
    SELECT
      'STARTING_BID_SUGGESTION' as threshold_key,
      'EXACT_BOOST' as strategy_id,
      CAST(NULL AS STRING) as product_family,
      -- If fast-start keywords have higher avg starting bid, suggest that as new min
      ROUND(AVG(CASE WHEN ramp_verdict = 'FAST_START' THEN starting_bid END), 2) as fast_start_avg_bid,
      ROUND(AVG(CASE WHEN ramp_verdict IN ('SLOW_START', 'STALLED') THEN starting_bid END), 2) as slow_start_avg_bid,
      COUNT(CASE WHEN ramp_verdict = 'FAST_START' THEN 1 END) as fast_count,
      COUNT(CASE WHEN ramp_verdict IN ('SLOW_START', 'STALLED') THEN 1 END) as slow_count
    FROM `onyga-482313.OI.V_PROMOTION_RAMP_ANALYSIS`
    WHERE starting_bid IS NOT NULL
      AND ramp_verdict IN ('FAST_START', 'NORMAL_START', 'SLOW_START', 'STALLED')
  ) s
  ON t.threshold_key = s.threshold_key AND t.strategy_id = s.strategy_id
  WHEN MATCHED AND s.fast_count >= 3 AND s.fast_start_avg_bid > COALESCE(s.slow_start_avg_bid, 0) THEN
    UPDATE SET
      suggested_value = s.fast_start_avg_bid,
      suggested_at = now,
      suggestion_reason = CONCAT(
        'FAST_START keywords avg starting bid: $', CAST(s.fast_start_avg_bid AS STRING),
        ' (', CAST(s.fast_count AS STRING), ' keywords). ',
        'SLOW/STALLED avg: $', CAST(COALESCE(s.slow_start_avg_bid, 0) AS STRING),
        ' (', CAST(s.slow_count AS STRING), ' keywords). ',
        'Suggest raising bid_min to $', CAST(s.fast_start_avg_bid AS STRING), '.'
      )
  WHEN NOT MATCHED AND s.fast_count >= 3 THEN
    INSERT (threshold_key, strategy_id, product_family, threshold_value, description,
            suggested_value, suggested_at, suggestion_reason, source, updated_at)
    VALUES (s.threshold_key, s.strategy_id, s.product_family, 0.5,
            'Starting bid suggestion based on ramp analysis',
            s.fast_start_avg_bid, now,
            CONCAT('FAST_START keywords avg bid: $', CAST(s.fast_start_avg_bid AS STRING)),
            'AUTO_SUGGEST', now);


  -- =============================================
  -- SUGGESTION 2: EXACT_BOOST TOS% effectiveness
  -- Compare TOS% between FAST_START and SLOW_START keywords
  -- =============================================
  MERGE INTO `onyga-482313.OI.DE_COACH_THRESHOLDS` t
  USING (
    SELECT
      'STARTING_TOS_SUGGESTION' as threshold_key,
      'EXACT_BOOST' as strategy_id,
      CAST(NULL AS STRING) as product_family,
      ROUND(AVG(CASE WHEN ramp_verdict = 'FAST_START' THEN starting_tos_pct END), 0) as fast_start_avg_tos,
      ROUND(AVG(CASE WHEN ramp_verdict IN ('SLOW_START', 'STALLED') THEN starting_tos_pct END), 0) as slow_start_avg_tos,
      COUNT(CASE WHEN ramp_verdict = 'FAST_START' THEN 1 END) as fast_count,
      COUNT(CASE WHEN ramp_verdict IN ('SLOW_START', 'STALLED') THEN 1 END) as slow_count
    FROM `onyga-482313.OI.V_PROMOTION_RAMP_ANALYSIS`
    WHERE starting_tos_pct IS NOT NULL
      AND ramp_verdict IN ('FAST_START', 'NORMAL_START', 'SLOW_START', 'STALLED')
  ) s
  ON t.threshold_key = s.threshold_key AND t.strategy_id = s.strategy_id
  WHEN MATCHED AND s.fast_count >= 3 THEN
    UPDATE SET
      suggested_value = s.fast_start_avg_tos,
      suggested_at = now,
      suggestion_reason = CONCAT(
        'FAST_START keywords avg TOS: ', CAST(CAST(s.fast_start_avg_tos AS INT64) AS STRING), '%. ',
        'SLOW/STALLED avg TOS: ', CAST(COALESCE(CAST(s.slow_start_avg_tos AS INT64), 0) AS STRING), '%. ',
        'Based on ', CAST(s.fast_count AS STRING), ' fast-starting keywords.'
      )
  WHEN NOT MATCHED AND s.fast_count >= 3 THEN
    INSERT (threshold_key, strategy_id, product_family, threshold_value, description,
            suggested_value, suggested_at, suggestion_reason, source, updated_at)
    VALUES (s.threshold_key, s.strategy_id, s.product_family, 500,
            'TOS% suggestion based on ramp analysis',
            s.fast_start_avg_tos, now,
            CONCAT('FAST_START avg TOS: ', CAST(CAST(s.fast_start_avg_tos AS INT64) AS STRING), '%'),
            'AUTO_SUGGEST', now);


  -- =============================================
  -- SUGGESTION 3: Wasted spend threshold per strategy
  -- If FAILING experiments consistently waste less than current threshold,
  -- suggest lowering it to catch waste earlier
  -- =============================================
  MERGE INTO `onyga-482313.OI.DE_COACH_THRESHOLDS` t
  USING (
    SELECT
      'WASTED_SPEND_THRESHOLD' as threshold_key,
      strategy_id,
      CAST(NULL AS STRING) as product_family,
      ROUND(AVG(wasted_spend), 0) as avg_wasted_spend,
      COUNT(*) as experiment_count
    FROM `onyga-482313.OI.V_EXPERIMENT_EVALUATION`
    WHERE verdict = 'FAILING'
      AND wasted_spend > 0
    GROUP BY strategy_id
  ) s
  ON t.threshold_key = s.threshold_key AND t.strategy_id = s.strategy_id
  WHEN MATCHED AND s.experiment_count >= 2
    AND s.avg_wasted_spend < t.threshold_value * 0.8 THEN
    UPDATE SET
      suggested_value = GREATEST(s.avg_wasted_spend * 0.8, 5),
      suggested_at = now,
      suggestion_reason = CONCAT(
        'FAILING experiments avg waste: $', CAST(s.avg_wasted_spend AS STRING),
        ' (', CAST(s.experiment_count AS STRING), ' experiments). ',
        'Current threshold: $', CAST(ROUND(t.threshold_value, 0) AS STRING),
        '. Suggest lowering to $', CAST(ROUND(GREATEST(s.avg_wasted_spend * 0.8, 5), 0) AS STRING),
        ' to catch waste earlier.'
      );


  -- =============================================
  -- SUGGESTION 4: PROMOTE threshold (weighted ROAS >= 1.4)
  -- Check success rate of promoted keywords
  -- =============================================
  MERGE INTO `onyga-482313.OI.DE_COACH_THRESHOLDS` t
  USING (
    SELECT
      'PROMOTE_ROAS_THRESHOLD' as threshold_key,
      'EXACT_BOOST' as strategy_id,
      CAST(NULL AS STRING) as product_family,
      COUNT(*) as total_promoted,
      COUNT(CASE WHEN ramp_verdict IN ('FAST_START', 'NORMAL_START') THEN 1 END) as successful_promotions,
      COUNT(CASE WHEN ramp_verdict IN ('STALLED', 'NO_CLICKS', 'NO_IMPRESSIONS') THEN 1 END) as failed_promotions,
      ROUND(SAFE_DIVIDE(
        COUNT(CASE WHEN ramp_verdict IN ('FAST_START', 'NORMAL_START') THEN 1 END),
        NULLIF(COUNT(*), 0)
      ) * 100, 1) as success_rate_pct
    FROM `onyga-482313.OI.V_PROMOTION_RAMP_ANALYSIS`
    WHERE ramp_verdict NOT IN ('TOO_EARLY', 'RAMPING')
  ) s
  ON t.threshold_key = s.threshold_key AND t.strategy_id = s.strategy_id
  WHEN MATCHED AND s.total_promoted >= 5 THEN
    UPDATE SET
      suggested_value = CASE
        WHEN s.success_rate_pct >= 80 THEN 1.2  -- very high success → can be less strict
        WHEN s.success_rate_pct >= 60 THEN 1.4  -- good success → keep current
        WHEN s.success_rate_pct >= 40 THEN 1.6  -- mediocre → raise threshold
        ELSE 2.0  -- poor → much stricter
      END,
      suggested_at = now,
      suggestion_reason = CONCAT(
        CAST(s.successful_promotions AS STRING), '/', CAST(s.total_promoted AS STRING),
        ' promoted keywords succeeded (',CAST(s.success_rate_pct AS STRING),'%). ',
        CASE
          WHEN s.success_rate_pct >= 80 THEN 'Excellent! Can lower promote threshold to 1.2.'
          WHEN s.success_rate_pct >= 60 THEN 'Good. Keep threshold at 1.4.'
          WHEN s.success_rate_pct >= 40 THEN 'Mediocre. Consider raising threshold to 1.6.'
          ELSE 'Poor. Raise threshold to 2.0 — too many promotions are failing.'
        END
      )
  WHEN NOT MATCHED AND s.total_promoted >= 5 THEN
    INSERT (threshold_key, strategy_id, product_family, threshold_value, description,
            suggested_value, suggested_at, suggestion_reason, source, updated_at)
    VALUES (s.threshold_key, s.strategy_id, s.product_family, 1.4,
            'Weighted ROAS threshold for promoting terms to EXACT_BOOST',
            CASE
              WHEN s.success_rate_pct >= 80 THEN 1.2
              WHEN s.success_rate_pct >= 60 THEN 1.4
              WHEN s.success_rate_pct >= 40 THEN 1.6
              ELSE 2.0
            END,
            now,
            CONCAT(CAST(s.success_rate_pct AS STRING), '% promotion success rate'),
            'AUTO_SUGGEST', now);


  -- =============================================
  -- SUGGESTION 5: CPC bid cap based on experiment outcomes
  -- If successful experiments consistently have CPC below template max,
  -- suggest tightening the range
  -- =============================================
  MERGE INTO `onyga-482313.OI.DE_COACH_THRESHOLDS` t
  USING (
    SELECT
      'BID_CAP_SUGGESTION' as threshold_key,
      strategy_id,
      CAST(NULL AS STRING) as product_family,
      ROUND(AVG(CASE WHEN verdict = 'SUCCESS' THEN avg_cpc END), 2) as success_avg_cpc,
      ROUND(AVG(CASE WHEN verdict = 'FAILING' THEN avg_cpc END), 2) as failing_avg_cpc,
      COUNT(CASE WHEN verdict = 'SUCCESS' THEN 1 END) as success_count,
      COUNT(CASE WHEN verdict = 'FAILING' THEN 1 END) as failing_count
    FROM `onyga-482313.OI.V_EXPERIMENT_EVALUATION`
    WHERE avg_cpc IS NOT NULL AND avg_cpc > 0
    GROUP BY strategy_id
  ) s
  ON t.threshold_key = s.threshold_key AND t.strategy_id = s.strategy_id
  WHEN MATCHED AND s.success_count >= 2 THEN
    UPDATE SET
      suggested_value = ROUND(s.success_avg_cpc * 1.2, 2),  -- 20% above success avg
      suggested_at = now,
      suggestion_reason = CONCAT(
        'SUCCESS experiments avg CPC: $', CAST(s.success_avg_cpc AS STRING),
        ' (', CAST(s.success_count AS STRING), '). ',
        'FAILING avg CPC: $', CAST(COALESCE(s.failing_avg_cpc, 0) AS STRING),
        ' (', CAST(s.failing_count AS STRING), '). ',
        'Suggested bid cap: $', CAST(ROUND(s.success_avg_cpc * 1.2, 2) AS STRING), '.'
      )
  WHEN NOT MATCHED AND s.success_count >= 2 THEN
    INSERT (threshold_key, strategy_id, product_family, threshold_value, description,
            suggested_value, suggested_at, suggestion_reason, source, updated_at)
    VALUES (s.threshold_key, s.strategy_id, s.product_family, 2.0,
            'Bid cap suggestion based on experiment CPC analysis',
            ROUND(s.success_avg_cpc * 1.2, 2), now,
            CONCAT('Based on ', CAST(s.success_count AS STRING), ' successful experiments'),
            'AUTO_SUGGEST', now);

END;
