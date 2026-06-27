// Cube: CoachWeeklyPlan - from DE_WEEKLY_PLAN (Coacher D rolling weekly plan)
// Per-cell weekly plan; the This Week page reads the CURRENT-week rows, rolled up per product.
cube(`CoachWeeklyPlan`, {
  sql: `SELECT
          CONCAT(CAST(week_start AS STRING),'|',parent_name,'|',COALESCE(season,''),'|',COALESCE(match_type,''),'|',COALESCE(intent_class,'')) AS id,
          CAST(week_start AS STRING) AS week_start, horizon, parent_name, season, match_type, intent_class,
          purpose, success_metric, expected_value, planned_spend, spend_mode,
          expected_net_profit, status
        FROM \`onyga-482313.OI.DE_WEEKLY_PLAN\``,

  refreshKey: { every: '30 minutes' },

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
    intentClass: { sql: `intent_class`, type: `string` },
    purpose: { sql: `purpose`, type: `string` },
    successMetric: { sql: `success_metric`, type: `string` },
    expectedValue: { sql: `expected_value`, type: `number` },
    plannedSpendDim: { sql: `planned_spend`, type: `number` },
    spendMode: { sql: `spend_mode`, type: `string` },
    expectedNetProfit: { sql: `expected_net_profit`, type: `number` },
    status: { sql: `status`, type: `string` },
  },
});
