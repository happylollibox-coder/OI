// Cube: CampaignBudgetStep1 — one row per ENABLED campaign for the Weekly Run per-family Step-1 Budget table.
// Reads V_BUDGET_STEP1_CAMPAIGN directly (small, config-driven — no T_ materialization needed).
// Tier (WINNING/MARGIN/LOSING) lets the UI group; spendDay drives the spend-desc order within each group.
cube(`CampaignBudgetStep1`, {
  sql: `SELECT campaign_id, parent_name, campaign_name, campaign_type, tier,
               net_roas, net_profit_day, spend_day, last_cpc, current_budget, new_budget, is_floor, is_defense, role,
               strategy_role, strategy_category, ramp_day, ramp_days, est_halo, net_incl_halo, age_days, age_bucket
        FROM \`onyga-482313.OI.V_BUDGET_STEP1_CAMPAIGN\``,

  refreshKey: { every: `10 minutes` },

  measures: { count: { type: `count` } },

  dimensions: {
    campaignId:    { sql: `campaign_id`,    type: `string`, primaryKey: true },
    parentName:    { sql: `parent_name`,    type: `string` },
    campaignName:  { sql: `campaign_name`,  type: `string` },
    campaignType:  { sql: `campaign_type`,  type: `string` },
    tier:          { sql: `tier`,           type: `string` },
    netRoas:       { sql: `net_roas`,       type: `number` },
    netProfitDay:  { sql: `net_profit_day`, type: `number` },
    spendDay:      { sql: `spend_day`,      type: `number` },
    lastCpc:       { sql: `last_cpc`,       type: `number` },
    currentBudget: { sql: `current_budget`, type: `number` },
    newBudget:     { sql: `new_budget`,     type: `number` },
    isFloor:       { sql: `is_floor`,       type: `boolean` },
    isDefense:     { sql: `is_defense`,     type: `boolean` },
    role:          { sql: `role`,           type: `string` },
    // Coverage role (AUTO/EXACT/BROAD/PHRASE/COMPETITOR/SB_VIDEO/*_DEFENSE) — the step-1 strategy split's
    // grain. Distinct from `role` above, which is only the 3-way PPC pool.
    strategyRole:  { sql: `strategy_role`,  type: `string` },
    strategyCategory: { sql: `strategy_category`, type: `string` },
    // Launch-ramp grace: which day of its 20 a NEW-tier campaign is on. NULL once mature.
    rampDay:       { sql: `ramp_day`,       type: `number` },
    rampDays:      { sql: `ramp_days`,      type: `number` },
    estHalo:       { sql: `est_halo`,       type: `number` },
    netInclHalo:   { sql: `net_incl_halo`,  type: `number` },
    // Age bucketing for the "Budget by age" section: NEW (<=20d, phase-1 controlled) / 1-3MO / 4-9MO / 10MO+.
    ageDays:       { sql: `age_days`,       type: `number` },
    ageBucket:     { sql: `age_bucket`,     type: `string` },
  },
});
