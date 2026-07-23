// Cube: CoachRunProduct - from T_WEEKLY_RUN_PRODUCT (Weekly Run Step 2 per-product budget panel).
cube(`CoachRunProduct`, {
  sql: `SELECT product, campaigns, recent_daily_spend, ads_net_day, ads_net_roas,
          net_profit_day, current_daily_budget, suggested_daily_budget
        FROM \`onyga-482313.OI.T_WEEKLY_RUN_PRODUCT\``,
  refreshKey: { sql: `SELECT MAX(finished_at) FROM \`onyga-482313.OI.LOG_PIPELINE_RUNS\` WHERE procedure_name = 'SP_REFRESH_CUBE_TABLES' AND status = 'OK'` },
  measures: { count: { type: `count` } },
  dimensions: {
    id: { sql: `product`, type: `string`, primaryKey: true },
    product: { sql: `product`, type: `string` },
    campaigns: { sql: `campaigns`, type: `number` },
    recentDailySpend: { sql: `recent_daily_spend`, type: `number` },
    adsNetDay: { sql: `ads_net_day`, type: `number` },
    adsNetRoas: { sql: `ads_net_roas`, type: `number` },
    netProfitDay: { sql: `net_profit_day`, type: `number` },
    currentDailyBudget: { sql: `current_daily_budget`, type: `number` },
    suggestedDailyBudget: { sql: `suggested_daily_budget`, type: `number` },
  },
});
