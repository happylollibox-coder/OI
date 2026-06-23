cube('PeakKeywordRecs', {
  sql: () => `SELECT * FROM \`onyga-482313\`.OI.V_PEAK_KEYWORD_RECS`,

  dimensions: {
    holidayName: { sql: () => `holiday_name`, type: 'string' },
    parentName: { sql: () => `parent_name`, type: 'string' },
    searchTerm: { sql: () => `search_term`, type: 'string' },
    targetingStatus: { sql: () => `targeting_status`, type: 'string' },
    recommendation: { sql: () => `recommendation`, type: 'string' },
    matchBucket: { sql: () => `match_bucket`, type: 'string' },
    isTrending: { sql: () => `is_trending`, type: 'boolean' },
    isOwnBrand: { sql: () => `is_own_brand`, type: 'boolean' },
    wordCount: { sql: () => `word_count`, type: 'number' },
    lyPeakOrders: { sql: () => `ly_peak_orders`, type: 'number' },
    amazonVolume: { sql: () => `amazon_volume`, type: 'number' },
    amazonSales: { sql: () => `amazon_sales`, type: 'number' },
    lyNetRoas: { sql: () => `ly_net_roas`, type: 'number' },
    lyAdSpend: { sql: () => `ly_ad_spend`, type: 'number' },
    researchRank: { sql: () => `research_rank`, type: 'number' },
    isCurrentlyAdvertised: { sql: () => `is_currently_advertised`, type: 'boolean' },
    priorityScore: { sql: () => `priority_score`, type: 'number' },
    reason: { sql: () => `reason`, type: 'string' },
  },
});
