// Cube: CoachWeeklyBenchmark - from V_WEEKLY_PRODUCT_BENCHMARK (Coacher D surface).
// Per-product peak/offseason historical net+spend benchmarks for the This Week page.
cube(`CoachWeeklyBenchmark`, {
  sql: `SELECT
          parent_name,
          last_peak_week, last_peak_net, last_peak_spend, peak_avg4_net, peak_avg4_spend, peak_weeks_n, peak_avg_from_week,
          last_off_week, last_off_net, last_off_spend, off_avg4_net, off_avg4_spend, off_weeks_n, off_avg_from_week
        FROM \`onyga-482313.OI.V_WEEKLY_PRODUCT_BENCHMARK\``,

  refreshKey: { every: '30 minutes' },

  measures: { count: { type: `count` } },

  dimensions: {
    parentName: { sql: `parent_name`, type: `string`, primaryKey: true },
    lastPeakWeek: { sql: `last_peak_week`, type: `string` },
    lastPeakNet: { sql: `last_peak_net`, type: `number` },
    lastPeakSpend: { sql: `last_peak_spend`, type: `number` },
    peakAvg4Net: { sql: `peak_avg4_net`, type: `number` },
    peakAvg4Spend: { sql: `peak_avg4_spend`, type: `number` },
    peakWeeksN: { sql: `peak_weeks_n`, type: `number` },
    peakAvgFromWeek: { sql: `peak_avg_from_week`, type: `string` },
    lastOffWeek: { sql: `last_off_week`, type: `string` },
    lastOffNet: { sql: `last_off_net`, type: `number` },
    lastOffSpend: { sql: `last_off_spend`, type: `number` },
    offAvg4Net: { sql: `off_avg4_net`, type: `number` },
    offAvg4Spend: { sql: `off_avg4_spend`, type: `number` },
    offWeeksN: { sql: `off_weeks_n`, type: `number` },
    offAvgFromWeek: { sql: `off_avg_from_week`, type: `string` },
  },
});
