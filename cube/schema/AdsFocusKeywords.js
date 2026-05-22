// Cube: AdsFocusKeywords - from V_ADS_FOCUS_KEYWORDS
// Pre-ranked top 10 winners + top 10 losers by keyword target per week.
// ~21 rows/week → safe to load entirely into the dashboard.

cube(`AdsFocusKeywords`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_ADS_FOCUS_KEYWORDS\``,

  measures: {
    spend: {
      sql: `spend`,
      type: `sum`,
      format: `currency`,
      description: `Total ad spend`,
    },
    orders: {
      sql: `orders`,
      type: `sum`,
      description: `Orders attributed to ads`,
    },
    sales: {
      sql: `sales`,
      type: `sum`,
      format: `currency`,
      description: `Sales attributed to ads`,
    },
    netProfit: {
      sql: `net_profit`,
      type: `sum`,
      format: `currency`,
      description: `Net profit (GROSS_PROFIT - Ads_cost)`,
    },
    keywordCount: {
      sql: `keyword_count`,
      type: `sum`,
      description: `Number of distinct keywords aggregated (useful for "other" bucket)`,
    },
  },

  dimensions: {
    id: {
      sql: `CONCAT(CAST(week_start AS STRING), '|', focus_bucket, '|', COALESCE(keyword, ''))`,
      type: `string`,
      primaryKey: true,
    },
    weekStart: {
      sql: `CAST(week_start AS TIMESTAMP)`,
      type: `time`,
      description: `Week start (Sunday-aligned)`,
    },
    focusBucket: {
      sql: `focus_bucket`,
      type: `string`,
      description: `winner, loser, other_winners, or other_losers`,
    },
    keyword: {
      sql: `keyword`,
      type: `string`,
      description: `Keyword target (or __OTHER__ for aggregated remainder)`,
    },
  },

  refreshKey: {
    sql: `SELECT MAX(date) FROM \`onyga-482313.OI.FACT_AMAZON_ADS\``,
  },
});
