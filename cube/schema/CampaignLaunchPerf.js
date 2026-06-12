// Cube: CampaignLaunchPerf — from T_CAMPAIGN_LAUNCH_PERF
// First-3-month performance per campaign (launch quality analysis)
cube(`CampaignLaunchPerf`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_CAMPAIGN_LAUNCH_PERF\``,

  refreshKey: { every: '1 hour' },

  measures: {
    count: { type: `count`, description: `Number of campaigns` },
    totalSpend: { sql: `ad_spend`, type: `sum` },
    totalUnits: { sql: `units`, type: `sum` },
    totalNetProfit: { sql: `net_profit`, type: `sum` },
  },

  dimensions: {
    campaignId: { sql: `campaign_id`, type: `string`, primaryKey: true },
    campaignName: { sql: `campaign_name`, type: `string` },
    campaignType: { sql: `campaign_type`, type: `string` },
    campaignState: { sql: `campaign_state`, type: `string` },
    creationDate: { sql: `creation_date`, type: `string` },
    windowEnd: { sql: `window_end`, type: `string` },
    windowStatus: { sql: `window_status`, type: `string` },
    experimentId: { sql: `experiment_id`, type: `string` },
    experimentName: { sql: `experiment_name`, type: `string` },
    strategyId: { sql: `strategy_id`, type: `string` },
    strategyName: { sql: `strategy_name`, type: `string` },
    campaignAgeDays: { sql: `campaign_age_days`, type: `number` },
    units: { sql: `units`, type: `number` },
    clicks: { sql: `clicks`, type: `number` },
    impressions: { sql: `impressions`, type: `number` },
    orders: { sql: `orders`, type: `number` },
    adSpend: { sql: `ad_spend`, type: `number` },
    adSales: { sql: `ad_sales`, type: `number` },
    grossProfit: { sql: `gross_profit`, type: `number` },
    netProfit: { sql: `net_profit`, type: `number` },
    cpc: { sql: `cpc`, type: `number` },
    netRoas: { sql: `net_roas`, type: `number` },
    activeDays: { sql: `active_days`, type: `number` },
  },
});
