// Cube: BudgetSuggestion — single-row suggestion inputs + 7-day spend-tier breakdown for the Step-1 dial.
// The panel computes the suggested total client-side as marginDailySpend / (chosenProvenPct / 100) and
// shows the last-7-days spend split by tier (losing / margin / winning / total).
cube(`BudgetSuggestion`, {
  sql: `SELECT 1 AS id,
               margin_campaign_daily_spend,
               losing_spend_7d, margin_spend_7d, winning_spend_7d, total_spend_7d,
               current_margin_pct, current_losing_new_pct,
               recent_avg_daily_spend, recent_avg_daily_net_profit,
               current_budget_ceilings, current_total_setting
        FROM \`onyga-482313.OI.V_BUDGET_TOTAL_SUGGESTION\``,

  refreshKey: { every: `10 minutes` },

  measures: { count: { type: `count` } },

  dimensions: {
    id:                     { sql: `id`,                          type: `number`, primaryKey: true },
    marginDailySpend:       { sql: `margin_campaign_daily_spend`, type: `number` },
    losingSpend7d:          { sql: `losing_spend_7d`,             type: `number` },
    marginSpend7d:          { sql: `margin_spend_7d`,             type: `number` },
    winningSpend7d:         { sql: `winning_spend_7d`,            type: `number` },
    totalSpend7d:           { sql: `total_spend_7d`,             type: `number` },
    currentMarginPct:       { sql: `current_margin_pct`,          type: `number` },
    currentLosingNewPct:    { sql: `current_losing_new_pct`,      type: `number` },
    recentAvgDailySpend:    { sql: `recent_avg_daily_spend`,      type: `number` },
    recentAvgDailyNetProfit:{ sql: `recent_avg_daily_net_profit`, type: `number` },
    currentBudgetCeilings:  { sql: `current_budget_ceilings`,     type: `number` },
    currentTotalSetting:    { sql: `current_total_setting`,       type: `number` },
  },
});
