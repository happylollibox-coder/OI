// Cube: CoachHotSignals - from V_COACH_HOT_SIGNALS
// 3-day rapid-reaction ads alerts (URGENT_STOP, HOT_WINNER, RAPID_DECLINE)
cube(`CoachHotSignals`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_COACH_HOT_SIGNALS\``,

  refreshKey: { every: '15 minutes' },

  measures: {
    count: {
      type: `count`,
      description: `Number of hot signals`,
    },
    totalSpend3d: {
      sql: `spend_3d`,
      type: `sum`,
      description: `Total 3-day spend`,
    },
    totalOrders3d: {
      sql: `orders_3d`,
      type: `sum`,
      description: `Total 3-day orders`,
    },
    totalClicks3d: {
      sql: `clicks_3d`,
      type: `sum`,
      description: `Total 3-day clicks`,
    },
  },

  dimensions: {
    id: {
      sql: `CONCAT(COALESCE(search_term,''), '|', COALESCE(campaign_id,''), '|', COALESCE(asin,''))`,
      type: `string`,
      primaryKey: true,
      description: `Unique row id`,
    },
    hotSignal: { sql: `hot_signal`, type: `string`, description: `Signal type: URGENT_STOP, HOT_WINNER, RAPID_DECLINE` },
    hotSignalReason: { sql: `hot_signal_reason`, type: `string`, description: `Human-readable signal explanation` },
    searchTerm: { sql: `search_term`, type: `string`, description: `Search term` },
    asin: { sql: `asin`, type: `string`, description: `ASIN` },
    productShortName: { sql: `product_short_name`, type: `string`, description: `Product short name` },
    parentName: { sql: `parent_name`, type: `string`, description: `Parent product family` },
    experimentId: { sql: `experiment_id`, type: `string`, description: `Experiment ID` },
    experimentName: { sql: `experiment_name`, type: `string`, description: `Experiment name` },
    strategyId: { sql: `strategy_id`, type: `string`, description: `Strategy ID` },
    strategyName: { sql: `strategy_name`, type: `string`, description: `Strategy name` },
    campaignId: { sql: `campaign_id`, type: `string`, description: `Campaign ID` },
    campaignName: { sql: `campaign_name`, type: `string`, description: `Campaign name` },
    campaignType: { sql: `campaign_type`, type: `string`, description: `Campaign type (SP/SB)` },
    adGroupId: { sql: `ad_group_id`, type: `string`, description: `Ad group ID` },
    spend3d: { sql: `spend_3d`, type: `number`, description: `3-day ad spend` },
    orders3d: { sql: `orders_3d`, type: `number`, description: `3-day orders` },
    clicks3d: { sql: `clicks_3d`, type: `number`, description: `3-day clicks` },
    impressions3d: { sql: `impressions_3d`, type: `number`, description: `3-day impressions` },
    cpc3d: { sql: `cpc_3d`, type: `number`, description: `3-day CPC` },
    cvr3d: { sql: `cvr_3d`, type: `number`, description: `3-day CVR %` },
    adsRoas3d: { sql: `ads_roas_3d`, type: `number`, description: `3-day ads ROAS` },
    netProfit3d: { sql: `net_profit_3d`, type: `number`, description: `3-day net profit` },
    marginPerUnit: { sql: `margin_per_unit`, type: `number`, description: `Margin per unit` },
    coach8wAction: { sql: `coach_8w_action`, type: `string`, description: `8-week coach action (context)` },
    coach8wRoas: { sql: `coach_8w_roas`, type: `number`, description: `8-week weighted total net ROAS` },
    coach8wSignal: { sql: `coach_8w_signal`, type: `string`, description: `8-week signal` },
    priorityScore: { sql: `priority_score`, type: `number`, description: `Priority urgency score` },
    sqpSearchVolume4w: { sql: `sqp_search_volume_4w`, type: `number`, description: `SQP 4-week search volume` },
    sqpOrganicRank: { sql: `sqp_organic_rank`, type: `number`, description: `SQP organic rank (avg 4w)` },
    daysWithData: { sql: `days_with_data`, type: `number`, description: `Days with data in 3d window` },
  },
});
