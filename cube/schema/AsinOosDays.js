// Cube: AsinOosDays - from V_ASIN_OOS_DAYS
// Per-ASIN out-of-stock day counts (28d/7d) from FACT_INVENTORY_SNAPSHOT.
// Feeds the coacher clear-case gate: a 0-order ads window that overlaps OOS
// days is shelf data, not demand data (owner case 2026-06-12).
// Grain: one row per ASIN.
cube(`AsinOosDays`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_ASIN_OOS_DAYS\``,

  measures: {
    count: { type: `count` },
  },

  dimensions: {
    asin: { sql: `asin`, type: `string`, primaryKey: true },
    oosDays28d: { sql: `oos_days_28d`, type: `number` },
    oosDays7d: { sql: `oos_days_7d`, type: `number` },
    observedDays28d: { sql: `observed_days_28d`, type: `number` },
    lastInStockDate: { sql: `last_in_stock_date`, type: `time` },
  },
});
