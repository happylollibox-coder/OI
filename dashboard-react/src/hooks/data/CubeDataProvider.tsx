import { createContext, useContext, useMemo, useRef, useReducer, useEffect, useCallback } from 'react';
import type { ReactNode } from 'react';
import { DatasetStore } from './datasetStore';
import type { DatasetName } from './datasetTypes';
import { DATASET_LOADERS } from '../useCubeData';
import { SHELL_CORE, PAGE_DATASETS } from './pageDatasets';
import type { DashboardData, PageId, SummaryRow } from '../../types';

const CUBE_API = import.meta.env.VITE_CUBE_API_URL || (import.meta.env.DEV ? 'http://localhost:4000' : '');

// Default shape so consumers always see arrays/objects (never undefined) before load.
const EMPTY: Partial<DashboardData> = {
  summary: [], actions: [], upcoming: [], peak: [], products: [], hero_asins: [],
  keyword_product_map: [], weekly_trends: [], daily_trends: [], daily_trends_by_asin: [], monthly_trends: [],
  weekly_trends_by_asin: [], monthly_trends_by_asin: [], learnings: [], experiments: [],
  budget_health: [], drivers: [], sqp_coverage_weeks: [], change_log: [], negative_keywords: [],
  experiment_weekly: [], sqp_weekly: [], sqp_ads_by_term: [], sqp_volume_4w: {}, experiment_campaigns: [],
  campaign_search_terms: [], campaign_search_terms_weekly: [], ads_7d: [], ads_7d_summary: [], holidays: [], experiment_templates: [],
  strategy_campaign_templates: [], coach_decisions: [], coach_cross_sell: [], coach_campaigns: [],
  experiment_evaluations: [], keyword_predictions: [], brand_strength_weekly: [],
  coach_phrase_negatives: [], product_creatives: [], hot_signals: [], ads_focus_terms: [],
  ads_focus_keywords: [], phrase_negatives: [], storage_costs: [], supply_chain: [], supply_pos: [],
  supply_payments: [], supply_shipments: [], supply_other_pos: [], peak_relevance: [], peak_keyword_recs: [], peak_stuck_campaigns: [],
  family_occasions: [], coach_strategy: [], campaign_launch_perf: [], campaign_launch_monthly: [],
  plan_ads_targets: [], asin_oos_days: [], negative_conflicts: [], launch_models: [], _meta: {},
};

// Dataset keys that map 1:1 to a DashboardData field (everything except the _meta inputs).
const DATA_FIELDS = (Object.keys(DATASET_LOADERS) as DatasetName[])
  .filter(n => n !== 'cubeMeta' && n !== 'dataFreshness');

type CubeCtx = {
  data: Partial<DashboardData>;
  loading: boolean;
  fromCube: boolean;
  ensureDatasets: (names: DatasetName[]) => Promise<void>;
  ensurePage: (page: PageId) => Promise<void>;
  isPageReady: (page: PageId) => boolean;
  prefetchRemaining: () => void;
};

const Ctx = createContext<CubeCtx | null>(null);

export function CubeDataProvider({ children }: { children: ReactNode }) {
  const storeRef = useRef<DatasetStore>(undefined);
  if (!storeRef.current) storeRef.current = new DatasetStore(DATASET_LOADERS);
  const store = storeRef.current;

  // Re-render whenever the store emits a change.
  const [version, bump] = useReducer((c: number) => c + 1, 0);
  useEffect(() => store.subscribe(bump), [store]);

  const data = useMemo<Partial<DashboardData>>(() => {
    const out: Partial<DashboardData> = { ...EMPTY };
    for (const f of DATA_FIELDS) {
      const s = store.getStatus(f);
      if (s === 'ready' || s === 'error') {
        (out as Record<string, unknown>)[f] = store.getData(f);
      }
    }
    const summary = (store.getData('summary') as SummaryRow[] | undefined) ?? [];
    const cm = (store.getData('cubeMeta') as { refreshed_at?: string; cube_source: 'preagg' | 'live' }) ?? { cube_source: 'live' };
    const df = (store.getData('dataFreshness') as { ads_max_date?: string; performance_max_date?: string }) ?? {};
    out._meta = {
      refreshed_at: cm.refreshed_at,
      cube_source: cm.cube_source,
      data_freshness: df,
      ...(summary[0] ? { date_ranges: { summary_7d: { start: summary[0].period_start || '', end: summary[0].period_end || '' } } } : {}),
    } as DashboardData['_meta'];
    return out;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [version, store]);

  const ensureDatasets = useCallback((names: DatasetName[]) => store.ensure(names), [store]);
  const ensurePage = useCallback((page: PageId) => store.ensure([...SHELL_CORE, ...(PAGE_DATASETS[page] ?? [])]), [store]);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const isPageReady = useCallback((page: PageId) => store.isPageReady([...SHELL_CORE, ...(PAGE_DATASETS[page] ?? [])]), [store, version]);
  const prefetchRemaining = useCallback(() => {
    const all = Object.keys(DATASET_LOADERS) as DatasetName[];
    const idle = store.idleDatasets(all);
    if (idle.length) store.ensure(idle);
  }, [store]);

  const loading = !!CUBE_API && !store.isPageReady(SHELL_CORE);

  const value: CubeCtx = { data, loading, fromCube: !!CUBE_API, ensureDatasets, ensurePage, isPageReady, prefetchRemaining };
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useCubeContext(): CubeCtx {
  const v = useContext(Ctx);
  if (!v) throw new Error('useCubeContext must be used within CubeDataProvider');
  return v;
}
