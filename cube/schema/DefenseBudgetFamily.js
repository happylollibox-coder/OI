// Cube: DefenseBudgetFamily — one row per family with defense campaigns, for the Weekly Run Step-1
// DEFENSE panel. Reads V_BUDGET_DEFENSE_FAMILY directly (small, config-driven — no T_ materialization).
cube(`DefenseBudgetFamily`, {
  sql: `SELECT parent_name, weight, defense_allocated, defense_spend_7d, defense_current_budget,
               ads_net_profit_day, ads_net_roas, n_defense, n_underbid
        FROM \`onyga-482313.OI.V_BUDGET_DEFENSE_FAMILY\``,

  refreshKey: { every: `10 minutes` },

  measures: { count: { type: `count` } },

  dimensions: {
    parentName:            { sql: `parent_name`,            type: `string`, primaryKey: true },
    weight:                { sql: `weight`,                 type: `number` },
    defenseAllocated:      { sql: `defense_allocated`,      type: `number` },
    defenseSpend7d:        { sql: `defense_spend_7d`,       type: `number` },
    defenseCurrentBudget:  { sql: `defense_current_budget`, type: `number` },
    adsNetProfitDay:       { sql: `ads_net_profit_day`,     type: `number` },
    adsNetRoas:            { sql: `ads_net_roas`,           type: `number` },
    nDefense:              { sql: `n_defense`,              type: `number` },
    nUnderbid:             { sql: `n_underbid`,             type: `number` },
  },
});
