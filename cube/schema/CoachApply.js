// Cube: CoachApply - from V_COACH_APPLY (Coacher F apply set, deduped one bid row per keyword).
// The Weekly Run inline Actions phase reads these per family to review + queue keyword bid changes.
cube(`CoachApply`, {
  sql: `SELECT
          entity_id, entity_type, campaign_id, parent_name, campaign_name, ad_group_id,
          targeting, match_type, operation, current_bid, new_bid, bid_change_pct,
          source_action, reason, priority_score
        FROM \`onyga-482313.OI.T_COACH_APPLY\``,

  refreshKey: { every: `30 minutes` },

  measures: {
    count: { type: `count` },
  },

  dimensions: {
    id: { sql: `entity_id`, type: `string`, primaryKey: true },
    entityType: { sql: `entity_type`, type: `string` },
    campaignId: { sql: `campaign_id`, type: `string` },
    parentName: { sql: `parent_name`, type: `string` },
    campaignName: { sql: `campaign_name`, type: `string` },
    adGroupId: { sql: `ad_group_id`, type: `string` },
    targeting: { sql: `targeting`, type: `string` },
    matchType: { sql: `match_type`, type: `string` },
    operation: { sql: `operation`, type: `string` },
    sourceAction: { sql: `source_action`, type: `string` },
    reason: { sql: `reason`, type: `string` },
    currentBid: { sql: `current_bid`, type: `number` },
    newBid: { sql: `new_bid`, type: `number` },
    bidChangePct: { sql: `bid_change_pct`, type: `number` },
    priorityScore: { sql: `priority_score`, type: `number` },
  },
});
