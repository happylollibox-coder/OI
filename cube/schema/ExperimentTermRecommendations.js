// Cube: ExperimentTermRecommendations - from V_EXPERIMENT_TERM_RECOMMENDATIONS
// Used for actions, keyword_product_map, drivers
cube(`ExperimentTermRecommendations`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_EXPERIMENT_TERM_RECOMMENDATIONS\` WHERE action != 'MONITOR' OR ads_spend >= 5`,

  refreshKey: { every: '30 minutes' },

  measures: {
    count: {
      type: `count`,
      description: `Number of term recommendations`,
    },
  },

  dimensions: {
    // Unpivoted Action Identity
    actionId: {
      sql: `action_id`,
      type: `string`,
      primaryKey: true,
      description: `Unique row id (action ID)`,
    },
    decisionBranchId: {
      sql: `decision_branch_id`,
      type: `string`,
      description: `Decision branch ID (shared by actions taking the same logic path)`,
    },
    actionType: {
      sql: `action_type`,
      type: `string`,
      description: `Type of action: TERM, TARGET, BUDGET, HERO`,
    },
    adsSpend: { sql: `ads_spend`, type: `number`, description: `Ads spend` },
    adsOrders: { sql: `ads_orders`, type: `number`, description: `Ads orders` },
    adsClicks: { sql: `ads_clicks`, type: `number`, description: `Ads clicks` },
    adsClicksRecent: { sql: `ads_clicks_recent`, type: `number`, description: `Ads clicks in last 5 days (approx 3 days API data)` },
    adsImpressions: { sql: `ads_impressions`, type: `number`, description: `Ads impressions` },
    cpc: { sql: `cpc`, type: `number`, description: `CPC` },
    adsCvrPct: { sql: `ads_cvr_pct`, type: `number`, description: `Ads CVR %` },
    marginPerUnit: { sql: `margin_per_unit`, type: `number`, description: `Margin per unit` },
    marketWeeklyOrders: { sql: `market_weekly_orders`, type: `number`, description: `Market weekly orders` },
    yourOrdersSharePct: { sql: `your_orders_share_pct`, type: `number`, description: `Impression share` },
    priorityScore: { sql: `priority_score`, type: `number`, description: `Priority score` },
    adsNetRoas: { sql: `ads_net_roas`, type: `number`, description: `Ads net ROAS` },
    weightedTotalNetRoas: { sql: `weighted_total_net_roas`, type: `number`, description: `Weighted Total Net ROAS (ads + organic, time-weighted)` },
    searchTerm: {
      sql: `search_term`,
      type: `string`,
      description: `Search term`,
    },
    experimentId: {
      sql: `experiment_id`,
      type: `string`,
      description: `Experiment ID`,
    },
    campaignId: {
      sql: `campaign_id`,
      type: `string`,
      description: `Campaign ID`,
    },
    adGroupId: {
      sql: `ad_group_id`,
      type: `string`,
      description: `Ad group ID (most recent for this campaign×term)`,
    },
    campaignName: {
      sql: `campaign_name`,
      type: `string`,
      description: `Campaign name`,
    },
    campaignType: {
      sql: `campaign_type`,
      type: `string`,
      description: `Campaign type (SP or SB)`,
    },
    portfolioName: {
      sql: `portfolio_name`,
      type: `string`,
      description: `Portfolio name`,
    },
    asin: {
      sql: `asin`,
      type: `string`,
      description: `Advertised ASIN`,
    },
    productShortName: {
      sql: `product_short_name`,
      type: `string`,
      description: `Product name`,
    },
    heroAsin: {
      sql: `hero_asin`,
      type: `string`,
      description: `Hero ASIN for this term`,
    },
    isHeroMatch: {
      sql: `is_hero_match`,
      type: `boolean`,
      description: `True if advertising hero ASIN`,
    },
    action: {
      sql: `action`,
      type: `string`,
      description: `KEEP, STOP, REDUCE_BID, PROMOTE_TO_EXACT, START, BOOST, MONITOR`,
    },
    adsSignal: {
      sql: `ads_signal`,
      type: `string`,
      description: `Performance signal`,
    },
    actionExplanation: {
      sql: `action_explanation`,
      type: `string`,
      description: `Human-readable decision tree explanation`,
    },
    heroProductName: {
      sql: `hero_product_name`,
      type: `string`,
      description: `Hero product name for this term`,
    },
    heroNetRoas: {
      sql: `hero_net_roas`,
      type: `number`,
      description: `Hero ASIN Net ROAS on this term`,
    },
    heroTotalOrders: {
      sql: `hero_total_orders`,
      type: `number`,
      description: `Hero ASIN total orders (ads + SQP)`,
    },
    heroAdsCtrPct: {
      sql: `hero_ads_ctr_pct`,
      type: `number`,
      description: `Hero ASIN Ads CTR %`,
    },
    sqpSearchVolume: {
      sql: `sqp_search_volume`,
      type: `number`,
      description: `SQP search query volume`,
    },
    sqpOrganicRank: {
      sql: `sqp_organic_rank`,
      type: `number`,
      description: `Average organic rank from SQP data (lower = better)`,
    },
    isTopOfPageOrganic: {
      sql: `is_top_of_page_organic`,
      type: `boolean`,
      description: `Whether organic rank <= 5 (top of page 1)`,
    },
    decisionTrace: {
      sql: `decision_trace`,
      type: `string`,
      description: `JSON array of decision trace steps from the SQL view`,
    },
  },
});
