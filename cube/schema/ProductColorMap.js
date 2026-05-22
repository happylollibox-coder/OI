// Cube: ProductColorMap — Lookup for product and family colors
// Source: V_PRODUCT_FAMILY_MAP (joined with DE_COLOR_MAP)
// Used by: PlanPage to dynamically render family/product dot colors
// Zero-code onboarding: new products inherit colors from DE_COLOR_MAP automatically
cube(`ProductColorMap`, {
  sql_table: `\`onyga-482313.OI.V_PRODUCT_FAMILY_MAP\``,

  refreshKey: { every: '1 day' },

  dimensions: {
    id: {
      sql: `asin`,
      type: `string`,
      primaryKey: true,
    },
    family: {
      sql: `family`,
      type: `string`,
    },
    productShortName: {
      sql: `product_short_name`,
      type: `string`,
    },
    familyColorHex: {
      sql: `family_color_hex`,
      type: `string`,
      description: `Hex color for the product family from DE_COLOR_MAP`,
    },
    productColorHex: {
      sql: `product_color_hex`,
      type: `string`,
      description: `Hex color for the individual product from DE_COLOR_MAP`,
    },
  },
});
