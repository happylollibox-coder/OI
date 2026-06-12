// Cube: CampaignLaunchMonthly — from T_CAMPAIGN_LAUNCH_MONTHLY
// Monthly-bucketed (M1/M2/M3) campaign launch performance with ASIN/parent for filtering
cube(`CampaignLaunchMonthly`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_CAMPAIGN_LAUNCH_MONTHLY\``,

  refreshKey: { every: '1 hour' },

  measures: {
    count: { type: `count`, description: `Number of campaigns` },
    totalNetProfit: { sql: `total_net_profit`, type: `sum` },
  },

  dimensions: {
    campaignId: { sql: `campaign_id`, type: `string`, primaryKey: true },
    campaignName: { sql: `campaign_name`, type: `string` },
    campaignType: { sql: `campaign_type`, type: `string` },
    campaignState: { sql: `campaign_state`, type: `string` },
    creationDate: { sql: `creation_date`, type: `string` },
    strategyName: { sql: `strategy_name`, type: `string` },
    asin: { sql: `asin`, type: `string` },
    parentName: { sql: `parent_name`, type: `string` },
    lastActiveDate: { sql: `last_active_date`, type: `string` },
    endDateDisplay: { sql: `end_date_display`, type: `string` },
    monthsActive: { sql: `months_active`, type: `number` },
    totalNetProfitDim: { sql: `total_net_profit`, type: `number` },
    netProfitMonthlyAvg: { sql: `net_profit_monthly_avg`, type: `number` },
    // Month 1
    m1Units: { sql: `m1_units`, type: `number` },
    m1Cpc: { sql: `m1_cpc`, type: `number` },
    m1AdSpend: { sql: `m1_ad_spend`, type: `number` },
    m1NetRoas: { sql: `m1_net_roas`, type: `number` },
    // Month 2
    m2Units: { sql: `m2_units`, type: `number` },
    m2Cpc: { sql: `m2_cpc`, type: `number` },
    m2AdSpend: { sql: `m2_ad_spend`, type: `number` },
    m2NetRoas: { sql: `m2_net_roas`, type: `number` },
    // Month 3
    m3Units: { sql: `m3_units`, type: `number` },
    m3Cpc: { sql: `m3_cpc`, type: `number` },
    m3AdSpend: { sql: `m3_ad_spend`, type: `number` },
    m3NetRoas: { sql: `m3_net_roas`, type: `number` },
  },
});
