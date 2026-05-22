// Cube: ShipmentsDashboard — from DE_MANUFACTURER_SHIPMENTS + lines + POs
// Shipments aggregated per shipment (one row per shipment) for the Supply page
cube(`ShipmentsDashboard`, {
  sql: `
    SELECT
      s.shipment_id,
      s.shipment_date,
      s.estimated_arrival_date,
      s.tracking_number,
      s.shipment_type,
      s.total_quantity,
      s.kg_price,
      s.cost_shipped,
      s.is_paid,
      s.paid_date,
      s.shipment_status,
      s.notes,
      s.created_at,
      -- Aggregated line data
      COALESCE(agg.line_count, 0) AS line_count,
      COALESCE(agg.total_allocated_cost, 0) AS total_allocated_cost,
      COALESCE(agg.total_quantity_shipped, 0) AS total_quantity_shipped,
      agg.products_list,
      -- Unpaid to shipment: cost_shipped minus paid amount (if is_paid = false, full cost_shipped is unpaid)
      CASE WHEN s.is_paid = FALSE THEN COALESCE(s.cost_shipped, 0) ELSE 0 END AS unpaid_to_shipment,
      -- Is open: not in terminal status
      s.shipment_status NOT IN ('PUT_AWAY', 'RECEIVED', 'INSPECTED') AS is_open
    FROM \`onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS\` s
    LEFT JOIN (
      SELECT
        sl.shipment_id,
        COUNT(*) AS line_count,
        SUM(COALESCE(sl.allocated_cost, 0)) AS total_allocated_cost,
        SUM(COALESCE(sl.quantity_shipped, 0)) AS total_quantity_shipped,
        STRING_AGG(DISTINCT po.product_name, ', ') AS products_list
      FROM \`onyga-482313.OI.DE_SHIPMENT_LINES\` sl
      LEFT JOIN \`onyga-482313.OI.DE_PURCHASE_ORDERS\` po
        ON sl.purchase_order_id = po.purchase_order_id
      GROUP BY sl.shipment_id
    ) agg ON s.shipment_id = agg.shipment_id
  `,

  refreshKey: { every: '5 minute' },

  measures: {
    totalCostShipped: {
      sql: `cost_shipped`,
      type: `sum`,
      description: `Total shipping cost`,
    },
    totalUnpaidShipment: {
      sql: `unpaid_to_shipment`,
      type: `sum`,
      description: `Total unpaid shipment cost`,
    },
    count: {
      type: `count`,
    },
  },

  dimensions: {
    shipmentId: {
      sql: `shipment_id`,
      type: `string`,
      primaryKey: true,
    },
    shipmentDate: {
      sql: `TIMESTAMP(shipment_date)`,
      type: `time`,
    },
    estimatedArrivalDate: {
      sql: `TIMESTAMP(estimated_arrival_date)`,
      type: `time`,
    },
    trackingNumber: {
      sql: `tracking_number`,
      type: `string`,
    },
    shipmentType: {
      sql: `shipment_type`,
      type: `string`,
    },
    totalQuantity: {
      sql: `total_quantity`,
      type: `number`,
    },
    costShipped: {
      sql: `cost_shipped`,
      type: `number`,
    },
    isPaid: {
      sql: `is_paid`,
      type: `boolean`,
    },
    paidDate: {
      sql: `TIMESTAMP(paid_date)`,
      type: `time`,
    },
    shipmentStatus: {
      sql: `shipment_status`,
      type: `string`,
    },
    notes: {
      sql: `notes`,
      type: `string`,
    },
    lineCount: {
      sql: `line_count`,
      type: `number`,
    },
    totalAllocatedCost: {
      sql: `total_allocated_cost`,
      type: `number`,
    },
    totalQuantityShipped: {
      sql: `total_quantity_shipped`,
      type: `number`,
    },
    productsList: {
      sql: `products_list`,
      type: `string`,
    },
    unpaidToShipment: {
      sql: `unpaid_to_shipment`,
      type: `number`,
    },
    isOpen: {
      sql: `is_open`,
      type: `boolean`,
    },
  },
});
