// Cube: PlanAdsTargets - from DE_PLAN_ADS_TARGETS
// Per-family / month / ad-channel planned ads targets emitted by the Plan wizard's Ads Path:
// planned daily ad spend, planned CPC, predicted ROAS/CVR/units/net-profit, season, multiplier.
// Consumed by the Ads Coacher (Actions page) to compare actuals against the plan.
cube(`PlanAdsTargets`, {
  sql: `SELECT * FROM \`onyga-482313.OI.DE_PLAN_ADS_TARGETS\``,

  refreshKey: { every: '1 minute' },  // fast refresh since user-edited (wizard overwrites per family)

  measures: {
    count: { type: 'count' },
  },

  dimensions: {
    family: { sql: 'family', type: 'string' },
    yr: { sql: 'yr', type: 'number' },
    mo: { sql: 'mo', type: 'number' },
    channel: { sql: 'channel', type: 'string' },
    dailySpendTarget: { sql: 'daily_spend_target', type: 'number' },
    cpcTarget: { sql: 'cpc_target', type: 'number' },
    predictedCvr: { sql: 'predicted_cvr', type: 'number' },
    predictedRoas: { sql: 'predicted_roas', type: 'number' },
    predictedUnits: { sql: 'predicted_units', type: 'number' },
    predictedNetProfit: { sql: 'predicted_net_profit', type: 'number' },
    adsShare: { sql: 'ads_share', type: 'number' },
    seasonType: { sql: 'season_type', type: 'string' },
    multiplierK: { sql: 'multiplier_k', type: 'number' },
    planStrategyId: { sql: 'plan_strategy_id', type: 'string' },
  },
});
