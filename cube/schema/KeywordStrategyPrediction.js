// Cube: KeywordStrategyPrediction - from V_KEYWORD_STRATEGY_PREDICTIONS
// Provides 6-factor strategic prediction per (search_term, asin)
cube(`KeywordStrategyPrediction`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_KEYWORD_STRATEGY_PREDICTIONS\``,

  refreshKey: { every: '6 hours' },

  measures: {
    count: {
      type: `count`,
      description: `Number of keyword predictions`,
    },
  },

  dimensions: {
    id: {
      sql: `CONCAT(COALESCE(search_term,''), '|', COALESCE(asin,''))`,
      type: `string`,
      primaryKey: true,
      description: `Unique row id`,
    },
    searchTerm: { sql: `search_term`, type: `string`, description: `Keyword` },
    asin: { sql: `asin`, type: `string`, description: `ASIN` },
    productShortName: { sql: `product_short_name`, type: `string`, description: `Product` },
    parentName: { sql: `parent_name`, type: `string`, description: `Parent family` },

    // Factor outputs
    baseCvr: { sql: `base_cvr`, type: `number`, description: `Lifetime CVR` },
    baseCpc: { sql: `base_cpc`, type: `number`, description: `Lifetime CPC` },
    lifetimeNetRoas: { sql: `lifetime_net_roas`, type: `number`, description: `Lifetime Net ROAS` },
    seasonalityMultiplier: { sql: `seasonality_multiplier`, type: `number`, description: `Seasonality factor` },
    hasSeasonalData: { sql: `CAST(has_seasonal_data AS STRING)`, type: `string`, description: `Whether seasonal data exists` },
    bestSeasonMonth: { sql: `CAST(best_season_month AS STRING)`, type: `string`, description: `Month number (1-12) with highest CVR` },
    bestSeasonMonthCvr: { sql: `best_season_month_cvr`, type: `number`, description: `CVR in the peak season month` },
    heroProductName: { sql: `hero_product_name`, type: `string`, description: `Product with highest CVR for this keyword` },
    peakMultiplier: { sql: `peak_multiplier`, type: `number`, description: `Peak event factor` },
    peakDescription: { sql: `peak_description`, type: `string`, description: `Upcoming peak event name` },
    predictedCpc: { sql: `predicted_cpc`, type: `number`, description: `Predicted CPC (recent 60d)` },
    cpcInflationRatio: { sql: `cpc_inflation_ratio`, type: `number`, description: `CPC inflation ratio (recent vs older)` },
    tosCvrBoost: { sql: `tos_cvr_boost`, type: `number`, description: `TOS CVR boost factor` },
    tosClickShare: { sql: `tos_click_share`, type: `number`, description: `Share of clicks from TOS` },
    organicHaloMultiplier: { sql: `organic_halo_multiplier`, type: `number`, description: `Organic halo multiplier` },
    organicWeeklyVelocity: { sql: `organic_weekly_velocity`, type: `number`, description: `Organic weekly purchase velocity` },

    // Predicted outputs
    predictedCvr: { sql: `predicted_cvr`, type: `number`, description: `Predicted CVR (adjusted)` },
    predictedNetRoas: { sql: `predicted_net_roas`, type: `number`, description: `Predicted Net ROAS` },
    strategicSignal: { sql: `strategic_signal`, type: `string`, description: `Strategic classification` },
    predictionConfidence: { sql: `prediction_confidence`, type: `number`, description: `Prediction confidence (0-100)` },

    // Context
    totalClicks: { sql: `total_clicks`, type: `number`, description: `Lifetime clicks` },
    totalOrders: { sql: `total_orders`, type: `number`, description: `Lifetime orders` },
    totalSpend: { sql: `total_spend`, type: `number`, description: `Lifetime spend` },
    daysWithData: { sql: `days_with_data`, type: `number`, description: `Number of days with data` },
    marginPerUnit: { sql: `margin_per_unit`, type: `number`, description: `Margin per unit` },
  },
});
