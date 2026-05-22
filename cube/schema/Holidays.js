// Cube: Holidays - from DIM_US_HOLIDAYS
// Used for upcoming.json, peak.json
cube(`Holidays`, {
  sql: `SELECT * FROM \`onyga-482313.OI.DIM_US_HOLIDAYS\``,

  refreshKey: { every: '1 hour' },

  measures: {
    count: {
      type: `count`,
      description: `Number of holidays`,
    },
  },

  dimensions: {
    holidayDate: {
      sql: `CAST(holiday_date AS TIMESTAMP)`,
      type: `time`,
      description: `Date of the holiday`,
    },
    holidayName: {
      sql: `holiday_name`,
      type: `string`,
      description: `Holiday name (e.g. Valentine's Day, Prime Day)`,
    },
    category: {
      sql: `category`,
      type: `string`,
      description: `Category (e.g. gift_season, promotional)`,
    },
    rampUpDays: {
      sql: `ramp_up_days`,
      type: `number`,
      description: `Days before holiday to start ramping`,
    },
    preSeasonStart: {
      sql: `CAST(pre_season_start AS TIMESTAMP)`,
      type: `time`,
      description: `Start of pre-season period`,
    },
    boostStart: {
      sql: `CAST(boost_start AS TIMESTAMP)`,
      type: `time`,
      description: `Start of boost phase`,
    },
    peakStart: {
      sql: `CAST(peak_start AS TIMESTAMP)`,
      type: `time`,
      description: `Start of peak phase`,
    },
  },
});
