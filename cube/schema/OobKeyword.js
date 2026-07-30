// Cube: OobKeyword — keyword layer of the Out-of-budget phase (Weekly Run), from V_OOB_KEYWORD (live
// read, like OobBudget). One row per (dark>10% SP campaign, target) with the click-band / ROAS-ladder
// bid suggestion. Spec: architecture/OOB_BUDGET_PHASE.md §v2.
cube(`OobKeyword`, {
  sql: `SELECT campaign_id, campaign_name, pct_dark, keyword_id, ad_group_id, target_text, match_type,
               is_auto, is_pt, current_bid, clicks_1d, spend_1d, cpc_1d, units_1d, roas_1d,
               clicks_prev2, spend_prev2, cpc_prev2, units_prev2, roas_prev2,
               converting, days_since_change, suggested_bid, bid_action, bid_reason
        FROM \`onyga-482313.OI.V_OOB_KEYWORD\``,

  // Same stamp as the other launch-track cubes: invalidate when the orchestration completes.
  refreshKey: { sql: `SELECT MAX(finished_at) FROM \`onyga-482313.OI.LOG_PIPELINE_RUNS\` WHERE procedure_name = 'SP_REFRESH_CUBE_TABLES' AND status = 'OK'` },
  measures: { count: { type: `count` } },

  dimensions: {
    rowId:       { sql: `CONCAT(campaign_id, '|', target_text)`, type: `string`, primaryKey: true },
    campaignId:  { sql: `campaign_id`,  type: `string` },
    campaignName:{ sql: `campaign_name`, type: `string` },
    pctDark:     { sql: `pct_dark`,     type: `number` },
    keywordId:   { sql: `keyword_id`,   type: `string` },
    adGroupId:   { sql: `ad_group_id`,  type: `string` },
    targetText:  { sql: `target_text`,  type: `string` },
    matchType:   { sql: `match_type`,   type: `string` },
    isAuto:      { sql: `is_auto`,      type: `boolean` },
    isPt:        { sql: `is_pt`,        type: `boolean` },
    currentBid:  { sql: `current_bid`,  type: `number` },
    clicks1d:    { sql: `clicks_1d`,    type: `number` },
    spend1d:     { sql: `spend_1d`,     type: `number` },
    cpc1d:       { sql: `cpc_1d`,       type: `number` },
    units1d:     { sql: `units_1d`,     type: `number` },
    roas1d:      { sql: `roas_1d`,      type: `number` },
    clicksPrev2: { sql: `clicks_prev2`, type: `number` },
    spendPrev2:  { sql: `spend_prev2`,  type: `number` },
    cpcPrev2:    { sql: `cpc_prev2`,    type: `number` },
    unitsPrev2:  { sql: `units_prev2`,  type: `number` },
    roasPrev2:   { sql: `roas_prev2`,   type: `number` },
    converting:  { sql: `converting`,   type: `boolean` },
    daysSinceChange: { sql: `days_since_change`, type: `number` },
    suggestedBid:{ sql: `suggested_bid`, type: `number` },
    bidAction:   { sql: `bid_action`,   type: `string` },
    bidReason:   { sql: `bid_reason`,   type: `string` },
  },
});
