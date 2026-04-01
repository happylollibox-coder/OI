// Cube: AdsCoachPhraseNegatives - from V_ADS_COACH_PHRASE_NEGATIVES
// ONE ROW PER PHRASE × CAMPAIGN: phrase-level negative keyword recommendations
cube(`AdsCoachPhraseNegatives`, {
  sql: `SELECT *, CONCAT(phrase, '|', campaign_id) as _id FROM \`onyga-482313.OI.T_ADS_COACH_PHRASE_NEGATIVES\``,

  refreshKey: { every: '30 minutes' },

  measures: {
    count: { type: `count`, description: `Number of phrase recommendations` },
  },

  dimensions: {
    id: { sql: `_id`, type: `string`, primaryKey: true },
    phrase: { sql: `phrase`, type: `string` },
    ngramSize: { sql: `ngram_size`, type: `number` },
    adGroupId: { sql: `ad_group_id`, type: `string` },
    campaignId: { sql: `campaign_id`, type: `string` },
    campaignName: { sql: `campaign_name`, type: `string` },
    campaignType: { sql: `campaign_type`, type: `string` },
    portfolioName: { sql: `portfolio_name`, type: `string` },
    phraseTermCount: { sql: `phrase_term_count`, type: `number` },
    phraseSpend8w: { sql: `phrase_spend_8w`, type: `number` },
    phraseOrders8w: { sql: `phrase_orders_8w`, type: `number` },
    phraseClicks8w: { sql: `phrase_clicks_8w`, type: `number` },
    // 1-year history & seasonality
    phraseOrders1y: { sql: `phrase_orders_1y`, type: `number` },
    phraseSpend1y: { sql: `phrase_spend_1y`, type: `number` },
    phraseSales1y: { sql: `phrase_sales_1y`, type: `number` },
    phraseRoas1y: { sql: `phrase_roas_1y`, type: `number` },
    top3MonthsPct: { sql: `top3_months_pct`, type: `number` },
    peakMonths: { sql: `peak_months`, type: `string` },
    seasonalTheme: { sql: `seasonal_theme`, type: `string` },
    action: { sql: `action`, type: `string` },
    priorityScore: { sql: `priority_score`, type: `number` },
    reason: { sql: `reason`, type: `string` },
  },
});
