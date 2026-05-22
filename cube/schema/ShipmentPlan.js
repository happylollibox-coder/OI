// Cube: ShipmentPlan — SUGGESTED rows from DE_SCHEDULED_SHIPMENTS
// SP_GENERATE_SHIPMENT_PLAN writes SUGGESTED rows here; approval flips status.
// Consumed by PlanPage ShipmentPlanSection and ReplenishmentFlowSection.
cube(`ShipmentPlan`, {
  sql: `SELECT * FROM \`onyga-482313.OI.DE_SCHEDULED_SHIPMENTS\` WHERE status = 'SUGGESTED'`,

  refreshKey: { every: '1 second' },

  measures: {
    totalShipQty: {
      sql: `ship_qty`,
      type: `sum`,
      description: `Total suggested ship quantity`,
    },
    count: {
      type: `count`,
    },
  },

  dimensions: {
    scheduleId: {
      sql: `schedule_id`,
      type: `string`,
      primaryKey: true,
      description: `Unique identifier (UUID)`,
    },
    product: {
      sql: `product`,
      type: `string`,
    },
    asin: {
      sql: `asin`,
      type: `string`,
    },
    shipmentType: {
      sql: `shipment_type`,
      type: `number`,
      description: `1=EMERGENCY, 2=EMERGENCY_PO, 3=AWD_MAINT, 4=Q4_BULK`,
    },
    shipmentTypeName: {
      sql: `shipment_type_name`,
      type: `string`,
    },
    route: {
      sql: `route`,
      type: `string`,
    },
    transitType: {
      sql: `transit_type`,
      type: `string`,
    },
    transitDays: {
      sql: `transit_days`,
      type: `number`,
    },
    priority: {
      sql: `priority`,
      type: `number`,
    },
    daysUntilOos: {
      sql: `days_until_oos`,
      type: `number`,
    },
    shipQty: {
      sql: `ship_qty`,
      type: `number`,
    },
    shipCartons: {
      sql: `ship_cartons`,
      type: `number`,
      description: `Number of full cartons (FLOOR of ship_qty / package_quantity)`,
    },
    mfrReadyBefore: {
      sql: `mfr_ready_before`,
      type: `number`,
    },
    inProduction: {
      sql: `in_production`,
      type: `number`,
    },
    needsNewPo: {
      sql: `needs_new_po`,
      type: `boolean`,
    },
    newPoQty: {
      sql: `new_po_qty`,
      type: `number`,
    },
    shipWednesday: {
      sql: `TIMESTAMP(ship_wednesday)`,
      type: `time`,
    },
    amazonPlanDate: {
      sql: `TIMESTAMP(amazon_plan_date)`,
      type: `time`,
    },
    arrivalDate: {
      sql: `TIMESTAMP(arrival_date)`,
      type: `time`,
    },
    shipmentNum: {
      sql: `shipment_num`,
      type: `number`,
    },
    availableStock: {
      sql: `available_stock`,
      type: `number`,
    },
    fbaStock: {
      sql: `fba_stock`,
      type: `number`,
    },
    awdStock: {
      sql: `awd_stock`,
      type: `number`,
    },
    inTransit: {
      sql: `in_transit`,
      type: `number`,
    },
    demandWindow: {
      sql: `demand_window`,
      type: `number`,
    },
    demandAwdWindow: {
      sql: `demand_awd_window`,
      type: `number`,
    },
    shipmentTriggerReason: {
      sql: `shipment_trigger_reason`,
      type: `string`,
    },
    shipQtyReason: {
      sql: `ship_qty_reason`,
      type: `string`,
    },
  },
});
