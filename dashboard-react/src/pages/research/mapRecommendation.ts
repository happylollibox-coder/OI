import type { RecommendationRow, RecommendationsByType } from './types';

const num = (v: unknown): number | null => (v == null ? null : Number(v));

export function mapRecommendation(t: Record<string, unknown>): RecommendationRow {
  return {
    rec_type: (t.rec_type as RecommendationRow['rec_type']) ?? 'EXACT',
    match_type: (t.match_type as RecommendationRow['match_type']) ?? 'EXACT',
    keyword: String(t.keyword ?? ''),
    rank: num(t.rank),
    overall_fit: num(t.overall_fit),
    market_sales: num(t.market_sales),
    market_volume: num(t.market_volume),
    coverage_count: num(t.coverage_count),
    cluster_size: num(t.cluster_size),
    status: (t.status as RecommendationRow['status']) ?? 'NEW',
    week_start: (t.week_start as string) ?? null,
  };
}

/** Normalize the grouped API payload into a fully-populated 4-key map. */
export function mapRecommendationsByType(payload: Record<string, unknown[]>): RecommendationsByType {
  const out: RecommendationsByType = { EXACT: [], PHRASE: [], BROAD: [], BRAND: [] };
  (['EXACT', 'PHRASE', 'BROAD', 'BRAND'] as const).forEach(k => {
    out[k] = (payload[k] || []).map(r => mapRecommendation(r as Record<string, unknown>));
  });
  return out;
}
