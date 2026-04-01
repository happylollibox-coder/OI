import { useState, useEffect } from 'react';
import type { DashboardData } from '../types';

/** All JSON data files. Used when Cube is not available. */
export const JSON_FILES = [
  'summary','actions','upcoming','peak','products','hero_asins',
  'keyword_product_map','weekly_trends','monthly_trends','weekly_trends_by_asin','monthly_trends_by_asin','learnings',
  'experiments','budget_health','drivers','change_log','negative_keywords',
  'experiment_weekly','sqp_weekly','sqp_volume_4w','experiment_campaigns','campaign_search_terms',
  'ads_7d','experiment_templates',
  '_meta'
] as const;

/** JSON-only fields (not in Cube). Fetched alongside Cube when VITE_CUBE_API_URL is set. */
export const JSON_ONLY_FILES = ['negative_keywords', '_meta'] as const;

const defaultFor = (key: string): unknown => (key === 'sqp_volume_4w' ? {} : key === '_meta' ? {} : []);

export function useJsonData(files?: readonly string[]) {
  const toFetch = files ?? JSON_FILES;
  const [data, setData] = useState<Partial<DashboardData>>({});
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all(
      toFetch.map(f =>
        fetch(`/data/${f}.json`).then(r => r.ok ? r.json() : defaultFor(f)).catch(() => defaultFor(f))
      )
    ).then(results => {
      const d: Record<string, unknown> = {};
      toFetch.forEach((f, i) => { d[f] = results[i]; });
      setData(d as Partial<DashboardData>);
      setLoading(false);
    });
  }, [toFetch.join(',')]);

  return { data, loading };
}
