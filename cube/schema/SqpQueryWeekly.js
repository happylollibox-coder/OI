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

  refreshKey: { sql: `SELECT MAX(week_start_date) FROM \`onyga-482313\`.OI.V_SQP_QUERY_WEEKLY` },
});
