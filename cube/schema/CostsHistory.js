// Cube: CostsHistory - from DIM_COSTS_HISTORY (SCD Type 2)
// Used for products (cogs, shipping, fba), summary, trends. Joins to FactlessBridge with temporal validity:
// bridge date must be between start_date and end_date (end_date NULL = current).
cube(`CostsHistory`, {
  sql: `SELECT asin, marketplace_id, sku, cost_of_goods, shipping_cost, FBA_COST_estimated_fee_total, TOTAL_COST_PER_UNIT, estimated_pick_pack_fee_per_unit, FBA_COST_estimated_referral_fee_per_unit, start_date, end_date FROM \`onyga-482313.OI.DIM_COSTS_HISTORY\``,

  refreshKey: { every: '1 hour' },

  joins: {
    FactlessBridge: {
      relationship: `hasMany`,
      sql: `${CUBE}.asin = ${FactlessBridge}.asin
        AND PARSE_DATE('%Y%m%d', CAST(${FactlessBridge}.date_key AS STRING)) >= ${CUBE}.start_date
        AND (${CUBE}.end_date IS NULL OR PARSE_DATE('%Y%m%d', CAST(${FactlessBridge}.date_key AS STRING)) <= ${CUBE}.end_date)`,
    },
  },

  measures: {
    count: {
      type: `count`,
      description: `Number of cost records`,
    },
  },

  dimensions: {
    asin: {
      sql: `asin`,
      type: `string`,
      description: `Product ASIN`,
    },
    startDate: {
      sql: `CAST(start_date AS TIMESTAMP)`,
      type: `time`,
      description: `Cost validity start`,
    },
    costRecordKey: {
      sql: `CONCAT(asin, '-', CAST(start_date AS STRING))`,
      type: `string`,
      primaryKey: true,
      description: `Unique key per cost record (asin + start_date)`,
    },
    costOfGoods: {
      sql: `cost_of_goods`,
      type: `number`,
      description: `Cost of goods`,
    },
    shippingCost: {
      sql: `shipping_cost`,
      type: `number`,
      description: `Shipping cost per unit`,
    },
    fbaCost: {
      sql: `FBA_COST_estimated_fee_total`,
      type: `number`,
      description: `FBA fee per unit`,
    },
    totalCostPerUnit: {
      sql: `TOTAL_COST_PER_UNIT`,
      type: `number`,
      description: `Total cost per unit (COGS + shipping + FBA)`,
    },
    pickPackFee: {
      sql: `estimated_pick_pack_fee_per_unit`,
      type: `number`,
      description: `FBA pick & pack fee per unit`,
    },
    referralFee: {
      sql: `FBA_COST_estimated_referral_fee_per_unit`,
      type: `number`,
      description: `FBA referral fee per unit`,
    },
    endDate: {
      sql: `CAST(end_date AS TIMESTAMP)`,
      type: `time`,
      description: `Cost validity end (NULL = current)`,
    },
  },
});
