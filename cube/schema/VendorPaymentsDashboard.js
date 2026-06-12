// Cube: VendorPaymentsDashboard — from DE_VENDOR_PAYMENTS
// Aggregated at (payment_date, vendor_name, payment_id) level
cube(`VendorPaymentsDashboard`, {
  sql: `
    SELECT
      vp.payment_id,
      vp.payment_date,
      vp.vendor_name,
      vp.currency,
      vp.payment_method,
      SUM(vp.payment_amount) AS payment_amount,
      COALESCE(SUM(vp.bank_fee), 0) AS bank_fee,
      SUM(vp.payment_amount) + COALESCE(SUM(vp.bank_fee), 0) AS total_amount,
      STRING_AGG(DISTINCT vp.notes, '; ') AS notes,
      STRING_AGG(DISTINCT COALESCE(vp.purchase_order_id, sl_po.purchase_order_id), ', ') AS purchase_order_ids,
      STRING_AGG(DISTINCT vp.shipment_id, ', ') AS shipment_ids
    FROM \`onyga-482313.OI.DE_VENDOR_PAYMENTS\` vp
    LEFT JOIN (
      SELECT DISTINCT shipment_id, purchase_order_id
      FROM \`onyga-482313.OI.DE_SHIPMENT_LINES\`
      WHERE purchase_order_id IS NOT NULL
    ) sl_po ON vp.shipment_id = sl_po.shipment_id
    GROUP BY
      vp.payment_id,
      vp.payment_date,
      vp.vendor_name,
      vp.currency,
      vp.payment_method
  `,

  refreshKey: { every: '1 second' },

  measures: {
    totalPayments: {
      sql: `payment_amount`,
      type: `sum`,
      description: `Total payment amount`,
    },
    totalBankFees: {
      sql: `bank_fee`,
      type: `sum`,
      description: `Total bank fees`,
    },
    totalAmount: {
      sql: `total_amount`,
      type: `sum`,
      description: `Total amount (payment + bank fee)`,
    },
    count: {
      type: `count`,
    },
  },

  dimensions: {
    rowKey: {
      sql: `CONCAT(CAST(payment_date AS STRING), '|', vendor_name, '|', COALESCE(payment_id, ''))`,
      type: `string`,
      primaryKey: true,
    },
    paymentId: {
      sql: `payment_id`,
      type: `string`,
    },
    purchaseOrderIds: {
      sql: `purchase_order_ids`,
      type: `string`,
    },
    shipmentIds: {
      sql: `shipment_ids`,
      type: `string`,
    },
    paymentDate: {
      sql: `TIMESTAMP(payment_date)`,
      type: `time`,
    },
    paymentAmount: {
      sql: `payment_amount`,
      type: `number`,
    },
    bankFee: {
      sql: `bank_fee`,
      type: `number`,
    },
    totalAmountDim: {
      sql: `total_amount`,
      type: `number`,
    },
    currency: {
      sql: `currency`,
      type: `string`,
    },
    paymentMethod: {
      sql: `payment_method`,
      type: `string`,
    },
    vendorName: {
      sql: `vendor_name`,
      type: `string`,
    },
    notes: {
      sql: `notes`,
      type: `string`,
    },
  },
});
