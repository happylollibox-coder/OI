// Cube: PausedHistory — historic performance of PAUSED campaigns from V_PAUSED_CAMPAIGN_HISTORY
// (live view). Weekly Run v12 sections: "Seasonal Paused" (LY-season window only) and "Other"
// (last month / 3 months / year). Keyword grain + campaign rollup rows (targetText null).
cube(`PausedHistory`, {
  sql: `SELECT campaign_id, campaign_name, channel, budget, is_defense, is_seasonal,
               season_holiday, CAST(season_start AS STRING) season_start, CAST(season_end AS STRING) season_end,
               target_text, clicks_m1, spend_m1, roas_m1, clicks_m3, spend_m3, roas_m3,
               clicks_y1, spend_y1, orders_y1, roas_y1,
               clicks_season, spend_season, orders_season, roas_season
        FROM \`onyga-482313.OI.V_PAUSED_CAMPAIGN_HISTORY\``,

  refreshKey: { every: '15 minutes' },
  measures: { count: { type: `count` } },

  dimensions: {
    rowId:        { sql: `CONCAT(campaign_id, '|', COALESCE(target_text, ''))`, type: `string`, primaryKey: true },
    campaignId:   { sql: `campaign_id`,    type: `string` },
    campaignName: { sql: `campaign_name`,  type: `string` },
    channel:      { sql: `channel`,        type: `string` },
    budget:       { sql: `budget`,         type: `number` },
    isDefense:    { sql: `is_defense`,     type: `boolean` },
    isSeasonal:   { sql: `is_seasonal`,    type: `boolean` },
    seasonHoliday:{ sql: `season_holiday`, type: `string` },
    seasonStart:  { sql: `season_start`,   type: `string` },
    seasonEnd:    { sql: `season_end`,     type: `string` },
    targetText:   { sql: `target_text`,    type: `string` },
    clicksM1:     { sql: `clicks_m1`,      type: `number` },
    spendM1:      { sql: `spend_m1`,       type: `number` },
    roasM1:       { sql: `roas_m1`,        type: `number` },
    clicksM3:     { sql: `clicks_m3`,      type: `number` },
    spendM3:      { sql: `spend_m3`,       type: `number` },
    roasM3:       { sql: `roas_m3`,        type: `number` },
    clicksY1:     { sql: `clicks_y1`,      type: `number` },
    spendY1:      { sql: `spend_y1`,       type: `number` },
    ordersY1:     { sql: `orders_y1`,      type: `number` },
    roasY1:       { sql: `roas_y1`,        type: `number` },
    clicksSeason: { sql: `clicks_season`,  type: `number` },
    spendSeason:  { sql: `spend_season`,   type: `number` },
    ordersSeason: { sql: `orders_season`,  type: `number` },
    roasSeason:   { sql: `roas_season`,    type: `number` },
  },
});
