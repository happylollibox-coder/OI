// Cube: UnifiedPerformance — single source of truth for dashboard performance
// Backed by: V_UNIFIED_DAILY (BigQuery view, grain: asin × date)
// Replaces: Summary, WeeklyTrends, WeeklyTrendsByAsin, MonthlyTrends, MonthlyTrendsByAsin
//
// Rules compliance:
//   [x] R1: One cube = one entity (Performance)
//   [x] R2: sql_table pointing to BigQuery view
//   [x] R3: 4 rollup pre-aggregations for different groupings
//   [x] R4: netProfit/netRoas/organicPct computed from aggregated components
//   [x] R5: Finest grain (asin × date) in view
//   [x] R7: All rollup measures are additive (sum/count)
//   [x] R8: Indexes on filter dimensions

cube(`UnifiedPerformance`, {
  sql_table: `\`onyga-482313.OI.T_UNIFIED_DAILY\``,

  measures: {
    count: {
      type: `count`,
      description: `Number of daily rows`,
    },
    sales: {
      sql: `sales`,
      type: `sum`,
      format: `currency`,
      description: `Total sales (USD)`,
    },
    adCost: {
      sql: `ad_cost`,
      type: `sum`,
      format: `currency`,
      description: `Total ads spend (USD)`,
    },
    cogs: {
      sql: `cogs`,
      type: `sum`,
      format: `currency`,
      description: `Total COGS (units × cost per unit)`,
    },
    orders: {
      sql: `orders`,
      type: `sum`,
      description: `Total orders`,
    },
    units: {
      sql: `units`,
      type: `sum`,
      description: `Total units sold`,
    },
    clicks: {
      sql: `clicks`,
      type: `sum`,
      description: `Total ad clicks`,
    },
    sessions: {
      sql: `sessions`,
      type: `sum`,
      description: `Total ASIN sessions`,
    },
    organicUnits: {
      sql: `organic_units`,
      type: `sum`,
      description: `Organic (non-ads) units`,
    },
    adOrders: {
      sql: `ad_orders`,
      type: `sum`,
      description: `Orders attributed to ads`,
    },
    impressions: {
      sql: `impressions`,
      type: `sum`,
      description: `Total ad impressions`,
    },
    // --- Computed measures (R4: never pre-aggregate ratios) ---
    netProfit: {
      sql: `${sales} - ${adCost} - ${cogs}`,
      type: `number`,
      description: `Net profit = sales - ad_cost - cogs`,
    },
    netRoas: {
      sql: `CASE WHEN ${adCost} > 0 THEN (${sales} - ${cogs}) / ${adCost} ELSE 0 END`,
      type: `number`,
      description: `Net ROAS = (sales - cogs) / ad_cost`,
    },
    organicPct: {
      sql: `CASE WHEN ${units} > 0 THEN GREATEST(${organicUnits}, 0) * 100.0 / ${units} ELSE 0 END`,
      type: `number`,
      description: `Organic % = organic_units / units × 100`,
    },
    tacos: {
      sql: `CASE WHEN ${sales} > 0 THEN ${adCost} * 100.0 / ${sales} ELSE 0 END`,
      type: `number`,
      description: `TACoS = ad_cost / sales × 100 (Total Ads Cost of Sales)`,
    },
    npPerUnit: {
      sql: `CASE WHEN ${units} > 0 THEN (${sales} - ${adCost} - ${cogs}) / ${units} ELSE 0 END`,
      type: `number`,
      description: `Net Profit per Unit = (sales - ad_cost - cogs) / units`,
    },
  },

  dimensions: {
    id: {
      sql: `CONCAT(asin, '|', CAST(date AS STRING))`,
      type: `string`,
      primaryKey: true,
    },
    family: {
      sql: `family`,
      type: `string`,
      description: `Product family (e.g. Lollibox, LolliME)`,
    },
    asin: {
      sql: `asin`,
      type: `string`,
      description: `Amazon ASIN`,
    },
    productShortName: {
      sql: `product_short_name`,
      type: `string`,
      description: `Short product name for display`,
    },
    date: {
      sql: `CAST(date AS TIMESTAMP)`,
      type: `time`,
      description: `Calendar date`,
    },
    weekStart: {
      sql: `CAST(week_start_date AS TIMESTAMP)`,
      type: `time`,
      description: `Calendar week start (Sunday)`,
    },
    monthStart: {
      sql: `CAST(month_start AS TIMESTAMP)`,
      type: `time`,
      description: `Calendar month start`,
    },
  },

  preAggregations: {
    // Pre-agg 1: Header cards + trend chart (by family per week)
    weeklyByFamily: {
      type: `rollup`,
      measures: [
        UnifiedPerformance.sales,
        UnifiedPerformance.adCost,
        UnifiedPerformance.cogs,
        UnifiedPerformance.orders,
        UnifiedPerformance.units,
        UnifiedPerformance.clicks,
        UnifiedPerformance.sessions,
        UnifiedPerformance.organicUnits,
        UnifiedPerformance.adOrders,
        UnifiedPerformance.impressions,
      ],
      dimensions: [
        UnifiedPerformance.family,
        UnifiedPerformance.weekStart,
      ],
      indexes: {
        familyIdx: { columns: [UnifiedPerformance.family] },
      },
      refreshKey: {
        sql: `SELECT CONCAT('v2~', CAST(MAX(date) AS STRING), '~', CAST(COUNT(*) AS STRING)) FROM \`onyga-482313.OI.T_UNIFIED_DAILY\``,
      },
      scheduledRefresh: true,
    },

    // Pre-agg 2: Family table drill-down (by family + asin per week)
    weeklyByAsin: {
      type: `rollup`,
      measures: [
        UnifiedPerformance.sales,
        UnifiedPerformance.adCost,
        UnifiedPerformance.cogs,
        UnifiedPerformance.orders,
        UnifiedPerformance.units,
        UnifiedPerformance.clicks,
        UnifiedPerformance.sessions,
        UnifiedPerformance.organicUnits,
        UnifiedPerformance.adOrders,
        UnifiedPerformance.impressions,
      ],
      dimensions: [
        UnifiedPerformance.family,
        UnifiedPerformance.asin,
        UnifiedPerformance.productShortName,
        UnifiedPerformance.weekStart,
      ],
      indexes: {
        familyIdx: { columns: [UnifiedPerformance.family] },
      },
      refreshKey: {
        sql: `SELECT CONCAT('v2~', CAST(MAX(date) AS STRING), '~', CAST(COUNT(*) AS STRING)) FROM \`onyga-482313.OI.T_UNIFIED_DAILY\``,
      },
      scheduledRefresh: true,
    },

    // Pre-agg 3: Monthly header (by family per month)
    monthlyByFamily: {
      type: `rollup`,
      measures: [
        UnifiedPerformance.sales,
        UnifiedPerformance.adCost,
        UnifiedPerformance.cogs,
        UnifiedPerformance.orders,
        UnifiedPerformance.units,
        UnifiedPerformance.clicks,
        UnifiedPerformance.sessions,
        UnifiedPerformance.organicUnits,
        UnifiedPerformance.adOrders,
        UnifiedPerformance.impressions,
      ],
      dimensions: [
        UnifiedPerformance.family,
        UnifiedPerformance.monthStart,
      ],
      indexes: {
        familyIdx: { columns: [UnifiedPerformance.family] },
      },
      refreshKey: {
        sql: `SELECT CONCAT('v2~', CAST(MAX(date) AS STRING), '~', CAST(COUNT(*) AS STRING)) FROM \`onyga-482313.OI.T_UNIFIED_DAILY\``,
      },
      scheduledRefresh: true,
    },

    // Pre-agg 4: Monthly family table (by family + asin per month)
    monthlyByAsin: {
      type: `rollup`,
      measures: [
        UnifiedPerformance.sales,
        UnifiedPerformance.adCost,
        UnifiedPerformance.cogs,
        UnifiedPerformance.orders,
        UnifiedPerformance.units,
        UnifiedPerformance.clicks,
        UnifiedPerformance.sessions,
        UnifiedPerformance.organicUnits,
        UnifiedPerformance.adOrders,
        UnifiedPerformance.impressions,
      ],
      dimensions: [
        UnifiedPerformance.family,
        UnifiedPerformance.asin,
        UnifiedPerformance.productShortName,
        UnifiedPerformance.monthStart,
      ],
      indexes: {
        familyIdx: { columns: [UnifiedPerformance.family] },
      },
      refreshKey: {
        sql: `SELECT CONCAT('v2~', CAST(MAX(date) AS STRING), '~', CAST(COUNT(*) AS STRING)) FROM \`onyga-482313.OI.T_UNIFIED_DAILY\``,
      },
      scheduledRefresh: true,
    },
  },
});
