// Cube: ExperimentTemplates - experiments with ads performance
// Backed by: V_EXPERIMENT_TEMPLATES (BigQuery view)
// Grain: one row per experiment
//
// Rules compliance:
//   [x] R1: One cube = one entity (Experiment Templates)
//   [x] R2: sql_table pointing to BigQuery view (was: inline CTE)
//   [x] R5: View does all aggregation — cube exposes pre-computed values
cube(`ExperimentTemplates`, {
  sql_table: `\`onyga-482313.OI.V_EXPERIMENT_TEMPLATES\``,

  joins: {
    Experiment: {
      relationship: `belongsTo`,
      sql: `${CUBE}.experiment_id = ${Experiment}.experiment_id`,
    },
  },

  refreshKey: { every: '30 minutes' },

  measures: { count: { type: `count`, description: `Number of experiments` } },
  dimensions: {
    experimentId: { sql: `experiment_id`, type: `string`, primaryKey: true },
    experimentName: { sql: `experiment_name`, type: `string` },
    strategyId: { sql: `strategy_id`, type: `string` },
    description: { sql: `description`, type: `string` },
    status: { sql: `status`, type: `string` },
    startDate: { sql: `start_date`, type: `string` },
    endDate: { sql: `end_date`, type: `string` },
    baselineDays: { sql: `baseline_days`, type: `number` },
    outcomeScore: { sql: `outcome_score`, type: `number` },
    outcomeTags: { sql: `outcome_tags`, type: `string` },
    outcomeNotes: { sql: `outcome_notes`, type: `string` },
    lifecycleStage: { sql: `lifecycle_stage`, type: `string` },
    graduationConfidence: { sql: `graduation_confidence`, type: `string` },
    seasonContext: { sql: `season_context`, type: `string` },
    daysRunning: { sql: `days_running`, type: `number` },
    totalSpend: { sql: `total_spend`, type: `number` },
    totalOrders: { sql: `total_orders`, type: `number` },
    totalClicks: { sql: `total_clicks`, type: `number` },
    totalImpressions: { sql: `total_impressions`, type: `number` },
    totalSales: { sql: `total_sales`, type: `number` },
    netRoas: { sql: `net_roas`, type: `number` },
    convRate: { sql: `conv_rate`, type: `number` },
    cpc: { sql: `cpc`, type: `number` },
    uniqueSearchTerms: { sql: `unique_search_terms`, type: `number` },
  },
});
