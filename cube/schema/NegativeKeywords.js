// Cube: NegativeKeywords - from DE_NEGATIVE_KEYWORDS
// Warehouse-owned negative-keyword registry (replaces the frozen Fivetran
// negative_keyword sync). Seeded once from an Amazon bulksheet; afterwards this
// system is the only authority that mutates it (SP_SYNC_NEGATIVES folds in every
// NEGATE_* / REMOVE_NEGATIVE we upload, read from FACT_PPC_CHANGE_LOG).
// Only ENABLED negatives are surfaced — REMOVED rows are history.
// Read-only review surface. Used on the Log page (Negative Keywords table) and
// the Peak readiness checklist ("negatives set per campaign").
cube(`NegativeKeywords`, {
  sql: `SELECT * FROM \`onyga-482313.OI.DE_NEGATIVE_KEYWORDS\` WHERE state = 'ENABLED'`,

  refreshKey: { every: '1 hour' },

  measures: {
    count: { type: `count`, description: `Number of enabled negative keywords` },
  },

  dimensions: {
    id: { sql: `negative_id`, type: `string`, primaryKey: true },
    campaignId: { sql: `campaign_id`, type: `string` },
    campaignName: { sql: `campaign_name`, type: `string` },
    adGroupName: { sql: `ad_group_name`, type: `string` },
    keywordText: { sql: `keyword_text`, type: `string`, description: `The negative keyword text` },
    matchType: { sql: `match_type`, type: `string`, description: `NEGATIVE_EXACT | NEGATIVE_PHRASE` },
    level: { sql: `level`, type: `string`, description: `CAMPAIGN | AD_GROUP` },
    source: { sql: `source`, type: `string`, description: `SEED | COACH | MANUAL` },
    addedAt: { sql: `added_at`, type: `time`, description: `When the negative was added` },
  },
});
