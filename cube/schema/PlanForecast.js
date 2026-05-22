// Cube: PlanForecast — from V_PLAN_FORECAST
// Single source of truth for supply chain forecasting, gap analysis, DOC, and supply readiness.
// Consumed by PlanPage initial load and AlertsPage.
cube(`PlanForecast`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_PLAN_FORECAST\``,

  refreshKey: { every: '1 hour' },

  measures: {
    totalGapFromPlan: {
      sql: `gap_from_plan`,
      type: `sum`,
      description: `Total gap between yearly plan and (stock + ytd sold)`,
    },
    totalStock: {
      sql: `total_stock`,
      type: `sum`,
      description: `Total inventory across all locations`,
    },
    totalYtdSold: {
      sql: `ytd_sold`,
      type: `sum`,
      description: `Total year-to-date units sold`,
    },
  },

  dimensions: {
    product: {
      sql: `product`,
      type: `string`,
      primaryKey: true,
      description: `Product short name from DIM_PRODUCT`,
    },
    asin: {
      sql: `asin`,
      type: `string`,
      description: `Amazon Standard Identification Number`,
    },
    packageQuantity: {
      sql: `package_quantity`,
      type: `number`,
      description: `Units per master carton`,
    },
    minManufQuantity: {
      sql: `min_manuf_quantity`,
      type: `number`,
      description: `Minimum manufacturer order quantity`,
    },
    manufactureDay: {
      sql: `manufacture_day`,
      type: `number`,
      description: `Days to manufacture from DIM_PRODUCT`,
    },
    shipmentDays: {
      sql: `shipment_days`,
      type: `number`,
      description: `Shipment transit days from DIM_PRODUCT`,
    },
    fullLeadDays: {
      sql: `full_lead_days`,
      type: `number`,
      description: `Full lead time: manufacture_day + shipment_days`,
    },
    fbaStock: {
      sql: `fba_stock`,
      type: `number`,
      description: `Current FBA inventory`,
    },
    awdStock: {
      sql: `awd_stock`,
      type: `number`,
      description: `Current AWD inventory`,
    },
    inTransit: {
      sql: `in_transit`,
      type: `number`,
      description: `Units currently in transit`,
    },
    atManufacturer: {
      sql: `at_manufacturer`,
      type: `number`,
      description: `Units at manufacturer`,
    },
    totalStockDim: {
      sql: `total_stock`,
      type: `number`,
      description: `Sum of all inventory locations`,
    },
    isAwdProduct: {
      sql: `is_awd_product`,
      type: `boolean`,
      description: `Whether product has AWD inventory`,
    },
    dailyRate: {
      sql: `daily_rate`,
      type: `number`,
      description: `Forecast-based daily demand rate (current month)`,
    },
    effectiveGrowth: {
      sql: `effective_growth`,
      type: `number`,
      description: `Growth multiplier derived from plan overrides`,
    },
    yearlyPlan: {
      sql: `yearly_plan`,
      type: `number`,
      description: `Target units for the current year`,
    },
    unconstrainedRemainingForecast: {
      sql: `unconstrained_remaining_forecast`,
      type: `number`,
      description: `The unconstrained remaining demand for the year`,
    },
    ytdSold: {
      sql: `ytd_sold`,
      type: `number`,
      description: `Year-to-date units sold`,
    },
    gapFromPlan: {
      sql: `gap_from_plan`,
      type: `number`,
      description: `yearlyPlan - totalStock - ytdSold (clamped to 0)`,
    },
    // Supply readiness tiers
    readyToShip: {
      sql: `ready_to_ship`,
      type: `number`,
      description: `Units at manufacturer with manufacturing complete (ready to ship)`,
    },
    inProduction: {
      sql: `in_production`,
      type: `number`,
      description: `Units at manufacturer still being manufactured`,
    },
    readyLeadDays: {
      sql: `ready_lead_days`,
      type: `number`,
      description: `Lead time for ready stock (shipment_days only)`,
    },
    productionLeadDays: {
      sql: `production_lead_days`,
      type: `number`,
      description: `Lead time for in-production stock (days_until_ready + shipment_days)`,
    },
    effectiveLeadDays: {
      sql: `effective_lead_days`,
      type: `number`,
      description: `Actual lead time based on supply status (fastest available tier)`,
    },
    supplyStatus: {
      sql: `supply_status`,
      type: `string`,
      description: `Supply readiness: READY, IN_PRODUCTION, or NEEDS_PO`,
    },
    fbaEffective: {
      sql: `fba_effective`,
      type: `number`,
      description: `FBA stock + in-transit (for display)`,
    },
    availableStock: {
      sql: `available_stock`,
      type: `number`,
      description: `FBA + in-transit + AWD (used for emergency check — AWD→FBA transfer is 3-5 days)`,
    },
    demandDuringLead: {
      sql: `demand_during_lead`,
      type: `number`,
      description: `Forecast demand during effective lead time period`,
    },
    isEmergency: {
      sql: `is_emergency`,
      type: `boolean`,
      description: `TRUE if available stock (FBA + transit + AWD) < demand during lead time`,
    },
    fbaDoc: {
      sql: `fba_doc`,
      type: `number`,
      description: `Days of coverage: FBA stock / daily rate`,
    },
    fbaDocEffective: {
      sql: `fba_doc_effective`,
      type: `number`,
      description: `Days of coverage: (FBA + in-transit) / daily rate`,
    },
    systemDoc: {
      sql: `system_doc`,
      type: `number`,
      description: `Days of coverage: total stock / daily rate`,
    },
    poFeasible: {
      sql: `po_feasible`,
      type: `boolean`,
      description: `TRUE if there is still time to manufacture + ship via FAST_SEA before Q4 peak (Dec 5)`,
    },
    poDeadline: {
      sql: `po_deadline`,
      type: `time`,
      description: `Latest date to place a PO so it arrives at FBA before Q4 peak deadline`,
    },
    forecastPhase: {
      sql: `forecast_phase`,
      type: `string`,
      description: `Forecast phase: PHASE_1 (model-based cold start), PHASE_2 (hybrid: own base + model seasonality), PHASE_3 (mature: standard forecast)`,
    },
    modelProduct: {
      sql: `model_product`,
      type: `string`,
      description: `The existing product whose launch model is being used for forecasting (NULL for Phase 3 products)`,
    },

    // Ads efficiency (from V_ADS_EFFICIENCY_PROFILE via V_PLAN_FORECAST)
    adsForecastUnits: {
      sql: `ads_forecast_units`,
      type: `number`,
      description: `Total unit forecast from ads 3-parameter model (Spend/CPC × Unit_CVR / Ads_Share), prorated by product share in family`,
    },
    adsSuggestedSpend: {
      sql: `ads_suggested_spend`,
      type: `number`,
      description: `Suggested ads spend target for this product (family total × product share)`,
    },
    adsCpc: {
      sql: `ads_cpc`,
      type: `number`,
      description: `Spend-weighted average CPC across forecast months`,
    },
    adsUnitCvrPct: {
      sql: `ads_unit_cvr_pct`,
      type: `number`,
      description: `Spend-weighted average unit CVR % (ads_units / clicks × 100)`,
    },
    adsSharePct: {
      sql: `ads_share_pct`,
      type: `number`,
      description: `Spend-weighted average ads share % (ads_units / total_units × 100)`,
    },
    adsNetRoas: {
      sql: `ads_net_roas`,
      type: `number`,
      description: `Spend-weighted average net ROAS (gross profit / spend)`,
    },
    family: {
      sql: `family`,
      type: `string`,
      description: `Product family from V_PRODUCT_FAMILY_MAP`,
    },

    // Demand windows
    demand30d: {
      sql: `demand_30d`,
      type: `number`,
      description: `Proportional demand over next 30 days`,
    },
    demand45d: {
      sql: `demand_45d`,
      type: `number`,
      description: `Proportional demand over next 45 days`,
    },
    demand60d: {
      sql: `demand_60d`,
      type: `number`,
      description: `Proportional demand over next 60 days`,
    },
    demand90d: {
      sql: `demand_90d`,
      type: `number`,
      description: `Proportional demand over next 90 days`,
    },
    proportionalDailyDemand: {
      sql: `proportional_daily_demand`,
      type: `number`,
      description: `Daily demand rate from 90-day proportional calculation`,
    },
    daysUntilOos: {
      sql: `days_until_oos`,
      type: `number`,
      description: `Days until out-of-stock based on proportional demand`,
    },
    emergencyPriority: {
      sql: `emergency_priority`,
      type: `number`,
      description: `Emergency priority: CEIL(weeks_to_OOS) + 1 (lower = more urgent)`,
    },
    q4Demand: {
      sql: `q4_demand`,
      type: `number`,
      description: `Q4 demand: Sep current year through Feb next year`,
    },
    preQ4Demand: {
      sql: `pre_q4_demand`,
      type: `number`,
      description: `Pre-Q4 demand: current month through Aug`,
    },
    forecastedSep1Pipeline: {
      sql: `forecasted_sep1_pipeline`,
      type: `number`,
      description: `Projected pipeline on Sep 1 (current stock - pre-Q4 demand)`,
    },
    sellableDocWalk: {
      sql: `sellable_doc_walk`,
      type: `number`,
      description: `Days of coverage (FBA+AWD) via month-by-month walkthrough`,
    },
    fbaDocWalk: {
      sql: `fba_doc_walk`,
      type: `number`,
      description: `Days of coverage (FBA only) via month-by-month walkthrough`,
    },
    shareCartonInFamily: {
      sql: `share_carton_in_family`,
      type: `number`,
      description: `Product share of carton in family for mixed shipments`,
    },
    last30dSold: {
      sql: `last_30d_sold`,
      type: `number`,
      description: `Units sold in last 30 days (actuals)`,
    },
    last30dPlanned: {
      sql: `last_30d_planned`,
      type: `number`,
      description: `Units planned/forecasted for last 30 days`,
    },
  },
});
