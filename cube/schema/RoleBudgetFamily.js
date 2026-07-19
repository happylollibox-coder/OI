// Cube: RoleBudgetFamily — one row per (family, role) for the Weekly Run Step-1 defense-type panels
// (BRAND_DEFENSE + PRODUCT_DEFENSE). Reads V_BUDGET_ROLE_FAMILY directly. Filter by `role` per panel.
cube(`RoleBudgetFamily`, {
  sql: `SELECT parent_name, role, weight, allocated, spend_7d, current_budget,
               ads_net_profit_day, ads_net_roas, n, n_underbid
        FROM \`onyga-482313.OI.V_BUDGET_ROLE_FAMILY\``,

  refreshKey: { every: `10 minutes` },

  measures: { count: { type: `count` } },

  dimensions: {
    // (parent_name, role) is the grain — composite key via a concat primaryKey.
    id:                    { sql: `CONCAT(parent_name, '|', role)`, type: `string`, primaryKey: true },
    parentName:            { sql: `parent_name`,        type: `string` },
    role:                  { sql: `role`,               type: `string` },
    weight:                { sql: `weight`,             type: `number` },
    allocated:             { sql: `allocated`,          type: `number` },
    spend7d:               { sql: `spend_7d`,           type: `number` },
    currentBudget:         { sql: `current_budget`,     type: `number` },
    adsNetProfitDay:       { sql: `ads_net_profit_day`, type: `number` },
    adsNetRoas:            { sql: `ads_net_roas`,       type: `number` },
    n:                     { sql: `n`,                  type: `number` },
    nUnderbid:             { sql: `n_underbid`,         type: `number` },
  },
});
