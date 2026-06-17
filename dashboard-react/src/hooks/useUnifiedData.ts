/**
 * Unified data hook: reads Cube datasets from CubeDataProvider, merges the
 * JSON-only fields (negative_keywords + _meta) from static files.
 */
import { useCubeContext } from './data/CubeDataProvider';
import { useJsonData, JSON_ONLY_FILES } from './useData';
import type { DashboardData } from '../types';

export function useUnifiedData(): { data: DashboardData; loading: boolean; fromCube: boolean } {
  const { data: cubeData, loading, fromCube } = useCubeContext();
  const { data: jsonData } = useJsonData(JSON_ONLY_FILES) as { data: Partial<DashboardData>; loading: boolean };

  const data = {
    ...cubeData,
    negative_keywords: (jsonData.negative_keywords ?? []) as DashboardData['negative_keywords'],
    _meta: { ...(jsonData._meta ?? {}), ...(cubeData._meta ?? {}) } as DashboardData['_meta'],
  } as DashboardData;

  return { data, loading, fromCube };
}
