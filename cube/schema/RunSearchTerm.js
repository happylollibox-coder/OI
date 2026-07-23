// Cube: RunSearchTerm — search terms under each NEW-campaign target (level 3 of the Weekly Run card).
// One row per (campaign, keyword, search_term), last 28 days. The card groups these into Spenders /
// Winners / Negates (top 3 + other). Reads V_RUN_SEARCH_TERM directly (small). Spec: architecture/CAMPAIGN_LAUNCH_RAMP.md.
cube(`RunSearchTerm`, {
  sql: `SELECT campaign_id, keyword_id, search_term, clicks, orders, units, spend, sales, net_roas, acos, is_winner, is_negate,
               d1_spend, d1_sales, d7_spend, d7_sales, d28_spend, d28_sales
        FROM \`onyga-482313.OI.V_RUN_SEARCH_TERM\``,

  // Refresh tied to the SP orchestration (one trigger) — cache invalidates when SP_REFRESH_CUBE_TABLES completes.
  refreshKey: { sql: `SELECT MAX(finished_at) FROM \`onyga-482313.OI.LOG_PIPELINE_RUNS\` WHERE procedure_name = 'SP_REFRESH_CUBE_TABLES' AND status = 'OK'` },
  measures: { count: { type: `count` } },

  dimensions: {
    rowId:      { sql: `CONCAT(campaign_id, '|', keyword_id, '|', search_term)`, type: `string`, primaryKey: true },
    campaignId: { sql: `campaign_id`, type: `string` },
    keywordId:  { sql: `keyword_id`,  type: `string` },
    searchTerm: { sql: `search_term`, type: `string` },
    clicks:     { sql: `clicks`,      type: `number` },
    orders:     { sql: `orders`,      type: `number` },
    units:      { sql: `units`,       type: `number` },
    spend:      { sql: `spend`,       type: `number` },
    sales:      { sql: `sales`,       type: `number` },
    netRoas:    { sql: `net_roas`,    type: `number` },
    acos:       { sql: `acos`,        type: `number` },
    isWinner:   { sql: `is_winner`,   type: `boolean` },
    isNegate:   { sql: `is_negate`,   type: `boolean` },
    // per-day-average spend & sales run-rate at 1d / 7d / 28d (shown on Spenders)
    d1Spend:  { sql: `d1_spend`,  type: `number` }, d1Sales:  { sql: `d1_sales`,  type: `number` },
    d7Spend:  { sql: `d7_spend`,  type: `number` }, d7Sales:  { sql: `d7_sales`,  type: `number` },
    d28Spend: { sql: `d28_spend`, type: `number` }, d28Sales: { sql: `d28_sales`, type: `number` },
  },
});
