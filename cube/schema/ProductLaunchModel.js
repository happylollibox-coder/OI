// Cube: ProductLaunchModel — from V_PRODUCT_LAUNCH_MODEL
// Available launch models for new product forecasting.
// Used by PlanPage to show model selection dropdown.
cube(`ProductLaunchModel`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_PRODUCT_LAUNCH_MODEL\``,

  refreshKey: { every: '1 day' },

  measures: {
    totalYear1Units: {
      sql: `year1_units`,
      type: `max`,
      description: `Total first-year units for this product`,
    },
  },

  dimensions: {
    product: {
      sql: `product`,
      type: `string`,
      description: `Product short name (the model product)`,
    },
    family: {
      sql: `family`,
      type: `string`,
      description: `Product family`,
    },
    monthNum: {
      sql: `month_num`,
      type: `number`,
      description: `Month number since launch (1-12)`,
    },
    totalUnits: {
      sql: `total_units`,
      type: `number`,
      description: `Units sold in this month`,
    },
    dailyRate: {
      sql: `daily_rate`,
      type: `number`,
      description: `Daily rate for this month`,
    },
    rampIndex: {
      sql: `ramp_index`,
      type: `number`,
      description: `Ramp index relative to month 2`,
    },
    year1Units: {
      sql: `year1_units`,
      type: `number`,
      description: `Total first-year units`,
    },
  },
});
