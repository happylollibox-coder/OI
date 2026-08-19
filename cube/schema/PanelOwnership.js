// Cube: PanelOwnership — THE single-home function for the Weekly Run panels, from
// FACT_PANEL_OWNERSHIP (the snapshot of V_PANEL_OWNERSHIP).
// Spec: architecture/PANEL_OWNERSHIP.md. Ori 2026-08-13: "same campaign with different measures
// shows in 2 criterias (this is not good)."
//
// One row per ENABLED campaign. Priority ladder Ori set: LOW STOCK > LAUNCH > REVIVALS > engines.
//   ownerRank 1 LOW_STOCK  FULL claim   — every lower panel defers, both levers (bid AND budget)
//   ownerRank 2 LAUNCH     PARTIAL      — blocks ROAS money cuts only (V_LAUNCH_EXEMPTION); evicts
//                                         nobody, because the launch controller has had no panel of
//                                         its own since 2026-08-01
//   ownerRank 3 REVIVAL    keyword-grain, already single-homed by FACT_PARK_REVERDICT.engine_immune
//   ownerRank 4 OOB / LIFT the engines; which of the two owns the bids is still decided by
//                          V_CAMPAIGN_CAP_STATE.is_oob_owned and is only REPORTED here
//
// HOW A PANEL USES THIS — the whole point is that the panel makes no decision. Read
// deferEnginePanel / deferRevivalPanel / deferLaunchPanel for the panel's own rank and, when true,
// render the row with deferAction + deferReason and NO suggested value (the DEFER_OOB shape), or
// drop it. Never re-derive the claim, never test riskState in TypeScript, never write the reason
// text in the component: every word of deferReason and claimReason is decided in the VIEW
// (feedback_all_logic_in_backend).
//
// WHY THE SNAPSHOT AND NOT THE VIEW: V_PANEL_OWNERSHIP reads V_LOW_STOCK_ADS, which sits at
// BigQuery's query-planning ceiling. Panels and engines read the TABLE so they all see the same
// answer as each other — the disagreement between two sources is the exact bug this exists to fix.
// The claim's inputs (inventory snapshot, ads anchor) move once a day, so a daily snapshot is
// exactly as fresh as the evidence under it.
cube(`PanelOwnership`, {
  sql: `SELECT * FROM \`onyga-482313.OI.FACT_PANEL_OWNERSHIP\``,

  // SNAPSHOT cube: rebuilt by SP_SNAPSHOT_PANEL_OWNERSHIP inside the daily orchestration, so the
  // table's own last_modified_time is the honest key (fact_oi_cube_refresh_key_restatement).
  refreshKey: {
    sql: `SELECT last_modified_time FROM \`onyga-482313.OI\`.__TABLES__ WHERE table_id = 'FACT_PANEL_OWNERSHIP'`,
  },

  measures: {
    count: { type: `count` },
    claimedCampaigns: { sql: `IF(claim_rank = 1, 1, 0)`, type: `sum` },
  },

  dimensions: {
    campaignId:    { sql: `campaign_id`,    type: `string`, primaryKey: true, shown: true },
    campaignName:  { sql: `campaign_name`,  type: `string` },
    channel:       { sql: `channel`,        type: `string` },
    servingStatus: { sql: `serving_status`, type: `string` },
    budgetNow:     { sql: `budget_now`,     type: `number` },
    family:        { sql: `family`,         type: `string` },

    isDefense:       { sql: `is_defense`,        type: `boolean` },
    isSeasonal:      { sql: `is_seasonal`,       type: `boolean` },
    isAutoCampaign:  { sql: `is_auto_campaign`,  type: `boolean` },
    isOobOwned:      { sql: `is_oob_owned`,      type: `boolean` },  // V_CAMPAIGN_CAP_STATE, reported
    daysCapped7d:    { sql: `days_capped_7d`,    type: `number` },
    isLaunch:        { sql: `is_launch`,         type: `boolean` },
    launchExemptActive: { sql: `launch_exempt_active`, type: `boolean` },
    launchExemptUntil:  { sql: `CAST(launch_exempt_until AS STRING)`, type: `string` },

    // the low-stock evidence the claim was taken on
    lowStockState:      { sql: `low_stock_state`,       type: `string` },  // family verdict as applied
    // v27.78 (Task 4.11): the third claim basis — TRUE when low stock is RE-AIMING this family's
    // ad doorways at an in-stock sibling rather than braking. Published so a panel can say WHICH
    // signal the claim rests on; without it the column reaches the table but no panel can read it.
    lsRedirectMode:     { sql: `ls_redirect_mode`,      type: `boolean` },
    bindingCoverDays:   { sql: `binding_cover_days`,    type: `number` },
    lowStockStateRow:   { sql: `low_stock_state_row`,   type: `string` },  // what the campaign row said
    bindingProduct:     { sql: `binding_product`,       type: `string` },
    lsAction:           { sql: `ls_action`,             type: `string` },
    lsNow:              { sql: `ls_now`,                type: `number` },
    lsSuggested:        { sql: `ls_suggested`,          type: `number` },
    lsProposalTargets:  { sql: `ls_proposal_targets`,   type: `number` },
    lsFreedPerDay:      { sql: `ls_freed_per_day`,      type: `number` },

    // the ladder
    owner:       { sql: `owner`,        type: `string` },   // LOW_STOCK | LAUNCH | OOB | LIFT
    ownerRank:   { sql: `owner_rank`,   type: `number` },
    claimRank:   { sql: `claim_rank`,   type: `number` },   // rank of the FULL claim; 99 = none
    claimScope:  { sql: `claim_scope`,  type: `string` },   // FULL | PARTIAL_NO_CUT
    claimReason: { sql: `claim_reason`, type: `string` },   // one short clause — backend-owned prose

    // the eviction — render these, decide nothing
    deferAction:       { sql: `defer_action`,       type: `string` },   // DEFER_LOW_STOCK | NULL
    deferReason:       { sql: `defer_reason`,       type: `string` },
    deferLaunchPanel:  { sql: `defer_launch_panel`,  type: `boolean` },
    deferRevivalPanel: { sql: `defer_revival_panel`, type: `boolean` },
    deferEnginePanel:  { sql: `defer_engine_panel`,  type: `boolean` },
  },
});
