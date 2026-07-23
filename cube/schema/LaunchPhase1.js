// Cube: LaunchPhase1 — per-target bid + per-campaign budget suggestions for campaigns in their first
// 20 days (the launch phase-1 controller). Reads V_LAUNCH_PHASE1 directly (small — no T_ materialization).
// Feeds the "Budget by age" NEW bucket: the Apply-all button queues suggested_bid / suggested_budget.
// Spec: architecture/CAMPAIGN_LAUNCH_RAMP.md §"Phase 1".
cube(`LaunchPhase1`, {
  sql: `SELECT campaign_id, campaign_name, day_of_ramp, pct_dark, current_budget, spend_today,
               camp_roas_1d, camp_eq3, camp_roas_prev2, suggested_budget, budget_reason,
               keyword_id, ad_group_id, target_text, target_type, match_type,
               clk3, tgt_roas_1d, tgt_eq3, tgt_roas_prev2, current_bid, suggested_bid, bid_action
        FROM \`onyga-482313.OI.V_LAUNCH_PHASE1\``,

  // Refresh tied to the SP orchestration (one trigger) — cache invalidates when SP_REFRESH_CUBE_TABLES completes.
  refreshKey: { sql: `SELECT MAX(finished_at) FROM \`onyga-482313.OI.LOG_PIPELINE_RUNS\` WHERE procedure_name = 'SP_REFRESH_CUBE_TABLES' AND status = 'OK'` },

  measures: { count: { type: `count` } },

  dimensions: {
    // one row per (campaign, target); keyword_id is unique within campaign, so composite PK
    rowId:         { sql: `CONCAT(campaign_id, '|', COALESCE(keyword_id, 'none'))`, type: `string`, primaryKey: true },
    campaignId:    { sql: `campaign_id`,   type: `string` },
    campaignName:  { sql: `campaign_name`, type: `string` },
    dayOfRamp:     { sql: `day_of_ramp`,   type: `number` },
    pctDark:       { sql: `pct_dark`,      type: `number` },
    currentBudget: { sql: `current_budget`, type: `number` },
    spendToday:    { sql: `spend_today`,   type: `number` },
    campRoas1d:    { sql: `camp_roas_1d`,  type: `number` },
    campEq3:       { sql: `camp_eq3`,      type: `number` },
    campRoasPrev2: { sql: `camp_roas_prev2`, type: `number` },
    suggestedBudget:{ sql: `suggested_budget`, type: `number` },
    budgetReason:  { sql: `budget_reason`,  type: `string` },
    keywordId:     { sql: `keyword_id`,    type: `string` },
    adGroupId:     { sql: `ad_group_id`,   type: `string` },
    targetText:    { sql: `target_text`,   type: `string` },
    targetType:    { sql: `target_type`,   type: `string` },
    matchType:     { sql: `match_type`,    type: `string` },
    clk3:          { sql: `clk3`,          type: `number` },
    tgtRoas1d:     { sql: `tgt_roas_1d`,   type: `number` },
    tgtEq3:        { sql: `tgt_eq3`,       type: `number` },
    tgtRoasPrev2:  { sql: `tgt_roas_prev2`, type: `number` },
    currentBid:    { sql: `current_bid`,   type: `number` },
    suggestedBid:  { sql: `suggested_bid`, type: `number` },
    bidAction:     { sql: `bid_action`,    type: `string` },
  },
});

// cache-bust: decisions on CORRECTED net ROAS + dark-loser budget cut (2026-07-19 v7)

// cache-bust v9: anchor last-2h rule
