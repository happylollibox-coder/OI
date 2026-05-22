// Cube: AdsEfficiencyProfile — from V_ADS_EFFICIENCY_PROFILE
// Per-family × forecast-month ads efficiency parameters.
// 3-parameter forecast model: Forecast = Spend / CPC × Unit_CVR / Ads_Share
// Consumed by PlanPage for ads spend targets and efficiency drill-down.
cube(`AdsEfficiencyProfile`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_ADS_EFFICIENCY_PROFILE\``,

  refreshKey: { every: '6 hour' },

  measures: {
    totalSuggestedSpend: {
      sql: `suggested_spend`,
      type: `sum`,
      description: `Total suggested ads spend across months`,
    },
    totalForecastUnits: {
      sql: `forecast_units`,
      type: `sum`,
      description: `Total unit forecast from 3-parameter model`,
    },
    avgNetRoas: {
      sql: `avg_net_roas`,
      type: `avg`,
      description: `Average net ROAS (gross profit / spend)`,
    },
  },

  dimensions: {
    family: {
      sql: `family`,
      type: `string`,
      description: `Product family (Lollibox, Fresh, LolliME, Bottle)`,
    },
    forecastYear: {
      sql: `forecast_year`,
      type: `number`,
      description: `Year of the forecast month`,
    },
    forecastMonth: {
      sql: `forecast_month`,
      type: `number`,
      description: `Month of the forecast (1-12)`,
    },

    // Tier composition
    offDays: {
      sql: `off_days`,
      type: `number`,
      description: `Off-season days in month`,
    },
    boostDays: {
      sql: `boost_days`,
      type: `number`,
      description: `Boost (pre-peak) days in month`,
    },
    peakDays: {
      sql: `peak_days`,
      type: `number`,
      description: `Peak holiday days in month`,
    },
    totalDays: {
      sql: `total_days`,
      type: `number`,
      description: `Total days in month`,
    },
    holidaysInMonth: {
      sql: `holidays_in_month`,
      type: `string`,
      description: `Comma-separated holiday names active in this month`,
    },

    // 3-parameter model
    cpc: {
      sql: `cpc`,
      type: `number`,
      description: `Blended CPC for the month (spend-weighted by tier)`,
    },
    unitCvrPct: {
      sql: `unit_cvr_pct`,
      type: `number`,
      description: `Unit CVR %: ads_units / clicks × 100`,
    },
    adsSharePct: {
      sql: `ads_share_pct`,
      type: `number`,
      description: `Ads share %: ads_units / total_units × 100`,
    },

    // Forecast outputs — TARGET path (historical avg daily spend)
    suggestedSpend: {
      sql: `suggested_spend`,
      type: `number`,
      description: `Monthly target ads spend based on historical daily spend × days`,
    },
    forecastUnits: {
      sql: `forecast_units`,
      type: `number`,
      description: `Target forecast units via Spend/CPC × Unit_CVR / Ads_Share`,
    },

    // Forecast outputs — CURRENT path (trailing 30d actual daily spend)
    currentDailySpend: {
      sql: `current_daily_spend`,
      type: `number`,
      description: `Trailing 30-day avg daily spend (current run rate)`,
    },
    currentSpend: {
      sql: `current_spend`,
      type: `number`,
      description: `Current monthly spend projection (30d avg × days in month)`,
    },
    currentForecastUnits: {
      sql: `current_forecast_units`,
      type: `number`,
      description: `Current path forecast units using trailing spend + seasonal efficiency`,
    },
    currentCpc: {
      sql: `current_cpc`,
      type: `number`,
      description: `Trailing 30-day actual CPC (spend / clicks)`,
    },
    currentNetProfit: {
      sql: `current_net_profit`,
      type: `number`,
      description: `Current path net profit = current_spend × (net_roas - 1)`,
    },
    targetNetProfit: {
      sql: `target_net_profit`,
      type: `number`,
      description: `Target path net profit = suggested_spend × (net_roas - 1)`,
    },

    // Profitability
    netRoas: {
      sql: `avg_net_roas`,
      type: `number`,
      description: `Net ROAS (gross profit / spend)`,
    },
    isProfitable: {
      sql: `is_profitable`,
      type: `boolean`,
      description: `TRUE if net ROAS > 1.0`,
    },
    costPerOrder: {
      sql: `cost_per_incremental_order`,
      type: `number`,
      description: `Cost per incremental order`,
    },
    maxMonthlySpend: {
      sql: `max_monthly_spend`,
      type: `number`,
      description: `Upper bound for monthly spend (suggested × 1.2-1.5)`,
    },

    // Per-tier diagnostics: offseason
    offCpc: {
      sql: `off_cpc`,
      type: `number`,
      description: `Offseason CPC`,
    },
    offUnitCvrPct: {
      sql: `off_unit_cvr_pct`,
      type: `number`,
      description: `Offseason unit CVR %`,
    },
    offNetRoas: {
      sql: `off_net_roas`,
      type: `number`,
      description: `Offseason net ROAS`,
    },
    offDailySpend: {
      sql: `off_daily_spend`,
      type: `number`,
      description: `Offseason avg daily spend`,
    },

    // Per-tier diagnostics: boost
    boostCpc: {
      sql: `boost_cpc`,
      type: `number`,
      description: `Boost tier CPC`,
    },
    boostUnitCvrPct: {
      sql: `boost_unit_cvr_pct`,
      type: `number`,
      description: `Boost tier unit CVR %`,
    },
    boostNetRoas: {
      sql: `boost_net_roas`,
      type: `number`,
      description: `Boost tier net ROAS`,
    },
    boostDailySpend: {
      sql: `boost_daily_spend`,
      type: `number`,
      description: `Boost tier avg daily spend`,
    },

    // Per-tier diagnostics: peak
    peakCpc: {
      sql: `peak_cpc`,
      type: `number`,
      description: `Peak tier CPC`,
    },
    peakUnitCvrPct: {
      sql: `peak_unit_cvr_pct`,
      type: `number`,
      description: `Peak tier unit CVR %`,
    },
    peakNetRoas: {
      sql: `peak_net_roas`,
      type: `number`,
      description: `Peak tier net ROAS`,
    },
    peakDailySpend: {
      sql: `peak_daily_spend`,
      type: `number`,
      description: `Peak tier avg daily spend`,
    },
  },
});
