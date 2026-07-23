// Cube: CoachWeeklyPlan - from DE_WEEKLY_PLAN (Coacher D rolling weekly plan)
// Per-cell weekly plan; the This Week page reads the CURRENT-week rows, rolled up per product.
cube(`CoachWeeklyPlan`, {
  sql: `SELECT
          CONCAT(CAST(week_start AS STRING),'|',parent_name,'|',COALESCE(season,''),'|',COALESCE(match_type,''),'|',COALESCE(intent_class,''),'|',COALESCE(campaign_type,''),'|',COALESCE(ad_format,'')) AS id,
          CAST(week_start AS STRING) AS week_start, horizon, parent_name, season, match_type, intent_class,
          campaign_type, ad_format,
          purpose, success_metric, expected_value, planned_spend, spend_mode,
          target_cpc, expected_net_profit, status, last_net, last_spend, last_units, last_cpc, actual_cpc, units_8w,
          avg_net_day_off, avg_net_day_peak,
          -- Coverage role, so the Weekly Run strategy filter slices the plan the same way it slices
          -- campaigns. Plan cells are at (match_type x intent x campaign_type) grain and carry no
          -- campaign_id, so they cannot join V_CAMPAIGN_ROLE — this mirrors its CASE and MUST be kept in
          -- step with it (same precedence: SB beats match type; AUTO next; ASIN/category = COMPETITOR).
          CASE
            WHEN UPPER(campaign_type) = 'SB'                       THEN 'SB_VIDEO'
            WHEN UPPER(match_type) = 'AUTO'                        THEN 'AUTO'
            WHEN UPPER(match_type) IN ('PRODUCT', 'CATEGORY')      THEN 'COMPETITOR'
            WHEN UPPER(match_type) IN ('EXACT', 'BROAD', 'PHRASE') THEN UPPER(match_type)
            ELSE 'OTHER'
          END AS strategy_role
        FROM \`onyga-482313.OI.T_WEEKLY_PLAN_CELL\``,

  refreshKey: { sql: `SELECT MAX(finished_at) FROM \`onyga-482313.OI.LOG_PIPELINE_RUNS\` WHERE procedure_name = 'SP_REFRESH_CUBE_TABLES' AND status = 'OK'` },

  measures: {
    count: { type: `count` },
    plannedSpend: { sql: `planned_spend`, type: `sum` },
  },

  dimensions: {
    id: { sql: `id`, type: `string`, primaryKey: true },
    weekStart: { sql: `week_start`, type: `string` },
    horizon: { sql: `horizon`, type: `string` },
    parentName: { sql: `parent_name`, type: `string` },
    season: { sql: `season`, type: `string` },
    matchType: { sql: `match_type`, type: `string` },
    strategyRole: { sql: `strategy_role`, type: `string` },
    intentClass: { sql: `intent_class`, type: `string` },
    campaignType: { sql: `campaign_type`, type: `string` },
    adFormat: { sql: `ad_format`, type: `string` },
    purpose: { sql: `purpose`, type: `string` },
    successMetric: { sql: `success_metric`, type: `string` },
    expectedValue: { sql: `expected_value`, type: `number` },
    plannedSpendDim: { sql: `planned_spend`, type: `number` },
    spendMode: { sql: `spend_mode`, type: `string` },
    targetCpc: { sql: `target_cpc`, type: `number` },
    actualCpc: { sql: `actual_cpc`, type: `number` },
    lastNet: { sql: `last_net`, type: `number` },
    lastSpend: { sql: `last_spend`, type: `number` },
    lastUnits: { sql: `last_units`, type: `number` },
    lastCpc: { sql: `last_cpc`, type: `number` },
    units8w: { sql: `units_8w`, type: `number` },
    avgNetDayOff: { sql: `avg_net_day_off`, type: `number` },
    avgNetDayPeak: { sql: `avg_net_day_peak`, type: `number` },
    expectedNetProfit: { sql: `expected_net_profit`, type: `number` },
    status: { sql: `status`, type: `string` },
  },
});
