import { useEffect, useState } from 'react';
import { cubeLoad } from './useCubeData';

/** The most recent bid/action change WE uploaded for a keyword-in-campaign
 *  (from FACT_PPC_CHANGE_LOG via the PpcActionOutcomes cube). */
export interface LastChange {
  date: string;    // YYYY-MM-DD (LA-local change date)
  action: string;  // e.g. INCREASE_BID, REDUCE_BID, NEGATE_TERM
}

const norm = (s: string) => s.trim().toUpperCase();
const kwKey = (campaignId: string, keywordId: string) => `${campaignId}|kw:${keywordId}`;
const tgKey = (campaignId: string, targeting: string) => `${campaignId}|tg:${norm(targeting)}`;

/**
 * Builds a lookup of the latest change per keyword-in-campaign, keyed by both
 * (campaign, keyword_id) and (campaign, targeting text) so the caller can match
 * on whichever it has. Falls back gracefully to an empty map in JSON-only mode.
 */
export function useLastChange(): {
  lastChangeFor: (campaignId?: string | null, keywordId?: string | null, targeting?: string | null) => LastChange | null;
  loading: boolean;
} {
  const [map, setMap] = useState<Map<string, LastChange>>(new Map());
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const rows = await cubeLoad({
          dimensions: [
            'PpcActionOutcomes.campaignId',
            'PpcActionOutcomes.keywordId',
            'PpcActionOutcomes.targeting',
            'PpcActionOutcomes.changeDate',
            'PpcActionOutcomes.action',
          ],
          // Newest first → first time we see a key is its most recent change.
          order: { 'PpcActionOutcomes.changeDate': 'desc' },
          limit: 5000,
        }) as Record<string, unknown>[];
        if (cancelled) return;
        const m = new Map<string, LastChange>();
        for (const r of rows) {
          const campaignId = String(r['PpcActionOutcomes.campaignId'] ?? '');
          const ts = r['PpcActionOutcomes.changeDate'];
          const date = ts ? String(ts).slice(0, 10) : '';
          if (!campaignId || !date) continue;
          const entry: LastChange = { date, action: String(r['PpcActionOutcomes.action'] ?? '') };
          const keywordId = String(r['PpcActionOutcomes.keywordId'] ?? '');
          const targeting = String(r['PpcActionOutcomes.targeting'] ?? '');
          if (keywordId) { const k = kwKey(campaignId, keywordId); if (!m.has(k)) m.set(k, entry); }
          if (targeting) { const k = tgKey(campaignId, targeting); if (!m.has(k)) m.set(k, entry); }
        }
        setMap(m);
      } catch {
        if (!cancelled) setMap(new Map());
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, []);

  const lastChangeFor = (campaignId?: string | null, keywordId?: string | null, targeting?: string | null): LastChange | null => {
    if (!campaignId) return null;
    if (keywordId) { const byKw = map.get(kwKey(campaignId, keywordId)); if (byKw) return byKw; }
    if (targeting) { const byTg = map.get(tgKey(campaignId, targeting)); if (byTg) return byTg; }
    return null;
  };

  return { lastChangeFor, loading };
}
