// Cube: PurchaseOrdersDashboard — from V_SUPPLY_ORDERS_DASHBOARD
// Enriched POs with payment & shipment status for the Supply page
cube(`PurchaseOrdersDashboard`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_SUPPLY_ORDERS_DASHBOARD\``,

  refreshKey: { every: '5 minute' },

  measures: {
    totalUnpaidManufacturer: {
      sql: `CASE WHEN unpaid_manufacturer > 0 THEN unpaid_manufacturer ELSE 0 END`,
      type: `sum`,
      description: `Total unpaid amount to manufacturers`,
    },
    totalUnpaidShipment: {
      sql: `CASE WHEN unpaid_shipment > 0 THEN unpaid_shipment ELSE 0 END`,
      type: `sum`,
      description: `Total unpaid shipment costs`,
    },
    totalUnpaid: {
      sql: `CASE WHEN total_unpaid > 0 THEN total_unpaid ELSE 0 END`,
      type: `sum`,
      description: `Total unpaid (manufacturer + shipment)`,
    },
    totalAmount: {
      sql: `total_amount`,
      type: `sum`,
      description: `Total PO amount`,
    },
    totalPaid: {
      sql: `total_paid`,
      type: `sum`,
      description: `Total paid to manufacturer`,
    },
    count: {
      type: `count`,
    },
  },

  dimensions: {
    purchaseOrderId: {
      sql: `purchase_order_id`,
      type: `string`,
      primaryKey: true,
    },
    orderDate: {
      sql: `TIMESTAMP(order_date)`,
      type: `time`,
    },
    expectedReadyDate: {
      sql: `TIMESTAMP(expected_ready_date)`,
      type: `time`,
    },
    estimatedArrivalDate: {
      sql: `TIMESTAMP(estimated_arrival_date)`,
      type: `time`,
      description: `Manual override for PO estimated arrival date`,
    },
    manufacturerName: {
      sql: `manufacturer_name`,
      type: `string`,
    },
    productName: {
      sql: `product_name`,
      type: `string`,
    },
    productAsin: {
      sql: `product_asin`,
      type: `string`,
    },
    productId: {
      sql: `product_id`,
      type: `string`,
    },
    quantity: {
      sql: `quantity`,
      type: `number`,
    },
    readyQuantity: {
      sql: `ready_quantity`,
      type: `number`,
    },
    totalAmountDim: {
      sql: `total_amount`,
      type: `number`,
    },
    totalPaidDim: {
      sql: `total_paid`,
      type: `number`,
    },
    unpaidManufacturer: {
      sql: `unpaid_manufacturer`,
      type: `number`,
    },
    totalShipmentCost: {
      sql: `total_shipment_cost`,
      type: `number`,
    },
    paidShipmentCost: {
      sql: `paid_shipment_cost`,
      type: `number`,
    },
    unpaidShipment: {
      sql: `unpaid_shipment`,
      type: `number`,
    },
    totalUnpaidDim: {
      sql: `total_unpaid`,
      type: `number`,
    },
    totalQuantityShipped: {
      sql: `total_quantity_shipped`,
      type: `number`,
    },
    remainingToShip: {
      sql: `remaining_to_ship`,
      type: `number`,
    },
    estimatedShipmentCost: {
      sql: `estimated_shipment_cost`,
      type: `number`,
    },
    paymentStatus: {
      sql: `payment_status`,
      type: `string`,
    },
    isOpen: {
      sql: `is_open`,
      type: `boolean`,
    },
    currency: {
      sql: `currency`,
      type: `string`,
    },
    notes: {
      sql: `notes`,
      type: `string`,
    },
  },
});
