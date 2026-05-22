// Cube: DataFreshness - max dates for ads and performance (for header freshness labels)
// Backed by: V_DATA_FRESHNESS (BigQuery view)
// Grain: one row per data source
//
// Rules compliance:
//   [x] R2: sql_table pointing to BigQuery view (was: inline UNION ALL)
cube(`DataFreshness`, {
  // The dashboard only needs 'ads' and 'perf' sources for header labels.
  // V_DATA_FRESHNESS has all sources; filter to the two needed here.
  sql: `SELECT source_name AS source, latest_date AS max_date
        FROM \`onyga-482313.OI.V_DATA_FRESHNESS\`
        WHERE source_name IN ('FACT_AMAZON_ADS', 'FACT_AMAZON_PERFORMANCE_DAILY')`,

  refreshKey: { every: '30 minutes' },

  measures: { count: { type: `count` } },
  dimensions: {
    source: { sql: `source`, type: `string`, primaryKey: true },
    maxDate: { sql: `CAST(max_date AS TIMESTAMP)`, type: `time` },
  },
});
