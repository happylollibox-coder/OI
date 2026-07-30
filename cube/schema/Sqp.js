// Cube: SQP - from FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY
// Used for sqp_weekly, sqp_volume_4w
cube(`Sqp`, {
  sql: `SELECT * FROM \`onyga-482313.OI.FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY\``,

  joins: {
    Product: {
      relationship: `belongsTo`,
      sql: `${CUBE}.ASIN = ${Product}.asin`,
    },
  },

  measures: {
    count: {
      type: `count`,
      description: `Number of rows`,
    },
    impressions: {
      sql: `Impressions`,
      type: `sum`,
      description: `Your product impressions on this search query`,
    },
    amazonImpressions: {
      sql: `AMAZON_IMPRESSIONS`,
      type: `sum`,
      description: `Total Amazon marketplace impressions for this query`,
    },
    clicks: {
      sql: `Clicks`,
      type: `sum`,
      description: `Clicks on your product from this search`,
    },
    orders: {
      sql: `ORDERS`,
      type: `sum`,
      description: `Orders from this search query`,
    },
    cartAdds: {
      sql: `Cart_Adds`,
      type: `sum`,
      description: `Add-to-cart events`,
    },
    amazonClicks: {
      sql: `AMAZON_Clicks`,
      type: `sum`,
      description: `Total Amazon clicks for this query`,
    },
    amazonOrders: {
      sql: `AMAZON_ORDERS`,
      type: `sum`,
      description: `Total Amazon orders for this query`,
    },
    adsImpressions: {
      sql: `ADS_Impressions`,
      type: `sum`,
      description: `Impressions from ads on this search`,
    },
    adsClicks: {
      sql: `ADS_Clicks`,
      type: `sum`,
      description: `Clicks from ads on this search`,
    },
    adsOrders: {
      sql: `ADS_Orders`,
      type: `sum`,
      description: `Orders attributed to ads on this search`,
    },
  },

  dimensions: {
    id: {
      sql: `CONCAT(CAST(Reporting_Date AS STRING), '|', COALESCE(ASIN, ''), '|', COALESCE(Search_Query, ''))`,
      type: `string`,
      primaryKey: true,
    },
    reportingDate: {
      sql: `CAST(Reporting_Date AS TIMESTAMP)`,
      type: `time`,
      description: `Week ending date (Search Query Performance is weekly)`,
    },
    asin: {
      sql: `ASIN`,
      type: `string`,
      description: `Product ASIN`,
    },
    searchQuery: {
      sql: `Search_Query`,
      type: `string`,
      description: `Search term / query text`,
    },
    showRatePct: {
      sql: `show_rate_pct`,
      type: `number`,
      description: `Your share of Amazon impressions (Impressions / AMAZON_IMPRESSIONS × 100)`,
    },
    estimatedOrganicRank: {
      sql: `estimated_organic_rank`,
      type: `number`,
      description: `Estimated organic rank position (1–52+)`,
    },
    organicRankZone: {
      sql: `organic_rank_zone`,
      type: `string`,
      description: `Page zone: upper_p1, mid_p1, lower_p1, bottom_p1, page_2_plus`,
    },
    searchQueryScore: {
      sql: `Search_Query_Score`,
      type: `number`,
      description: `Amazon Search Query Score (relevance)`,
    },
  },

  // Restatement-safe key — see the note in Ads.js. Amazon backfills the open week IN PLACE:
  // on 2026-07-23 week 2026-07-18 went from 8,065 to 8,835 rows with ADS_Clicks 11,969 -> 11,961,
  // ADS_Orders 435 -> 443 and ORGANIC_ORDERS 99 -> 63, all while MAX(Reporting_Date) stayed 07-18.
  refreshKey: {
    sql: `SELECT last_modified_time FROM \`onyga-482313.OI.__TABLES__\` WHERE table_id = 'FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY'`,
  },

  preAggregations: {
    // Temporarily disabled — stale partition tables cause NOT FOUND errors
    // sqpWeekly: { ... },
  },
});
