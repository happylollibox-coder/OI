-- =============================================
-- OI Database Project - V_STRATEGY_CURRENT_RECOMMENDATIONS View
-- =============================================
--
-- Purpose: Shows recommended strategy settings adjusted for the CURRENT season.
--          Automatically applies peak/off-season multipliers based on this week's
--          seasonal index from V_SEASONAL_INDEX_WEEKLY.
--
--          Use this view when setting up new campaigns or adjusting existing ones -
--          it gives you the RIGHT numbers for RIGHT NOW.
--
-- Season classification:
--   PEAK:       seasonal_index >= 1.5 (Valentine's, Easter, Mother's Day, BF/CM, Christmas)
--   RAMP_UP:    seasonal_index >= 0.8 AND < 1.5 AND trending up before peak
--   NORMAL:     seasonal_index >= 0.5 AND < 1.5
--   OFF_SEASON: seasonal_index < 0.5 (summer, post-holiday January)
--
-- Source: DIM_STRATEGY_TEMPLATE, V_SEASONAL_INDEX_WEEKLY
-- Project: onyga-482313
-- Dataset: OI
--
-- =============================================

CREATE OR REPLACE VIEW `onyga-482313.OI.V_STRATEGY_CURRENT_RECOMMENDATIONS`
AS
WITH current_season AS (
  -- Find the current week's seasonal index
  SELECT
    si.reference_date,
    si.iso_week,
    si.seasonal_index,
    si.nearest_holiday,
    si.season_phase,
    -- Classify current season mode
    CASE
      WHEN si.seasonal_index >= 1.5 THEN 'PEAK'
      WHEN si.season_phase = 'RAMP_UP' THEN 'RAMP_UP'
      WHEN si.seasonal_index < 0.5 THEN 'OFF_SEASON'
      ELSE 'NORMAL'
    END as current_season_mode,
    si.seasonal_index as current_seasonal_index
  FROM `onyga-482313.OI.V_SEASONAL_INDEX_WEEKLY` si
  WHERE si.iso_week = EXTRACT(ISOWEEK FROM CURRENT_DATE())
),
-- Next 4 weeks lookahead for planning
upcoming_season AS (
  SELECT
    si.iso_week,
    si.seasonal_index,
    si.nearest_holiday,
    si.season_phase,
    CASE
      WHEN si.seasonal_index >= 1.5 THEN 'PEAK'
      WHEN si.season_phase = 'RAMP_UP' THEN 'RAMP_UP'
      WHEN si.seasonal_index < 0.5 THEN 'OFF_SEASON'
      ELSE 'NORMAL'
    END as season_mode
  FROM `onyga-482313.OI.V_SEASONAL_INDEX_WEEKLY` si
  WHERE si.iso_week BETWEEN EXTRACT(ISOWEEK FROM CURRENT_DATE()) + 1
    AND EXTRACT(ISOWEEK FROM CURRENT_DATE()) + 4
),
next_peak AS (
  SELECT MIN(iso_week) as next_peak_week, MIN(nearest_holiday) as next_peak_holiday
  FROM upcoming_season
  WHERE season_mode IN ('PEAK', 'RAMP_UP')
),
graduated_strategies AS (
  -- Count graduated experiments per strategy for confidence
  SELECT
    strategy_id,
    COUNT(*) as graduated_count,
    ROUND(AVG(outcome_score), 1) as avg_outcome_score
  FROM `onyga-482313.OI.DIM_EXPERIMENT`
  WHERE lifecycle_stage = 'GRADUATED'
  GROUP BY 1
)
SELECT
  st.strategy_id,
  st.strategy_name,
  st.description,

  -- Current season context
  cs.current_season_mode,
  cs.current_seasonal_index,
  cs.nearest_holiday as current_nearest_holiday,
  cs.season_phase as current_season_phase,

  -- Season applicability check
  st.season_applicability,
  CASE
    WHEN st.season_applicability = 'PEAK_ONLY' AND cs.current_season_mode = 'OFF_SEASON' THEN FALSE
    WHEN st.season_applicability = 'OFF_SEASON_ONLY' AND cs.current_season_mode = 'PEAK' THEN FALSE
    ELSE TRUE
  END as is_applicable_now,

  -- ADJUSTED settings for current season
  st.recommended_campaign_type,
  st.recommended_match_type,
  st.recommended_bidding_strategy,

  -- Adjusted bid range
  ROUND(st.recommended_bid_min * CASE
    WHEN cs.current_season_mode = 'PEAK' THEN COALESCE(st.peak_bid_multiplier, 1.0)
    WHEN cs.current_season_mode = 'RAMP_UP' THEN (1.0 + COALESCE(st.peak_bid_multiplier, 1.0)) / 2.0  -- halfway between normal and peak
    WHEN cs.current_season_mode = 'OFF_SEASON' THEN COALESCE(st.offseason_bid_multiplier, 1.0)
    ELSE 1.0
  END, 2) as adjusted_bid_min,

  ROUND(st.recommended_bid_max * CASE
    WHEN cs.current_season_mode = 'PEAK' THEN COALESCE(st.peak_bid_multiplier, 1.0)
    WHEN cs.current_season_mode = 'RAMP_UP' THEN (1.0 + COALESCE(st.peak_bid_multiplier, 1.0)) / 2.0
    WHEN cs.current_season_mode = 'OFF_SEASON' THEN COALESCE(st.offseason_bid_multiplier, 1.0)
    ELSE 1.0
  END, 2) as adjusted_bid_max,

  -- Adjusted daily budget
  ROUND(st.recommended_daily_budget * CASE
    WHEN cs.current_season_mode = 'PEAK' THEN COALESCE(st.peak_budget_multiplier, 1.0)
    WHEN cs.current_season_mode = 'RAMP_UP' THEN (1.0 + COALESCE(st.peak_budget_multiplier, 1.0)) / 2.0
    WHEN cs.current_season_mode = 'OFF_SEASON' THEN COALESCE(st.offseason_budget_multiplier, 1.0)
    ELSE 1.0
  END, 2) as adjusted_daily_budget,

  -- Adjusted TOS placement
  GREATEST(0, st.recommended_top_of_search_pct + CASE
    WHEN cs.current_season_mode = 'PEAK' THEN COALESCE(st.peak_tos_add_pct, 0)
    WHEN cs.current_season_mode = 'RAMP_UP' THEN COALESCE(st.peak_tos_add_pct, 0) / 2
    WHEN cs.current_season_mode = 'OFF_SEASON' THEN COALESCE(st.offseason_tos_add_pct, 0)
    ELSE 0
  END) as adjusted_top_of_search_pct,

  st.recommended_product_page_pct as adjusted_product_page_pct,

  -- Base (non-adjusted) settings for reference
  st.recommended_bid_min as base_bid_min,
  st.recommended_bid_max as base_bid_max,
  st.recommended_daily_budget as base_daily_budget,
  st.recommended_top_of_search_pct as base_top_of_search_pct,

  -- Seasonal guidance notes
  CASE
    WHEN cs.current_season_mode = 'PEAK' THEN st.peak_notes
    WHEN cs.current_season_mode = 'RAMP_UP' THEN CONCAT('Approaching peak: ', COALESCE(st.peak_notes, 'Prepare to scale up.'))
    WHEN cs.current_season_mode = 'OFF_SEASON' THEN st.offseason_notes
    ELSE 'Normal season. Use base settings.'
  END as seasonal_guidance,

  -- Upcoming peak warning
  np.next_peak_week,
  np.next_peak_holiday,
  CASE
    WHEN np.next_peak_week IS NOT NULL
    THEN CONCAT('Next peak in ~', CAST((np.next_peak_week - EXTRACT(ISOWEEK FROM CURRENT_DATE())) * 7 AS STRING), ' days: ', COALESCE(np.next_peak_holiday, 'unknown'))
    ELSE 'No peak in next 4 weeks'
  END as peak_lookahead,

  -- Graduation status
  COALESCE(gs.graduated_count, 0) as times_graduated,
  gs.avg_outcome_score as avg_graduated_score,
  st.min_experiments_to_graduate,
  st.min_days_to_graduate,
  st.min_seasonal_lift_to_graduate,

  st.use_case,
  st.is_active

FROM `onyga-482313.OI.DIM_STRATEGY_TEMPLATE` st
CROSS JOIN current_season cs
CROSS JOIN next_peak np
LEFT JOIN graduated_strategies gs ON st.strategy_id = gs.strategy_id
WHERE st.is_active = TRUE;
