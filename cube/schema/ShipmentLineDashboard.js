// Cube: ShipmentLineDashboard — per-product shipment line data
// One row per product × shipment for accurate per-product transit quantities
// Fixes the double-counting bug where total_quantity_shipped was attributed to every product in a multi-product shipment

cube(`ShipmentLineDashboard`, {
  sql: `
    SELECT
      sl.line_id,
      sl.shipment_id,
      COALESCE(dim.product_short_name, po.product_name) AS product_name,
      sl.quantity_shipped,
      sl.num_cartons,
      sl.allocated_cost,
      s.shipment_type,
      s.shipment_status,
      s.shipment_date,
      s.estimated_arrival_date,
      s.tracking_number,
      s.deliverer
    FROM \`onyga-482313.OI.DE_SHIPMENT_LINES\` sl
    JOIN \`onyga-482313.OI.DE_MANUFACTURER_SHIPMENTS\` s ON s.shipment_id = sl.shipment_id
    LEFT JOIN \`onyga-482313.OI.DE_PURCHASE_ORDERS\` po ON po.purchase_order_id = sl.purchase_order_id
    LEFT JOIN \`onyga-482313.OI.DIM_PRODUCT\` dim ON dim.asin = po.product_asin
    WHERE sl.quantity_shipped > 0
  `,

  refreshKey: { every: '5 minute' },

  measures: {
    totalQtyShipped: {
      sql: `quantity_shipped`,
      type: `sum`,
      description: `Total quantity shipped per product line`,
    },
    totalAllocatedCost: {
      sql: `allocated_cost`,
      type: `sum`,
    },
    count: {
      type: `count`,
    },
  },

  dimensions: {
    lineId: {
      sql: `line_id`,
      type: `string`,
      primaryKey: true,
    },
    shipmentId: {
      sql: `shipment_id`,
      type: `string`,
    },
    productName: {
      sql: `product_name`,
      type: `string`,
    },
    shipmentType: {
      sql: `shipment_type`,
      type: `string`,
    },
    shipmentStatus: {
      sql: `shipment_status`,
      type: `string`,
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
    deliverer: {
      sql: `deliverer`,
      type: `string`,
    },
  },
});
