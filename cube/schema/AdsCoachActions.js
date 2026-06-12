// Cube: AdsCoachActions - from FACT_ADS_COACH_ACTIONS
// ONE ROW PER SEARCH TERM × CAMPAIGN × ACTION
cube(`AdsCoachActions`, {
  sql: `SELECT * FROM \`onyga-482313.OI.FACT_ADS_COACH_ACTIONS\` WHERE action_type != 'MONITOR' OR ads_spend_4w >= 5`,

  refreshKey: { every: '30 minutes' },

  measures: {
    count: { type: `count`, description: `Number of pending actions` },
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
      description: `Short hash grouping rows that share the same decision logic path`,
    },
    actionType: {
      sql: `action_type`,
      type: `string`,
      description: `Type of action: TERM, TARGET, BUDGET, HERO`,
    },
    action: {
      sql: `action`,
      type: `string`,
      description: `The recommended action to take`,
    },
    actionExplanation: {
      sql: `action_explanation`,
      type: `string`,
      description: `Human-readable explanation`,
    },
    reason: {
      sql: `action_explanation`,
      type: `string`,
      description: `Alias for actionExpression for backwards compatibility`,
    },
    decisionTrace: {
      sql: `decision_trace`,
      type: `string`,
      description: `JSON array of decision trace steps`,
    },
    priorityScore: { sql: `priority_score`, type: `number` },
    confidence: { sql: `confidence`, type: `string` },
    adsSignal: { sql: `ads_signal`, type: `string`, description: `Performance signal: STRONG, PROFITABLE, MARGINAL, UNPROFITABLE, WASTED_SPEND, INSUFFICIENT_DATA` },

    // Strategy Context
    campaignId: { sql: `campaign_id`, type: `string` },

    campaignName: { sql: `campaign_name`, type: `string` },
    campaignType: { sql: `campaign_type`, type: `string` },
    experimentId: { sql: `experiment_id`, type: `string` },
    experimentName: { sql: `experiment_name`, type: `string` },
    strategyId: { sql: `strategy_id`, type: `string` },
    strategyName: { sql: `strategy_name`, type: `string` },
    coachMode: { sql: `coach_mode`, type: `string` },
    strategicTask: { sql: `strategic_task`, type: `string` },
    activeOccasion: { sql: `active_occasion`, type: `string` },
    currentPhase: { sql: `current_phase`, type: `string` },
    ppDays: { sql: `pp_days`, type: `number` },
    ppTargetNetRoas: { sql: `pp_target_net_roas`, type: `number` },
    ppTargetSpend: { sql: `pp_target_spend`, type: `number` },
    ppTargetOrders: { sql: `pp_target_orders`, type: `number` },
    ppCampaignNetRoas: { sql: `pp_campaign_net_roas`, type: `number` },

    // Entities
    searchTerm: { sql: `search_term`, type: `string` },
    asin: { sql: `asin`, type: `string` },
    productShortName: { sql: `product_short_name`, type: `string` },
    parentName: { sql: `parent_name`, type: `string` },
    targeting: { sql: `targeting`, type: `string` },
    keywordId: { sql: `keyword_id`, type: `string` },
    matchType: { sql: `match_type`, type: `string`, description: `Amazon keyword match type: BROAD, EXACT, PHRASE` },

    // Metrics
    adsSpend4w: { sql: `ads_spend_4w`, type: `number` },
    adsOrders4w: { sql: `ads_orders_4w`, type: `number` },
    adsClicks1w: { sql: `ads_clicks_1w`, type: `number` },
    adsImpressions1w: { sql: `ads_impressions_1w`, type: `number` },
    adsClicks4w: { sql: `ads_clicks_4w`, type: `number` },
    adsImpressions4w: { sql: `ads_impressions_4w`, type: `number` },
    adsSpend1w: { sql: `ads_spend_1w`, type: `number` },
    adsCpc1w: { sql: `ads_cpc_1w`, type: `number` },
    adsSales4w: { sql: `ads_sales_4w`, type: `number` },
    adsRoas4w: { sql: `net_roas_4w`, type: `number` }, 
    adsCpc4w: { sql: `ads_cpc_4w`, type: `number` },
    adsCvrPct4w: { sql: `ads_cvr_pct_4w`, type: `number` },
    adsNetRoas4w: { sql: `net_roas_4w`, type: `number` },
    adsNetProfit4w: { sql: `net_profit_4w`, type: `number` },
    marginPerUnit: { sql: `margin_per_unit`, type: `number` },
    termSpend4w: { sql: `term_spend_4w`, type: `number` },
    termOrders4w: { sql: `term_orders_4w`, type: `number` },
    termCampaignCount: { sql: `term_campaign_count`, type: `number` },
    termSellingCampaigns: { sql: `term_selling_campaigns`, type: `number` },
    spendSharePct: { sql: `spend_share_pct`, type: `number` },
    ordersSharePct: { sql: `orders_share_pct`, type: `number` },

    sqpOrders4w: { sql: `sqp_orders_4w`, type: `number` },

    // Bids & Budgets
    currentBid: { sql: `current_bid`, type: `number`, description: `Current keyword bid from bulksheet snapshot ($)` },
    recommendedBid: { sql: `recommended_bid`, type: `number`, description: `Graduated recommended bid based on target ROAS ($)` },
    bidChangePct: { sql: `bid_change_pct`, type: `number`, description: `Bid change percentage (+40, +30, +20, +10, -15, -25, -35)` },
    targetNetRoas8w: { sql: `target_net_roas_8w`, type: `number` },
    targetClicks8w: { sql: `target_clicks_8w`, type: `number` },
    targetOrders8w: { sql: `target_orders_8w`, type: `number` },
    targetSpend8w: { sql: `target_spend_8w`, type: `number` },

    tosPct: { sql: `tos_pct`, type: `number` },
    productPagePct: { sql: `product_page_pct`, type: `number` },
    b2bPct: { sql: `b2b_pct`, type: `number` },
    prePeakBid: { sql: `pre_peak_bid`, type: `number` },
    prePeakTosPct: { sql: `pre_peak_tos_pct`, type: `number` },
    prePeakPpPct: { sql: `pre_peak_pp_pct`, type: `number` },
    prePeakB2bPct: { sql: `pre_peak_b2b_pct`, type: `number` },
    prePeakAvgCpc: { sql: `pre_peak_avg_cpc`, type: `number` },
    lastDayCpc: { sql: `last_day_cpc`, type: `number` },

    currentBudget: { sql: `current_budget`, type: `number` },
    prePeakBudget: { sql: `pre_peak_budget`, type: `number` },
    recommendedBudget: { sql: `recommended_budget`, type: `number` },

    // Hero ASIN
    heroAsin: { sql: `hero_asin`, type: `string`, description: `Hero ASIN for this term` },
    heroProductName: { sql: `hero_product_name`, type: `string`, description: `Hero product name` },
    isHeroMatch: { sql: `is_hero_match`, type: `boolean`, description: `True if advertising correct hero` },
    heroNetRoas: { sql: `hero_net_roas`, type: `number`, description: `Hero ASIN Net ROAS` },
    heroTotalOrders: { sql: `hero_total_orders`, type: `number`, description: `Hero ASIN total orders` },

    // ROAS windows + SQP context
    adsNetRoas3d: { sql: `ads_net_roas_3d`, type: `number`, description: `Ads Net ROAS (3-day raw)` },
    adsOrders3d: { sql: `ads_orders_3d`, type: `number`, description: `Ads Orders (3-day raw)` },
    adsUnits3d: { sql: `ads_units_3d`, type: `number`, description: `Ads Units (3-day raw)` },
    adsNetRoas1w: { sql: `ads_net_roas_1w`, type: `number`, description: `Ads Net ROAS (7-day raw)` },
    adsOrders1w: { sql: `ads_orders_1w`, type: `number`, description: `Ads Orders (7-day raw)` },
    adsUnits1w: { sql: `ads_units_1w`, type: `number`, description: `Ads Units (7-day raw)` },
    lyNetRoas: { sql: `ly_net_roas`, type: `number`, description: `Net ROAS last year equivalent period` },
    lyOrders: { sql: `ly_orders`, type: `number`, description: `Orders last year equivalent period` },
    lyUnits: { sql: `ly_units`, type: `number`, description: `Units last year equivalent period` },
    lySpend: { sql: `ly_spend`, type: `number`, description: `Spend last year equivalent period` },
    lyClicks: { sql: `ly_clicks`, type: `number`, description: `Clicks last year equivalent period` },
    lyCpc: { sql: `ly_cpc`, type: `number`, description: `CPC last year equivalent period` },
    q4PeakSpend: { sql: `q4_peak_spend`, type: `number`, description: `Q4 peak spend` },
    q4PeakNetRoas: { sql: `q4_peak_net_roas`, type: `number`, description: `Net ROAS Q4/December peak` },
    q4PeakOrders: { sql: `q4_peak_orders`, type: `number`, description: `Orders Q4/December peak` },
    q4PeakUnits: { sql: `q4_peak_units`, type: `number`, description: `Units Q4/December peak` },
    sqpAmazonSearchVolume8w: { sql: `sqp_amazon_search_volume_8w`, type: `number`, description: `SQP Amazon Search Volume (8w)` },
    sqpClicks8w: { sql: `sqp_clicks_8w`, type: `number`, description: `SQP Total Clicks (8w)` },
    sqpSales8w: { sql: `sqp_sales_8w`, type: `number`, description: `SQP Total Sales $ (8w)` },
    sqpOrders8w: { sql: `sqp_orders_8w`, type: `number`, description: `SQP Total Orders (8w)` },
    ltNetRoas: { sql: `lt_net_roas`, type: `number`, description: `Lifetime (12m) Net ROAS` },
    ltOrders: { sql: `lt_orders`, type: `number`, description: `Lifetime (12m) Orders` },
    ltUnits: { sql: `lt_units`, type: `number`, description: `Lifetime (12m) Units` },
    ltFirstSeen: { sql: `lt_first_seen`, type: `string`, description: `First date with ads data for this term` },
    ltLastSeen: { sql: `lt_last_seen`, type: `string`, description: `Last date with ads data for this term` },
  },
});
