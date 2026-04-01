/**
 * Unified data hook: Cube when available, JSON for negative_keywords and _meta only.
 * - When VITE_CUBE_API_URL is set and Cube returns data: use Cube for Cube-backed fields.
 * - When Cube is not set or returns no data: Cube fields are empty.
 *
 * DATA SOURCES:
 * ───────────
 * CUBE: summary, actions, weekly_trends, ads_7d, etc.
 * JSON (always): negative_keywords, _meta
 */
import { useCubeData } from './useCubeData';
import { useJsonData, JSON_ONLY_FILES } from './useData';
import type { DashboardData } from '../types';

const CUBE_API = import.meta.env.VITE_CUBE_API_URL || (import.meta.env.DEV ? 'http://localhost:4000' : '');

const EMPTY: DashboardData = {
  summary: [], actions: [], upcoming: [], peak: [], products: [],
  hero_asins: [], keyword_product_map: [], weekly_trends: [], monthly_trends: [], weekly_trends_by_asin: [], monthly_trends_by_asin: [],
  learnings: [], experiments: [], budget_health: [], drivers: [], sqp_coverage_weeks: [],
  change_log: [], negative_keywords: [], experiment_weekly: [], sqp_weekly: [], sqp_volume_4w: {},
  experiment_campaigns: [], campaign_search_terms: [],
  ads_7d: [], ads_7d_summary: [], holidays: [], experiment_templates: [],
  coach_decisions: [], coach_terms: [], coach_campaigns: [], experiment_evaluations: [],
  keyword_predictions: [], brand_strength_weekly: [], coach_phrase_negatives: [], product_creatives: [], hot_signals: [],
  _meta: {},
};

export function useUnifiedData(): { data: DashboardData; loading: boolean; fromCube: boolean } {
  const { data: cubeData, loading: cubeLoading } = useCubeData();
  const { data: jsonData, loading: jsonLoading } = useJsonData(JSON_ONLY_FILES) as { data: Partial<DashboardData>; loading: boolean };
  const useCube = !!CUBE_API;
  const cubeHasData = !cubeLoading && Object.keys(cubeData).length > 0;

  const loading = useCube ? (cubeLoading || jsonLoading) : jsonLoading;

  const data: DashboardData = (useCube && cubeHasData)
    ? ({
        ...cubeData,
        negative_keywords: (jsonData.negative_keywords ?? []) as DashboardData['negative_keywords'],
        _meta: { ...(jsonData._meta ?? {}), ...(cubeData._meta ?? {}) } as DashboardData['_meta'],
      } as DashboardData)
    : {
        ...EMPTY,
        negative_keywords: (jsonData.negative_keywords ?? []) as DashboardData['negative_keywords'],
        _meta: (jsonData._meta ?? {}) as DashboardData['_meta'],
      };

  if (import.meta.env.DEV && !loading) {
    const src = useCube && cubeHasData ? 'Cube' : 'JSON';
    const n = data.summary?.length ?? 0;
    console.log('[useUnifiedData] summary source:', src, '| rows:', n, '| fromCube:', useCube && cubeHasData);
  }

  return { data, loading, fromCube: useCube && cubeHasData };
}
