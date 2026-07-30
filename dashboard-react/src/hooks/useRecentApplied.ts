import { useEffect, useState } from 'react';
import { apiFetch } from '../utils/apiFetch';

/**
 * LIVE "already applied" signal, read straight from FACT_PPC_CHANGE_LOG via /api/applied-recent —
 * NOT through the cube. days_since_suggestion is materialised into the cube T_* tables, which only
 * refresh on the slow periodic rebuild, so a bulksheet you just uploaded won't show as applied until
 * then (Ori 2026-07-25). This map lets the launch cards + mature filter override the stale cube value
 * with the fresher one, so an upload registers in seconds.
 *
 * `effectiveDaysSince(keyword_id, cubeValue)` returns the SMALLER of the cube value and the live value
 * (both are "days since last upload"; the smaller is the more recent = the truth). null when neither knows.
 */
export function useRecentApplied(): {
  appliedMap: Map<string, number>;
  effectiveDaysSince: (keywordId: string | null | undefined, cubeVal: number | null | undefined) => number | null;
  loading: boolean;
} {
  const [appliedMap, setAppliedMap] = useState<Map<string, number>>(new Map());
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await apiFetch('/api/applied-recent');
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const json = await res.json();
        if (cancelled) return;
        const m = new Map<string, number>();
        for (const [kid, dss] of Object.entries(json.applied ?? {})) {
          const n = Number(dss);
          if (kid && Number.isFinite(n)) m.set(kid, n);
        }
        setAppliedMap(m);
      } catch {
        if (!cancelled) setAppliedMap(new Map()); // fall back to cube-only in JSON mode / on error
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, []);

  const effectiveDaysSince = (keywordId: string | null | undefined, cubeVal: number | null | undefined): number | null => {
    const live = keywordId != null ? appliedMap.get(String(keywordId)) : undefined;
    const c = cubeVal == null ? Infinity : cubeVal;
    const l = live == null ? Infinity : live;
    const min = Math.min(c, l);
    return Number.isFinite(min) ? min : null;
  };

  return { appliedMap, effectiveDaysSince, loading };
}
