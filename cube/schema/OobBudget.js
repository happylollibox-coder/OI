// Cube: OobBudget — the "Out of budget" technical phase on the Weekly Run page, from V_OOB_BUDGET_PHASE.
// One row per enabled campaign (SP+SB, launch AND working) that hit CAMPAIGN_OUT_OF_BUDGET on its
// channel's anchor day, with dark %, utilization, net-ROAS windows and ONE budget suggestion (the
// launch controller's dark-gated ladder applied uniformly). Spec: architecture/OOB_BUDGET_PHASE.md.
cube(`OobBudget`, {
  sql: `SELECT campaign_id, campaign_name, channel, engine, CAST(anchor_date AS STRING) anchor_date,
               current_budget, spend_1d, utilization, pct_dark, roas_1d, roas_prev2,
               days_since_budget_change, action, suggested_budget, reason
        FROM \`onyga-482313.OI.V_OOB_BUDGET_PHASE\``,

  // Refresh tied to the SP orchestration (one trigger) — cache invalidates when SP_REFRESH_CUBE_TABLES
  // completes. Live view read, so intra-day status changes appear on the next orchestration stamp.
  refreshKey: { sql: `SELECT MAX(finished_at) FROM \`onyga-482313.OI.LOG_PIPELINE_RUNS\` WHERE procedure_name = 'SP_REFRESH_CUBE_TABLES' AND status = 'OK'` },
  measures: { count: { type: `count` } },

  dimensions: {
    campaignId:    { sql: `campaign_id`,   type: `string`, primaryKey: true },
    campaignName:  { sql: `campaign_name`, type: `string` },
    channel:       { sql: `channel`,       type: `string` },
    engine:        { sql: `engine`,        type: `string` },
    anchorDate:    { sql: `anchor_date`,   type: `string` },
    currentBudget: { sql: `current_budget`,type: `number` },
    spend1d:       { sql: `spend_1d`,      type: `number` },
    utilization:   { sql: `utilization`,   type: `number` },
    pctDark:       { sql: `pct_dark`,      type: `number` },
    roas1d:        { sql: `roas_1d`,       type: `number` },
    roasPrev2:     { sql: `roas_prev2`,    type: `number` },
    daysSinceBudgetChange: { sql: `days_since_budget_change`, type: `number` },
    action:        { sql: `action`,        type: `string` },
    suggestedBudget: { sql: `suggested_budget`, type: `number` },
    reason:        { sql: `reason`,        type: `string` },
  },
});
