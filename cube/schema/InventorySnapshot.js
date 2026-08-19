cube(`InventorySnapshot`, {
  sql: `
    SELECT
      agg.Date,
      agg.ASIN,
      agg.source_type,
      agg.quantity_balance,
      agg.COGS_AMOUNT,
      agg.LANDED_COGS_AMOUNT,
      agg.SELL_AMOUNT,
      agg.PAID_AMOUNT,
      agg.cost_of_goods,
      agg.shipping_cost,
      agg.loaded_at,
      p.product_short_name,
      p.parent_name AS product_family
    FROM (
      SELECT
        Date, ASIN, source_type,
        SUM(quantity_balance) AS quantity_balance,
        SUM(COGS_AMOUNT) AS COGS_AMOUNT,
        SUM(LANDED_COGS_AMOUNT) AS LANDED_COGS_AMOUNT,
        SUM(SELL_AMOUNT) AS SELL_AMOUNT,
        SUM(PAID_AMOUNT) AS PAID_AMOUNT,
        SUM(cost_of_goods) AS cost_of_goods,
        SUM(shipping_cost) AS shipping_cost,
        MAX(loaded_at) AS loaded_at
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

    // COGS_AMOUNT is FEE-LOADED: it values stock at
    // DIM_COSTS_HISTORY.TOTAL_COST_PER_UNIT = manufacturing + freight + Amazon
    // pick&pack + referral. Right for the profit on a unit that SELLS, wrong for
    // valuing unsold stock (overstates ~2.25x). For asset / balance-sheet value
    // use totalLandedCogs. See architecture/FINANCE_SNAPSHOT_EXPORT.md.
    totalCogs: {
      type: `sum`,
      sql: `${CUBE}.COGS_AMOUNT`,
      title: `COGS Value (incl. Amazon fees)`,
    },

    totalLandedCogs: {
      type: `sum`,
      sql: `${CUBE}.LANDED_COGS_AMOUNT`,
      title: `Landed COGS Value`,
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

    lastLoadedAt: {
      type: `max`,
      sql: `${CUBE}.loaded_at`,
      title: `Last Refreshed`,
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
