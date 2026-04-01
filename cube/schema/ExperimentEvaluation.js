// Cube: ExperimentEvaluation - from V_EXPERIMENT_EVALUATION
// Read-only: per experiment check results and verdict
cube(`ExperimentEvaluation`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_EXPERIMENT_EVALUATION\``,

  refreshKey: { every: '30 minutes' },

  measures: {
    count: { type: `count`, description: `Number of experiments` },
  },

  dimensions: {
    experimentId: { sql: `experiment_id`, type: `string`, primaryKey: true },
    experimentName: { sql: `experiment_name`, type: `string` },
    strategyId: { sql: `strategy_id`, type: `string` },
    strategyName: { sql: `strategy_name`, type: `string` },
    status: { sql: `status`, type: `string` },
    startDate: { sql: `CAST(start_date AS TIMESTAMP)`, type: `time` },
    experimentDescription: { sql: `experiment_description`, type: `string` },
    strategyGoal: { sql: `strategy_goal`, type: `string` },
    useCase: { sql: `use_case`, type: `string` },

    // Performance
    totalSpend: { sql: `total_spend`, type: `number` },
    totalOrders: { sql: `total_orders`, type: `number` },
    totalSales: { sql: `total_sales`, type: `number` },
    daysWithData: { sql: `days_with_data`, type: `number` },
    uniqueTerms: { sql: `unique_terms`, type: `number` },
    convertingTerms: { sql: `converting_terms`, type: `number` },
    avgCpc: { sql: `avg_cpc`, type: `number` },
    cvrPct: { sql: `cvr_pct`, type: `number` },
    grossRoas: { sql: `gross_roas`, type: `number` },
    wastedSpend: { sql: `wasted_spend`, type: `number` },
    wastedPct: { sql: `wasted_pct`, type: `number` },
    termsGraduatedToExact: { sql: `terms_graduated_to_exact`, type: `number` },

    // Evidence
    topConvertingTerms: { sql: `top_converting_terms`, type: `string` },
    topWastedTerms: { sql: `top_wasted_terms`, type: `string` },

    // Checks
    check1Cpc: { sql: `check_1_cpc`, type: `string` },
    check2Roas: { sql: `check_2_roas`, type: `string` },
    check3Data: { sql: `check_3_data`, type: `string` },
    check4Discovery: { sql: `check_4_discovery`, type: `string` },
    check5Graduated: { sql: `check_5_graduated`, type: `string` },
    check6Waste: { sql: `check_6_waste`, type: `string` },
    check7Cvr: { sql: `check_7_cvr`, type: `string` },

    // Verdict
    verdict: { sql: `verdict`, type: `string` },
    verdictReason: { sql: `verdict_reason`, type: `string` },

    // Template thresholds
    recommendedBidMax: { sql: `recommended_bid_max`, type: `number` },
    recommendedDailyBudget: { sql: `recommended_daily_budget`, type: `number` },
  },
});
