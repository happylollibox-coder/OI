cube('PeakRelevance', {
  sql: () => `SELECT * FROM \`onyga-482313\`.OI.V_PEAK_RELEVANCE`,

  dimensions: {
    holidayName: { sql: () => `holiday_name`, type: 'string' },
    holidayDate: { sql: () => `holiday_date`, type: 'string' },
    family: { sql: () => `family`, type: 'string' },
    isRelevantPeak: { sql: () => `is_relevant_peak`, type: 'boolean' },
    confidence: { sql: () => `confidence`, type: 'string' },
    coachRecommendation: { sql: () => `coach_recommendation`, type: 'string' },
    reason: { sql: () => `reason`, type: 'string' },
    ordersChangePct: { sql: () => `orders_change_pct`, type: 'number' },
    unitsChangePct: { sql: () => `units_change_pct`, type: 'number' },
    salesChangePct: { sql: () => `sales_change_pct`, type: 'number' },
    netRoasDelta: { sql: () => `net_roas_delta`, type: 'number' },
    baselineAvgDailyOrders: { sql: () => `baseline_avg_daily_orders`, type: 'number' },
    peakAvgDailyOrders: { sql: () => `peak_avg_daily_orders`, type: 'number' },
    baselineNetRoas: { sql: () => `baseline_net_roas`, type: 'number' },
    peakNetRoas: { sql: () => `peak_net_roas`, type: 'number' },
  },
});
