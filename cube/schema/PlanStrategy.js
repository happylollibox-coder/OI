// Cube: PlanStrategy - from DE_PLAN_STRATEGY
// Versioned plans with lifecycle (DRAFT/APPROVED)
// Per-family monthly spend strategy (multiplier + target ROAS)
cube(`PlanStrategy`, {
  sql: `SELECT * FROM \`onyga-482313.OI.DE_PLAN_STRATEGY\``,

  refreshKey: { every: '1 minute' },  // fast refresh since user-edited

  measures: {
    count: { type: 'count' },
  },

  dimensions: {
    planId: { sql: 'plan_id', type: 'string' },
    planName: { sql: 'plan_name', type: 'string' },
    planYear: { sql: 'plan_year', type: 'number' },
    planVersion: { sql: 'plan_version', type: 'number' },
    status: { sql: 'status', type: 'string' },
    family: { sql: 'family', type: 'string' },
    strategy: { sql: 'strategy', type: 'string' },
    forecastYear: { sql: 'forecast_year', type: 'number' },
    forecastMonth: { sql: 'forecast_month', type: 'number' },
    multiplier: { sql: 'multiplier', type: 'number' },
    targetRoas: { sql: 'target_roas', type: 'number' },
    baseRoas: { sql: 'base_roas', type: 'number' },
  },
});
