cube(`StrategyCampaignTemplate`, {
  sql: `SELECT * FROM \`onyga-482313\`.OI.DIM_STRATEGY_CAMPAIGN_TEMPLATE`,

  // Tiny config dimension table — no pre-aggregations needed.
  preAggregations: {},

  // No updated_at column; refresh hourly so edits to the recipe propagate.
  refreshKey: {
    every: `1 hour`
  },

  dimensions: {
    id: {
      sql: `CONCAT(strategy_id, '-', CAST(campaign_seq AS STRING))`,
      type: `string`,
      primaryKey: true,
      description: `Synthetic key: strategy_id + campaign_seq`
    },

    strategyId: {
      sql: `strategy_id`,
      type: `string`,
      description: `Strategy template id (e.g., EXACT_BOOST, BRAND_DEFENSE)`
    },

    campaignSeq: {
      sql: `campaign_seq`,
      type: `number`,
      description: `Priority order of the campaign within the strategy`
    },

    adFormat: {
      sql: `ad_format`,
      type: `string`,
      description: `SP, SB_VIDEO, SB_STORE`
    },

    matchType: {
      sql: `match_type`,
      type: `string`,
      description: `EXACT, BROAD, AUTO, PHRASE, PRODUCT_TARGETING`
    },

    biddingStrategy: {
      sql: `bidding_strategy`,
      type: `string`,
      description: `DOWN_ONLY, UP_AND_DOWN`
    },

    bidMin: {
      sql: `bid_min`,
      type: `number`,
      description: `Minimum bid for the ad group / keyword`
    },

    bidMax: {
      sql: `bid_max`,
      type: `number`,
      description: `Maximum bid for the ad group / keyword`
    },

    dailyBudget: {
      sql: `daily_budget`,
      type: `number`,
      description: `Daily budget for the campaign`
    },

    topOfSearchPct: {
      sql: `top_of_search_pct`,
      type: `number`,
      description: `Top-of-search placement bid adjustment %`
    },

    productPagePct: {
      sql: `product_page_pct`,
      type: `number`,
      description: `Product page placement bid adjustment %`
    },

    namingHint: {
      sql: `naming_hint`,
      type: `string`,
      description: `Campaign naming convention hint`
    },

    isRequired: {
      sql: `is_required`,
      type: `boolean`,
      description: `Must-have vs nice-to-have campaign in the recipe`
    }
  },

  measures: {
    count: {
      type: `count`
    }
  }
});
