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

  // Restatement-safe key — see the note in Ads.js. Keys on the physical base tables behind
  // V_KEYWORD_DAILY (both live in fivetran-hl, which the Cloud Run SA can read: it holds
  // roles/bigquery.dataViewer + jobUser on that project). Amazon restates the report in place:
  // on 2026-07-23 the 07-14→07-20 window moved cost 1,153.73 -> 1,152.75 and sales_14_d
  // 2,431.10 -> 2,593.45 across an unchanged 353 rows, with MAX(date) pinned at 2026-07-20.
  // keyword_history is included because keyword_text / match_type — the cube's grain — come from it.
  refreshKey: {
    sql: `SELECT MAX(last_modified_time) FROM \`fivetran-hl.amazon_ads.__TABLES__\` WHERE table_id IN ('targeting_keyword_report', 'keyword_history')`,
  },
});
