// Cube: LaunchTermNegative — search terms to negate inside a campaign's launch window: >=15 clicks,
// 0 orders. Reads V_LAUNCH_TERM_NEGATIVES directly. Feeds the "Budget by age" NEW bucket Apply-all,
// which queues NEGATE_TERM actions. Spec: architecture/CAMPAIGN_LAUNCH_RAMP.md §"Phase 1".
cube(`LaunchTermNegative`, {
  sql: `SELECT campaign_id, campaign_name, matched_target, search_term, clicks, orders, spend, reason
        FROM \`onyga-482313.OI.V_LAUNCH_TERM_NEGATIVES\``,

  refreshKey: { every: `10 minutes` },

  measures: { count: { type: `count` } },

  dimensions: {
    rowId:        { sql: `CONCAT(campaign_id, '|', search_term)`, type: `string`, primaryKey: true },
    campaignId:   { sql: `campaign_id`,    type: `string` },
    campaignName: { sql: `campaign_name`,  type: `string` },
    matchedTarget:{ sql: `matched_target`, type: `string` },
    searchTerm:   { sql: `search_term`,    type: `string` },
    clicks:       { sql: `clicks`,         type: `number` },
    spend:        { sql: `spend`,          type: `number` },
    reason:       { sql: `reason`,         type: `string` },
  },
});
