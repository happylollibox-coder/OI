// Cube: AdsCoachCrossSell - from V_ADS_COACH_CROSSSELL (materialized to T_ADS_COACH_CROSSSELL)
// ONE ROW PER target_asin x advertise_asin: proven in-brand co-purchase affinity gaps
cube(`AdsCoachCrossSell`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_ADS_COACH_CROSSSELL\``,

  refreshKey: { every: '30 minutes' },

  dimensions: {
    pairId:        { sql: `CONCAT(target_asin, '|', advertise_asin)`, type: `string`, primaryKey: true },
    targetAsin:    { sql: `target_asin`, type: `string` },
    advertiseAsin: { sql: `advertise_asin`, type: `string` },
    targetName:    { sql: `target_name`, type: `string` },
    advertiseName: { sql: `advertise_name`, type: `string` },
    targetParent:  { sql: `target_parent`, type: `string` },
    confidence:    { sql: `confidence`, type: `string` },
  },

  measures: {
    crossOrders30d: { sql: `cross_orders_30d`, type: `sum` },
    crossSales30d:  { sql: `cross_sales_30d`, type: `sum` },
    count:          { type: `count` },
  },
});
