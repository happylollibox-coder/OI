// Cube: ForecastDemand - from V_FORECAST_DEMAND
// Family-level daily-ramp demand forecast with per-product share split
// Includes cannibalization for new variants and peak/offseason indicators
cube(`ForecastDemand`, {
  sql: `
    SELECT f.*, fm.family_color_hex AS color_hex
    FROM \`onyga-482313.OI.V_FORECAST_DEMAND\` f
    LEFT JOIN (SELECT DISTINCT family, family_color_hex FROM \`onyga-482313.OI.V_PRODUCT_FAMILY_MAP\`) fm
      ON f.family = fm.family
  `,
  refreshKey: { every: '6 hour' },

  measures: {
    forecastUnits: {
      sql: `forecast_units`,
      type: `sum`,
      description: `Product-level forecasted demand units (family forecast × product share)`,
    },
    familyForecastUnits: {
      sql: `family_forecast_units`,
      type: `max`,
      description: `Family-level total forecasted demand units`,
    },
    sqrtLift: {
      sql: `sqrt_lift`,
      type: `avg`,
      description: `√(clamped YoY units lift) per family`,
    },
    peakDays: {
      sql: `peak_days`,
      type: `max`,
      description: `Number of peak (holiday) days in this forecast month`,
    },
    offseasonDays: {
      sql: `offseason_days`,
      type: `max`,
      description: `Number of offseason days in this forecast month`,
    },
  },

  dimensions: {
    product: {
      sql: `product`,
      type: `string`,
      description: `Product short name (e.g., White Lollibox, Fresh in Pink)`,
      primaryKey: true,
      shown: true,
    },
    family: {
      sql: `family`,
      type: `string`,
      description: `Product family (Lollibox, Fresh, LolliME, Bottle)`,
    },
    colorHex: {
      sql: `color_hex`,
      type: `string`,
    },
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
    productShare: {
      sql: `product_share`,
      type: `number`,
      description: `Product share within family (0-1). Adjusted for cannibalization if new variants exist.`,
    },
    isNewProduct: {
      sql: `CAST(is_new_product AS STRING)`,
      type: `string`,
      description: `Whether this is a new product with no sales history`,
    },
    isDraft: {
      sql: `CAST(is_draft AS STRING)`,
      type: `string`,
      description: `Whether this product has <60 days history (draft badge)`,
    },
    peakHolidays: {
      sql: `peak_holidays`,
      type: `string`,
      description: `Comma-separated holiday names active in this forecast month`,
    },
    forecastPhase: {
      sql: `forecast_phase`,
      type: `string`,
      description: `Forecast phase: PHASE_1 (model-based cold start), PHASE_2 (hybrid), PHASE_3 (mature)`,
    },
    modelProduct: {
      sql: `model_product`,
      type: `string`,
      description: `The existing product whose launch model is used for this forecast`,
    },
  },
});
