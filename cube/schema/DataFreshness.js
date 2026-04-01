// Cube: DataFreshness - max dates for ads and performance (for header freshness labels)
cube(`DataFreshness`, {
  refreshKey: { every: '30 minutes' },

  sql: `
SELECT 'ads' as source, MAX(\`date\`) as max_date FROM \`onyga-482313.OI.FACT_AMAZON_ADS\`
UNION ALL
SELECT 'perf' as source, MAX(\`DATE\`) as max_date
FROM \`onyga-482313.OI.FACT_AMAZON_PERFORMANCE_DAILY\` WHERE DATA_SOURCE = 'STG_AMAZON_PERFORMANCE'
`,

  measures: { count: { type: `count` } },
  dimensions: {
    source: { sql: `source`, type: `string`, primaryKey: true },
    maxDate: { sql: `CAST(max_date AS TIMESTAMP)`, type: `time` },
  },
});
