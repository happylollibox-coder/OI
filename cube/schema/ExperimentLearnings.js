// Cube: ExperimentLearnings - from V_EXPERIMENT_LEARNINGS
// Used for learnings (Learn page)
cube(`ExperimentLearnings`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_EXPERIMENT_LEARNINGS\``,

  refreshKey: { every: '30 minutes' },

  measures: {
    count: {
      type: `count`,
      description: `Number of learning rows`,
    },
    experimentCount: {
      sql: `experiment_count`,
      type: `sum`,
      description: `Experiments in this dimension`,
    },
  },

  dimensions: {
    rowKey: { sql: `row_key`, type: `string`, primaryKey: true },
    learningDimension: { sql: `learning_dimension`, type: `string` },
    dimensionValue: { sql: `dimension_value`, type: `string` },
    avgOrganicLiftPct: { sql: `avg_organic_lift_pct`, type: `number` },
    avgTotalLiftPct: { sql: `avg_total_lift_pct`, type: `number` },
    avgRoas: { sql: `avg_roas`, type: `number` },
    avgAdSpend: { sql: `avg_ad_spend`, type: `number` },
    avgDaysRunning: { sql: `avg_days_running`, type: `number` },
    successfulCount: { sql: `successful_count`, type: `number` },
    unsuccessfulCount: { sql: `unsuccessful_count`, type: `number` },
  },
});
