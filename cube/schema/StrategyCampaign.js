// Cube: StrategyCampaign — one row per current campaign with resolved strategy + lifetime perf.
// Backed by V_STRATEGY_CAMPAIGN_PERF (campaigns with lifetime spend > 0).
cube(`StrategyCampaign`, {
  sql_table: `\`onyga-482313.OI.V_STRATEGY_CAMPAIGN_PERF\``,
  refreshKey: { every: `30 minutes` },
  measures: {
    count: { type: `count` },
    spend: { sql: `spend`, type: `sum`, format: `currency` },
    orders: { sql: `orders`, type: `sum` },
    clicks: { sql: `clicks`, type: `sum` },
    impressions: { sql: `impressions`, type: `sum` },
    sales: { sql: `sales`, type: `sum`, format: `currency` },
  },
  dimensions: {
    campaignId: { sql: `campaign_id`, type: `string`, primaryKey: true },
    campaignName: { sql: `campaign_name`, type: `string` },
    campaignType: { sql: `campaign_type`, type: `string` },
    parentName: { sql: `parent_name`, type: `string` },
    strategyId: { sql: `strategy_id`, type: `string` },
    strategySource: { sql: `strategy_source`, type: `string` },
    isActive: { sql: `is_active`, type: `boolean` },
    netRoas: { sql: `net_roas`, type: `number` },
    convRate: { sql: `conv_rate`, type: `number` },
    cpc: { sql: `cpc`, type: `number` },
    lastDate: { sql: `last_date`, type: `string` },
  },
});
