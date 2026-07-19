// Cube: LaunchCardDaily — per (launch campaign, target, day) measures for the Weekly Run "New campaigns"
// card template. One row per target per each of the last 3 complete days. Reads V_LAUNCH_CARD_DAILY.
cube(`LaunchCardDaily`, {
  sql: `SELECT campaign_id, target_text, targeting_type, date, day_rank, spend, clicks, ctr, units, net_roas
        FROM \`onyga-482313.OI.V_LAUNCH_CARD_DAILY\``,

  refreshKey: { every: `10 minutes` },

  measures: { count: { type: `count` } },

  dimensions: {
    rowId:        { sql: `CONCAT(campaign_id, '|', target_text, '|', CAST(day_rank AS STRING))`, type: `string`, primaryKey: true },
    campaignId:   { sql: `campaign_id`,    type: `string` },
    targetText:   { sql: `target_text`,    type: `string` },
    targetingType:{ sql: `targeting_type`, type: `string` },
    dayRank:      { sql: `day_rank`,        type: `number` },
    theDate:      { sql: `date`,            type: `string` },
    spend:        { sql: `spend`,           type: `number` },
    clicks:       { sql: `clicks`,          type: `number` },
    ctr:          { sql: `ctr`,             type: `number` },
    units:        { sql: `units`,           type: `number` },
    netRoas:      { sql: `net_roas`,        type: `number` },
  },
});
