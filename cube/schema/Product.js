// Cube: Product - from DIM_PRODUCT
cube(`Product`, {
  sql: `SELECT * FROM \`onyga-482313.OI.DIM_PRODUCT\` WHERE asin IS NOT NULL AND asin != 'UNKNOWN' AND is_active = TRUE AND oi_is_active = TRUE`,

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
    packageQuantity: {
      sql: `package_quantity`,
      type: `number`,
      description: `Number of units per master carton`,
    },
    manufactureDay: {
      sql: `manufacture_day`,
      type: `number`,
      description: `Manufacturing lead time in days`,
    },
    shipmentDays: {
      sql: `shipment_days`,
      type: `number`,
      description: `Shipping transit time in days`,
    },
    packageCubicFeet: {
      sql: `ROUND(package_length_value * package_width_value * package_height_value / 1728.0, 4)`,
      type: `number`,
      description: `Cubic feet per unit (L×W×H inches / 1728)`,
    },
  },
});
