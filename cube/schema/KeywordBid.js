// Cube: KeywordBid — latest set bid per (keyword text, match type).
// Backed by V_KEYWORD_DAILY (keyword×day from the true keyword report). FACT_AMAZON_ADS uses a
// different keyword_id space than the targeting report, so the Ads-page drill-down joins bids on the
// keyword TEXT + match type (FACT_AMAZON_ADS.targeting + targeting_type) rather than on keyword_id.
// One row per (keyword_text, match_type), taking the most-recent day's bid.
cube(`KeywordBid`, {
  sql: `
    SELECT
      keyword_text,
      match_type,
      ANY_VALUE(keyword_bid HAVING MAX date) AS keyword_bid
    FROM \`onyga-482313.OI.V_KEYWORD_DAILY\`
    WHERE keyword_text IS NOT NULL
    GROUP BY keyword_text, match_type
  `,

  measures: {
    count: { type: `count` },
  },

  dimensions: {
    id:          { sql: `CONCAT(keyword_text, '|', COALESCE(match_type, ''))`, type: `string`, primaryKey: true },
    keywordText: { sql: `keyword_text`, type: `string`, description: `Keyword display text (joins to Ads.targeting)` },
    matchType:   { sql: `match_type`,   type: `string`, description: `EXACT / PHRASE / BROAD` },
    keywordBid:  { sql: `keyword_bid`,  type: `number`, description: `Latest set bid (USD)` },
  },

  refreshKey: {
    sql: `SELECT MAX(date) FROM \`onyga-482313.OI.V_KEYWORD_DAILY\``,
  },
});
