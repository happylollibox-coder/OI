// Cube: CampaignDim — campaign identity/state flags from V_DIM_CAMPAIGN_CURRENT (live view).
// Built for the Weekly Run v9 sections (Ori 2026-08-02): paused SEASONAL campaigns show inside
// the Seasonal section (revival visibility); paused non-seasonal go to "Other — paused".
// ARCHIVED campaigns are excluded everywhere. Spec: architecture/OOB_BUDGET_PHASE.md §v9.
cube(`CampaignDim`, {
  sql: `SELECT campaign_id, campaign_name, campaign_type, campaign_state, daily_budget,
               LOWER(campaign_name) LIKE '%brand defense%' AS is_defense,
               REGEXP_CONTAINS(LOWER(campaign_name), r'christmas|xmas|valentine|easter|halloween|thanksgiving|black friday|bfcm|cyber monday|back to school|mother.?s day|father.?s day|santa|advent|holiday') AS is_seasonal
        FROM \`onyga-482313.OI.V_DIM_CAMPAIGN_CURRENT\`
        WHERE campaign_state != 'ARCHIVED'`,

  // Live-view cube: identity/state only, 15-min TTL bounds staleness (same policy as OobBudget).
  refreshKey: { every: '15 minutes' },
  measures: { count: { type: `count` } },

  dimensions: {
    campaignId:   { sql: `campaign_id`,    type: `string`, primaryKey: true },
    campaignName: { sql: `campaign_name`,  type: `string` },
    channel:      { sql: `campaign_type`,  type: `string` },   // 'SP' | 'SB'
    state:        { sql: `campaign_state`, type: `string` },   // ENABLED | PAUSED
    dailyBudget:  { sql: `daily_budget`,   type: `number` },
    isDefense:    { sql: `is_defense`,     type: `boolean` },
    isSeasonal:   { sql: `is_seasonal`,    type: `boolean` },
  },
});
