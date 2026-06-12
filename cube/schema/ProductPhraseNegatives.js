// Cube: ProductPhraseNegatives - from T_PRODUCT_PHRASE_NEGATIVES
// ONE ROW PER PHRASE × FAMILY: curated negative keyword phrases per product
cube(`ProductPhraseNegatives`, {
  sql: `SELECT *, CONCAT(effective_parent_name, '|', phrase, '|', match_type) as _id FROM \`onyga-482313.OI.T_PRODUCT_PHRASE_NEGATIVES\``,

  refreshKey: { every: '1 hour' },

  measures: {
    count: { type: `count`, description: `Number of negative phrases` },
  },

  dimensions: {
    id: { sql: `_id`, type: `string`, primaryKey: true },
    effectiveParentName: { sql: `effective_parent_name`, type: `string`, description: `Product family (Lollibox, Bottle, Fresh, LolliME)` },
    phrase: { sql: `phrase`, type: `string`, description: `The negative keyword phrase text` },
    matchType: { sql: `match_type`, type: `string`, description: `Negative Phrase or Negative Exact` },
    source: { sql: `source`, type: `string`, description: `MANUAL or COACH` },
    originLevel: { sql: `origin_level`, type: `string`, description: `_ALL, FAMILY, or PRODUCT` },
  },
});
