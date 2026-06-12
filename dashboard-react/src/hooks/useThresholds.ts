import { useState, useEffect, useCallback, useMemo } from 'react';
import { apiFetch } from '../utils/apiFetch';

/** Shape of one threshold row */
export interface ThresholdRow {
  threshold_key: string;
  strategy_id: string;
  product_family: string | null;
  threshold_value: number;
  description: string | null;
  suggested_value: number | null;
  suggested_at: string | null;
  suggestion_reason: string | null;
  peak_multiplier: number;
  boost_peak_multiplier: number;
  source: string;
  updated_at: string | null;
  updated_by: string | null;
}

/** Grouped by strategy */
export interface StrategyGroup {
  strategyId: string;
  thresholds: ThresholdRow[];
}

/**
 * Fetch thresholds from Cube.js via Vite proxy (same-origin).
 * Uses relative URL `/cubejs-api/v1/load` — Vite proxies this to Cube on port 4000.
 */
async function fetchFromCube(): Promise<ThresholdRow[]> {
  const query = {
    dimensions: [
      'CoachThresholds.thresholdKey',
      'CoachThresholds.strategyId',
      'CoachThresholds.productFamily',
      'CoachThresholds.thresholdValue',
      'CoachThresholds.description',
      'CoachThresholds.suggestedValue',
      'CoachThresholds.suggestedAt',
      'CoachThresholds.suggestionReason',
      'CoachThresholds.peakMultiplier',
      'CoachThresholds.boostPeakMultiplier',
      'CoachThresholds.source',
      'CoachThresholds.updatedAt',
      'CoachThresholds.updatedBy',
    ],
  };

  const res = await fetch('/cubejs-api/v1/load', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: '__no_auth__' },
    body: JSON.stringify({ query }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`Cube ${res.status}: ${body.slice(0, 200)}`);
  }

  const json = await res.json();
  const data: Record<string, unknown>[] = json?.data || [];

  return data.map((r) => ({
    threshold_key: String(r['CoachThresholds.thresholdKey'] ?? ''),
    strategy_id: String(r['CoachThresholds.strategyId'] ?? ''),
    product_family: r['CoachThresholds.productFamily'] as string | null,
    threshold_value: Number(r['CoachThresholds.thresholdValue'] ?? 0),
    description: r['CoachThresholds.description'] as string | null,
    suggested_value: r['CoachThresholds.suggestedValue'] != null ? Number(r['CoachThresholds.suggestedValue']) : null,
    suggested_at: r['CoachThresholds.suggestedAt'] as string | null,
    suggestion_reason: r['CoachThresholds.suggestionReason'] as string | null,
    peak_multiplier: Number(r['CoachThresholds.peakMultiplier'] ?? 1),
    boost_peak_multiplier: Number(r['CoachThresholds.boostPeakMultiplier'] ?? 1),
    source: String(r['CoachThresholds.source'] ?? 'MANUAL'),
    updated_at: r['CoachThresholds.updatedAt'] as string | null,
    updated_by: r['CoachThresholds.updatedBy'] as string | null,
  }));
}

export function useThresholds() {
  const [rows, setRows] = useState<ThresholdRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const fetchThresholds = useCallback(async () => {
    try {
      setLoading(true);
      const data = await fetchFromCube();
      setRows(data);
      setError(null);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Failed to load thresholds';
      setError(msg);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchThresholds(); }, [fetchThresholds]);

  /**
   * Write threshold updates via `/api/thresholds` — Vite proxies this to Flask.
   * In dev: proxied to localhost:5001 (or Cloud Run).
   * In prod: the deployed dashboard needs a proxy or direct Cloud Run URL.
   */
  const updateThreshold = useCallback(async (
    thresholdKey: string,
    strategyId: string,
    productFamily: string | null,
    newValue: number
  ) => {
    setSaving(true);
    try {
      const res = await apiFetch('/api/thresholds', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          threshold_key: thresholdKey,
          strategy_id: strategyId,
          product_family: productFamily,
          threshold_value: newValue,
        }),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      // Wait for BigQuery propagation, then refresh from Cube
      setTimeout(() => fetchThresholds(), 3000);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : 'Update failed');
    } finally {
      setSaving(false);
    }
  }, [fetchThresholds]);

  const approveSuggestion = useCallback(async (
    thresholdKey: string,
    strategyId: string,
    productFamily: string | null
  ) => {
    setSaving(true);
    try {
      const res = await apiFetch('/api/thresholds', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          threshold_key: thresholdKey,
          strategy_id: strategyId,
          product_family: productFamily,
          approve_suggestion: true,
        }),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      setTimeout(() => fetchThresholds(), 3000);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : 'Approve failed');
    } finally {
      setSaving(false);
    }
  }, [fetchThresholds]);

  /** Group rows by strategy, GLOBAL first */
  const grouped = useMemo<StrategyGroup[]>(() => {
    const map: Record<string, ThresholdRow[]> = {};
    rows.forEach(r => {
      if (!map[r.strategy_id]) map[r.strategy_id] = [];
      map[r.strategy_id].push(r);
    });
    const keys = Object.keys(map).sort((a, b) => {
      if (a === 'GLOBAL') return -1;
      if (b === 'GLOBAL') return 1;
      return a.localeCompare(b);
    });
    return keys.map(k => ({ strategyId: k, thresholds: map[k] }));
  }, [rows]);

  return { rows, grouped, loading, error, saving, updateThreshold, approveSuggestion, refetch: fetchThresholds };
}
