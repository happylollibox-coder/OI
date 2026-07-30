// Cube: ExperimentDaily - from FACT_EXPERIMENT_DAILY
// Used for experiment_weekly (daily experiment snapshots by ASIN)
cube(`ExperimentDaily`, {
  sql: `SELECT * FROM \`onyga-482313.OI.FACT_EXPERIMENT_DAILY\``,

  joins: {
    Experiment: {
      relationship: `belongsTo`,
      sql: `${CUBE}.experiment_id = ${Experiment}.experiment_id`,
    },
    Product: {
      relationship: `belongsTo`,
      sql: `${CUBE}.asin = ${Product}.asin`,
    },
  },

  measures: {
    count: {
      type: `count`,
      description: `Number of rows`,
    },
    adsExpOrders: {
      sql: `ads_exp_orders`,
      type: `sum`,
      description: `Orders from experiment campaigns`,
    },
    adsExpCost: {
      sql: `ads_exp_cost`,
      type: `sum`,
      format: `currency`,
      description: `Ad spend on experiment campaigns`,
    },
    adsAllOrders: {
      sql: `ads_all_orders`,
      type: `sum`,
      description: `Orders from all campaigns (experiment + baseline)`,
    },
    adsAllCost: {
      sql: `ads_all_cost`,
      type: `sum`,
      format: `currency`,
      description: `Ad spend across all campaigns`,
    },
    performanceTotalOrders: {
      sql: `performance_total_orders`,
      type: `sum`,
      description: `Total orders (ads + organic)`,
    },
    performanceTotalSales: {
      sql: `performance_total_sales`,
      type: `sum`,
      format: `currency`,
      description: `Total sales in USD`,
    },
    performanceOrganicUnits: {
      sql: `performance_organic_units`,
      type: `sum`,
      description: `Organic (non-ad) units`,
    },
    performanceSessions: {
      sql: `performance_sessions`,
      type: `sum`,
      description: `Sessions on the ASIN`,
    },
  },

  dimensions: {
    id: {
      sql: `CONCAT(CAST(snapshot_date AS STRING), '|', COALESCE(experiment_id, ''), '|', COALESCE(asin, ''))`,
      type: `string`,
      primaryKey: true,
    },
    snapshotDate: {
      sql: `CAST(snapshot_date AS TIMESTAMP)`,
      type: `time`,
      description: `Daily snapshot date`,
    },
    experimentId: {
      sql: `experiment_id`,
      type: `string`,
      description: `Experiment identifier`,
    },
    asin: {
      sql: `asin`,
      type: `string`,
      description: `Product ASIN`,
    },
  },

  // Restatement-safe key — see the note in Ads.js. This table restates at a CONSTANT row count:
  // on 2026-07-23 ads_all_cost moved 533,718.38 -> 535,361.51 across 7,384 rows both before and
  // after, with MAX(snapshot_date) pinned at 2026-07-23. Neither MAX() nor COUNT(*) sees that.
  refreshKey: {
    sql: `SELECT last_modified_time FROM \`onyga-482313.OI.__TABLES__\` WHERE table_id = 'FACT_EXPERIMENT_DAILY'`,
  },

  preAggregations: {
    // Temporarily disabled — stale partition tables cause NOT FOUND errors
    // experimentWeekly: { ... },
  },
});
