// Cube: Experiment - from DIM_EXPERIMENT
cube(`Experiment`, {
  sql: `SELECT * FROM \`onyga-482313.OI.DIM_EXPERIMENT\``,

  refreshKey: { every: '1 hour' },

  measures: {
    count: {
      type: `count`,
      description: `Number of experiments`,
    },
  },

  dimensions: {
    experimentId: {
      sql: `experiment_id`,
      type: `string`,
      primaryKey: true,
      description: `Unique experiment identifier`,
    },
    experimentName: {
      sql: `experiment_name`,
      type: `string`,
      description: `Experiment display name`,
    },
    strategyId: {
      sql: `strategy_id`,
      type: `string`,
      description: `Strategy template this experiment follows`,
    },
    status: {
      sql: `status`,
      type: `string`,
      description: `Experiment status (e.g. active, paused, completed)`,
    },
    startDate: {
      sql: `CAST(start_date AS TIMESTAMP)`,
      type: `time`,
      description: `Experiment start date`,
    },
    endDate: {
      sql: `CAST(end_date AS TIMESTAMP)`,
      type: `time`,
      description: `Experiment end date`,
    },
  },
});
