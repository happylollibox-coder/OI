// Cube: ScheduledShipments — from DE_SCHEDULED_SHIPMENTS
// All statuses except SHIPPED (those are in DE_MANUFACTURER_SHIPMENTS).
// Consumed by PlanPage for approval UI and ReplenishmentFlow.
cube(`ScheduledShipments`, {
  sql: `SELECT * FROM \`onyga-482313.OI.DE_SCHEDULED_SHIPMENTS\`
        WHERE status IN ('SUGGESTED', 'APPROVED', 'SCHEDULED')`,

  refreshKey: { every: '1 second' },

  measures: {
    totalShipQty: {
      sql: `ship_qty`,
      type: `sum`,
      description: `Total committed ship quantity`,
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
      description: `Unique schedule identifier (UUID)`,
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
    shipQty: {
      sql: `ship_qty`,
      type: `number`,
    },
    shipCartons: {
      sql: `ship_cartons`,
      type: `number`,
      description: `Number of full cartons`,
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
    status: {
      sql: `status`,
      type: `string`,
      description: `SUGGESTED, APPROVED, or SCHEDULED`,
    },
    shipmentTriggerReason: {
      sql: `shipment_trigger_reason`,
      type: `string`,
    },
    shipQtyReason: {
      sql: `ship_qty_reason`,
      type: `string`,
    },
    approvedAt: {
      sql: `approved_at`,
      type: `time`,
    },
    scheduledAt: {
      sql: `scheduled_at`,
      type: `time`,
    },
    linkedShipmentId: {
      sql: `linked_shipment_id`,
      type: `string`,
    },
    notes: {
      sql: `notes`,
      type: `string`,
    },
  },
});
