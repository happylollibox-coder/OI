// Cube: SQP x Ads by search term — from T_SQP_ADS_BY_TERM
// Feeds dashboard data.sqp_ads_by_term (SQP page Search Terms panel).
cube(`SqpAdsByTerm`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_SQP_ADS_BY_TERM\``,

  joins: {
    Product: {
      relationship: `belongsTo`,
      sql: `${CUBE}.asin = ${Product}.asin`,
    },
  },

  measures: {
    count:            { type: `count` },
    impressions:      { sql: `impressions`, type: `sum` },
    clicks:           { sql: `clicks`, type: `sum` },
    cartAdds:         { sql: `cart_adds`, type: `sum` },
    orders:           { sql: `orders`, type: `sum` },
    organicOrders:    { sql: `organic_orders`, type: `sum` },
    amazonImpressions:{ sql: `amazon_impressions`, type: `sum` },
    amazonOrders:     { sql: `amazon_orders`, type: `sum` },
    adImpressions:    { sql: `ad_impressions`, type: `sum` },
    adClicks:         { sql: `ad_clicks`, type: `sum` },
    adOrders:         { sql: `ad_orders`, type: `sum` },
    adUnits:          { sql: `ad_units`, type: `sum` },
    adSpend:          { sql: `ad_spend`, type: `sum` },
    adSales:          { sql: `ad_sales`, type: `sum` },
    adGrossProfit:    { sql: `ad_gross_profit`, type: `sum` },
  },

  dimensions: {
    id: {
      sql: `CONCAT(CAST(reporting_date AS STRING), '|', COALESCE(asin,''), '|', COALESCE(term_key,''))`,
      type: `string`,
      primaryKey: true,
    },
    reportingDate:        { sql: `CAST(reporting_date AS TIMESTAMP)`, type: `time` },
    asin:                 { sql: `asin`, type: `string` },
    searchTerm:           { sql: `search_term`, type: `string` },
    showRatePct:          { sql: `show_rate_pct`, type: `number` },
    estimatedOrganicRank: { sql: `estimated_organic_rank`, type: `number` },
    organicRankZone:      { sql: `organic_rank_zone`, type: `string` },
    searchQueryScore:     { sql: `search_query_score`, type: `number` },
  },

  refreshKey: {
    sql: `SELECT MAX(reporting_date) FROM \`onyga-482313.OI.T_SQP_ADS_BY_TERM\``,
  },
});
