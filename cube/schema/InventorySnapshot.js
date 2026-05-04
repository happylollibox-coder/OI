cube(`InventorySnapshot`, {
  sql: `
    SELECT
      agg.Date,
      agg.ASIN,
      agg.source_type,
      agg.quantity_balance,
      agg.COGS_AMOUNT,
      agg.SELL_AMOUNT,
      agg.PAID_AMOUNT,
      agg.cost_of_goods,
      agg.shipping_cost,
      p.product_short_name,
      p.parent_name AS product_family
    FROM (
      SELECT
        Date, ASIN, source_type,
        SUM(quantity_balance) AS quantity_balance,
        SUM(COGS_AMOUNT) AS COGS_AMOUNT,
        SUM(SELL_AMOUNT) AS SELL_AMOUNT,
        SUM(PAID_AMOUNT) AS PAID_AMOUNT,
        SUM(cost_of_goods) AS cost_of_goods,
        SUM(shipping_cost) AS shipping_cost
      FROM \`onyga-482313.OI.FACT_INVENTORY_SNAPSHOT\`
      GROUP BY Date, ASIN, source_type
    ) agg
    LEFT JOIN \`onyga-482313.OI.DIM_PRODUCT\` p
      ON p.asin = agg.ASIN
      AND p.marketplace = 'ATVPDKIKX0DER'
  `,

  sqlAlias: `inv`,

  measures: {
    totalUnits: {
      type: `sum`,
      sql: `${CUBE}.quantity_balance`,
      title: `Total Units`,
    },

    totalCogs: {
      type: `sum`,
      sql: `${CUBE}.COGS_AMOUNT`,
      title: `COGS Value`,
    },

    totalSellValue: {
      type: `sum`,
      sql: `${CUBE}.SELL_AMOUNT`,
      title: `Sell Value`,
    },

    totalPaidAmount: {
      type: `sum`,
      sql: `${CUBE}.PAID_AMOUNT`,
      title: `Paid Amount`,
    },

    latestSnapshotDate: {
      type: `max`,
      sql: `Date`,
      title: `Snapshot Date`,
    },

    productCount: {
      type: `countDistinct`,
      sql: `${CUBE}.ASIN`,
      title: `Products`,
    },
  },

  dimensions: {
    date: {
      sql: `CAST(Date AS TIMESTAMP)`,
      type: `time`,
      title: `Snapshot Date`,
    },

    asin: {
      sql: `ASIN`,
      type: `string`,
      title: `ASIN`,
    },

    productShortName: {
      sql: `product_short_name`,
      type: `string`,
      title: `Product`,
    },

    productFamily: {
      sql: `product_family`,
      type: `string`,
      title: `Product Family`,
    },

    sourceType: {
      sql: `source_type`,
      type: `string`,
      title: `Source`,
    },

    costOfGoods: {
      sql: `cost_of_goods`,
      type: `number`,
      title: `Manufacture Cost Per Unit`,
    },

    shippingCost: {
      sql: `shipping_cost`,
      type: `number`,
      title: `Shipment Cost Per Unit`,
    },

    quantityBalance: {
      sql: `quantity_balance`,
      type: `number`,
      title: `Quantity Balance`,
    },
  },
});
