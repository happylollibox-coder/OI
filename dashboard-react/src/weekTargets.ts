// Self-contained lookup of this week's plan target per product (Coacher D), for the Actions page
// to explain which week target each action serves. Reads the CoachWeeklyPlanProduct rollup (same
// source as the This Week page) so the chip's net matches it — forward ads-direct $ from SCALE
// cells, NOT the old trailing-trend expected_net_profit. Loaded once + cached.
import { cubeLoad } from './hooks/useCubeData';

export type WeekTarget = { purposes: string; fwdNet: number | null; scaleCells: number; probeClicks: number };

let cache: Promise<Map<string, WeekTarget>> | null = null;

export function loadWeekTargets(): Promise<Map<string, WeekTarget>> {
  if (cache) return cache;
  cache = (async () => {
    const map = new Map<string, WeekTarget>();
    try {
      const rows = await cubeLoad({
        dimensions: ['CoachWeeklyPlanProduct.parentName', 'CoachWeeklyPlanProduct.purposes',
          'CoachWeeklyPlanProduct.forwardAdsNet', 'CoachWeeklyPlanProduct.scaleCells',
          'CoachWeeklyPlanProduct.probeMapClicks'],
        filters: [{ member: 'CoachWeeklyPlanProduct.horizon', operator: 'equals', values: ['CURRENT'] }],
      });
      for (const r of rows as Record<string, unknown>[]) {
        const k = String(r['CoachWeeklyPlanProduct.parentName'] ?? '');
        if (!k) continue;
        map.set(k, {
          purposes: String(r['CoachWeeklyPlanProduct.purposes'] ?? ''),
          fwdNet: r['CoachWeeklyPlanProduct.forwardAdsNet'] != null ? Number(r['CoachWeeklyPlanProduct.forwardAdsNet']) : null,
          scaleCells: Number(r['CoachWeeklyPlanProduct.scaleCells'] ?? 0),
          probeClicks: Number(r['CoachWeeklyPlanProduct.probeMapClicks'] ?? 0),
        });
      }
    } catch { /* cube/plan not available — chip simply won't render */ }
    return map;
  })();
  return cache;
}
