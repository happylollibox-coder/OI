// Cube: SupplyChain — from V_SUPPLY_CHAIN_SUMMARY
// Per-ASIN supply chain health: days of coverage, next shipment info
cube(`SupplyChain`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_SUPPLY_CHAIN_SUMMARY\``,

  refreshKey: {
    sql: `
      SELECT CONCAT(
        COALESCE(CAST(MAX(snapshot_date) AS STRING), ''),
        '_',
        COALESCE(CAST(MAX(approved_at) AS STRING), '')
      )
      FROM (
        SELECT MAX(Date) AS snapshot_date FROM \`onyga-482313.OI.FACT_INVENTORY_SNAPSHOT\`
      )
      CROSS JOIN (
        SELECT MAX(approved_at) AS approved_at FROM \`onyga-482313.OI.DE_AWD_SETTINGS\`
      )
    `
  },

  measures: {
    minDaysOfCoverage: {
      sql: `days_of_coverage`,
      type: `min`,
      description: `Minimum days of coverage across products (weakest link)`,
    },
    totalSellableQty: {
      sql: `sellable_qty`,
      type: `sum`,
      description: `Total sellable units (FBA + AWD)`,
    },
    totalInTransitQty: {
      sql: `in_transit_qty`,
      type: `sum`,
      description: `Total in-transit units`,
    },
    totalNextShipmentQty: {
      sql: `next_shipment_qty`,
      type: `sum`,
      description: `Total quantity in next pending shipments`,
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
      description: `Product display name`,
    },
    productType: {
      sql: `product_type`,
      type: `string`,
      description: `Product family (Lollibox, LolliME, Bottle, Fresh)`,
    },
    snapshotDate: {
      sql: `snapshot_date`,
      type: `string`,
      description: `Date of the latest inventory snapshot`,
    },
    sellableQty: {
      sql: `sellable_qty`,
      type: `number`,
      description: `Sellable units (FBA + AWD)`,
    },
    inTransitQty: {
      sql: `in_transit_qty`,
      type: `number`,
      description: `Units currently in transit`,
    },
    totalAvailableQty: {
      sql: `total_available_qty`,
      type: `number`,
      description: `Sellable + in-transit units`,
    },
    dailyVelocity: {
      sql: `daily_velocity`,
      type: `number`,
      description: `Forecast-based daily demand rate (from V_PLAN_FORECAST)`,
    },
    daysOfCoverage: {
      sql: `days_of_coverage`,
      type: `number`,
      description: `Sellable stock / daily velocity (days until stockout)`,
    },
    fbaDaysOfCoverage: {
      sql: `fba_days_of_coverage`,
      type: `number`,
      description: `FBA stock / daily velocity`,
    },
    awdDaysOfCoverage: {
      sql: `awd_days_of_coverage`,
      type: `number`,
      description: `AWD stock / daily velocity`,
    },
    fbaStockQty: {
      sql: `fba_stock_qty`,
      type: `number`,
      description: `FBA sellable units`,
    },
    awdStockQty: {
      sql: `awd_stock_qty`,
      type: `number`,
      description: `AWD sellable units`,
    },
    mfrStockQty: {
      sql: `mfr_stock_qty`,
      type: `number`,
      description: `MFR Ready units (manufactured, ready to ship from factory)`,
    },
    nextShipmentDate: {
      sql: `next_shipment_date`,
      type: `string`,
      description: `Estimated arrival date of next pending shipment`,
    },
    daysToNextShipment: {
      sql: `days_to_next_shipment`,
      type: `number`,
      description: `Days until next shipment arrives`,
    },
    nextShipmentQty: {
      sql: `next_shipment_qty`,
      type: `number`,
      description: `Quantity in next pending shipment`,
    },
    awdTargetMin: {
      sql: `awd_target_min`,
      type: `number`,
      description: `Calculated AWD Min Units (30 DOC)`,
    },
    awdTargetMax: {
      sql: `awd_target_max`,
      type: `number`,
      description: `Calculated AWD Max Units (45 DOC)`,
    },
    awdApprovedMin: {
      sql: `awd_approved_min`,
      type: `number`,
      description: `Manually approved AWD Min Units`,
    },
    awdApprovedMax: {
      sql: `awd_approved_max`,
      type: `number`,
      description: `Manually approved AWD Max Units`,
    },
    awdDiffPct: {
      sql: `awd_diff_pct`,
      type: `number`,
      description: `Difference percentage between target max and approved max`,
    },
    last30dSold: {
      sql: `last_30d_sold`,
      type: `number`,
      description: `Actual sales units in the last 30 days`,
    },
    last30dPlanned: {
      sql: `last_30d_planned`,
      type: `number`,
      description: `Planned forecast for the same last 30-day window as last30dSold`,
    },
    next30dPlanned: {
      sql: `next_30d_planned`,
      type: `number`,
      description: `Planned demand for the next 30 days`,
    },
    next3160dPlanned: {
      sql: `next_31_60d_planned`,
      type: `number`,
      description: `Planned demand for days 31-60`,
    },
    next6190dPlanned: {
      sql: `next_61_90d_planned`,
      type: `number`,
      description: `Planned demand for days 61-90`,
    },
  },
});
