// Cube: ExperimentBudgetHealth - from V_EXPERIMENT_BUDGET_HEALTH
// Used for budget_health
cube(`ExperimentBudgetHealth`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_EXPERIMENT_BUDGET_HEALTH\``,

  refreshKey: { every: '30 minutes' },

  measures: {
    count: {
      type: `count`,
      description: `Number of budget health rows`,
    },
  },

  dimensions: {
    experimentId: {
      sql: `experiment_id`,
      type: `string`,
      primaryKey: true,
      description: `Experiment ID`,
    },
    experimentName: {
      sql: `experiment_name`,
      type: `string`,
      description: `Experiment name`,
    },
    dataStatus: {
      sql: `data_status`,
      type: `string`,
      description: `Data status`,
    },
    adsRoasTrend: {
      sql: `ads_roas_trend`,
      type: `string`,
      description: `ROAS trend`,
    },
    budgetUtilizationPct: {
      sql: `budget_utilization_pct`,
      type: `number`,
      description: `Budget utilization %`,
    },
  },
});
