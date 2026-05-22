// Cube: Summary — pre-computed 7-day performance summary per product family
// Backed by: V_SUMMARY_7D (BigQuery view, grain: family)
// Used by: HOME page header cards, Per Product Family table, global nav bar
//
// Rules compliance:
//   [x] R1: One cube = one entity (Summary)
//   [x] R2: sql_table pointing to BigQuery view
//   [x] R4: Ratios (net_roas, organic_pct) pre-computed in BQ view — exposed as dimensions
//   [x] R5: View does all aggregation — cube just exposes pre-computed values
//   [x] R9: All fields are dimensions (pre-aggregated data)

cube(`Summary`, {
  sql_table: `\`onyga-482313.OI.T_SUMMARY_7D\``,

  dimensions: {
    id: {
      sql: `product_type`,
      type: `string`,
      primaryKey: true,
    },
    productType: {
      sql: `product_type`,
      type: `string`,
      description: `Product family (Lollibox, LolliME, Fresh, Bottle)`,
    },
    colorHex: {
      sql: `color_hex`,
      type: `string`,
      description: `Hex color code mapped from DE_COLOR_MAP`,
    },

    // --- Current 7d ---
    sales7d: {
      sql: `sales_7d`,
      type: `number`,
      description: `Total sales (current 7d)`,
    },
    adCost7d: {
      sql: `ad_cost_7d`,
      type: `number`,
      description: `Total ads spend (current 7d)`,
    },
    cogs7d: {
      sql: `cogs_7d`,
      type: `number`,
      description: `Total COGS (current 7d)`,
    },
    netProfit7d: {
      sql: `net_profit_7d`,
      type: `number`,
      description: `Net profit = sales - ad_cost - cogs (current 7d)`,
    },
    orders7d: {
      sql: `orders_7d`,
      type: `number`,
      description: `Total orders (current 7d)`,
    },
    organicUnits7d: {
      sql: `organic_units_7d`,
      type: `number`,
      description: `Organic units (current 7d)`,
    },
    adOrders7d: {
      sql: `ad_orders_7d`,
      type: `number`,
      description: `Ad orders (current 7d)`,
    },
    clicks7d: {
      sql: `clicks_7d`,
      type: `number`,
      description: `Ad clicks (current 7d)`,
    },
    sessions7d: {
      sql: `sessions_7d`,
      type: `number`,
      description: `ASIN sessions (current 7d)`,
    },
    units7d: {
      sql: `units_7d`,
      type: `number`,
      description: `Total units (current 7d)`,
    },
    netRoas: {
      sql: `net_roas`,
      type: `number`,
      description: `Net ROAS = (sales - cogs) / ad_cost (current 7d)`,
    },
    organicPct: {
      sql: `organic_pct`,
      type: `number`,
      description: `Organic % = organic_units / units × 100 (current 7d)`,
    },

    // --- Previous 7d ---
    salesPrev7d: {
      sql: `sales_prev_7d`,
      type: `number`,
      description: `Total sales (previous 7d)`,
    },
    adCostPrev7d: {
      sql: `ad_cost_prev_7d`,
      type: `number`,
      description: `Total ads spend (previous 7d)`,
    },
    cogsPrev7d: {
      sql: `cogs_prev_7d`,
      type: `number`,
      description: `Total COGS (previous 7d)`,
    },
    netProfitPrev7d: {
      sql: `net_profit_prev_7d`,
      type: `number`,
      description: `Net profit (previous 7d)`,
    },
    ordersPrev7d: {
      sql: `orders_prev_7d`,
      type: `number`,
      description: `Total orders (previous 7d)`,
    },
    organicUnitsPrev7d: {
      sql: `organic_units_prev_7d`,
      type: `number`,
      description: `Organic units (previous 7d)`,
    },
    netRoasPrev: {
      sql: `net_roas_prev`,
      type: `number`,
      description: `Net ROAS (previous 7d)`,
    },
    organicPctPrev: {
      sql: `organic_pct_prev`,
      type: `number`,
      description: `Organic % (previous 7d)`,
    },

    // --- Changes ---
    salesChangePct: {
      sql: `sales_change_pct`,
      type: `number`,
      description: `Sales % change vs previous 7d`,
    },
    costChangePct: {
      sql: `cost_change_pct`,
      type: `number`,
      description: `Ad cost % change vs previous 7d`,
    },

    // --- Period ---
    periodStart: {
      sql: `period_start`,
      type: `string`,
      description: `Start date of current 7d period`,
    },
    periodEnd: {
      sql: `period_end`,
      type: `string`,
      description: `End date of current 7d period`,
    },
  },

  refreshKey: {
    sql: `SELECT MAX(date) FROM \`onyga-482313.OI.T_UNIFIED_DAILY\``,
  },
});
