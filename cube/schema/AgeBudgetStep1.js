// Cube: AgeBudgetStep1 — one row per age bucket (NEW <=20d / 1-3MO / 4-9MO / 10MO+) for the Weekly Run
// "Budget by age" split, the sibling of StrategyBudgetStep1. Same columns, grouped by age instead of
// strategy role. Reads V_BUDGET_STEP1_AGE directly (small, config-driven — no T_ materialization needed).
cube(`AgeBudgetStep1`, {
  sql: `SELECT age_bucket, n_campaigns, losing_spend_7d, margin_spend_7d, winning_spend_7d,
               total_spend_7d, last_cpc_7d, ads_net_profit_avg, current_budget, allocated_daily
        FROM \`onyga-482313.OI.V_BUDGET_STEP1_AGE\``,

  refreshKey: { every: `10 minutes` },

  measures: { count: { type: `count` } },

  dimensions: {
    ageBucket:       { sql: `age_bucket`,        type: `string`, primaryKey: true },
    nCampaigns:      { sql: `n_campaigns`,       type: `number` },
    losingSpend7d:   { sql: `losing_spend_7d`,   type: `number` },
    marginSpend7d:   { sql: `margin_spend_7d`,   type: `number` },
    winningSpend7d:  { sql: `winning_spend_7d`,  type: `number` },
    totalSpend7d:    { sql: `total_spend_7d`,    type: `number` },
    lastCpc7d:       { sql: `last_cpc_7d`,       type: `number` },
    adsNetProfitAvg: { sql: `ads_net_profit_avg`, type: `number` },
    currentBudget:   { sql: `current_budget`,    type: `number` },
    allocatedDaily:  { sql: `allocated_daily`,   type: `number` },
  },
});
