// Cube: SbLaunchCampaign — campaign-level measures for Sponsored-Brands (incl. video) launch campaigns,
// from sb_campaign_report (the only complete + current SB source; per-keyword SB reporting is dead). The
// Weekly Run card renders these as a campaign-level row with NO per-target drill-down. Spec: architecture/CAMPAIGN_LAUNCH_RAMP.md.
cube(`SbLaunchCampaign`, {
  sql: `SELECT campaign_id, campaign_name, day_of_ramp, current_budget, suggested_budget, budget_reason, pct_dark, spend_today,
               camp_roas_1d, camp_roas_prev2, CAST(anchor_date AS STRING) anchor_date,
               r2_spend, r2_cpc, r2_clk, r2_ctr, r2_tos, r2_roas, r2_acos, r2_impr, r2_orders,
               r3_spend, r3_cpc, r3_clk, r3_ctr, r3_tos, r3_roas, r3_acos, r3_impr, r3_orders
        FROM \`onyga-482313.OI.V_SB_LAUNCH_CAMPAIGN\``,

  // Refresh tied to the SP orchestration (one trigger) — cache invalidates when SP_REFRESH_CUBE_TABLES completes.
  // LIVE-VIEW cube (Ori 2026-07-30 'do we need caching?'): sources change intraday and view fixes
  // don't move the orchestration stamp — a 15-min TTL bounds staleness; T_-backed cubes keep the stamp.
  refreshKey: { every: '15 minutes' },
  measures: { count: { type: `count` } },

  dimensions: {
    campaignId:   { sql: `campaign_id`,   type: `string`, primaryKey: true },
    campaignName: { sql: `campaign_name`, type: `string` },
    dayOfRamp:    { sql: `day_of_ramp`,   type: `number` },
    currentBudget:  { sql: `current_budget`,   type: `number` },
    suggestedBudget:{ sql: `suggested_budget`, type: `number` },
    budgetReason:   { sql: `budget_reason`,    type: `string` },
    spendToday:     { sql: `spend_today`,      type: `number` },
    campRoas1d:     { sql: `camp_roas_1d`,     type: `number` },
    campRoasPrev2:  { sql: `camp_roas_prev2`,  type: `number` },
    pctDark:      { sql: `pct_dark`,      type: `number` },
    anchorDate:   { sql: `anchor_date`,   type: `string` },
    r2Spend: { sql: `r2_spend`, type: `number` }, r2Cpc: { sql: `r2_cpc`, type: `number` }, r2Clk: { sql: `r2_clk`, type: `number` },
    r2Ctr: { sql: `r2_ctr`, type: `number` }, r2Tos: { sql: `r2_tos`, type: `number` }, r2Roas: { sql: `r2_roas`, type: `number` },
    r2Acos: { sql: `r2_acos`, type: `number` }, r2Impr: { sql: `r2_impr`, type: `number` }, r2Orders: { sql: `r2_orders`, type: `number` },
    r3Spend: { sql: `r3_spend`, type: `number` }, r3Cpc: { sql: `r3_cpc`, type: `number` }, r3Clk: { sql: `r3_clk`, type: `number` },
    r3Ctr: { sql: `r3_ctr`, type: `number` }, r3Tos: { sql: `r3_tos`, type: `number` }, r3Roas: { sql: `r3_roas`, type: `number` },
    r3Acos: { sql: `r3_acos`, type: `number` }, r3Impr: { sql: `r3_impr`, type: `number` }, r3Orders: { sql: `r3_orders`, type: `number` },
  },
});

// cache-bust v2: TOS nulled — sb_campaign_report's top_of_search field is placement mix (86%), not competitive IS (<5%)

// cache-bust v3: budget suggestion (SB-native signals) + camp roas dims

// cache-bust 2026-07-30c: budget-constrained probing (PARK 90d-orders evidence fix, affordable-CPC trim, no probe while capped)
