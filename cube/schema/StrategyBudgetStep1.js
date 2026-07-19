// Cube: StrategyBudgetStep1 — one row per Coverage role (strategy) for the Weekly Run Step-1 strategy
// split, the sibling of FamilyBudgetStep1. Offense sub-roles only (AUTO / EXACT / BROAD / PHRASE /
// COMPETITOR / SB_VIDEO / OTHER) — brand + product defense have their own PPC modes and budget panels.
// Reads V_BUDGET_STEP1_STRATEGY directly (small, config-driven — no T_ materialization needed).
cube(`StrategyBudgetStep1`, {
  sql: `SELECT strategy_role, n_campaigns, losing_spend_7d, margin_spend_7d, winning_spend_7d,
               total_spend_7d, last_cpc_7d, ads_net_profit_avg, net_incl_halo_avg,
               current_budget, allocated_daily
        FROM \`onyga-482313.OI.V_BUDGET_STEP1_STRATEGY\``,

  refreshKey: { every: `10 minutes` },

  measures: { count: { type: `count` } },

  dimensions: {
    strategyRole:    { sql: `strategy_role`,     type: `string`, primaryKey: true },
    nCampaigns:      { sql: `n_campaigns`,       type: `number` },
    losingSpend7d:   { sql: `losing_spend_7d`,   type: `number` },
    marginSpend7d:   { sql: `margin_spend_7d`,   type: `number` },
    winningSpend7d:  { sql: `winning_spend_7d`,  type: `number` },
    totalSpend7d:    { sql: `total_spend_7d`,    type: `number` },
    lastCpc7d:       { sql: `last_cpc_7d`,       type: `number` },
    adsNetProfitAvg: { sql: `ads_net_profit_avg`, type: `number` },
    netInclHaloAvg:  { sql: `net_incl_halo_avg`, type: `number` },
    currentBudget:   { sql: `current_budget`,    type: `number` },
    allocatedDaily:  { sql: `allocated_daily`,   type: `number` },
  },
});
