cube(`FamilyOccasionMap`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_FAMILY_OCCASION_MAP\``,

  measures: {
    count: { type: `count` },
  },

  dimensions: {
    parentName: { sql: `parent_name`, type: `string`, title: `Family` },
    occasion: { sql: `occasion`, type: `string`, title: `Occasion` },
    liftRatio: { sql: `lift_ratio`, type: `number`, title: `Lift Ratio` },
    peakDailyOrders: { sql: `peak_daily_orders`, type: `number`, title: `Peak Daily Orders` },
    offSeasonDailyOrders: { sql: `off_season_daily_orders`, type: `number`, title: `Off-Season Daily Orders` },
    rankByLift: { sql: `rank_by_lift`, type: `number`, title: `Rank` },
    isPrimary: { sql: `is_primary`, type: `boolean`, title: `Is Primary` },
    isOverride: { sql: `is_override`, type: `boolean`, title: `Is Override` },
  },
});
