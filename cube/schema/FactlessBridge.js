// Cube: FactlessBridge - from FACT_FACTLESS_BRIDGE
// Central hub connecting (date_key, asin) across facts. CostsHistory joins here with temporal validity.
cube(`FactlessBridge`, {
  sql: `SELECT date_key, asin, factless_key FROM \`onyga-482313.OI.FACT_FACTLESS_BRIDGE\` WHERE date_key != -1 AND asin != 'UNKNOWN'`,

  refreshKey: { every: '1 hour' },

  dimensions: {
    dateKey: {
      sql: `date_key`,
      type: `number`,
      description: `Date as YYYYMMDD (INT64)`,
    },
    asin: {
      sql: `asin`,
      type: `string`,
      description: `Product ASIN`,
    },
    factlessKey: {
      sql: `factless_key`,
      type: `string`,
      primaryKey: true,
      description: `Composite key: date_key-asin`,
    },
  },
});
