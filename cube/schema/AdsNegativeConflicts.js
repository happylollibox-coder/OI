// Cube: AdsNegativeConflicts - from V_ADS_NEGATIVE_CONFLICTS
// Identifies cases where a campaign negates a search term that the advertised product
// actually converts on — either a self-block or a brand term blocked in a defense campaign.
// Read-only review surface: ~20 rows. Used in ActionsPage "Remove conflicting negatives" audit.
cube(`AdsNegativeConflicts`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_ADS_NEGATIVE_CONFLICTS\``,

  dimensions: {
    id: { sql: `CONCAT(campaign_id, '|', negated_term, '|', asin)`, type: `string`, primaryKey: true },
    campaignId: { sql: `campaign_id`, type: `string` },
    campaignName: { sql: `campaign_name`, type: `string` },
    negatedTerm: { sql: `negated_term`, type: `string` },
    asin: { sql: `asin`, type: `string` },
    productShortName: { sql: `product_short_name`, type: `string` },
    parentName: { sql: `parent_name`, type: `string` },
    converterOrders: { sql: `converter_orders`, type: `number` },
    converterSales: { sql: `converter_sales`, type: `number` },
    conflictType: { sql: `conflict_type`, type: `string` },
  },

  measures: {
    count: { type: `count` },
  },
});
