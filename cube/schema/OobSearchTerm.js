// Cube: OobSearchTerm — search-term layer of the Out-of-budget phase, from V_OOB_SEARCH_TERM (live
// read). 28-day window; is_negate = ≥10 clicks · 0 orders · term ≠ keyword (AUTO skips the term test,
// PT excluded). Spec: architecture/OOB_BUDGET_PHASE.md §v2.
cube(`OobSearchTerm`, {
  sql: `SELECT campaign_id, engine, keyword_id, target_text, search_term, kind, clicks, orders, spend, spend_1d, sales,
               net_roas, net_roas_90d, clicks_90d, orders_90d, spend_90d, ad_group_ids, term_clicks_90d, term_orders_90d, is_big, sqp_wait, market_purchases_90d, term_is_keyword, is_winner, is_negate
        FROM \`onyga-482313.OI.V_OOB_SEARCH_TERM\``,

  // LIVE-VIEW cube (Ori 2026-07-30 'do we need caching?'): sources change intraday and view fixes
  // don't move the orchestration stamp — a 15-min TTL bounds staleness; T_-backed cubes keep the stamp.
  refreshKey: { every: '15 minutes' },
  measures: { count: { type: `count` } },

  dimensions: {
    rowId:      { sql: `CONCAT(campaign_id, '|', target_text, '|', search_term)`, type: `string`, primaryKey: true },
    campaignId: { sql: `campaign_id`, type: `string` },
    engine:     { sql: `engine`,      type: `string` },   // 'OOB' | 'LIFT' — which panel owns the campaign
    keywordId:  { sql: `keyword_id`,  type: `string` },
    targetText: { sql: `target_text`, type: `string` },
    searchTerm: { sql: `search_term`, type: `string` },
    kind:       { sql: `kind`,        type: `string` },
    spend1d:    { sql: `spend_1d`,    type: `number` },
    clicks:     { sql: `clicks`,      type: `number` },
    orders:     { sql: `orders`,      type: `number` },
    spend:      { sql: `spend`,       type: `number` },
    sales:      { sql: `sales`,       type: `number` },
    netRoas:    { sql: `net_roas`,    type: `number` },
    netRoas90d: { sql: `net_roas_90d`, type: `number` },
    adGroupIds: { sql: `ad_group_ids`, type: `string` },
    clicks90d:  { sql: `clicks_90d`,  type: `number` },
    orders90d:  { sql: `orders_90d`,  type: `number` },
    spend90d:   { sql: `spend_90d`,   type: `number` },
    termClicks90d: { sql: `term_clicks_90d`, type: `number` },
    termOrders90d: { sql: `term_orders_90d`, type: `number` },
    isBig:      { sql: `is_big`,      type: `boolean` },
    sqpWait:    { sql: `sqp_wait`,    type: `boolean` },
    marketPurchases90d: { sql: `market_purchases_90d`, type: `number` },
    termIsKeyword: { sql: `term_is_keyword`, type: `boolean` },
    isWinner:   { sql: `is_winner`,   type: `boolean` },
    isNegate:   { sql: `is_negate`,   type: `boolean` },
  },
});

// cache-bust 2026-07-30c: budget-constrained probing (PARK 90d-orders evidence fix, affordable-CPC trim, no probe while capped)
