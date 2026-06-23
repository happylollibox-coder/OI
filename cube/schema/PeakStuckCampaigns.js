cube('PeakStuckCampaigns', {
  sql: () => `SELECT * FROM \`onyga-482313\`.OI.V_PEAK_STUCK_CAMPAIGNS`,

  dimensions: {
    campaignName: { sql: () => `campaign_name`, type: 'string', primaryKey: true },
    parentName: { sql: () => `parent_name`, type: 'string' },
    campaignState: { sql: () => `campaign_state`, type: 'string' },
    stuckFlag: { sql: () => `stuck_flag`, type: 'string' },
    budgetUtilPct: { sql: () => `budget_util_pct`, type: 'number' },
    budget: { sql: () => `budget`, type: 'number' },
    recentOrders: { sql: () => `recent_orders`, type: 'number' },
    netRoas: { sql: () => `net_roas`, type: 'number' },
    daysSinceBudgetChg: { sql: () => `days_since_budget_chg`, type: 'number' },
    reason: { sql: () => `reason`, type: 'string' },
  },
});
