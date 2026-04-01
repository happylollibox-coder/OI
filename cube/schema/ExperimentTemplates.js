// Cube: ExperimentTemplates - experiments with ads performance (from refresh_data experiment_templates logic)
cube(`ExperimentTemplates`, {
  refreshKey: { every: '30 minutes' },

  sql: `
WITH exp_data AS (
  SELECT e.strategy_id, e.experiment_id, e.experiment_name, e.description, e.status,
    CAST(e.start_date AS STRING) as start_date, CAST(e.end_date AS STRING) as end_date,
    e.baseline_days, e.outcome_score, e.outcome_tags, e.outcome_notes,
    e.lifecycle_stage, e.graduation_confidence, e.season_context,
    DATE_DIFF(COALESCE(e.end_date, CURRENT_DATE()), e.start_date, DAY) as days_running
  FROM \`onyga-482313.OI.DIM_EXPERIMENT\` e
),
exp_perf AS (
  SELECT ec.experiment_id,
    ROUND(SUM(a.Ads_cost), 2) as total_spend, SUM(a.Ads_orders) as total_orders, SUM(a.Ads_clicks) as total_clicks,
    SUM(a.Ads_impressions) as total_impressions, ROUND(SUM(a.Ads_sales), 2) as total_sales,
    -- COGS=0: FACT_AMAZON_ADS has no COGS at experiment level; FN_NET_ROAS(sales,cogs,ad_cost) used elsewhere
    ROUND(\`onyga-482313.OI.FN_NET_ROAS\`(SUM(a.Ads_sales), 0, SUM(a.Ads_cost)), 2) as net_roas,
    ROUND(SAFE_DIVIDE(SUM(a.Ads_orders) * 100.0, NULLIF(SUM(a.Ads_clicks), 0)), 2) as conv_rate,
    ROUND(SAFE_DIVIDE(SUM(a.Ads_cost), NULLIF(SUM(a.Ads_clicks), 0)), 2) as cpc,
    COUNT(DISTINCT a.search_term) as unique_search_terms
  FROM \`onyga-482313.OI.DIM_EXPERIMENT_CAMPAIGN\` ec
  JOIN \`onyga-482313.OI.FACT_AMAZON_ADS\` a ON ec.campaign_id = a.campaign_id
  WHERE a.Ads_cost > 0 GROUP BY ec.experiment_id
)
SELECT d.strategy_id, d.experiment_id, d.experiment_name, d.description, d.status,
  d.start_date, d.end_date, d.baseline_days, d.outcome_score, d.outcome_tags, d.outcome_notes,
  d.lifecycle_stage, d.graduation_confidence, d.season_context, d.days_running,
  p.total_spend, p.total_orders, p.total_clicks, p.total_impressions, p.total_sales,
  p.net_roas, p.conv_rate, p.cpc, p.unique_search_terms
FROM exp_data d LEFT JOIN exp_perf p ON d.experiment_id = p.experiment_id
`,

  measures: { count: { type: `count`, description: `Number of experiments` } },
  dimensions: {
    experimentId: { sql: `experiment_id`, type: `string`, primaryKey: true },
    experimentName: { sql: `experiment_name`, type: `string` },
    strategyId: { sql: `strategy_id`, type: `string` },
    description: { sql: `description`, type: `string` },
    status: { sql: `status`, type: `string` },
    startDate: { sql: `start_date`, type: `string` },
    endDate: { sql: `end_date`, type: `string` },
    baselineDays: { sql: `baseline_days`, type: `number` },
    outcomeScore: { sql: `outcome_score`, type: `number` },
    outcomeTags: { sql: `outcome_tags`, type: `string` },
    outcomeNotes: { sql: `outcome_notes`, type: `string` },
    lifecycleStage: { sql: `lifecycle_stage`, type: `string` },
    graduationConfidence: { sql: `graduation_confidence`, type: `string` },
    seasonContext: { sql: `season_context`, type: `string` },
    daysRunning: { sql: `days_running`, type: `number` },
    totalSpend: { sql: `total_spend`, type: `number` },
    totalOrders: { sql: `total_orders`, type: `number` },
    totalClicks: { sql: `total_clicks`, type: `number` },
    totalImpressions: { sql: `total_impressions`, type: `number` },
    totalSales: { sql: `total_sales`, type: `number` },
    netRoas: { sql: `net_roas`, type: `number` },
    convRate: { sql: `conv_rate`, type: `number` },
    cpc: { sql: `cpc`, type: `number` },
    uniqueSearchTerms: { sql: `unique_search_terms`, type: `number` },
  },
});
