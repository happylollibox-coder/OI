// Cube: ExperimentCampaign - from DIM_EXPERIMENT_CAMPAIGN
// Links campaigns to experiments
cube(`ExperimentCampaign`, {
  sql: `SELECT * FROM \`onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN\``,

  refreshKey: { every: '1 hour' },

  joins: {
    Experiment: {
      relationship: `belongsTo`,
      sql: `${CUBE}.experiment_id = ${Experiment}.experiment_id`,
    },
  },

  measures: {
    count: {
      type: `count`,
      description: `Number of campaign links`,
    },
  },

  dimensions: {
    experimentId: {
      sql: `experiment_id`,
      type: `string`,
      primaryKey: true,
      description: `Experiment ID`,
    },
    campaignId: {
      sql: `campaign_id`,
      type: `string`,
      description: `Amazon Ads campaign ID`,
    },
    campaignName: {
      sql: `campaign_name`,
      type: `string`,
      description: `Campaign display name`,
    },
    topOfSearchPct: {
      sql: `top_of_search_pct`,
      type: `number`,
      description: `TOS placement boost %`,
    },
    productPagePct: {
      sql: `product_page_pct`,
      type: `number`,
      description: `Product page placement boost %`,
    },
    restOfSearchPct: {
      sql: `rest_of_search_pct`,
      type: `number`,
      description: `Rest of search placement boost %`,
    },
  },
});
