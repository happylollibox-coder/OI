// Cube: AdsChannelEfficiency — from V_ADS_CHANNEL_EFFICIENCY
// Per-family × month × search_type (BRAND/NON_BRAND) ads efficiency.
// Provides CPC, CVR, Net ROAS split by brand vs non-brand keywords.
// Used by PlanWizard Step 3 (Ads Path) for channel-split analysis.
cube(`AdsChannelEfficiency`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_ADS_CHANNEL_EFFICIENCY\``,

  refreshKey: { every: '6 hour' },

  measures: {
    totalSpend: {
      sql: `spend`,
      type: `sum`,
      description: `Total ads spend`,
    },
    totalClicks: {
      sql: `clicks`,
      type: `sum`,
      description: `Total clicks`,
    },
    totalUnits: {
      sql: `units`,
      type: `sum`,
      description: `Total ad-attributed units`,
    },
    totalOrders: {
      sql: `orders`,
      type: `sum`,
      description: `Total ad-attributed orders`,
    },
    totalSales: {
      sql: `sales`,
      type: `sum`,
      description: `Total ad-attributed sales revenue`,
    },
  },

  dimensions: {
    family: {
      sql: `family`,
      type: `string`,
      description: `Product family`,
    },
    year: {
      sql: `yr`,
      type: `number`,
      description: `Year`,
    },
    month: {
      sql: `mo`,
      type: `number`,
      description: `Month (1-12)`,
    },
    searchType: {
      sql: `search_type`,
      type: `string`,
      description: `BRAND or NON_BRAND`,
    },
    cpc: {
      sql: `cpc`,
      type: `number`,
      description: `Cost per click`,
    },
    unitCvrPct: {
      sql: `unit_cvr_pct`,
      type: `number`,
      description: `Unit conversion rate (%)`,
    },
    netRoas: {
      sql: `net_roas`,
      type: `number`,
      description: `Net ROAS (gross profit / spend)`,
    },
    grossRoas: {
      sql: `gross_roas`,
      type: `number`,
      description: `Gross ROAS (sales / spend)`,
    },
    currentDailySpend: {
      sql: `current_daily_spend`,
      type: `number`,
      description: `Trailing 30d avg daily spend`,
    },
    currentCpc: {
      sql: `current_cpc`,
      type: `number`,
      description: `Trailing 30d CPC`,
    },
    current30dSpend: {
      sql: `current_30d_spend`,
      type: `number`,
      description: `Total spend in trailing 30 days`,
    },
    current30dUnits: {
      sql: `current_30d_units`,
      type: `number`,
      description: `Total units in trailing 30 days`,
    },
    activeDays: {
      sql: `active_days`,
      type: `number`,
      description: `Days with ad activity in this month`,
    },
  },
});
