// Cube: Product - from DIM_PRODUCT
cube(`Product`, {
  sql: `SELECT * FROM \`onyga-482313.OI.DIM_PRODUCT\` WHERE asin IS NOT NULL AND asin != 'UNKNOWN'`,

  refreshKey: { every: '1 hour' },

  measures: {
    count: {
      type: `count`,
      description: `Number of products`,
    },
  },

  dimensions: {
    asin: {
      sql: `asin`,
      type: `string`,
      primaryKey: true,
      description: `Amazon Standard Identification Number`,
    },
    productShortName: {
      sql: `product_short_name`,
      type: `string`,
      description: `Short product name for display`,
    },
    productType: {
      sql: `product_type`,
      type: `string`,
      description: `Product family/type (e.g. Lollibox, LolliME)`,
    },
    parentName: {
      sql: `parent_name`,
      type: `string`,
      description: `Parent product / collection name`,
    },
  },
});
