// Cube: AdsCoachTerm - from V_ADS_COACH_SEARCH_TERM
// ONE ROW PER SEARCH TERM × CAMPAIGN: campaign-specific action
cube(`AdsCoachTerm`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_ADS_COACH_SEARCH_TERM\``,

  refreshKey: { every: '30 minutes' },

  measures: {
    count: { type: `count`, description: `Number of term-campaign rows` },
  },

  dimensions: {
    id: {
      sql: `CONCAT(campaign_id, '|', search_term, '|', COALESCE(asin,''))`,
      type: `string`,
      primaryKey: true,
    },
    campaignId: { sql: `campaign_id`, type: `string` },
    adGroupId: { sql: `ad_group_id`, type: `string`, description: `Ad group ID (most recent for this campaign×term)` },
    campaignName: { sql: `campaign_name`, type: `string` },
    campaignType: { sql: `campaign_type`, type: `string` },
    searchTerm: { sql: `search_term`, type: `string` },
    asin: { sql: `asin`, type: `string` },
    productShortName: { sql: `product_short_name`, type: `string` },
    parentName: { sql: `parent_name`, type: `string` },
    experimentId: { sql: `experiment_id`, type: `string` },
    experimentName: { sql: `experiment_name`, type: `string` },
    strategyId: { sql: `strategy_id`, type: `string` },
    strategyName: { sql: `strategy_name`, type: `string` },

    // This campaign's metrics
    adsSpend4w: { sql: `ads_spend_4w`, type: `number` },
    adsOrders4w: { sql: `ads_orders_4w`, type: `number` },
    adsClicks4w: { sql: `ads_clicks_4w`, type: `number` },
    adsSales4w: { sql: `ads_sales_4w`, type: `number` },
    adsCpc4w: { sql: `ads_cpc_4w`, type: `number` },
    adsCvrPct4w: { sql: `ads_cvr_pct_4w`, type: `number` },
    adsNetRoas4w: { sql: `ads_net_roas_4w`, type: `number` },
    adsNetProfit4w: { sql: `ads_net_profit_4w`, type: `number` },
    marginPerUnit: { sql: `margin_per_unit`, type: `number` },

    // Cross-campaign context
    termSpend4w: { sql: `term_spend_4w`, type: `number` },
    termOrders4w: { sql: `term_orders_4w`, type: `number` },
    termCampaignCount: { sql: `term_campaign_count`, type: `number` },
    termSellingCampaigns: { sql: `term_selling_campaigns`, type: `number` },
    spendSharePct: { sql: `spend_share_pct`, type: `number` },
    ordersSharePct: { sql: `orders_share_pct`, type: `number` },

    // SQP
    sqpOrders4w: { sql: `sqp_orders_4w`, type: `number` },

    // Target keyword (dual-grain)
    targeting: { sql: `targeting`, type: `string` },
    keywordId: { sql: `keyword_id`, type: `string` },
    targetAction: { sql: `target_action`, type: `string` },
    effectiveRoas: { sql: `effective_roas`, type: `number` },
    adsWeightedNetRoas: { sql: `ads_weighted_net_roas`, type: `number` },
    targetNetRoas8w: { sql: `target_net_roas_8w`, type: `number` },
    targetClicks8w: { sql: `target_clicks_8w`, type: `number` },
    targetOrders8w: { sql: `target_orders_8w`, type: `number` },
    targetSpend8w: { sql: `target_spend_8w`, type: `number` },
    targetDecisionTrace: { sql: `target_decision_trace`, type: `string`, description: `JSON array of target-level decision trace steps` },
    recommendationObject: { sql: `recommendation_object`, type: `string`, description: `What the recommendation applies to: TARGET or TERM` },
    currentBid: { sql: `current_bid`, type: `number`, description: `Current keyword bid from bulksheet snapshot ($)` },
    recommendedBid: { sql: `recommended_bid`, type: `number`, description: `Graduated recommended bid based on target ROAS ($)` },
    bidChangePct: { sql: `bid_change_pct`, type: `number`, description: `Bid change percentage (+40, +30, +20, +10, -15, -25, -35)` },
    matchType: { sql: `match_type`, type: `string`, description: `Amazon keyword match type: BROAD, EXACT, PHRASE` },

    // Action (campaign-specific)
    action: { sql: `action`, type: `string` },
    priorityScore: { sql: `priority_score`, type: `number` },
    confidence: { sql: `confidence`, type: `string` },
    reason: { sql: `reason`, type: `string` },

    // Hero ASIN
    heroAsin: { sql: `hero_asin`, type: `string`, description: `Hero ASIN for this term` },
    heroProductName: { sql: `hero_product_name`, type: `string`, description: `Hero product name` },
    isHeroMatch: { sql: `is_hero_match`, type: `boolean`, description: `True if advertising correct hero` },
    heroAction: { sql: `hero_action`, type: `string`, description: `SWITCH_HERO when wrong ASIN` },
    heroActionExplanation: { sql: `hero_action_explanation`, type: `string`, description: `Hero switch instructions` },
    heroNetRoas: { sql: `hero_net_roas`, type: `number`, description: `Hero ASIN Net ROAS` },
    heroTotalOrders: { sql: `hero_total_orders`, type: `number`, description: `Hero ASIN total orders` },
  },
});
