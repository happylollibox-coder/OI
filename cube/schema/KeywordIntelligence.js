// Cube: KeywordIntelligence - from V_KEYWORD_INTELLIGENCE
// Used for inline keyword intelligence panel in Coach Priority Queue
// Lazy-loaded per keyword when user expands a complex term
cube(`KeywordIntelligence`, {
  sql: `SELECT * FROM \`onyga-482313.OI.V_KEYWORD_INTELLIGENCE\``,

  refreshKey: { every: '1 hour' },

  measures: {
    count: {
      type: `count`,
      description: `Number of keywords with intelligence data`,
    },
  },

  dimensions: {
    searchTerm: {
      sql: `search_term`,
      type: `string`,
      primaryKey: true,
      description: `Search term (lowercase)`,
    },
    totalSpend: { sql: `total_spend`, type: `number`, description: `Total 4-week spend across all campaigns` },
    totalOrders: { sql: `total_orders`, type: `number`, description: `Total 4-week orders across all campaigns` },
    totalClicks: { sql: `total_clicks`, type: `number`, description: `Total 4-week clicks across all campaigns` },
    productCount: { sql: `product_count`, type: `number`, description: `Number of unique products advertising this term` },
    campaignCount: { sql: `campaign_count`, type: `number`, description: `Number of campaigns targeting this term` },

    // Current hero
    heroAsin: { sql: `hero_asin`, type: `string`, description: `Current hero ASIN` },
    heroProductName: { sql: `hero_product_name`, type: `string`, description: `Current hero product name` },
    heroNetRoas: { sql: `hero_net_roas`, type: `number`, description: `Current hero Net ROAS` },
    heroCvrPct: { sql: `hero_cvr_pct`, type: `number`, description: `Current hero CVR %` },

    // Hero stability
    heroStabilityPct: { sql: `hero_stability_pct`, type: `number`, description: `% of last 12 months this ASIN was #1 hero` },
    heroDataMonths: { sql: `hero_data_months`, type: `number`, description: `Number of months current hero has data` },
    monthsWithData: { sql: `months_with_data`, type: `number`, description: `Total months with any hero data` },

    // Spend allocation
    heroSpend: { sql: `hero_spend`, type: `number`, description: `4-week spend on hero ASIN` },
    heroSpendPct: { sql: `hero_spend_pct`, type: `number`, description: `% of total spend going to hero` },

    // Complexity
    complexityScore: { sql: `complexity_score`, type: `number`, description: `0=simple, 1-2=review, 3+=must review` },
    isMultiCampaign: { sql: `is_multi_campaign`, type: `boolean`, description: `3+ campaigns target this term` },
    isHeroUnstable: { sql: `is_hero_unstable`, type: `boolean`, description: `Hero stability <60%` },
    isHeroUnproven: { sql: `is_hero_unproven`, type: `boolean`, description: `Current hero has <4 months of data` },
    isFragmented: { sql: `is_fragmented`, type: `boolean`, description: `<50% of spend goes to hero` },

    // JSON details for inline panel
    productBreakdown: { sql: `product_breakdown`, type: `string`, description: `JSON array of per-ASIN metrics (4 weeks)` },
    monthlyHeroes: { sql: `monthly_heroes`, type: `string`, description: `JSON array of monthly hero timeline` },
    productBreakdown12m: { sql: `product_breakdown_12m`, type: `string`, description: `JSON array of per-ASIN metrics (12 months)` },
    productBreakdownByMonth: { sql: `product_breakdown_by_month`, type: `string`, description: `JSON array of product breakdowns grouping by month` },
  },
});
