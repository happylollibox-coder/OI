// Cube: Ads - from FACT_AMAZON_ADS
// Used for ads_7d, campaign hierarchy, drainers, best terms

cube(`Ads`, {
  // R9 note: WHERE kept inline (not segment) because this is a mandatory data-quality filter
  // that must always apply — rows with zero cost AND zero impressions are noise
  sql: `SELECT * FROM \`onyga-482313.OI.FACT_AMAZON_ADS\` WHERE Ads_cost > 0 OR Ads_impressions > 0`,

  joins: {
    Product: {
      relationship: `belongsTo`,
      sql: `${CUBE}.most_advertised_asin_impressions = ${Product}.asin`,
    },
  },

  measures: {
    count: {
      type: `count`,
      description: `Number of rows`,
    },
    spend: {
      sql: `Ads_cost`,
      type: `sum`,
      format: `currency`,
      description: `Total ad spend (cost) in USD`,
    },
    orders: {
      sql: `Ads_orders`,
      type: `sum`,
      description: `Orders attributed to ads`,
    },
    clicks: {
      sql: `Ads_clicks`,
      type: `sum`,
      description: `Ad clicks`,
    },
    impressions: {
      sql: `Ads_impressions`,
      type: `sum`,
      description: `Ad impressions`,
    },
    sales: {
      sql: `Ads_sales`,
      type: `sum`,
      format: `currency`,
      description: `Sales attributed to ads (USD)`,
    },
    cogs: {
      sql: `\`onyga-482313.OI.FN_COGS\`(Ads_units, TOTAL_COST_PER_UNIT)`,
      type: `sum`,
      format: `currency`,
      description: `COGS from DIM_COSTS_HISTORY (units × cost per unit)`,
    },
    grossProfit: {
      sql: `GROSS_PROFIT`,
      type: `sum`,
      format: `currency`,
      description: `Sales − COGS (from DIM_COSTS_HISTORY join in SP_FACT_AMAZON_ADS)`,
    },
  },

  dimensions: {
    id: {
      sql: `CONCAT(CAST(date AS STRING), '|', COALESCE(CAST(campaign_id AS STRING), ''), '|', COALESCE(CAST(ad_group_id AS STRING), ''), '|', COALESCE(CAST(keyword_id AS STRING), ''), '|', COALESCE(search_term, ''))`,
      type: `string`,
      primaryKey: true,
    },
    date: {
      sql: `CAST(date AS TIMESTAMP)`,
      type: `time`,
      description: `Report date`,
    },
    weekStart: {
      sql: `CAST(DATE_TRUNC(date, WEEK(SUNDAY)) AS TIMESTAMP)`,
      type: `time`,
      description: `Week start (Sunday), aligned with DIM_TIME`,
    },
    campaignId: {
      sql: `campaign_id`,
      type: `string`,
      description: `Amazon Ads campaign identifier`,
    },
    campaignName: {
      sql: `campaign_name`,
      type: `string`,
      description: `Campaign display name`,
    },
    campaignType: {
      sql: `campaign_type`,
      type: `string`,
      description: `Campaign type (e.g. Sponsored Products, Sponsored Brands)`,
    },
    searchTerm: {
      sql: `search_term`,
      type: `string`,
      description: `Search term that triggered the ad`,
    },
    adGroupId: {
      sql: `ad_group_id`,
      type: `string`,
      description: `Ad group identifier`,
    },
    keywordId: {
      sql: `keyword_id`,
      type: `string`,
      description: `Keyword identifier`,
    },
    mostAdvertisedAsin: {
      sql: `most_advertised_asin_impressions`,
      type: `string`,
      description: `ASIN with most impressions for this row`,
    },
  },

  refreshKey: {
    sql: `SELECT MAX(date) FROM \`onyga-482313.OI.FACT_AMAZON_ADS\``,
  },

  preAggregations: {
    // Pre-aggregations temporarily disabled — the partition tables in
    // dev_pre_aggregations were stale/missing, causing NOT FOUND errors.
    // Re-enable once the pre-agg dataset is rebuilt with:
    //   CUBEJS_DEV_MODE=true + scheduled refresh
    //
    // adsByWeekCampaign: { ... },
    // adsBySundayWeekCampaign: { ... },
  },
});
