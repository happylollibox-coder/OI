// Cube: ForecastRoas - from V_FORECAST_ROAS
// Event-anchored, OOS-aware, lift-adjusted ROAS forecast by Family × Month
// Auto-refreshes daily via rolling 8-week YoY comparison
cube(`ForecastRoas`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_FORECAST_ROAS\``,

  refreshKey: { every: '6 hour' },

  measures: {
    forecastRoas: {
      sql: `forecast_roas`,
      type: `avg`,
      description: `Forecasted Net ROAS (event-mapped × √YoY lift)`,
    },
    eventMappedRoas: {
      sql: `event_mapped_roas`,
      type: `avg`,
      description: `Raw event-mapped ROAS before lift adjustment`,
    },
    sqrtLift: {
      sql: `sqrt_lift`,
      type: `avg`,
      description: `√(clamped YoY lift) applied to the forecast`,
    },
    forecastUnits: {
      sql: `forecast_units_base`,
      type: `sum`,
      description: `Mapped units from historical event-matched weeks`,
    },
    mappedRevenue: {
      sql: `mapped_rev`,
      type: `sum`,
      description: `Mapped revenue from historical event-matched weeks`,
    },
    mappedAdSpend: {
      sql: `mapped_ad`,
      type: `sum`,
      description: `Mapped ad spend from historical event-matched weeks`,
    },
  },

  dimensions: {
    forecastYear: {
      sql: `forecast_year`,
      type: `number`,
      description: `Year of the forecast month`,
    },
    forecastMonth: {
      sql: `forecast_month`,
      type: `number`,
      description: `Month of the forecast (1-12)`,
    },
    family: {
      sql: `family`,
      type: `string`,
      description: `Product family (Lollibox, Fresh, LolliME, Bottle)`,
    },
    rawYoyLift: {
      sql: `raw_yoy_lift`,
      type: `number`,
      description: `Raw unclamped YoY ROAS lift`,
    },
    clampedYoyLift: {
      sql: `clamped_yoy_lift`,
      type: `number`,
      description: `YoY lift clamped to [0.80, 1.50]`,
    },
  },
});
