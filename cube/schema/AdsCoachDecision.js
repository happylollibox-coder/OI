// Cube: AdsCoachDecision - from V_ADS_COACH_DECISION
// ONE ROW PER SEARCH TERM: aggregated evidence + decision
cube(`AdsCoachDecision`, {
  sql: `SELECT * FROM \`onyga-482313.OI.T_ADS_COACH_DECISION\``,

  refreshKey: { every: '30 minutes' },

  measures: {
    count: { type: `count`, description: `Number of terms` },
  },

  dimensions: {
    searchTerm: { sql: `search_term`, type: `string`, primaryKey: true },
    bestAsin: { sql: `best_asin`, type: `string` },
    productShortName: { sql: `product_short_name`, type: `string` },
    parentName: { sql: `parent_name`, type: `string` },
    marginPerUnit: { sql: `margin_per_unit`, type: `number` },

    // Cross-campaign context
    campaignCount4w: { sql: `campaign_count_4w`, type: `number` },
    campaignTypeCount4w: { sql: `campaign_type_count_4w`, type: `number` },
    sellingCampaigns4w: { sql: `selling_campaigns_4w`, type: `number` },

    // Ads 4w
    adsSpend4w: { sql: `ads_spend_4w`, type: `number` },
    adsOrders4w: { sql: `ads_orders_4w`, type: `number` },
    adsUnits4w: { sql: `ads_units_4w`, type: `number` },
    adsClicks4w: { sql: `ads_clicks_4w`, type: `number` },
    adsImpressions4w: { sql: `ads_impressions_4w`, type: `number` },
    adsSales4w: { sql: `ads_sales_4w`, type: `number` },
    adsCpc4w: { sql: `ads_cpc_4w`, type: `number` },
    adsCvrPct4w: { sql: `ads_cvr_pct_4w`, type: `number` },
    adsCostPerOrder4w: { sql: `ads_cost_per_order_4w`, type: `number` },
    adsNetRoas4w: { sql: `ads_net_roas_4w`, type: `number` },
    adsNetProfit4w: { sql: `ads_net_profit_4w`, type: `number` },

    // Ads Lifetime
    adsSpendLifetime: { sql: `ads_spend_lifetime`, type: `number` },
    adsOrdersLifetime: { sql: `ads_orders_lifetime`, type: `number` },
    adsNetRoasLifetime: { sql: `ads_net_roas_lifetime`, type: `number` },

    // Ads 7d activity (stale-action detection)
    adsImpressions7d: { sql: `ads_impressions_7d`, type: `number` },
    adsSpend7d: { sql: `ads_spend_7d`, type: `number` },
    adsClicks7d: { sql: `ads_clicks_7d`, type: `number` },
    lastAdDate: { sql: `last_ad_date`, type: `time` },
    adsActiveLast7d: { sql: `ads_active_last_7d`, type: `boolean` },

    // Ads LY Peak
    adsSpendLyPeak: { sql: `ads_spend_ly_peak`, type: `number` },
    adsOrdersLyPeak: { sql: `ads_orders_ly_peak`, type: `number` },
    adsUnitsLyPeak: { sql: `ads_units_ly_peak`, type: `number` },
    adsClicksLyPeak: { sql: `ads_clicks_ly_peak`, type: `number` },
    adsImpressionsLyPeak: { sql: `ads_impressions_ly_peak`, type: `number` },
    adsSalesLyPeak: { sql: `ads_sales_ly_peak`, type: `number` },
    adsCpcLyPeak: { sql: `ads_cpc_ly_peak`, type: `number` },
    adsCvrPctLyPeak: { sql: `ads_cvr_pct_ly_peak`, type: `number` },
    adsNetRoasLyPeak: { sql: `ads_net_roas_ly_peak`, type: `number` },

    // SQP 4w Your ASIN
    sqpImpressions4w: { sql: `sqp_impressions_4w`, type: `number` },
    sqpClicks4w: { sql: `sqp_clicks_4w`, type: `number` },
    sqpCartAdds4w: { sql: `sqp_cart_adds_4w`, type: `number` },
    sqpOrders4w: { sql: `sqp_orders_4w`, type: `number` },
    sqpSales4w: { sql: `sqp_sales_4w`, type: `number` },
    sqpOrganicUnits4w: { sql: `sqp_organic_units_4w`, type: `number` },
    sqpShowRate4w: { sql: `sqp_show_rate_4w`, type: `number` },
    sqpImpressionShare4w: { sql: `sqp_impression_share_4w`, type: `number` },
    sqpOrganicRank4w: { sql: `sqp_organic_rank_4w`, type: `number` },

    // SQP 4w Amazon market
    sqpAmazonImpressions4w: { sql: `sqp_amazon_impressions_4w`, type: `number` },
    sqpAmazonClicks4w: { sql: `sqp_amazon_clicks_4w`, type: `number` },
    sqpAmazonCartAdds4w: { sql: `sqp_amazon_cart_adds_4w`, type: `number` },
    sqpAmazonOrders4w: { sql: `sqp_amazon_orders_4w`, type: `number` },
    sqpAmazonSearchVolume4w: { sql: `sqp_amazon_search_volume_4w`, type: `number` },

    // SQP LY Peak Your ASIN
    sqpImpressionsLyPeak: { sql: `sqp_impressions_ly_peak`, type: `number` },
    sqpClicksLyPeak: { sql: `sqp_clicks_ly_peak`, type: `number` },
    sqpCartAddsLyPeak: { sql: `sqp_cart_adds_ly_peak`, type: `number` },
    sqpOrdersLyPeak: { sql: `sqp_orders_ly_peak`, type: `number` },
    sqpSalesLyPeak: { sql: `sqp_sales_ly_peak`, type: `number` },
    sqpShowRateLyPeak: { sql: `sqp_show_rate_ly_peak`, type: `number` },
    sqpImpressionShareLyPeak: { sql: `sqp_impression_share_ly_peak`, type: `number` },
    sqpOrganicRankLyPeak: { sql: `sqp_organic_rank_ly_peak`, type: `number` },

    // SQP LY Peak Amazon market
    sqpAmazonImpressionsLyPeak: { sql: `sqp_amazon_impressions_ly_peak`, type: `number` },
    sqpAmazonClicksLyPeak: { sql: `sqp_amazon_clicks_ly_peak`, type: `number` },
    sqpAmazonCartAddsLyPeak: { sql: `sqp_amazon_cart_adds_ly_peak`, type: `number` },
    sqpAmazonOrdersLyPeak: { sql: `sqp_amazon_orders_ly_peak`, type: `number` },
    sqpAmazonSearchVolumeLyPeak: { sql: `sqp_amazon_search_volume_ly_peak`, type: `number` },

    // Decision
    signal: { sql: `ads_signal`, type: `string` },
    decision: { sql: `decision`, type: `string` },
    priorityScore: { sql: `priority_score`, type: `number` },
    confidence: { sql: `confidence`, type: `string` },
    reason: { sql: `reason`, type: `string` },
  },
});
