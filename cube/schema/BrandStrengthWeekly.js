// Cube: BrandStrengthWeekly - from T_BRAND_STRENGTH_WEEKLY
// Grain: (week_start_date × brand_keyword × parent_name)
// Used by: Brand page
//
// Rules compliance:
//   [x] R1: One cube = one entity (Brand Strength)
//   [x] R2: sql_table pointing to BigQuery table
//   [x] R4: Pre-computed ratios exposed as dimensions, not avg measures
//   [x] R7: All measures are additive (sum/max)
cube(`BrandStrengthWeekly`, {
  sql_table: `\`onyga-482313.OI.T_BRAND_STRENGTH_WEEKLY\``,

  dimensions: {
    id: {
      sql: `CONCAT(CAST(week_start_date AS STRING), '|', COALESCE(brand_keyword, ''), '|', COALESCE(parent_name, ''))`,
      type: `string`,
      primaryKey: true,
    },
    weekStartDate: {
      sql: `CAST(week_start_date AS STRING)`,
      type: `string`,
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
    parentName: {
      sql: `parent_name`,
      type: `string`,
      description: `Product family (e.g. Lollibox, LolliME, Fresh, Bottle)`,
    },
    tag: {
      sql: `tag`,
      type: `string`,
    },
    // Pre-computed ratios — exposed as dimensions to prevent double-averaging (R4)
    avgShowRate: {
      sql: `avg_show_rate`,
      type: `number`,
      description: `Pre-computed avg show rate for this keyword-week`,
    },
    avgImpressionShare: {
      sql: `avg_impression_share`,
      type: `number`,
      description: `Pre-computed avg impression share for this keyword-week`,
    },
    avgOrganicRank: {
      sql: `avg_organic_rank`,
      type: `number`,
      description: `Pre-computed avg organic rank for this keyword-week`,
    },
    adsCpc: {
      sql: `ads_cpc`,
      type: `number`,
      description: `Pre-computed CPC for this keyword-week`,
    },
    brandCvr: {
      sql: `brand_cvr`,
      type: `number`,
      description: `Pre-computed brand CVR for this keyword-week`,
    },
    brandDominanceScore: {
      sql: `brand_dominance_score`,
      type: `number`,
      description: `Pre-computed dominance score for this keyword-week (equal 3-way: show rate, CVR, YoY imp ratio)`,
    },
    sqpMonthImpressions: {
      sql: `sqp_month_impressions`,
      type: `number`,
      description: `SQP impressions for the month this week falls in`,
    },
    sqpLyMonthImpressions: {
      sql: `sqp_ly_month_impressions`,
      type: `number`,
      description: `SQP impressions for the same month last year`,
    },
  },

  measures: {
    count: {
      type: `count`,
    },
    // Additive measures only (R7)
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
    totalSearchVolume: {
      sql: `total_search_volume`,
      type: `sum`,
    },
    brandQueryCount: {
      sql: `brand_asin_count`,
      type: `max`,
    },
    // Ads additive measures
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
  },
});
