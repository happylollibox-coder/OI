// Cube: OobSearchTerm — search-term layer of the Out-of-budget phase, from V_OOB_SEARCH_TERM (live
// read). 28-day window; is_negate = ≥10 clicks · 0 orders · term ≠ keyword (AUTO skips the term test,
// PT excluded). Spec: architecture/OOB_BUDGET_PHASE.md §v2.
cube(`OobSearchTerm`, {
  sql: `SELECT campaign_id, keyword_id, target_text, search_term, kind, clicks, orders, spend, sales,
               net_roas, clicks_90d, orders_90d, spend_90d, term_clicks_90d, term_orders_90d, is_big, term_is_keyword, is_winner, is_negate
        FROM \`onyga-482313.OI.V_OOB_SEARCH_TERM\``,

  refreshKey: { sql: `SELECT MAX(finished_at) FROM \`onyga-482313.OI.LOG_PIPELINE_RUNS\` WHERE procedure_name = 'SP_REFRESH_CUBE_TABLES' AND status = 'OK'` },
  measures: { count: { type: `count` } },

  dimensions: {
    rowId:      { sql: `CONCAT(campaign_id, '|', target_text, '|', search_term)`, type: `string`, primaryKey: true },
    campaignId: { sql: `campaign_id`, type: `string` },
    keywordId:  { sql: `keyword_id`,  type: `string` },
    targetText: { sql: `target_text`, type: `string` },
    searchTerm: { sql: `search_term`, type: `string` },
    kind:       { sql: `kind`,        type: `string` },
    clicks:     { sql: `clicks`,      type: `number` },
    orders:     { sql: `orders`,      type: `number` },
    spend:      { sql: `spend`,       type: `number` },
    sales:      { sql: `sales`,       type: `number` },
    netRoas:    { sql: `net_roas`,    type: `number` },
    clicks90d:  { sql: `clicks_90d`,  type: `number` },
    orders90d:  { sql: `orders_90d`,  type: `number` },
    spend90d:   { sql: `spend_90d`,   type: `number` },
    termClicks90d: { sql: `term_clicks_90d`, type: `number` },
    termOrders90d: { sql: `term_orders_90d`, type: `number` },
    isBig:      { sql: `is_big`,      type: `boolean` },
    termIsKeyword: { sql: `term_is_keyword`, type: `boolean` },
    isWinner:   { sql: `is_winner`,   type: `boolean` },
    isNegate:   { sql: `is_negate`,   type: `boolean` },
  },
});

// cache-bust 2026-07-30c: budget-constrained probing (PARK 90d-orders evidence fix, affordable-CPC trim, no probe while capped)
