// All loadable Cube dataset units. Names match DashboardData fields 1:1,
// EXCEPT 'cubeMeta' + 'dataFreshness', which are assembled into data._meta.
export type DatasetName =
  | 'summary' | 'weekly_trends' | 'monthly_trends' | 'weekly_trends_by_asin'
  | 'monthly_trends_by_asin' | 'daily_trends' | 'daily_trends_by_asin' | 'products' | 'product_creatives'
  | 'experiments' | 'ads_7d_summary' | 'ads_7d' | 'sqp_weekly' | 'sqp_coverage_weeks'
  | 'sqp_volume_4w' | 'change_log' | 'upcoming' | 'peak' | 'hero_asins'
  | 'keyword_product_map' | 'learnings' | 'budget_health' | 'drivers'
  | 'experiment_weekly' | 'experiment_campaigns' | 'campaign_search_terms' | 'campaign_search_terms_weekly'
  | 'experiment_templates' | 'holidays' | 'coach_decisions' | 'actions'
  | 'coach_campaigns' | 'experiment_evaluations' | 'keyword_predictions'
  | 'brand_strength_weekly' | 'coach_phrase_negatives' | 'hot_signals' | 'storage_costs'
  | 'supply_chain' | 'supply_pos' | 'supply_payments' | 'supply_shipments'
  | 'peak_relevance' | 'family_occasions' | 'coach_strategy' | 'ads_focus_terms'
  | 'ads_focus_keywords' | 'campaign_launch_perf' | 'campaign_launch_monthly'
  | 'plan_ads_targets' | 'asin_oos_days' | 'negative_conflicts'
  | 'strategy_campaign_templates' | 'coach_cross_sell' | 'negative_keywords'
  | 'cubeMeta' | 'dataFreshness';

export type Status = 'idle' | 'loading' | 'ready' | 'error';

// Matches the empty-value fallbacks in the current resolveLoader().
export function fallbackFor(name: DatasetName): unknown {
  if (name === 'sqp_volume_4w') return {} as Record<string, number>;
  if (name === 'cubeMeta') return { cube_source: 'live' as const };
  if (name === 'dataFreshness') return {};
  return [];
}
