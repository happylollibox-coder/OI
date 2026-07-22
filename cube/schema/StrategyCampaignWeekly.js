// Cube: StrategyCampaignWeekly — campaign×week ads perf with resolved strategy.
// Backed by V_STRATEGY_CAMPAIGN_WEEKLY.
cube(`StrategyCampaignWeekly`, {
  sql_table: `\`onyga-482313.OI.V_STRATEGY_CAMPAIGN_WEEKLY\``,
  refreshKey: { every: `30 minutes` },
  measures: {
    spend: { sql: `spend`, type: `sum`, format: `currency` },
    orders: { sql: `orders`, type: `sum` },
    clicks: { sql: `clicks`, type: `sum` },
    impressions: { sql: `impressions`, type: `sum` },
    sales: { sql: `sales`, type: `sum`, format: `currency` },
  },
  dimensions: {
    id: { sql: `CONCAT(CAST(week_start AS STRING), '|', campaign_id)`, type: `string`, primaryKey: true },
    weekStart: { sql: `CAST(week_start AS TIMESTAMP)`, type: `time` },
    campaignId: { sql: `campaign_id`, type: `string` },
    campaignName: { sql: `campaign_name`, type: `string` },
    parentName: { sql: `parent_name`, type: `string` },
    strategyId: { sql: `strategy_id`, type: `string` },
  },
});
