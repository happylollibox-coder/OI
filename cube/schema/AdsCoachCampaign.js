// Cube: AdsCoachCampaign - from V_ADS_COACH_CAMPAIGN
// Per campaign: aggregated term decisions → campaign-level action
cube(`AdsCoachCampaign`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_ADS_COACH_CAMPAIGN\``,

  refreshKey: { every: '30 minutes' },

  measures: {
    count: { type: `count`, description: `Number of campaigns` },
  },

  dimensions: {
    campaignId: { sql: `campaign_id`, type: `string`, primaryKey: true },
    campaignName: { sql: `campaign_name`, type: `string` },
    campaignType: { sql: `campaign_type`, type: `string` },
    experimentId: { sql: `experiment_id`, type: `string` },
    experimentName: { sql: `experiment_name`, type: `string` },
    strategyId: { sql: `strategy_id`, type: `string` },
    strategyName: { sql: `strategy_name`, type: `string` },
    experimentStatus: { sql: `experiment_status`, type: `string` },

    // Totals
    totalTerms: { sql: `total_terms`, type: `number` },
    totalSpend4w: { sql: `total_spend_4w`, type: `number` },
    totalOrders4w: { sql: `total_orders_4w`, type: `number` },
    totalSales4w: { sql: `total_sales_4w`, type: `number` },
    totalNetProfit4w: { sql: `total_net_profit_4w`, type: `number` },
    campaignNetRoas4w: { sql: `campaign_net_roas_4w`, type: `number` },
    campaignAvgCpc4w: { sql: `campaign_avg_cpc_4w`, type: `number` },
    campaignCvrPct4w: { sql: `campaign_cvr_pct_4w`, type: `number` },

    // LY Peak
    totalSpendLyPeak: { sql: `total_spend_ly_peak`, type: `number` },
    totalOrdersLyPeak: { sql: `total_orders_ly_peak`, type: `number` },

    // SQP
    totalSqpOrders4w: { sql: `total_sqp_orders_4w`, type: `number` },
    totalSqpOrganicUnits4w: { sql: `total_sqp_organic_units_4w`, type: `number` },

    // Decision counts
    termsNegate: { sql: `terms_negate`, type: `number` },
    termsReduce: { sql: `terms_reduce`, type: `number` },
    termsKeep: { sql: `terms_keep`, type: `number` },
    termsScale: { sql: `terms_scale`, type: `number` },
    termsMonitor: { sql: `terms_monitor`, type: `number` },

    // Spend by decision
    spendOnNegateTerms: { sql: `spend_on_negate_terms`, type: `number` },
    spendOnReduceTerms: { sql: `spend_on_reduce_terms`, type: `number` },

    // Action
    campaignAction: { sql: `campaign_action`, type: `string` },
    estWeeklySavings: { sql: `est_weekly_savings`, type: `number` },
    topNegateTerms: { sql: `top_negate_terms`, type: `string` },
    topScaleTerms: { sql: `top_scale_terms`, type: `string` },
    totalPriorityScore: { sql: `total_priority_score`, type: `number` },
    actionSummary: { sql: `action_summary`, type: `string` },

    // Hero mismatch
    termsHeroMismatch: { sql: `terms_hero_mismatch`, type: `number`, description: `Count of SWITCH_HERO terms` },
    spendOnWrongHero: { sql: `spend_on_wrong_hero`, type: `number`, description: `Total spend on wrong hero ASIN` },

    // Placement
    placementAction: { sql: `placement_action`, type: `string`, description: `BOOST_TOS / REDUCE_TOS / MAINTAIN` },
  },
});
