// Cube: CoachRunNegative - from T_WEEKLY_RUN_NEGATIVE (Weekly Run Step 3, level 3 = negatives per keyword).
// Engine NEGATE_TERM recommendations: irrelevant / money-wasting search terms to add as negatives.
cube(`CoachRunNegative`, {
  sql: `SELECT id, parent_name, campaign_id, keyword_id, ad_group_id, campaign_name, targeting,
          match_type, search_term, reason, priority_score, peak_clicks, peak_orders, peak_net, peak_converts,
          hero_asin, hero_product_name, hero_cvr, wrong_asin
        FROM \`onyga-482313.OI.T_WEEKLY_RUN_NEGATIVE\``,
  refreshKey: { every: `30 minutes` },
  measures: { count: { type: `count` } },
  dimensions: {
    id: { sql: `id`, type: `string`, primaryKey: true },
    parentName: { sql: `parent_name`, type: `string` },
    campaignId: { sql: `campaign_id`, type: `string` },
    keywordId: { sql: `keyword_id`, type: `string` },
    adGroupId: { sql: `ad_group_id`, type: `string` },
    campaignName: { sql: `campaign_name`, type: `string` },
    targeting: { sql: `targeting`, type: `string` },
    matchType: { sql: `match_type`, type: `string` },
    searchTerm: { sql: `search_term`, type: `string` },
    reason: { sql: `reason`, type: `string` },
    priorityScore: { sql: `priority_score`, type: `number` },
    peakClicks: { sql: `peak_clicks`, type: `number` },
    peakOrders: { sql: `peak_orders`, type: `number` },
    peakNet: { sql: `peak_net`, type: `number` },
    peakConverts: { sql: `peak_converts`, type: `boolean` },
    heroAsin: { sql: `hero_asin`, type: `string` },
    heroProductName: { sql: `hero_product_name`, type: `string` },
    heroCvr: { sql: `hero_cvr`, type: `number` },
    wrongAsin: { sql: `wrong_asin`, type: `boolean` },
  },
});
