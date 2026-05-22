// Cube: BrandSearchMonthly - from V_BRAND_SEARCH_MONTHLY
// Grain: (year × month × family) — per-family branded search metrics
// Used by: PlanWizard Growth step (organic demand signal per family)
//
// Rules compliance:
//   [x] R1: One cube = one entity (Brand Search Growth)
//   [x] R2: sql_table pointing to BigQuery view
//   [x] R7: All measures are additive (sum)
cube(`BrandSearchMonthly`, {
  sql_table: `\`onyga-482313.OI.V_BRAND_SEARCH_MONTHLY\``,

  dimensions: {
    id: {
      sql: `CONCAT(CAST(yr AS STRING), '-', CAST(mo AS STRING), '-', family)`,
      type: `string`,
      primaryKey: true,
    },
    year: {
      sql: `yr`,
      type: `number`,
    },
    month: {
      sql: `mo`,
      type: `number`,
    },
    family: {
      sql: `family`,
      type: `string`,
    },
  },

  measures: {
    // ── Branded channel ──
    brandedPurchases: {
      sql: `branded_purchases`,
      type: `sum`,
      description: `SQP conversions from branded searches`,
    },
    brandedImpressions: {
      sql: `branded_impressions`,
      type: `sum`,
    },
    brandedClicks: {
      sql: `branded_clicks`,
      type: `sum`,
    },
    adsUnits: {
      sql: `ads_units`,
      type: `sum`,
      description: `Ad units on branded search terms (brand defense)`,
    },
    adsOrders: {
      sql: `ads_orders`,
      type: `sum`,
    },
    adsSpend: {
      sql: `ads_spend`,
      type: `sum`,
      description: `Ad spend on branded search terms`,
    },
    adsSales: {
      sql: `ads_sales`,
      type: `sum`,
    },
    // ── Total channel (all queries, no brand filter) ──
    totalSqpPurchases: {
      sql: `total_sqp_purchases`,
      type: `sum`,
      description: `SQP conversions from ALL searches`,
    },
    totalAdsUnits: {
      sql: `total_ads_units`,
      type: `sum`,
      description: `Ad units from ALL search terms`,
    },
    totalAdsSpend: {
      sql: `total_ads_spend`,
      type: `sum`,
      description: `Ad spend on ALL search terms`,
    },
    totalAdsSales: {
      sql: `total_ads_sales`,
      type: `sum`,
    },
  },
});
