// Cube: AdsFocusTerms - from V_ADS_FOCUS_TERMS
// Pre-ranked top 10 winners + top 10 losers by search term per week.
// ~21 rows/week → safe to load entirely into the dashboard.

cube(`AdsFocusTerms`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_ADS_FOCUS_TERMS\``,

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
      description: `Net profit (GROSS_PROFIT from FACT_AMAZON_ADS)`,
    },
    termCount: {
      sql: `term_count`,
      type: `sum`,
      description: `Number of distinct search terms aggregated (useful for "other" bucket)`,
    },
  },

  dimensions: {
    id: {
      sql: `CONCAT(CAST(week_start AS STRING), '|', focus_bucket, '|', COALESCE(search_term, ''), '|', COALESCE(asin, ''))`,
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
      description: `winner, loser, or other`,
    },
    searchTerm: {
      sql: `search_term`,
      type: `string`,
      description: `Search term (or __OTHER__ for aggregated remainder)`,
    },
    asin: {
      sql: `asin`,
      type: `string`,
      description: `Most advertised ASIN for this term`,
    },
    productShortName: {
      sql: `product_short_name`,
      type: `string`,
      description: `Product short name from DIM_PRODUCT`,
    },
  },

  refreshKey: {
    sql: `SELECT MAX(date) FROM \`onyga-482313.OI.FACT_AMAZON_ADS\``,
  },
});
