cube(`StorageCost`, {
  sql: `
    SELECT
      week_start_date,
      asin,
      product_type,
      weekly_storage_cost
    FROM \`onyga-482313.OI.V_WEEKLY_STORAGE_COST\`
  `,

  sqlAlias: `stc`,

  measures: {
    totalStorageCost: {
      type: `sum`,
      sql: `weekly_storage_cost`,
      title: `Storage Cost`,
    },
  },

  dimensions: {
    weekStartDate: {
      sql: `CAST(week_start_date AS STRING)`,
      type: `string`,
      title: `Week`,
    },

    asin: {
      sql: `asin`,
      type: `string`,
      title: `ASIN`,
    },

    productType: {
      sql: `product_type`,
      type: `string`,
      title: `Product Family`,
    },
  },
});
