// Cube: ParentHeroAsin - from V_PARENT_HERO_ASIN
// Used for hero_asins
cube(`ParentHeroAsin`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_PARENT_HERO_ASIN\``,

  refreshKey: { every: '30 minutes' },

  joins: {
    Product: {
      relationship: `belongsTo`,
      sql: `${CUBE}.asin = ${Product}.asin`,
    },
  },

  measures: {
    count: {
      type: `count`,
      description: `Number of hero ASIN rows`,
    },
  },

  dimensions: {
    searchTerm: {
      sql: `search_term`,
      type: `string`,
      description: `Search term`,
    },
    parentName: {
      sql: `parent_name`,
      type: `string`,
      description: `Parent product name`,
    },
    asin: {
      sql: `asin`,
      type: `string`,
      primaryKey: true,
      description: `Child ASIN (hero for this term)`,
    },
    productShortName: {
      sql: `product_short_name`,
      type: `string`,
      description: `Product display name`,
    },
    heroRank: {
      sql: `hero_rank`,
      type: `number`,
      description: `Rank within term+parent (1=best)`,
    },
    heroScore: {
      sql: `hero_score`,
      type: `number`,
      description: `Organic growth potential score`,
    },
    sqpCvrPct: {
      sql: `sqp_cvr_pct`,
      type: `number`,
      description: `SQP conversion rate %`,
    },
    sqpCtrPct: {
      sql: `sqp_ctr_pct`,
      type: `number`,
      description: `SQP click-through rate %`,
    },
    sqpImpressions: {
      sql: `sqp_impressions`,
      type: `number`,
      description: `SQP impressions`,
    },
    sqpClicks: {
      sql: `sqp_clicks`,
      type: `number`,
      description: `SQP clicks`,
    },
    sqpConversions: {
      sql: `sqp_conversions`,
      type: `number`,
      description: `SQP conversions`,
    },
    adsSpend: {
      sql: `ads_spend`,
      type: `number`,
      description: `Ads spend on this term`,
    },
    adsOrders: {
      sql: `ads_orders`,
      type: `number`,
      description: `Ads orders`,
    },
    adsClicks: {
      sql: `ads_clicks`,
      type: `number`,
      description: `Ads clicks`,
    },
    adsNetRoas: {
      sql: `ads_net_roas`,
      type: `number`,
      description: `Ads net ROAS`,
    },
    marginPerUnit: {
      sql: `margin_per_unit`,
      type: `number`,
      description: `Margin per unit`,
    },
    reason: {
      sql: `reason`,
      type: `string`,
      description: `Hero selection reason`,
    },
  },
});
