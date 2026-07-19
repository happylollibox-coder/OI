// Cube: FamilyBudgetStep1 — one row per family for the Weekly Run Step-1 waterfall table.
// Reads V_BUDGET_STEP1_FAMILY directly (small, config-driven — no T_ materialization needed).
cube(`FamilyBudgetStep1`, {
  sql: `SELECT parent_name, floor, allocated_daily, source,
               business_net_profit_avg, ads_net_profit_avg, weight,
               losing_spend_7d, margin_spend_7d, winning_spend_7d, total_spend_7d, last_cpc_7d, current_budget
        FROM \`onyga-482313.OI.V_BUDGET_STEP1_FAMILY\``,

  refreshKey: { every: `10 minutes` },

  measures: { count: { type: `count` } },

  dimensions: {
    parentName:           { sql: `parent_name`,             type: `string`, primaryKey: true },
    floor:                { sql: `floor`,                   type: `number` },
    allocatedDaily:       { sql: `allocated_daily`,         type: `number` },
    source:               { sql: `source`,                  type: `string` },
    businessNetProfitAvg: { sql: `business_net_profit_avg`, type: `number` },
    adsNetProfitAvg:      { sql: `ads_net_profit_avg`,      type: `number` },
    weight:               { sql: `weight`,                  type: `number` },
    losingSpend7d:        { sql: `losing_spend_7d`,         type: `number` },
    marginSpend7d:        { sql: `margin_spend_7d`,         type: `number` },
    winningSpend7d:       { sql: `winning_spend_7d`,        type: `number` },
    totalSpend7d:         { sql: `total_spend_7d`,          type: `number` },
    lastCpc7d:            { sql: `last_cpc_7d`,             type: `number` },
    currentBudget:        { sql: `current_budget`,          type: `number` },
  },
});
