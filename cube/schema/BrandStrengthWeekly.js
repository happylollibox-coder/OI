cube(`BrandStrengthWeekly`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_BRAND_STRENGTH_WEEKLY\``,

  dimensions: {
    weekStartDate: {
      sql: `CAST(week_start_date AS STRING)`,
      type: `string`,
      primaryKey: true,
    },
    brandKeyword: {
      sql: `brand_keyword`,
      type: `string`,
    },
    phraseType: {
      sql: `phrase_type`,
      type: `string`,
    },
    requestedProduct: {
      sql: `requested_product`,
      type: `string`,
    },
    tag: {
      sql: `tag`,
      type: `string`,
    },
  },

  measures: {
    // SQP metrics
    sqpImpressions: {
      sql: `sqp_impressions`,
      type: `sum`,
    },
    sqpClicks: {
      sql: `sqp_clicks`,
      type: `sum`,
    },
    sqpConversions: {
      sql: `sqp_conversions`,
      type: `sum`,
    },
    sqpCartAdds: {
      sql: `sqp_cart_adds`,
      type: `sum`,
    },
    avgShowRate: {
      sql: `avg_show_rate`,
      type: `avg`,
    },
    avgImpressionShare: {
      sql: `avg_impression_share`,
      type: `avg`,
    },
    avgOrganicRank: {
      sql: `avg_organic_rank`,
      type: `avg`,
    },
    totalSearchVolume: {
      sql: `total_search_volume`,
      type: `sum`,
    },
    brandQueryCount: {
      sql: `brand_query_count`,
      type: `max`,
    },

    // Ads metrics
    adsImpressions: {
      sql: `ads_impressions`,
      type: `sum`,
    },
    adsClicks: {
      sql: `ads_clicks`,
      type: `sum`,
    },
    adsOrders: {
      sql: `ads_orders`,
      type: `sum`,
    },
    adsUnits: {
      sql: `ads_units`,
      type: `sum`,
    },
    adsSpend: {
      sql: `ads_spend`,
      type: `sum`,
    },
    adsSales: {
      sql: `ads_sales`,
      type: `sum`,
    },
    adsCpc: {
      sql: `ads_cpc`,
      type: `avg`,
    },

    // Derived
    brandCvr: {
      sql: `brand_cvr`,
      type: `avg`,
    },
    brandDominanceScore: {
      sql: `brand_dominance_score`,
      type: `avg`,
    },
  },
});
