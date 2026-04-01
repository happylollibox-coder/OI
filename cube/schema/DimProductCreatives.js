cube(`DimProductCreatives`, {
  sql: `SELECT * FROM \`onyga-482313\`.OI.DIM_PRODUCT_CREATIVES`,

  preAggregations: {
    // No pre-aggregations needed for a tiny dimension table
  },

  refreshKey: {
    every: `5 minutes`,
    sql: `SELECT MAX(updated_at) FROM \`onyga-482313\`.OI.DIM_PRODUCT_CREATIVES`
  },

  joins: {
    Product: {
      relationship: `hasMany`,
      sql: `${CUBE}.product_family = ${Product}.product_type`
    }
  },

  dimensions: {
    productFamily: {
      sql: `product_family`,
      type: `string`,
      primaryKey: true,
      description: `Product family (e.g., BOX, ME, FRESH, BOTTLE)`
    },

    brandEntityId: {
      sql: `brand_entity_id`,
      type: `string`,
      description: `Amazon Brand Entity ID`
    },

    brandName: {
      sql: `brand_name`,
      type: `string`,
      description: `Brand Name used in ads`
    },

    videoAssetId: {
      sql: `video_asset_id`,
      type: `string`,
      description: `Amazon Video Media Asset ID`
    },

    updatedAt: {
      sql: `updated_at`,
      type: `time`,
      description: `Timestamp of last update`
    }
  }
});
