import type { DatasetName } from './datasetTypes';
import type { PageId } from '../../types';

// Loaded on every page: exactly what Header + FilterBar read.
// (_meta is assembled from cubeMeta + dataFreshness; see CubeDataProvider.)
export const SHELL_CORE: DatasetName[] = [
  'cubeMeta', 'dataFreshness', 'actions', 'weekly_trends', 'sqp_weekly', 'peak',
];

export const PAGE_DATASETS: Record<PageId, DatasetName[]> = {
  home: ['actions', 'ads_7d', 'ads_7d_summary', 'asin_oos_days', 'campaign_search_terms', 'change_log',
    'daily_trends_by_asin', 'experiment_campaigns', 'experiments', 'holidays', 'monthly_trends', 'monthly_trends_by_asin',
    'peak', 'products', 'sqp_coverage_weeks', 'sqp_weekly', 'storage_costs', 'supply_chain',
    'upcoming', 'weekly_trends', 'weekly_trends_by_asin'],
  kpi: ['actions', 'ads_7d', 'ads_7d_summary', 'ads_focus_keywords', 'ads_focus_terms',
    'campaign_launch_monthly', 'campaign_launch_perf', 'coach_campaigns', 'daily_trends',
    'monthly_trends', 'monthly_trends_by_asin', 'peak', 'products', 'sqp_weekly', 'storage_costs',
    'supply_chain', 'weekly_trends', 'weekly_trends_by_asin'],
  peak: ['budget_health', 'campaign_search_terms', 'daily_trends', 'drivers', 'experiment_campaigns',
    'experiments', 'holidays', 'keyword_product_map', 'negative_keywords', 'peak', 'peak_relevance', 'peak_keyword_recs', 'peak_stuck_campaigns', 'sqp_weekly',
    'summary', 'weekly_trends'],
  family: ['budget_health', 'drivers', 'experiments', 'hero_asins', 'holidays', 'keyword_product_map',
    'monthly_trends', 'peak', 'sqp_ads_by_term', 'sqp_coverage_weeks', 'sqp_weekly', 'summary', 'weekly_trends',
    'weekly_trends_by_asin'],
  sqp: ['budget_health', 'drivers', 'experiments', 'hero_asins', 'holidays', 'keyword_product_map',
    'monthly_trends', 'peak', 'sqp_ads_by_term', 'sqp_coverage_weeks', 'sqp_weekly', 'summary', 'weekly_trends',
    'weekly_trends_by_asin'],
  actions: ['actions', 'ads_7d', 'asin_oos_days', 'coach_cross_sell', 'coach_decisions',
    'coach_phrase_negatives', 'coach_strategy', 'daily_trends', 'hot_signals', 'keyword_predictions',
    'negative_conflicts', 'plan_ads_targets', 'supply_chain'],
  ads: ['ads_7d', 'campaign_search_terms', 'campaign_search_terms_weekly', 'coach_decisions', 'experiment_campaigns', 'holidays',
    'keyword_product_map', 'peak', 'sqp_volume_4w', 'sqp_weekly'],
  do: ['actions', 'ads_7d', 'coach_campaigns', 'product_creatives', 'products',
    'strategy_campaign_templates', 'supply_chain'],
  experiment: ['budget_health', 'change_log', 'experiment_weekly', 'experiments', 'holidays',
    'keyword_product_map', 'peak'],
  strategies: ['experiment_campaigns', 'experiment_templates', 'experiment_weekly', 'holidays',
    'keyword_product_map', 'peak'],
  learn: ['actions', 'experiment_templates', 'experiment_weekly', 'learnings', 'peak_relevance'],
  supply: ['supply_payments', 'supply_pos', 'supply_shipments'],
  plan: ['monthly_trends', 'products', 'weekly_trends_by_asin'],
  health: ['products', 'summary'],
  kwds: ['keyword_product_map', 'products'],
  log: ['change_log', 'negative_keywords'],
  products: ['products'],
  brand: ['brand_strength_weekly'],
  admin: [],
  alerts: [],
  research: [],
};
