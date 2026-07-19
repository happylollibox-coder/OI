// Cube: CoachFamilyWeekNet - from V_FAMILY_WEEK_ADS_NET (coacher ads net per family x week).
// Home's family table reads this for "Ads Net Profit" so it equals This Week / Weekly Run exactly.
cube(`CoachFamilyWeekNet`, {
  sql: `SELECT CONCAT(parent_name,'|',week_start) AS id, parent_name, week_start, ads_net, ads_spend
        FROM \`onyga-482313.OI.V_FAMILY_WEEK_ADS_NET\``,

  refreshKey: { every: '30 minutes' },

  measures: { count: { type: `count` } },

  dimensions: {
    id: { sql: `id`, type: `string`, primaryKey: true },
    parentName: { sql: `parent_name`, type: `string` },
    weekStart: { sql: `week_start`, type: `string` },
    adsNet: { sql: `ads_net`, type: `number` },
    adsSpend: { sql: `ads_spend`, type: `number` },
  },
});
