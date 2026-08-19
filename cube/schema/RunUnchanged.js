// Cube: RunUnchanged — the row-grain drill behind the summary strip's UNCHANGED line
// (V_RUN_UNCHANGED live read). Phase 6 Task 7. Spec: architecture/WEEKLY_RUN_UX.md.
// One row per keyword with NO instruction today: its state-machine class, record, next
// appointment and the state machine's own reason sentence. PASSTHROUGH ONLY.
cube(`RunUnchanged`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_RUN_UNCHANGED\``,
  refreshKey: { every: '15 minutes' },
  measures: { count: { type: `count` } },
  dimensions: {
    rowId:         { sql: `CONCAT(campaign_id, '|', COALESCE(keyword_id, ''))`, type: `string`, primaryKey: true },
    campaignId:    { sql: `campaign_id`,    type: `string` },
    campaignName:  { sql: `campaign_name`,  type: `string` },
    family:        { sql: `family`,         type: `string` },
    keywordId:     { sql: `keyword_id`,     type: `string` },
    targetText:    { sql: `target_text`,    type: `string` },
    matchType:     { sql: `match_type`,     type: `string` },
    channel:       { sql: `channel`,        type: `string` },
    currentBid:    { sql: `current_bid`,    type: `number` },
    state:         { sql: `state`,          type: `string` },
    ownerEngine:   { sql: `owner_engine`,   type: `string` },
    class:         { sql: `class`,          type: `string` },
    settledClk90:  { sql: `settled_clk90`,  type: `number` },
    settledRoas90: { sql: `settled_roas90`, type: `number` },
    recordClass:   { sql: `record_class`,   type: `string` },  // the VIEW's 1.0/0.6 bands — the strip colors by this, never by TSX thresholds
    nextCheckDate: { sql: `CAST(next_check_date AS STRING)`, type: `string` },
    nextCheckWhat: { sql: `next_check_what`, type: `string` },
    whyShort:      { sql: `why_short`,      type: `string` },
  },
});
// cache-bust 2026-08-16b: + recordClass passthrough (V_RUN_UNCHANGED record_class)
