// Cube: AdsNegativeConflicts - from V_ADS_NEGATIVE_CONFLICTS
// Identifies cases where a campaign negates a search term that the advertised product
// actually converts on — either a self-block or a brand term blocked in a defense campaign.
// Read-only review surface. Used in ActionsPage "Remove conflicting negatives" audit.
// Carries archive identifiers (real Keyword ID) + recency + the blocking campaign's
// all-time net ROAS / product-changed context so a conflict can be judged and removed.
cube(`AdsNegativeConflicts`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_ADS_NEGATIVE_CONFLICTS\``,

  dimensions: {
    id: { sql: `CONCAT(campaign_id, '|', negated_term, '|', asin, '|', negative_id)`, type: `string`, primaryKey: true },
    campaignId: { sql: `campaign_id`, type: `string` },
    campaignName: { sql: `campaign_name`, type: `string` },
    negatedTerm: { sql: `negated_term`, type: `string` },
    // Archive identifiers (real Amazon Keyword ID + ad group + match type) so the
    // conflict can be removed via bulksheet from the dashboard.
    negativeId: { sql: `negative_id`, type: `string` },
    adGroupId: { sql: `ad_group_id`, type: `string` },
    matchType: { sql: `match_type`, type: `string` },
    level: { sql: `level`, type: `string` },
    asin: { sql: `asin`, type: `string` },
    productShortName: { sql: `product_short_name`, type: `string` },
    parentName: { sql: `parent_name`, type: `string` },
    converterOrders: { sql: `converter_orders`, type: `number` },
    converterSales: { sql: `converter_sales`, type: `number` },
    // Recency: does it still convert in the last 90 days (not just sometime last year)?
    converterOrders90d: { sql: `converter_orders_90d`, type: `number` },
    converterSales90d: { sql: `converter_sales_90d`, type: `number` },
    // Blocking campaign context: all-time net ROAS + whether its product has changed.
    campaignNetRoasAllTime: { sql: `campaign_net_roas_all_time`, type: `number` },
    campaignGrossRoasAllTime: { sql: `campaign_gross_roas_all_time`, type: `number` },
    campaignSpendAllTime: { sql: `campaign_spend_all_time`, type: `number` },
    campaignDistinctAsins: { sql: `campaign_distinct_asins`, type: `number` },
    campaignProductChanged: { sql: `campaign_product_changed`, type: `boolean` },
    conflictType: { sql: `conflict_type`, type: `string` },
  },

  measures: {
    count: { type: `count` },
  },
});
