// Cube: LaunchNegatives - from T_LAUNCH_NEGATIVES
// ONE ROW PER STRATEGY × FAMILY × PHRASE: the negatives a new campaign launches with.
// Keyed on strategy (not campaign) because the campaign has no id at bulksheet time.
// BRAND_DEFENSE / PRODUCT_DEFENSE are absent by construction — the exclusion is
// enforced in V_LAUNCH_NEGATIVES, so consumers must not re-implement it.
cube(`LaunchNegatives`, {
  sql: `SELECT *, CONCAT(strategy_id, '|', parent_name, '|', phrase, '|', match_type) as _id FROM \`onyga-482313.OI.T_LAUNCH_NEGATIVES\``,

  refreshKey: { every: '1 hour' },

  measures: {
    count: { type: `count`, description: `Number of launch negative phrases` },
  },

  dimensions: {
    id: { sql: `_id`, type: `string`, primaryKey: true },
    strategyId: { sql: `strategy_id`, type: `string`, description: `Strategy the new campaign is scaffolded from (EXACT_BOOST, SEASONAL_PUSH, ...)` },
    parentName: { sql: `parent_name`, type: `string`, description: `Product family (Lollibox, Bottle, Fresh, LolliME, Bunny, LolliBall)` },
    phrase: { sql: `phrase`, type: `string`, description: `The negative keyword phrase text` },
    matchType: { sql: `match_type`, type: `string`, description: `Negative Phrase or Negative Exact` },
    bulksheetMatchType: { sql: `bulksheet_match_type`, type: `string`, description: `Amazon bulksheet token: NEGATIVE_PHRASE or NEGATIVE_EXACT` },
    source: { sql: `source`, type: `string`, description: `MANUAL or COACH` },
    originLevel: { sql: `origin_level`, type: `string`, description: `_ALL, FAMILY, or PRODUCT` },
  },
});
