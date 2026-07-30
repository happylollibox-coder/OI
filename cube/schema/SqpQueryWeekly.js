cube(`SqpQueryWeekly`, {
  sql: `SELECT * FROM \`onyga-482313\`.OI.V_SQP_QUERY_WEEKLY`,

  measures: {
    weeksAppeared:    { sql: `1`, type: `count` },
    totalImpressions: { sql: `TOTAL_IMPRESSIONS`, type: `sum` },
    totalClicks:      { sql: `TOTAL_CLICKS`, type: `sum` },
    totalPurchases:   { sql: `TOTAL_PURCHASES`, type: `sum` },
    brandImpressions: { sql: `BRAND_IMPRESSIONS`, type: `sum` },
    brandClicks:      { sql: `BRAND_CLICKS`, type: `sum` },
    brandPurchases:   { sql: `BRAND_PURCHASES`, type: `sum` },
    brandSales:       { sql: `BRAND_SALES`, type: `sum` },
    medianClickPrice: { sql: `TOTAL_MEDIAN_CLICK_PRICE`, type: `avg` },
  },

  dimensions: {
    id:            { sql: `CONCAT(Year, '-', Week, '-', query_text)`, type: `string`, primaryKey: true },
    queryText:     { sql: `query_text`, type: `string` },
    costTier:      { sql: `cost_tier`, type: `string` },
    gender:        { sql: `gender`, type: `string` },
    ageGroup:      { sql: `age_group`, type: `string` },
    occasion:      { sql: `occasion`, type: `string` },
    weekStartDate: { sql: `CAST(week_start_date AS TIMESTAMP)`, type: `time` },
  },

  // Restatement-safe key — see the note in Ads.js. Keys on the physical base table behind
  // V_SQP_QUERY_WEEKLY (FACT_SEARCH_QUERY), since a view has no last_modified_time of its own.
  // The open week backfills in place: on 2026-07-23 week 2026-07-12 went from 412 to 1,496
  // distinct queries and deduped market impressions 103.6M -> 208.5M, MAX(week_start_date) frozen.
  // DE_SEARCH_TERM_SEGMENTS and DIM_PRODUCT are included because the view's segment dimensions
  // (costTier / gender / ageGroup / occasion, and the brand classification) are derived from them.
  refreshKey: {
    sql: `SELECT MAX(last_modified_time) FROM \`onyga-482313.OI.__TABLES__\` WHERE table_id IN ('FACT_SEARCH_QUERY', 'DE_SEARCH_TERM_SEGMENTS', 'DIM_PRODUCT')`,
  },
});
